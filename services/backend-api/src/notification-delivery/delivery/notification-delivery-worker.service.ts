import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { NotificationDeliveryAttempt, Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import { NotificationProviderRegistryService } from '../adapters/notification-provider-registry.service';
import { NotificationRateLimiterService } from '../common/notification-rate-limiter.service';

@Injectable()
export class NotificationDeliveryWorkerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(NotificationDeliveryWorkerService.name);
  private readonly enabled: boolean;
  private readonly intervalMilliseconds: number;
  private readonly defaultBatchSize: number;
  private readonly maxAttempts: number;
  private readonly retryBaseMilliseconds: number;
  private readonly callbackBaseUrl: string;
  private interval?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly registry: NotificationProviderRegistryService,
    private readonly rateLimiter: NotificationRateLimiterService,
    private readonly audit: AuditService,
  ) {
    this.enabled =
      String(this.config.get('NOTIFICATION_DELIVERY_ENABLED', 'false')).toLowerCase() === 'true';
    this.intervalMilliseconds = Number(this.config.get('NOTIFICATION_DELIVERY_INTERVAL_MS', 5000));
    this.defaultBatchSize = Number(this.config.get('NOTIFICATION_DELIVERY_BATCH_SIZE', 25));
    this.maxAttempts = Number(this.config.get('NOTIFICATION_DELIVERY_MAX_ATTEMPTS', 5));
    this.retryBaseMilliseconds = Number(
      this.config.get('NOTIFICATION_DELIVERY_RETRY_BASE_MS', 30000),
    );
    this.callbackBaseUrl = this.config.getOrThrow<string>('NOTIFICATION_CALLBACK_BASE_URL');
  }

  onModuleInit(): void {
    if (!this.enabled) {
      return;
    }

    this.interval = setInterval(() => {
      void this.runBatch().catch((error: unknown) => {
        this.logger.error(
          'Notification delivery interval failed.',
          error instanceof Error ? error.stack : String(error),
        );
      });
    }, this.intervalMilliseconds);
    this.interval.unref();
  }

  onModuleDestroy(): void {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }

  async runBatch(requestedBatchSize?: number): Promise<{
    claimed: number;
    succeeded: number;
    failed: number;
    deadLettered: number;
    skipped: number;
  }> {
    const batchSize = Math.min(Math.max(requestedBatchSize ?? this.defaultBatchSize, 1), 200);
    const lockKey = 'solid-tracker:notification-delivery:worker';
    const lockToken = await this.rateLimiter.acquireLock(
      lockKey,
      Math.max(this.intervalMilliseconds * 2, 30000),
    );

    if (!lockToken) {
      return {
        claimed: 0,
        succeeded: 0,
        failed: 0,
        deadLettered: 0,
        skipped: 1,
      };
    }

    try {
      await this.recoverStaleProcessing();

      const queued = await this.prisma.notification.findMany({
        where: { status: 'QUEUED' },
        select: { id: true },
        orderBy: { queuedAt: 'asc' },
        take: batchSize,
      });
      const remaining = Math.max(batchSize - queued.length, 0);
      const dueAttempts =
        remaining > 0
          ? await this.prisma.notificationDeliveryAttempt.findMany({
              where: {
                status: 'FAILED',
                nextRetryAt: { lte: new Date() },
                notificationId: {
                  notIn: queued.map((item) => item.id),
                },
              },
              select: { notificationId: true },
              orderBy: { nextRetryAt: 'asc' },
              take: remaining * 3,
            })
          : [];
      const ids = Array.from(
        new Set([
          ...queued.map((item) => item.id),
          ...dueAttempts.map((item) => item.notificationId),
        ]),
      ).slice(0, batchSize);
      const summary = {
        claimed: 0,
        succeeded: 0,
        failed: 0,
        deadLettered: 0,
        skipped: 0,
      };

      for (const notificationId of ids) {
        const result = await this.processNotification(notificationId);

        if (result === 'SKIPPED') {
          summary.skipped += 1;
          continue;
        }

        summary.claimed += 1;

        if (result === 'SUCCEEDED') {
          summary.succeeded += 1;
        } else if (result === 'DEAD_LETTER') {
          summary.deadLettered += 1;
        } else {
          summary.failed += 1;
        }
      }

      return summary;
    } finally {
      await this.rateLimiter.releaseLock(lockKey, lockToken);
    }
  }

  private async processNotification(
    notificationId: string,
  ): Promise<'SUCCEEDED' | 'FAILED' | 'DEAD_LETTER' | 'SKIPPED'> {
    const notification = await this.prisma.notification.findUnique({
      where: { id: notificationId },
    });

    if (!notification || !['QUEUED', 'FAILED'].includes(notification.status)) {
      return 'SKIPPED';
    }

    const manualRetry = notification.failureReason === 'MANUAL_RETRY';
    const previousAttemptCount = await this.prisma.notificationDeliveryAttempt.count({
      where: { notificationId },
    });

    if (previousAttemptCount >= this.maxAttempts && !manualRetry) {
      await this.prisma.notification.update({
        where: { id: notificationId },
        data: {
          status: 'FAILED',
          failedAt: new Date(),
          failureReason: 'DEAD_LETTER: maximum delivery attempts reached.',
        },
      });

      return 'DEAD_LETTER';
    }

    const claimed = await this.prisma.notification.updateMany({
      where: {
        id: notificationId,
        status: notification.status,
      },
      data: {
        status: 'PROCESSING',
        processingAt: new Date(),
        failureReason: null,
      },
    });

    if (claimed.count !== 1) {
      return 'SKIPPED';
    }

    const attemptNumber = previousAttemptCount + 1;
    const provider = this.registry.providerFor(notification.channel);
    const idempotencyKey = `${notification.id}:${attemptNumber}`;
    let attempt: NotificationDeliveryAttempt | undefined;

    try {
      const allowed = await this.rateLimiter.consume({
        key: `solid-tracker:notification-rate:${provider}:` + notification.channel,
        limit: 120,
        windowSeconds: 60,
      });

      if (!allowed) {
        throw new Error('Notification provider rate limit was exceeded.');
      }

      attempt = await this.prisma.notificationDeliveryAttempt.create({
        data: {
          notificationId: notification.id,
          attemptNumber,
          provider,
          idempotencyKey,
          status: 'PROCESSING',
          requestPayload: this.json({
            channel: notification.channel,
            recipient: notification.recipient,
            subject: notification.subject,
          }),
        },
      });

      const result = await this.registry.send({
        notificationId: notification.id,
        idempotencyKey,
        channel: notification.channel,
        recipient: notification.recipient,
        subject: notification.subject,
        content: notification.renderedContent,
        callbackUrl: `${this.callbackBaseUrl}/` + encodeURIComponent(provider.toLowerCase()),
      });
      const now = new Date();

      await this.prisma.$transaction([
        this.prisma.notificationDeliveryAttempt.update({
          where: { id: attempt.id },
          data: {
            provider: result.provider,
            providerMessageId: result.providerMessageId,
            status: result.status === 'DELIVERED' ? 'DELIVERED' : 'SENT',
            responsePayload: result.responsePayload,
            completedAt: now,
          },
        }),
        this.prisma.notification.update({
          where: { id: notification.id },
          data: {
            provider: result.provider,
            providerMessageId: result.providerMessageId,
            status: result.status,
            sentAt: now,
            deliveredAt: result.status === 'DELIVERED' ? now : null,
            failedAt: null,
            failureReason: null,
          },
        }),
      ]);

      await this.audit.record({
        action: 'notification.delivery.sent',
        resourceType: 'Notification',
        resourceId: notification.id,
        correlationId: idempotencyKey,
        metadata: {
          attemptNumber,
          provider: result.provider,
          providerMessageId: result.providerMessageId,
          status: result.status,
        },
      });

      return 'SUCCEEDED';
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : String(error);
      const deadLetter = attemptNumber >= this.maxAttempts;
      const nextRetryAt = deadLetter ? null : new Date(Date.now() + this.retryDelay(attemptNumber));

      if (!attempt) {
        await this.prisma.notificationDeliveryAttempt.create({
          data: {
            notificationId: notification.id,
            attemptNumber,
            provider,
            idempotencyKey,
            status: deadLetter ? 'DEAD_LETTER' : 'FAILED',
            errorMessage: message,
            nextRetryAt,
            completedAt: new Date(),
          },
        });
      } else {
        await this.prisma.notificationDeliveryAttempt.update({
          where: { id: attempt.id },
          data: {
            status: deadLetter ? 'DEAD_LETTER' : 'FAILED',
            errorMessage: message,
            nextRetryAt,
            completedAt: new Date(),
          },
        });
      }

      await this.prisma.notification.update({
        where: { id: notification.id },
        data: {
          status: 'FAILED',
          failedAt: new Date(),
          failureReason: deadLetter ? `DEAD_LETTER: ${message}` : message,
        },
      });

      await this.audit.record({
        action: deadLetter ? 'notification.delivery.dead-lettered' : 'notification.delivery.failed',
        resourceType: 'Notification',
        resourceId: notification.id,
        correlationId: idempotencyKey,
        metadata: {
          attemptNumber,
          provider,
          error: message,
          nextRetryAt: nextRetryAt?.toISOString() ?? null,
        },
      });

      return deadLetter ? 'DEAD_LETTER' : 'FAILED';
    }
  }

  private async recoverStaleProcessing(): Promise<void> {
    const staleBefore = new Date(
      Date.now() - Math.max(this.intervalMilliseconds * 4, 5 * 60 * 1000),
    );
    const stale = await this.prisma.notification.findMany({
      where: {
        status: 'PROCESSING',
        processingAt: { lt: staleBefore },
      },
      select: { id: true },
      take: 100,
    });

    if (stale.length === 0) {
      return;
    }

    const ids = stale.map((item) => item.id);
    const now = new Date();

    await this.prisma.$transaction([
      this.prisma.notification.updateMany({
        where: { id: { in: ids } },
        data: {
          status: 'FAILED',
          failedAt: now,
          failureReason: 'Delivery processing lease expired.',
        },
      }),
      this.prisma.notificationDeliveryAttempt.updateMany({
        where: {
          notificationId: { in: ids },
          status: 'PROCESSING',
        },
        data: {
          status: 'FAILED',
          errorMessage: 'Delivery processing lease expired.',
          nextRetryAt: now,
          completedAt: now,
        },
      }),
    ]);
  }

  private retryDelay(attemptNumber: number): number {
    const exponent = Math.max(attemptNumber - 1, 0);
    const base = this.retryBaseMilliseconds * 2 ** exponent;
    const capped = Math.min(base, 24 * 60 * 60 * 1000);
    const jitter = Math.floor(capped * 0.1);

    return capped + Math.floor(Math.random() * Math.max(jitter, 1));
  }

  private json(value: unknown): Prisma.InputJsonValue {
    return JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
  }
}
