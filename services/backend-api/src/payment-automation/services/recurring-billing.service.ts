import {
  ConflictException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../../billing/common/billing-access.service';
import { BillingDateService } from '../../billing/common/billing-date.service';
import { InvoicesService } from '../../billing/invoices/invoices.service';
import { AutomationIdentityService } from '../common/automation-identity.service';
import { AutomationRunKeyService } from '../common/automation-run-key.service';
import { GatewaySignatureService } from '../common/gateway-signature.service';
import type { RunBillingAutomationDto } from '../dto/run-billing-automation.dto';

@Injectable()
export class RecurringBillingService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RecurringBillingService.name);
  private readonly enabled: boolean;
  private readonly intervalMs: number;
  private readonly defaultBatchSize: number;
  private readonly defaultDueInDays: number;
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly dates: BillingDateService,
    private readonly invoices: InvoicesService,
    private readonly identity: AutomationIdentityService,
    private readonly runKeys: AutomationRunKeyService,
    private readonly signatures: GatewaySignatureService,
    private readonly auditService: AuditService,
    configService: ConfigService,
  ) {
    this.enabled = this.boolean(configService.get('PAYMENT_AUTOMATION_ENABLED', false));
    this.intervalMs = Math.max(
      configService.get<number>('PAYMENT_AUTOMATION_INTERVAL_MS', 60000),
      60000,
    );
    this.defaultBatchSize = configService.get<number>('PAYMENT_AUTOMATION_BATCH_SIZE', 50);
    this.defaultDueInDays = configService.get<number>('PAYMENT_AUTOMATION_DUE_IN_DAYS', 7);
  }

  onModuleInit(): void {
    if (!this.enabled) {
      return;
    }

    this.timer = setInterval(() => {
      void this.runScheduled();
    }, this.intervalMs);

    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  async run(auth: AuthContext, dto: RunBillingAutomationDto) {
    this.access.assertPlatform(auth);

    return this.execute(auth, {
      asOf: dto.asOf ? new Date(dto.asOf) : new Date(),
      dueInDays: dto.dueInDays,
      batchSize: dto.batchSize,
      dryRun: dto.dryRun,
      source: 'MANUAL',
    });
  }

  async status() {
    const recentRuns = await this.prisma.paymentGatewayEvent.findMany({
      where: {
        gateway: 'OTHER',
        eventType: 'BILLING_AUTOMATION_RUN',
      },
      orderBy: {
        receivedAt: 'desc',
      },
      take: 10,
    });

    const dueSubscriptions = await this.prisma.subscription.count({
      where: {
        autoRenew: true,
        status: {
          in: ['TRIALING', 'ACTIVE', 'PAST_DUE'],
        },
        nextBillingAt: {
          lte: new Date(),
        },
      },
    });

    return {
      enabled: this.enabled,
      intervalMs: this.intervalMs,
      defaultBatchSize: this.defaultBatchSize,
      defaultDueInDays: this.defaultDueInDays,
      dueSubscriptions,
      recentRuns,
    };
  }

  private async runScheduled(): Promise<void> {
    try {
      const auth = await this.identity.platformAuth();

      await this.execute(auth, {
        asOf: new Date(),
        dueInDays: this.defaultDueInDays,
        batchSize: this.defaultBatchSize,
        dryRun: false,
        source: 'SCHEDULED',
      });
    } catch (error) {
      this.logger.error(
        error instanceof Error ? error.message : 'Unknown scheduled billing error.',
      );
    }
  }

  private async execute(
    auth: AuthContext,
    input: {
      asOf: Date;
      dueInDays: number;
      batchSize: number;
      dryRun: boolean;
      source: 'MANUAL' | 'SCHEDULED';
    },
  ) {
    const dueSubscriptions = await this.prisma.subscription.findMany({
      where: {
        autoRenew: true,
        status: {
          in: ['TRIALING', 'ACTIVE', 'PAST_DUE'],
        },
        nextBillingAt: {
          lte: input.asOf,
        },
      },
      orderBy: {
        nextBillingAt: 'asc',
      },
      take: input.batchSize,
      include: {
        servicePlan: true,
      },
    });

    if (input.dryRun) {
      return {
        dryRun: true,
        asOf: input.asOf,
        dueSubscriptionIds: dueSubscriptions.map((subscription) => subscription.id),
      };
    }

    const runKey = this.runKeys.key(input.asOf, this.intervalMs);
    const runPayload: Prisma.InputJsonValue = {
      source: input.source,
      asOf: input.asOf.toISOString(),
      dueInDays: input.dueInDays,
      batchSize: input.batchSize,
    };

    let runEvent;

    try {
      runEvent = await this.prisma.paymentGatewayEvent.create({
        data: {
          gateway: 'OTHER',
          externalEventId: runKey,
          eventType: 'BILLING_AUTOMATION_RUN',
          payload: runPayload,
          payloadHash: this.signatures.hash(runPayload),
          status: 'PROCESSING',
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return {
          idempotent: true,
          runKey,
          message: 'This billing automation interval has already been claimed.',
        };
      }

      throw error;
    }

    const results: Array<Record<string, unknown>> = [];

    try {
      for (const subscription of dueSubscriptions) {
        try {
          results.push(await this.processSubscription(auth, subscription.id, input.dueInDays));
        } catch (error) {
          results.push({
            subscriptionId: subscription.id,
            status: 'FAILED',
            error: error instanceof Error ? error.message : 'Unknown subscription billing error.',
          });
        }
      }

      const overdue = await this.markOverdueInvoices(input.asOf);
      const summary = {
        runKey,
        processed: results.length,
        succeeded: results.filter((item) => item.status === 'SUCCEEDED').length,
        failed: results.filter((item) => item.status === 'FAILED').length,
        overdueInvoices: overdue.invoiceCount,
        pastDueSubscriptions: overdue.subscriptionCount,
        results,
      };

      await this.prisma.paymentGatewayEvent.update({
        where: {
          id: runEvent.id,
        },
        data: {
          status: 'PROCESSED',
          processedAt: new Date(),
          payload: JSON.parse(
            JSON.stringify({
              ...this.record(runPayload),
              summary,
            }),
          ) as Prisma.InputJsonValue,
        },
      });

      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId: this.access.actorOrganizationId(auth),
        action: 'billing-automation.completed',
        resourceType: 'BillingAutomationRun',
        resourceId: runEvent.id,
        scopeType: 'PLATFORM',
        afterData: summary,
      });

      return summary;
    } catch (error) {
      await this.prisma.paymentGatewayEvent.update({
        where: {
          id: runEvent.id,
        },
        data: {
          status: 'FAILED',
          errorMessage:
            error instanceof Error ? error.message : 'Unknown billing automation error.',
        },
      });

      throw error;
    }
  }

  private async processSubscription(
    auth: AuthContext,
    subscriptionId: string,
    dueInDays: number,
  ): Promise<Record<string, unknown>> {
    const subscription = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
      include: {
        servicePlan: true,
      },
    });

    if (!subscription) {
      throw new ConflictException('Subscription disappeared during billing.');
    }

    const periodStart = subscription.currentPeriodStart ?? subscription.nextBillingAt ?? new Date();
    const periodEnd =
      subscription.currentPeriodEnd ??
      this.dates.addInterval(
        periodStart,
        subscription.servicePlan.billingIntervalUnit,
        subscription.servicePlan.billingIntervalCount,
      );

    let invoice = await this.prisma.invoice.findFirst({
      where: {
        subscriptionId,
        billingPeriodStart: periodStart,
        billingPeriodEnd: periodEnd,
        status: {
          not: 'VOID',
        },
      },
    });

    if (!invoice) {
      invoice = await this.invoices.createFromSubscription(auth, subscriptionId, dueInDays);
    }

    if (invoice.status === 'DRAFT') {
      invoice = await this.invoices.issue(auth, invoice.id, {});
    }

    const nextPeriodStart = periodEnd;
    const nextPeriodEnd = this.dates.addInterval(
      nextPeriodStart,
      subscription.servicePlan.billingIntervalUnit,
      subscription.servicePlan.billingIntervalCount,
    );

    const updatedSubscription = await this.prisma.subscription.update({
      where: {
        id: subscription.id,
      },
      data: {
        status: 'ACTIVE',
        currentPeriodStart: nextPeriodStart,
        currentPeriodEnd: nextPeriodEnd,
        nextBillingAt: nextPeriodEnd,
        trialEndsAt: null,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'subscription.period-advanced',
      resourceType: 'Subscription',
      resourceId: subscription.id,
      scopeType: 'CUSTOMER',
      scopeId: subscription.customerId,
      beforeData: subscription,
      afterData: updatedSubscription,
      metadata: {
        invoiceId: invoice.id,
      },
    });

    return {
      subscriptionId: subscription.id,
      invoiceId: invoice.id,
      invoiceNumber: invoice.invoiceNumber,
      status: 'SUCCEEDED',
      nextBillingAt: updatedSubscription.nextBillingAt,
    };
  }

  private async markOverdueInvoices(asOf: Date): Promise<{
    invoiceCount: number;
    subscriptionCount: number;
  }> {
    const dateBoundary = new Date(
      Date.UTC(asOf.getUTCFullYear(), asOf.getUTCMonth(), asOf.getUTCDate()),
    );
    const overdueInvoices = await this.prisma.invoice.findMany({
      where: {
        dueDate: {
          lt: dateBoundary,
        },
        status: {
          in: ['ISSUED', 'PARTIALLY_PAID'],
        },
      },
      select: {
        id: true,
        subscriptionId: true,
      },
    });

    if (overdueInvoices.length === 0) {
      return {
        invoiceCount: 0,
        subscriptionCount: 0,
      };
    }

    await this.prisma.invoice.updateMany({
      where: {
        id: {
          in: overdueInvoices.map((invoice) => invoice.id),
        },
      },
      data: {
        status: 'OVERDUE',
      },
    });

    const subscriptionIds = Array.from(
      new Set(
        overdueInvoices
          .map((invoice) => invoice.subscriptionId)
          .filter((value): value is string => Boolean(value)),
      ),
    );

    if (subscriptionIds.length > 0) {
      await this.prisma.subscription.updateMany({
        where: {
          id: {
            in: subscriptionIds,
          },
          status: 'ACTIVE',
        },
        data: {
          status: 'PAST_DUE',
        },
      });
    }

    return {
      invoiceCount: overdueInvoices.length,
      subscriptionCount: subscriptionIds.length,
    };
  }

  private boolean(value: unknown): boolean {
    return value === true || String(value).toLowerCase() === 'true';
  }

  private record(value: unknown): Record<string, unknown> {
    return value !== null && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }
}
