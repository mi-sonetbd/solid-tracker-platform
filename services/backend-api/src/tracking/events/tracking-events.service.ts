import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type { TrackingEventQueryDto } from '../common/tracking-query.dto';
import { jsonSafe, toInputJson } from '../common/tracking-json.util';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import { NotificationsService } from '../notifications/notifications.service';
import type { TraccarWebhookDto } from './dto/traccar-webhook.dto';

@Injectable()
export class TrackingEventsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly jobs: IntegrationJobsService,
    private readonly notifications: NotificationsService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: TrackingEventQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.eventWhere(auth);
    const occurredAt =
      query.from || query.to
        ? {
            gte: query.from ? new Date(query.from) : undefined,
            lte: query.to ? new Date(query.to) : undefined,
          }
        : undefined;

    const where: Prisma.TrackingEventWhereInput = {
      AND: [
        scopeWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.vehicleId
          ? {
              vehicleId: query.vehicleId,
            }
          : {},
        query.deviceId
          ? {
              deviceId: query.deviceId,
            }
          : {},
        query.eventType
          ? {
              eventType: query.eventType,
            }
          : {},
        query.severity
          ? {
              severity: query.severity,
            }
          : {},
        query.processingStatus
          ? {
              processingStatus: query.processingStatus,
            }
          : {},
        occurredAt
          ? {
              occurredAt,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  eventCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  eventType: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  deduplicationKey: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.trackingEvent.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          occurredAt: 'desc',
        },
        include: {
          customer: true,
          vehicle: true,
          device: true,
          traccarServer: {
            select: {
              id: true,
              serverCode: true,
              name: true,
            },
          },
          acknowledgedBy: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
          _count: {
            select: {
              notifications: true,
            },
          },
        },
      }),
      this.prisma.trackingEvent.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async get(auth: AuthContext, eventId: string) {
    await this.access.assertTrackingEvent(auth, eventId);

    const event = await this.prisma.trackingEvent.findUnique({
      where: {
        id: eventId,
      },
      include: {
        customer: true,
        vehicle: true,
        device: true,
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
          },
        },
        acknowledgedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
        notifications: true,
      },
    });

    return jsonSafe(event);
  }

  async acknowledge(auth: AuthContext, eventId: string) {
    await this.access.assertTrackingEvent(auth, eventId);

    const before = await this.prisma.trackingEvent.findUnique({
      where: {
        id: eventId,
      },
    });

    if (!before) {
      throw new NotFoundException('Tracking event was not found.');
    }

    const updated = await this.prisma.trackingEvent.update({
      where: {
        id: eventId,
      },
      data: {
        acknowledgedAt: before.acknowledgedAt ?? new Date(),
        acknowledgedByUserId: before.acknowledgedByUserId ?? auth.userId,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.event.acknowledged',
      resourceType: 'TrackingEvent',
      resourceId: eventId,
      scopeType: 'VEHICLE',
      scopeId: updated.vehicleId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async ingest(serverCode: string, dto: TraccarWebhookDto) {
    const position = dto.position ?? {};

    const server = await this.prisma.traccarServer.findFirst({
      where: {
        serverCode,
        status: {
          in: ['ACTIVE', 'DEGRADED', 'MAINTENANCE'],
        },
      },
    });

    if (!server) {
      throw new NotFoundException('Webhook Traccar server was not found.');
    }

    const externalDeviceId = this.bigInt(dto.device.id ?? dto.event.deviceId, 'device.id');
    const uniqueId = this.stringValue(dto.device.uniqueId);
    const mappingConditions: Prisma.TraccarDeviceMappingWhereInput[] = [
      {
        traccarDeviceId: externalDeviceId,
      },
    ];

    if (uniqueId) {
      mappingConditions.push({
        traccarUniqueId: uniqueId,
      });
    }

    const mapping = await this.prisma.traccarDeviceMapping.findFirst({
      where: {
        traccarServerId: server.id,
        isActive: true,
        OR: mappingConditions,
      },
    });

    if (!mapping) {
      throw new NotFoundException('Webhook device does not have an active Solid Tracker mapping.');
    }

    const assignment = await this.prisma.vehicleDeviceAssignment.findFirst({
      where: {
        deviceId: mapping.deviceId,
        status: 'ACTIVE',
      },
      include: {
        vehicle: true,
      },
    });

    if (!assignment) {
      throw new BadRequestException('Webhook device is not actively assigned to a vehicle.');
    }

    const eventType = this.stringValue(dto.event.type) ?? 'unknown';
    const occurredAt = this.dateValue(
      dto.event.eventTime ?? position.fixTime ?? position.deviceTime ?? position.serverTime,
    );
    const traccarEventId = this.optionalBigInt(dto.event.id);
    const deduplicationKey = traccarEventId
      ? `${server.id}:${traccarEventId.toString()}`
      : this.fallbackDeduplicationKey({
          serverId: server.id,
          deviceId: mapping.deviceId,
          eventType,
          occurredAt,
          positionId: position.id,
        });

    const existing = await this.prisma.trackingEvent.findUnique({
      where: {
        deduplicationKey,
      },
    });

    if (existing) {
      return jsonSafe({
        event: existing,
        duplicate: true,
      });
    }

    const job = await this.jobs.create({
      jobType: 'PROCESS_EVENT',
      traccarServerId: server.id,
      entityType: 'TraccarEvent',
      entityId: traccarEventId?.toString() ?? deduplicationKey,
      idempotencyKey: `process-event:${deduplicationKey}`,
      payload: dto,
      correlationId: deduplicationKey.slice(0, 100),
    });

    await this.jobs.processing(job.id);

    const event = await this.prisma.trackingEvent.create({
      data: {
        eventCode: this.codes.event(),
        customerId: assignment.vehicle.customerId,
        vehicleId: assignment.vehicleId,
        deviceId: mapping.deviceId,
        traccarServerId: server.id,
        traccarEventId,
        deduplicationKey,
        eventType,
        severity: this.severity(eventType, dto.event.attributes),
        latitude: this.optionalNumber(position.latitude),
        longitude: this.optionalNumber(position.longitude),
        occurredAt,
        attributes: toInputJson({
          event: dto.event,
          position: dto.position ?? null,
          device: {
            id: dto.device.id,
            uniqueId: dto.device.uniqueId,
            name: dto.device.name,
          },
        }),
        processingStatus: 'PROCESSING',
      },
    });

    try {
      const notifications = await this.notifications.enqueueForEvent(event);
      const processed = await this.prisma.trackingEvent.update({
        where: {
          id: event.id,
        },
        data: {
          processingStatus: 'PROCESSED',
          processingError: null,
        },
      });

      await this.jobs.succeeded(job.id, {
        trackingEventId: event.id,
        notificationCount: notifications.length,
      });

      return jsonSafe({
        event: processed,
        notifications,
        duplicate: false,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown event-processing error';

      await this.prisma.trackingEvent.update({
        where: {
          id: event.id,
        },
        data: {
          processingStatus: 'FAILED',
          processingError: message,
        },
      });

      await this.jobs.failed(job.id, error);
      throw error;
    }
  }

  private severity(eventType: string, attributes: unknown): 'INFO' | 'WARNING' | 'CRITICAL' {
    const normalized = eventType.toLowerCase();
    const alarm =
      attributes && typeof attributes === 'object' && 'alarm' in attributes
        ? String((attributes as Record<string, unknown>).alarm).toLowerCase()
        : '';

    if (
      normalized.includes('sos') ||
      normalized.includes('panic') ||
      normalized.includes('tamper') ||
      alarm.includes('sos') ||
      alarm.includes('panic')
    ) {
      return 'CRITICAL';
    }

    if (
      normalized.includes('overspeed') ||
      normalized.includes('geofence') ||
      normalized.includes('offline') ||
      normalized.includes('alarm') ||
      alarm.length > 0
    ) {
      return 'WARNING';
    }

    return 'INFO';
  }

  private fallbackDeduplicationKey(input: {
    serverId: string;
    deviceId: string;
    eventType: string;
    occurredAt: Date;
    positionId: unknown;
  }): string {
    return createHash('sha256')
      .update(
        JSON.stringify({
          ...input,
          occurredAt: input.occurredAt.toISOString(),
        }),
      )
      .digest('hex');
  }

  private bigInt(value: unknown, field: string): bigint {
    const parsed = this.optionalBigInt(value);

    if (parsed === null) {
      throw new BadRequestException(`${field} must be a valid integer.`);
    }

    return parsed;
  }

  private optionalBigInt(value: unknown): bigint | null {
    if (typeof value === 'bigint' || typeof value === 'number' || typeof value === 'string') {
      try {
        return BigInt(value);
      } catch {
        return null;
      }
    }

    return null;
  }

  private stringValue(value: unknown): string | null {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
  }

  private dateValue(value: unknown): Date {
    const date =
      value instanceof Date
        ? new Date(value.getTime())
        : typeof value === 'string' || typeof value === 'number'
          ? new Date(value)
          : new Date();

    if (Number.isNaN(date.getTime())) {
      throw new BadRequestException('Webhook event time is invalid.');
    }

    return date;
  }

  private optionalNumber(value: unknown): number | undefined {
    const number =
      typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : Number.NaN;

    return Number.isFinite(number) ? number : undefined;
  }
}
