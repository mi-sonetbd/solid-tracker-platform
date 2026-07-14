import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import type { NotificationStatus } from '../../generated/prisma/client';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { NotificationProviderRegistryService } from '../adapters/notification-provider-registry.service';
import { NotificationDeliveryAccessService } from '../common/notification-access.service';
import { NotificationCodeService } from '../common/notification-code.service';
import { NotificationSignatureService } from '../common/notification-signature.service';
import type { EnqueueTemplateNotificationDto } from '../dto/enqueue-template-notification.dto';
import type { NotificationDeliveryQueryDto } from '../dto/notification-delivery-query.dto';
import type { NotificationProviderCallbackDto } from '../dto/notification-provider-callback.dto';
import type { RetryNotificationDto } from '../dto/retry-notification.dto';
import { NotificationTemplatesService } from '../templates/notification-templates.service';
import { NotificationDeliveryWorkerService } from './notification-delivery-worker.service';

@Injectable()
export class NotificationDeliveryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: NotificationDeliveryAccessService,
    private readonly codes: NotificationCodeService,
    private readonly templates: NotificationTemplatesService,
    private readonly worker: NotificationDeliveryWorkerService,
    private readonly registry: NotificationProviderRegistryService,
    private readonly signatures: NotificationSignatureService,
    private readonly audit: AuditService,
  ) {}

  async list(auth: AuthContext, query: NotificationDeliveryQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.NotificationWhereInput = {
      AND: [
        this.access.notificationWhere(auth),
        query.status
          ? {
              status: query.status as NotificationStatus,
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
                  providerMessageId: {
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
        orderBy: { queuedAt: 'desc' },
        include: {
          customer: {
            select: {
              id: true,
              customerCode: true,
              primaryMobile: true,
              individualProfile: {
                select: { fullName: true },
              },
              organizationProfile: {
                select: { displayName: true },
              },
            },
          },
          user: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
        },
      }),
      this.prisma.notification.count({ where }),
    ]);

    const latestAttempts = await this.prisma.notificationDeliveryAttempt.findMany({
      where: {
        notificationId: {
          in: items.map((item) => item.id),
        },
      },
      orderBy: [{ notificationId: 'asc' }, { attemptNumber: 'desc' }],
    });
    const latestByNotification = new Map<string, (typeof latestAttempts)[number]>();

    for (const attempt of latestAttempts) {
      if (!latestByNotification.has(attempt.notificationId)) {
        latestByNotification.set(attempt.notificationId, attempt);
      }
    }

    return {
      items: items.map((item) => ({
        ...item,
        latestAttempt: latestByNotification.get(item.id) ?? null,
      })),
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async enqueue(auth: AuthContext, dto: EnqueueTemplateNotificationDto) {
    await this.access.assertCustomer(auth, dto.customerId);

    if (dto.userId) {
      const membership = await this.prisma.customerMembership.findFirst({
        where: {
          customerId: dto.customerId,
          userId: dto.userId,
          status: 'ACTIVE',
        },
        select: { id: true },
      });

      if (!membership) {
        throw new BadRequestException('Notification user must be an active customer member.');
      }
    }

    const rendered = await this.templates.renderActive({
      templateKey: dto.templateKey,
      channel: dto.channel,
      locale: dto.locale ?? 'en',
      variables: dto.variables,
    });
    const notification = await this.prisma.notification.create({
      data: {
        notificationCode: this.codes.notification(),
        customerId: dto.customerId,
        userId: dto.userId,
        trackingEventId: dto.trackingEventId,
        notificationRuleId: dto.notificationRuleId,
        channel: dto.channel,
        recipient: dto.recipient.trim(),
        subject: rendered.subject,
        renderedContent: rendered.content,
        status: 'QUEUED',
      },
    });

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'notification.delivery.enqueued',
      resourceType: 'Notification',
      resourceId: notification.id,
      metadata: {
        templateId: rendered.templateId,
        channel: notification.channel,
        recipient: notification.recipient,
      },
    });

    return notification;
  }

  async attempts(auth: AuthContext, notificationId: string) {
    await this.access.assertNotification(auth, notificationId);

    return this.prisma.notificationDeliveryAttempt.findMany({
      where: { notificationId },
      orderBy: { attemptNumber: 'desc' },
    });
  }

  async retry(auth: AuthContext, notificationId: string, dto: RetryNotificationDto) {
    this.access.assertPlatform(auth);
    const notification = await this.prisma.notification.findUnique({
      where: { id: notificationId },
    });

    if (!notification) {
      throw new NotFoundException('Notification was not found.');
    }

    if (!['FAILED', 'CANCELLED'].includes(notification.status)) {
      throw new BadRequestException('Only failed or cancelled notifications can be retried.');
    }

    const updated = await this.prisma.notification.update({
      where: { id: notificationId },
      data: {
        status: 'QUEUED',
        queuedAt: new Date(),
        processingAt: null,
        failedAt: null,
        failureReason: 'MANUAL_RETRY',
      },
    });

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'notification.delivery.retry-requested',
      resourceType: 'Notification',
      resourceId: notificationId,
      metadata: { reason: dto.reason },
    });

    return updated;
  }

  async run(auth: AuthContext, batchSize?: number) {
    this.access.assertPlatform(auth);
    const result = await this.worker.runBatch(batchSize);

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'notification.delivery.batch-run',
      resourceType: 'NotificationDeliveryWorker',
      metadata: result,
    });

    return result;
  }

  async metrics(auth: AuthContext) {
    this.access.assertPlatform(auth);
    const [notificationCounts, attemptCounts, oldestQueued, providerEventFailures] =
      await Promise.all([
        this.prisma.notification.groupBy({
          by: ['status'],
          _count: { _all: true },
        }),
        this.prisma.notificationDeliveryAttempt.groupBy({
          by: ['status'],
          _count: { _all: true },
        }),
        this.prisma.notification.findFirst({
          where: { status: 'QUEUED' },
          orderBy: { queuedAt: 'asc' },
          select: { queuedAt: true },
        }),
        this.prisma.notificationProviderEvent.count({
          where: { status: 'FAILED' },
        }),
      ]);

    return {
      notifications: Object.fromEntries(
        notificationCounts.map((item) => [item.status, item._count._all]),
      ),
      attempts: Object.fromEntries(attemptCounts.map((item) => [item.status, item._count._all])),
      oldestQueuedAt: oldestQueued?.queuedAt ?? null,
      oldestQueuedAgeSeconds: oldestQueued
        ? Math.floor((Date.now() - oldestQueued.queuedAt.getTime()) / 1000)
        : 0,
      providerEventFailures,
      generatedAt: new Date(),
    };
  }

  async deadLetters(auth: AuthContext, query: NotificationDeliveryQueryDto) {
    this.access.assertPlatform(auth);
    const skip = (query.page - 1) * query.pageSize;
    const [attempts, total] = await Promise.all([
      this.prisma.notificationDeliveryAttempt.findMany({
        where: { status: 'DEAD_LETTER' },
        skip,
        take: query.pageSize,
        orderBy: { completedAt: 'desc' },
      }),
      this.prisma.notificationDeliveryAttempt.count({
        where: { status: 'DEAD_LETTER' },
      }),
    ]);
    const notifications = await this.prisma.notification.findMany({
      where: {
        id: {
          in: attempts.map((attempt) => attempt.notificationId),
        },
      },
    });
    const byId = new Map(notifications.map((item) => [item.id, item]));

    return {
      items: attempts.map((attempt) => ({
        attempt,
        notification: byId.get(attempt.notificationId) ?? null,
      })),
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async callback(input: {
    provider: string;
    timestamp?: string;
    eventId?: string;
    signature?: string;
    dto: NotificationProviderCallbackDto;
  }) {
    const provider = input.provider.toUpperCase();
    const secret = this.registry.callbackSecret(provider);

    if (input.eventId !== input.dto.externalEventId) {
      throw new BadRequestException('Callback event ID header does not match the payload.');
    }

    this.signatures.verify({
      secret,
      timestamp: input.timestamp,
      eventId: input.eventId,
      signature: input.signature,
      payload: input.dto,
    });

    try {
      await this.prisma.notificationProviderEvent.create({
        data: {
          provider,
          externalEventId: input.dto.externalEventId,
          providerMessageId: input.dto.providerMessageId,
          eventType: input.dto.status,
          status: 'RECEIVED',
          signatureValid: true,
          payload: JSON.parse(JSON.stringify(input.dto)) as Prisma.InputJsonValue,
        },
      });
    } catch (error: unknown) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return {
          accepted: true,
          idempotent: true,
          externalEventId: input.dto.externalEventId,
        };
      }

      throw error;
    }

    const attempt = await this.prisma.notificationDeliveryAttempt.findFirst({
      where: {
        provider,
        providerMessageId: input.dto.providerMessageId,
      },
      orderBy: { attemptNumber: 'desc' },
    });

    if (!attempt) {
      await this.prisma.notificationProviderEvent.update({
        where: {
          provider_externalEventId: {
            provider,
            externalEventId: input.dto.externalEventId,
          },
        },
        data: {
          status: 'FAILED',
          processedAt: new Date(),
          error: 'Delivery attempt was not found for provider message ID.',
        },
      });

      throw new NotFoundException('Delivery attempt was not found for the provider callback.');
    }

    const now = input.dto.occurredAt ? new Date(input.dto.occurredAt) : new Date();
    const notificationUpdate: Prisma.NotificationUpdateInput = {};

    if (input.dto.status === 'SENT') {
      notificationUpdate.status = 'SENT';
      notificationUpdate.sentAt = now;
      notificationUpdate.failureReason = null;
    } else if (input.dto.status === 'DELIVERED') {
      notificationUpdate.status = 'DELIVERED';
      notificationUpdate.sentAt = now;
      notificationUpdate.deliveredAt = now;
      notificationUpdate.failureReason = null;
    } else {
      notificationUpdate.status = 'FAILED';
      notificationUpdate.failedAt = now;
      notificationUpdate.failureReason =
        input.dto.errorMessage ?? 'Notification provider reported failure.';
    }

    await this.prisma.$transaction([
      this.prisma.notification.update({
        where: { id: attempt.notificationId },
        data: notificationUpdate,
      }),
      this.prisma.notificationDeliveryAttempt.update({
        where: { id: attempt.id },
        data: {
          status: input.dto.status,
          errorCode: input.dto.errorCode,
          errorMessage: input.dto.errorMessage,
          responsePayload: JSON.parse(JSON.stringify(input.dto)) as Prisma.InputJsonValue,
          completedAt: now,
        },
      }),
      this.prisma.notificationProviderEvent.update({
        where: {
          provider_externalEventId: {
            provider,
            externalEventId: input.dto.externalEventId,
          },
        },
        data: {
          notificationId: attempt.notificationId,
          status: 'PROCESSED',
          processedAt: new Date(),
        },
      }),
    ]);

    await this.audit.record({
      action: 'notification.delivery.callback-processed',
      resourceType: 'Notification',
      resourceId: attempt.notificationId,
      correlationId: input.dto.externalEventId,
      metadata: {
        provider,
        providerMessageId: input.dto.providerMessageId,
        status: input.dto.status,
      },
    });

    return {
      accepted: true,
      idempotent: false,
      notificationId: attempt.notificationId,
      status: input.dto.status,
    };
  }
}
