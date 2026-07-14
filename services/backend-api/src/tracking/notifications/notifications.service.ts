import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import type { NotificationRule, Prisma, TrackingEvent } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type { NotificationQueryDto, NotificationRuleQueryDto } from '../common/tracking-query.dto';
import { jsonSafe } from '../common/tracking-json.util';
import type { CreateNotificationRuleDto } from './dto/create-notification-rule.dto';
import type { UpdateNotificationDeliveryDto } from './dto/update-notification-delivery.dto';
import type { UpdateNotificationRuleDto } from './dto/update-notification-rule.dto';

interface ResolvedRecipient {
  userId?: string;
  address: string;
}

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly auditService: AuditService,
  ) {}

  async listRules(auth: AuthContext, query: NotificationRuleQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.notificationRuleWhere(auth);
    const where: Prisma.NotificationRuleWhereInput = {
      AND: [
        scopeWhere,
        {
          archivedAt: null,
        },
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
        query.search
          ? {
              OR: [
                {
                  ruleCode: {
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
                  recipientAddress: {
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
      this.prisma.notificationRule.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          customer: true,
          vehicle: true,
          recipientUser: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
              mobileNumber: true,
              email: true,
            },
          },
          _count: {
            select: {
              notifications: true,
            },
          },
        },
      }),
      this.prisma.notificationRule.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async createRule(auth: AuthContext, dto: CreateNotificationRuleDto) {
    await this.access.assertCustomer(auth, dto.customerId);
    await this.assertVehicleCustomer(dto.customerId, dto.vehicleId);
    await this.assertRecipient({
      customerId: dto.customerId,
      recipientType: dto.recipientType,
      recipientUserId: dto.recipientUserId,
      recipientAddress: dto.recipientAddress,
    });
    this.assertQuietHours(dto.quietHoursStartMinute, dto.quietHoursEndMinute);

    const rule = await this.prisma.notificationRule.create({
      data: {
        ruleCode: this.codes.notificationRule(),
        customerId: dto.customerId,
        vehicleId: dto.vehicleId,
        eventType: dto.eventType.trim(),
        minimumSeverity: dto.minimumSeverity,
        channel: dto.channel,
        recipientType: dto.recipientType,
        recipientUserId: dto.recipientType === 'USER' ? dto.recipientUserId : null,
        recipientAddress:
          dto.recipientType === 'CUSTOM_ADDRESS' ? dto.recipientAddress?.trim() : null,
        enabled: dto.enabled ?? true,
        quietHoursStartMinute: dto.quietHoursStartMinute,
        quietHoursEndMinute: dto.quietHoursEndMinute,
        cooldownSeconds: dto.cooldownSeconds ?? 0,
        dailyLimit: dto.dailyLimit,
        createdByUserId: auth.userId,
      },
      include: {
        customer: true,
        vehicle: true,
        recipientUser: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.notification-rule.created',
      resourceType: 'NotificationRule',
      resourceId: rule.id,
      scopeType: 'CUSTOMER',
      scopeId: rule.customerId,
      afterData: jsonSafe(rule),
    });

    return jsonSafe(rule);
  }

  async updateRule(auth: AuthContext, ruleId: string, dto: UpdateNotificationRuleDto) {
    const before = await this.prisma.notificationRule.findFirst({
      where: {
        AND: [
          {
            id: ruleId,
            archivedAt: null,
          },
          this.access.notificationRuleWhere(auth),
        ],
      },
    });

    if (!before) {
      throw new NotFoundException(
        'Notification rule was not found within the authenticated scope.',
      );
    }

    const recipientType = dto.recipientType ?? before.recipientType;
    const recipientUserId = dto.recipientUserId ?? before.recipientUserId ?? undefined;
    const recipientAddress = dto.recipientAddress ?? before.recipientAddress ?? undefined;

    await this.assertVehicleCustomer(
      before.customerId,
      dto.vehicleId ?? before.vehicleId ?? undefined,
    );
    await this.assertRecipient({
      customerId: before.customerId,
      recipientType,
      recipientUserId,
      recipientAddress,
    });
    this.assertQuietHours(
      dto.quietHoursStartMinute ?? before.quietHoursStartMinute ?? undefined,
      dto.quietHoursEndMinute ?? before.quietHoursEndMinute ?? undefined,
    );

    const updated = await this.prisma.notificationRule.update({
      where: {
        id: ruleId,
      },
      data: {
        vehicleId: dto.vehicleId,
        eventType: dto.eventType?.trim(),
        minimumSeverity: dto.minimumSeverity,
        channel: dto.channel,
        recipientType: dto.recipientType,
        recipientUserId: recipientType === 'USER' ? recipientUserId : null,
        recipientAddress: recipientType === 'CUSTOM_ADDRESS' ? recipientAddress?.trim() : null,
        enabled: dto.enabled,
        quietHoursStartMinute: dto.quietHoursStartMinute,
        quietHoursEndMinute: dto.quietHoursEndMinute,
        cooldownSeconds: dto.cooldownSeconds,
        dailyLimit: dto.dailyLimit,
      },
      include: {
        customer: true,
        vehicle: true,
        recipientUser: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.notification-rule.updated',
      resourceType: 'NotificationRule',
      resourceId: ruleId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async archiveRule(auth: AuthContext, ruleId: string) {
    const before = await this.prisma.notificationRule.findFirst({
      where: {
        AND: [
          {
            id: ruleId,
            archivedAt: null,
          },
          this.access.notificationRuleWhere(auth),
        ],
      },
    });

    if (!before) {
      throw new NotFoundException(
        'Notification rule was not found within the authenticated scope.',
      );
    }

    const updated = await this.prisma.notificationRule.update({
      where: {
        id: ruleId,
      },
      data: {
        enabled: false,
        archivedAt: new Date(),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.notification-rule.archived',
      resourceType: 'NotificationRule',
      resourceId: ruleId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async listNotifications(auth: AuthContext, query: NotificationQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.notificationWhere(auth);
    const where: Prisma.NotificationWhereInput = {
      AND: [
        scopeWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.trackingEventId
          ? {
              trackingEventId: query.trackingEventId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  notificationCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  recipient: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  subject: {
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
      this.prisma.notification.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          queuedAt: 'desc',
        },
        include: {
          user: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
          trackingEvent: true,
          notificationRule: true,
        },
      }),
      this.prisma.notification.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async getNotification(auth: AuthContext, notificationId: string) {
    await this.access.assertNotification(auth, notificationId);

    const notification = await this.prisma.notification.findUnique({
      where: {
        id: notificationId,
      },
      include: {
        customer: true,
        user: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
            mobileNumber: true,
            email: true,
          },
        },
        trackingEvent: true,
        notificationRule: true,
      },
    });

    return jsonSafe(notification);
  }

  async updateDelivery(
    auth: AuthContext,
    notificationId: string,
    dto: UpdateNotificationDeliveryDto,
  ) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.notification.findUnique({
      where: {
        id: notificationId,
      },
    });

    if (!before) {
      throw new NotFoundException('Notification was not found.');
    }

    const now = new Date();
    const updated = await this.prisma.notification.update({
      where: {
        id: notificationId,
      },
      data: {
        status: dto.status,
        provider: dto.provider,
        providerMessageId: dto.providerMessageId,
        failureReason:
          dto.status === 'FAILED' ? (dto.failureReason ?? 'Provider delivery failed.') : null,
        processingAt: dto.status === 'PROCESSING' ? now : before.processingAt,
        sentAt:
          dto.status === 'SENT' || dto.status === 'DELIVERED'
            ? (before.sentAt ?? now)
            : before.sentAt,
        deliveredAt: dto.status === 'DELIVERED' ? now : before.deliveredAt,
        failedAt: dto.status === 'FAILED' ? now : before.failedAt,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.notification.delivery-updated',
      resourceType: 'Notification',
      resourceId: notificationId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async enqueueForEvent(event: TrackingEvent) {
    const rules = await this.prisma.notificationRule.findMany({
      where: {
        customerId: event.customerId,
        enabled: true,
        archivedAt: null,
        eventType: {
          in: [event.eventType, 'ANY'],
        },
        OR: [
          {
            vehicleId: null,
          },
          {
            vehicleId: event.vehicleId,
          },
        ],
      },
    });

    const created: unknown[] = [];

    for (const rule of rules) {
      if (!this.severityAllowed(event.severity, rule.minimumSeverity)) {
        continue;
      }

      if (this.inQuietHours(rule, event.occurredAt)) {
        continue;
      }

      if (!(await this.withinDeliveryLimits(rule))) {
        continue;
      }

      const recipients = await this.resolveRecipients(rule);

      for (const recipient of recipients) {
        const notification = await this.prisma.notification.create({
          data: {
            notificationCode: this.codes.notification(),
            customerId: event.customerId,
            userId: recipient.userId,
            trackingEventId: event.id,
            notificationRuleId: rule.id,
            channel: rule.channel,
            recipient: recipient.address,
            subject: `${event.eventType} alert`,
            renderedContent:
              `${event.eventType} was detected for vehicle ` +
              `${event.vehicleId} at ${event.occurredAt.toISOString()}.`,
            status: 'QUEUED',
          },
        });

        created.push(notification);
      }
    }

    return created;
  }

  private async assertVehicleCustomer(customerId: string, vehicleId?: string): Promise<void> {
    if (!vehicleId) {
      return;
    }

    const vehicle = await this.prisma.vehicle.findFirst({
      where: {
        id: vehicleId,
        customerId,
      },
      select: {
        id: true,
      },
    });

    if (!vehicle) {
      throw new BadRequestException(
        'Notification-rule vehicle must belong to the selected customer.',
      );
    }
  }

  private async assertRecipient(input: {
    customerId: string;
    recipientType: 'USER' | 'CUSTOMER_OWNER' | 'CUSTOMER_ADMIN' | 'CUSTOM_ADDRESS';
    recipientUserId?: string;
    recipientAddress?: string;
  }): Promise<void> {
    if (input.recipientType === 'USER') {
      if (!input.recipientUserId) {
        throw new BadRequestException('recipientUserId is required for USER recipients.');
      }

      const membership = await this.prisma.customerMembership.findFirst({
        where: {
          customerId: input.customerId,
          userId: input.recipientUserId,
          status: 'ACTIVE',
        },
        select: {
          id: true,
        },
      });

      if (!membership) {
        throw new BadRequestException('Recipient user must be an active customer member.');
      }
    }

    if (input.recipientType === 'CUSTOM_ADDRESS' && !input.recipientAddress?.trim()) {
      throw new BadRequestException('recipientAddress is required for CUSTOM_ADDRESS recipients.');
    }
  }

  private assertQuietHours(start?: number, end?: number): void {
    const oneProvided = (start === undefined) !== (end === undefined);

    if (oneProvided) {
      throw new BadRequestException('Both quiet-hours start and end must be provided together.');
    }
  }

  private severityAllowed(
    actual: 'INFO' | 'WARNING' | 'CRITICAL',
    minimum: 'INFO' | 'WARNING' | 'CRITICAL',
  ): boolean {
    const rank = {
      INFO: 1,
      WARNING: 2,
      CRITICAL: 3,
    } as const;

    return rank[actual] >= rank[minimum];
  }

  private inQuietHours(rule: NotificationRule, occurredAt: Date): boolean {
    if (rule.quietHoursStartMinute === null || rule.quietHoursEndMinute === null) {
      return false;
    }

    const minute = occurredAt.getUTCHours() * 60 + occurredAt.getUTCMinutes();
    const start = rule.quietHoursStartMinute;
    const end = rule.quietHoursEndMinute;

    if (start === end) {
      return true;
    }

    return start < end ? minute >= start && minute < end : minute >= start || minute < end;
  }

  private async withinDeliveryLimits(rule: NotificationRule): Promise<boolean> {
    const now = new Date();

    if (rule.cooldownSeconds > 0) {
      const recent = await this.prisma.notification.findFirst({
        where: {
          notificationRuleId: rule.id,
          queuedAt: {
            gte: new Date(now.getTime() - rule.cooldownSeconds * 1000),
          },
        },
        select: {
          id: true,
        },
      });

      if (recent) {
        return false;
      }
    }

    if (rule.dailyLimit !== null) {
      const startOfDay = new Date(now);
      startOfDay.setUTCHours(0, 0, 0, 0);

      const count = await this.prisma.notification.count({
        where: {
          notificationRuleId: rule.id,
          queuedAt: {
            gte: startOfDay,
          },
        },
      });

      if (count >= rule.dailyLimit) {
        return false;
      }
    }

    return true;
  }

  private async resolveRecipients(rule: NotificationRule): Promise<ResolvedRecipient[]> {
    if (rule.recipientType === 'CUSTOM_ADDRESS') {
      return rule.recipientAddress
        ? [
            {
              address: rule.recipientAddress,
            },
          ]
        : [];
    }

    if (rule.recipientType === 'USER') {
      if (!rule.recipientUserId) {
        return [];
      }

      const user = await this.prisma.user.findUnique({
        where: {
          id: rule.recipientUserId,
        },
        select: {
          id: true,
          mobileNumber: true,
          email: true,
        },
      });

      return user ? this.userRecipient(rule.channel, user) : [];
    }

    const roleCode = rule.recipientType === 'CUSTOMER_OWNER' ? 'CUSTOMER_OWNER' : 'CUSTOMER_ADMIN';

    const users = await this.prisma.user.findMany({
      where: {
        status: 'ACTIVE',
        roleAssignments: {
          some: {
            scopeType: 'CUSTOMER',
            scopeId: rule.customerId,
            status: 'ACTIVE',
            role: {
              code: roleCode,
            },
          },
        },
      },
      select: {
        id: true,
        mobileNumber: true,
        email: true,
      },
    });

    return users.flatMap((user) => this.userRecipient(rule.channel, user));
  }

  private userRecipient(
    channel: NotificationRule['channel'],
    user: {
      id: string;
      mobileNumber: string;
      email: string | null;
    },
  ): ResolvedRecipient[] {
    if (channel === 'EMAIL') {
      return user.email
        ? [
            {
              userId: user.id,
              address: user.email,
            },
          ]
        : [];
    }

    if (['SMS', 'WHATSAPP', 'VOICE_CALL'].includes(channel)) {
      return [
        {
          userId: user.id,
          address: user.mobileNumber,
        },
      ];
    }

    return [
      {
        userId: user.id,
        address: `user:${user.id}`,
      },
    ];
  }
}
