import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { MobileAccessService } from '../common/mobile-access.service';
import { MobileCacheService } from '../common/mobile-cache.service';
import { mobileJsonSafe } from '../common/mobile-json.util';

@Injectable()
export class MobileDashboardService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
    private readonly cache: MobileCacheService,
  ) {}

  async dashboard(auth: AuthContext) {
    const customerIds = this.access.customerIds(auth);
    const cacheKey = ['mobile', 'dashboard', auth.userId, ...customerIds.slice().sort()].join(':');

    return this.cache.getOrSet(cacheKey, this.cache.defaultTtlSeconds, async () => {
      const [
        customers,
        vehicles,
        activeSubscriptions,
        outstandingInvoices,
        recentEvents,
        recentNotifications,
      ] = await Promise.all([
        this.prisma.customer.findMany({
          where: {
            id: {
              in: customerIds,
            },
            archivedAt: null,
          },
          orderBy: {
            createdAt: 'asc',
          },
          select: {
            id: true,
            customerCode: true,
            customerType: true,
            status: true,
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
        }),
        this.prisma.vehicle.findMany({
          where: this.access.vehicleWhere(auth),
          orderBy: {
            createdAt: 'asc',
          },
          select: {
            id: true,
            vehicleCode: true,
            registrationNumber: true,
            vehicleType: true,
            manufacturer: true,
            modelName: true,
            color: true,
            status: true,
            deviceAssignments: {
              where: {
                status: 'ACTIVE',
                assignmentType: 'PRIMARY',
              },
              take: 1,
              orderBy: {
                startedAt: 'desc',
              },
              select: {
                startedAt: true,
                device: {
                  select: {
                    id: true,
                    deviceCode: true,
                    lifecycleStatus: true,
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
              take: 1,
              orderBy: {
                createdAt: 'desc',
              },
              select: {
                id: true,
                subscriptionCode: true,
                status: true,
                currentPeriodEnd: true,
                nextBillingAt: true,
                servicePlan: {
                  select: {
                    name: true,
                    basePrice: true,
                    currency: true,
                  },
                },
              },
            },
          },
        }),
        this.prisma.subscription.count({
          where: {
            customerId: {
              in: customerIds,
            },
            status: {
              in: ['TRIALING', 'ACTIVE', 'PAST_DUE'],
            },
          },
        }),
        this.prisma.invoice.aggregate({
          where: {
            customerId: {
              in: customerIds,
            },
            status: {
              in: ['ISSUED', 'PARTIALLY_PAID', 'OVERDUE'],
            },
          },
          _count: {
            _all: true,
          },
          _sum: {
            outstandingAmount: true,
          },
        }),
        this.prisma.trackingEvent.findMany({
          where: {
            customerId: {
              in: customerIds,
            },
          },
          orderBy: {
            occurredAt: 'desc',
          },
          take: 5,
          select: {
            id: true,
            eventCode: true,
            vehicleId: true,
            eventType: true,
            severity: true,
            latitude: true,
            longitude: true,
            occurredAt: true,
            acknowledgedAt: true,
          },
        }),
        this.prisma.notification.findMany({
          where: {
            customerId: {
              in: customerIds,
            },
            OR: [
              {
                userId: null,
              },
              {
                userId: auth.userId,
              },
            ],
          },
          orderBy: {
            createdAt: 'desc',
          },
          take: 5,
          select: {
            id: true,
            notificationCode: true,
            channel: true,
            subject: true,
            renderedContent: true,
            status: true,
            createdAt: true,
            deliveredAt: true,
          },
        }),
      ]);

      const activeTrackerCount = vehicles.filter(
        (vehicle) => vehicle.deviceAssignments.length > 0,
      ).length;
      const onlineTrackerCount = vehicles.filter(
        (vehicle) =>
          vehicle.deviceAssignments[0]?.device.traccarMappings[0]?.syncStatus === 'SYNCED',
      ).length;
      const vehicleContracts = vehicles.map(({ subscriptions, ...vehicle }) => ({
        ...vehicle,
        subscription: subscriptions[0] ?? null,
      }));

      return mobileJsonSafe({
        data: {
          customers,
          summary: {
            customerCount: customers.length,
            vehicleCount: vehicles.length,
            activeTrackerCount,
            onlineTrackerCount,
            activeSubscriptionCount: activeSubscriptions,
            outstandingInvoiceCount: outstandingInvoices._count._all,
            outstandingAmount: outstandingInvoices._sum.outstandingAmount ?? 0,
          },
          vehicles: vehicleContracts,
          recentEvents,
          recentNotifications,
        },
        meta: {
          generatedAt: new Date().toISOString(),
          cacheTtlSeconds: this.cache.defaultTtlSeconds,
        },
      });
    });
  }
}
