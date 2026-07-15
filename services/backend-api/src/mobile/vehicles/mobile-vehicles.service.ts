import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingPositionsService } from '../../tracking/positions/tracking-positions.service';
import { MobileAccessService } from '../common/mobile-access.service';
import { mobileJsonSafe } from '../common/mobile-json.util';
import type {
  MobileCursorQueryDto,
  MobileEventQueryDto,
  MobileHistoryQueryDto,
} from '../common/mobile-query.dto';
import { MobileTripBuilderService } from './mobile-trip-builder.service';

@Injectable()
export class MobileVehiclesService {
  private readonly historyMaximumHours: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
    private readonly trackingPositions: TrackingPositionsService,
    private readonly trips: MobileTripBuilderService,
    config: ConfigService,
  ) {
    this.historyMaximumHours = Number(config.get('MOBILE_HISTORY_MAX_HOURS', 168));
  }

  async list(auth: AuthContext, query: MobileCursorQueryDto) {
    const items = await this.prisma.vehicle.findMany({
      where: this.access.vehicleWhere(auth),
      orderBy: [
        {
          createdAt: 'asc',
        },
        {
          id: 'asc',
        },
      ],
      cursor: query.cursor
        ? {
            id: query.cursor,
          }
        : undefined,
      skip: query.cursor ? 1 : 0,
      take: query.limit + 1,
      select: {
        id: true,
        vehicleCode: true,
        registrationNumber: true,
        vehicleType: true,
        manufacturer: true,
        modelName: true,
        manufacturingYear: true,
        color: true,
        status: true,
        customer: {
          select: {
            id: true,
            customerCode: true,
            individualProfile: {
              select: {
                fullName: true,
              },
            },
            organizationProfile: {
              select: {
                displayName: true,
              },
            },
          },
        },
        deviceAssignments: {
          where: {
            status: 'ACTIVE',
            assignmentType: 'PRIMARY',
          },
          orderBy: {
            startedAt: 'desc',
          },
          take: 1,
          select: {
            id: true,
            startedAt: true,
            device: {
              select: {
                id: true,
                deviceCode: true,
                imei: true,
                lifecycleStatus: true,
                firmwareVersion: true,
                deviceModel: {
                  select: {
                    manufacturer: true,
                    modelName: true,
                    protocol: true,
                    networkType: true,
                  },
                },
                traccarMappings: {
                  where: {
                    isActive: true,
                    isPrimary: true,
                  },
                  take: 1,
                  select: {
                    syncStatus: true,
                    lastSyncedAt: true,
                    lastSyncError: true,
                  },
                },
              },
            },
          },
        },
        subscriptions: {
          where: {
            status: {
              in: ['TRIALING', 'ACTIVE', 'PAST_DUE', 'SUSPENDED'],
            },
          },
          orderBy: {
            createdAt: 'desc',
          },
          take: 1,
          select: {
            id: true,
            subscriptionCode: true,
            status: true,
            currentPeriodEnd: true,
            nextBillingAt: true,
            servicePlan: {
              select: {
                name: true,
                currency: true,
                basePrice: true,
              },
            },
          },
        },
      },
    });

    const hasMore = items.length > query.limit;

    if (hasMore) {
      items.pop();
    }

    const contracts = items.map(({ subscriptions, ...vehicle }) => ({
      ...vehicle,
      subscription: subscriptions[0] ?? null,
    }));

    return mobileJsonSafe({
      data: contracts,
      meta: {
        limit: query.limit,
        count: contracts.length,
        nextCursor: hasMore && items.length > 0 ? items[items.length - 1].id : null,
      },
    });
  }

  async detail(auth: AuthContext, vehicleId: string) {
    await this.access.assertVehicle(auth, vehicleId);
    const vehicle = await this.prisma.vehicle.findUniqueOrThrow({
      where: {
        id: vehicleId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
          },
        },
        deviceAssignments: {
          where: {
            status: 'ACTIVE',
          },
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            device: {
              include: {
                deviceModel: true,
                traccarMappings: {
                  where: {
                    isActive: true,
                  },
                  orderBy: {
                    createdAt: 'desc',
                  },
                },
              },
            },
            installation: true,
          },
        },
        subscriptions: {
          orderBy: {
            createdAt: 'desc',
          },
          take: 3,
          include: {
            servicePlan: true,
          },
        },
        vehicleGeofenceAssignments: {
          where: {
            status: 'ACTIVE',
          },
          include: {
            geofence: true,
          },
        },
      },
    });

    const { subscriptions, ...vehicleContract } = vehicle;

    return mobileJsonSafe({
      data: {
        ...vehicleContract,
        subscriptions: subscriptions,
      },
      meta: {
        generatedAt: new Date().toISOString(),
      },
    });
  }

  async livePosition(auth: AuthContext, vehicleId: string) {
    const result = await this.trackingPositions.livePosition(auth, vehicleId);

    return mobileJsonSafe({
      data: result,
      meta: {
        generatedAt: new Date().toISOString(),
      },
    });
  }

  async history(auth: AuthContext, vehicleId: string, query: MobileHistoryQueryDto) {
    this.assertHistoryRange(query);
    const result = await this.trackingPositions.history(auth, vehicleId, query);

    return mobileJsonSafe({
      data: result,
      meta: {
        maximumHours: this.historyMaximumHours,
      },
    });
  }

  async tripFeed(auth: AuthContext, vehicleId: string, query: MobileHistoryQueryDto) {
    this.assertHistoryRange(query);
    const history = await this.trackingPositions.history(auth, vehicleId, query);
    const trips = this.trips.build(history.positions);

    return mobileJsonSafe({
      data: trips,
      meta: {
        vehicleId,
        from: history.from,
        to: history.to,
        count: trips.length,
      },
    });
  }

  async eventFeed(auth: AuthContext, vehicleId: string, query: MobileEventQueryDto) {
    const vehicle = await this.access.assertVehicle(auth, vehicleId);
    const occurredAt = this.dateWhere(query.from, query.to);
    const items = await this.prisma.trackingEvent.findMany({
      where: {
        vehicleId,
        customerId: vehicle.customerId,
        severity: query.severity,
        eventType: query.eventType,
        occurredAt,
      },
      orderBy: [
        {
          occurredAt: 'desc',
        },
        {
          id: 'desc',
        },
      ],
      cursor: query.cursor
        ? {
            id: query.cursor,
          }
        : undefined,
      skip: query.cursor ? 1 : 0,
      take: query.limit + 1,
      select: {
        id: true,
        eventCode: true,
        eventType: true,
        severity: true,
        latitude: true,
        longitude: true,
        occurredAt: true,
        receivedAt: true,
        attributes: true,
        processingStatus: true,
        acknowledgedAt: true,
      },
    });
    const hasMore = items.length > query.limit;

    if (hasMore) {
      items.pop();
    }

    return mobileJsonSafe({
      data: items,
      meta: {
        vehicleId,
        limit: query.limit,
        count: items.length,
        nextCursor: hasMore && items.length > 0 ? items[items.length - 1].id : null,
      },
    });
  }

  private assertHistoryRange(query: MobileHistoryQueryDto): void {
    const to = query.to ? new Date(query.to) : new Date();
    const from = query.from ? new Date(query.from) : new Date(to.getTime() - 24 * 60 * 60 * 1000);

    if (from >= to) {
      throw new BadRequestException('History from must be earlier than to.');
    }

    const hours = (to.getTime() - from.getTime()) / (60 * 60 * 1000);

    if (hours > this.historyMaximumHours) {
      throw new BadRequestException(
        `Mobile history is limited to ${this.historyMaximumHours} hours per request.`,
      );
    }
  }

  private dateWhere(
    from?: string,
    to?: string,
  ):
    | {
        gte?: Date;
        lte?: Date;
      }
    | undefined {
    if (!from && !to) {
      return undefined;
    }

    return {
      gte: from ? new Date(from) : undefined,
      lte: to ? new Date(to) : undefined,
    };
  }
}
