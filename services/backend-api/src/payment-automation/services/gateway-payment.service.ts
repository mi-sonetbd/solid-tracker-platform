import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PaymentGateway, Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../../billing/common/billing-access.service';
import { PaymentsService } from '../../billing/payments/payments.service';
import { GatewayRegistryService } from '../adapters/gateway-registry.service';
import { AutomationIdentityService } from '../common/automation-identity.service';
import { GatewaySignatureService } from '../common/gateway-signature.service';
import type {
  AutomatedPaymentGateway,
  GatewayResult,
  GatewayWebhookHeaders,
} from '../common/gateway-types';
import type { InitializeGatewayPaymentDto } from '../dto/initialize-gateway-payment.dto';

const payableInvoiceStatuses = ['ISSUED', 'PARTIALLY_PAID', 'OVERDUE'] as const;

@Injectable()
export class GatewayPaymentService {
  private readonly callbackBaseUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly payments: PaymentsService,
    private readonly registry: GatewayRegistryService,
    private readonly identity: AutomationIdentityService,
    private readonly signatures: GatewaySignatureService,
    private readonly auditService: AuditService,
    configService: ConfigService,
  ) {
    this.callbackBaseUrl = (
      configService.get<string>('PAYMENT_CALLBACK_BASE_URL') ??
      'http://localhost:3000/api/v1/payment-gateways/webhooks'
    ).replace(/\/+$/, '');
  }

  async initialize(auth: AuthContext, paymentId: string, dto: InitializeGatewayPaymentDto) {
    await this.access.assertPayment(auth, paymentId);

    const payment = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
          },
        },
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment was not found.');
    }

    if (!['INITIATED', 'PENDING'].includes(payment.status)) {
      throw new ConflictException('Only initiated or pending payments can be initialized.');
    }

    const gateway = this.automationGateway(payment.paymentGateway);
    const adapter = this.registry.get(gateway);

    const invoice = await this.prisma.invoice.findUnique({
      where: {
        id: dto.invoiceId,
      },
    });

    if (!invoice || invoice.customerId !== payment.customerId) {
      throw new BadRequestException('Gateway invoice must belong to the payment customer.');
    }

    if (invoice.currency !== payment.currency) {
      throw new BadRequestException('Gateway payment and invoice currencies must match.');
    }

    if (
      !payableInvoiceStatuses.includes(invoice.status as (typeof payableInvoiceStatuses)[number])
    ) {
      throw new ConflictException('Gateway payment requires a payable invoice.');
    }

    if (payment.amount.gt(invoice.outstandingAmount)) {
      throw new BadRequestException('Payment amount exceeds the invoice outstanding amount.');
    }

    const customerName =
      payment.customer.individualProfile?.fullName ??
      payment.customer.organizationProfile?.displayName ??
      payment.customer.customerCode;

    const callbackUrl = `${this.callbackBaseUrl}/${gateway}`;

    const initiation = await adapter.initialize({
      paymentId: payment.id,
      paymentNumber: payment.paymentNumber,
      gateway,
      amount: payment.amount.toString(),
      currency: payment.currency,
      customerName,
      customerMobile: payment.customer.primaryMobile ?? undefined,
      customerEmail: payment.customer.primaryEmail ?? undefined,
      invoiceId: invoice.id,
      invoiceNumber: invoice.invoiceNumber,
      callbackUrl,
      successUrl: dto.successUrl,
      cancelUrl: dto.cancelUrl,
      failureUrl: dto.failureUrl,
    });

    const existingMetadata = this.record(payment.metadata);
    const metadata = JSON.parse(
      JSON.stringify({
        ...existingMetadata,
        gatewayAutomation: {
          invoiceId: invoice.id,
          invoiceNumber: invoice.invoiceNumber,
          customerReference: dto.customerReference ?? null,
          callbackUrl,
          initializedAt: new Date().toISOString(),
          initiation: initiation.raw,
        },
      }),
    ) as Prisma.InputJsonValue;

    const updated = await this.prisma.payment.update({
      where: {
        id: payment.id,
      },
      data: {
        status: 'PENDING',
        gatewayReference: initiation.gatewayReference,
        gatewayTransactionId: initiation.gatewayTransactionId,
        metadata,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment-gateway.initialized',
      resourceType: 'Payment',
      resourceId: payment.id,
      scopeType: 'CUSTOMER',
      scopeId: payment.customerId,
      beforeData: payment,
      afterData: updated,
      metadata: {
        gateway,
        invoiceId: invoice.id,
        redirectUrlConfigured: Boolean(initiation.redirectUrl),
      },
    });

    return {
      payment: updated,
      gateway,
      gatewayReference: initiation.gatewayReference,
      gatewayTransactionId: initiation.gatewayTransactionId,
      redirectUrl: initiation.redirectUrl,
    };
  }

  async webhook(
    gatewayValue: string,
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ) {
    const gateway = this.gateway(gatewayValue);
    const adapter = this.registry.get(gateway);
    const verified = await adapter.verifyWebhook(headers, payload);

    if (!verified) {
      throw new UnauthorizedException('Payment gateway callback verification failed.');
    }

    const result = await adapter.parseWebhook(headers, payload);

    return this.processResult(gateway, result, payload);
  }

  async reconcile(auth: AuthContext, paymentId: string) {
    this.access.assertPlatform(auth);

    const payment = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment was not found.');
    }

    const gateway = this.automationGateway(payment.paymentGateway);
    const adapter = this.registry.get(gateway);
    const result = await adapter.query(payment);

    return this.processResult(
      gateway,
      result,
      result.raw,
      `reconcile:${payment.id}:${result.externalEventId}`,
    );
  }

  async retryEvent(auth: AuthContext, eventId: string) {
    this.access.assertPlatform(auth);

    const event = await this.prisma.paymentGatewayEvent.findUnique({
      where: {
        id: eventId,
      },
    });

    if (!event) {
      throw new NotFoundException('Payment gateway event was not found.');
    }

    if (event.status !== 'FAILED') {
      throw new ConflictException('Only failed gateway events can be retried.');
    }

    const payload = this.record(event.payload);
    const gateway = this.automationGateway(event.gateway);
    const adapter = this.registry.get(gateway);
    const result = await adapter.parseWebhook(
      {
        eventId: event.externalEventId,
      },
      payload,
    );

    await this.prisma.paymentGatewayEvent.update({
      where: {
        id: event.id,
      },
      data: {
        status: 'RECEIVED',
        errorMessage: null,
        processedAt: null,
      },
    });

    return this.processExistingEvent(event.id, gateway, result);
  }

  private async processResult(
    gateway: AutomatedPaymentGateway,
    result: GatewayResult,
    payload: Record<string, unknown>,
    externalEventId = result.externalEventId,
  ) {
    const systemAuth = await this.identity.platformAuth();
    const event = await this.payments.gatewayEvent(systemAuth, {
      gateway,
      externalEventId,
      eventType: result.eventType,
      payload,
    });

    if (['PROCESSED', 'IGNORED'].includes(event.status)) {
      return {
        event,
        idempotent: true,
      };
    }

    return this.processExistingEvent(event.id, gateway, result);
  }

  private async processExistingEvent(
    eventId: string,
    gateway: AutomatedPaymentGateway,
    result: GatewayResult,
  ) {
    const claim = await this.prisma.paymentGatewayEvent.updateMany({
      where: {
        id: eventId,
        status: {
          in: ['RECEIVED', 'FAILED'],
        },
      },
      data: {
        status: 'PROCESSING',
        errorMessage: null,
      },
    });

    if (claim.count === 0) {
      return {
        event: await this.prisma.paymentGatewayEvent.findUnique({
          where: {
            id: eventId,
          },
        }),
        idempotent: true,
      };
    }

    try {
      const payment = await this.findPayment(gateway, result);

      if (!payment) {
        const ignored = await this.prisma.paymentGatewayEvent.update({
          where: {
            id: eventId,
          },
          data: {
            status: 'IGNORED',
            processedAt: new Date(),
            errorMessage: 'No matching payment was found.',
          },
        });

        return {
          event: ignored,
          payment: null,
        };
      }

      await this.validateResult(payment, result);
      const systemAuth = await this.identity.platformAuth();

      if (result.status === 'SUCCEEDED') {
        if (!['SUCCEEDED', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(payment.status)) {
          const invoiceId = await this.resolveInvoiceId(payment);
          await this.payments.confirm(systemAuth, payment.id, {
            gatewayTransactionId: result.gatewayTransactionId,
            gatewayReference: result.gatewayReference ?? result.paymentReference,
            allocations: [
              {
                invoiceId,
                amount: payment.amount.toString(),
              },
            ],
          });
        }
      } else if (result.status === 'FAILED' || result.status === 'CANCELLED') {
        if (['INITIATED', 'PENDING'].includes(payment.status)) {
          await this.payments.fail(systemAuth, payment.id, {
            reason: result.failureReason ?? `Gateway reported ${result.status}.`,
          });
        }
      }

      const processed = await this.prisma.paymentGatewayEvent.update({
        where: {
          id: eventId,
        },
        data: {
          paymentId: payment.id,
          status: 'PROCESSED',
          processedAt: new Date(),
          errorMessage: null,
        },
      });

      return {
        event: processed,
        payment: await this.prisma.payment.findUnique({
          where: {
            id: payment.id,
          },
          include: {
            allocations: true,
            refunds: true,
            commissionEntries: true,
          },
        }),
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown gateway processing error.';

      await this.prisma.paymentGatewayEvent.update({
        where: {
          id: eventId,
        },
        data: {
          status: 'FAILED',
          errorMessage: message,
        },
      });

      throw error;
    }
  }

  private async findPayment(gateway: PaymentGateway, result: GatewayResult) {
    const conditions: Prisma.PaymentWhereInput[] = [
      {
        paymentNumber: result.paymentReference,
      },
      {
        gatewayReference: result.paymentReference,
      },
    ];

    if (result.gatewayReference) {
      conditions.push({
        gatewayReference: result.gatewayReference,
      });
    }

    if (result.gatewayTransactionId) {
      conditions.push({
        gatewayTransactionId: result.gatewayTransactionId,
      });
    }

    return this.prisma.payment.findFirst({
      where: {
        paymentGateway: gateway,
        OR: conditions,
      },
    });
  }

  private async validateResult(
    payment: {
      amount: Prisma.Decimal;
      currency: string;
    },
    result: GatewayResult,
  ): Promise<void> {
    if (result.currency && result.currency.toUpperCase() !== payment.currency.toUpperCase()) {
      throw new BadRequestException('Gateway callback currency does not match the payment.');
    }

    if (result.amount && !new Prisma.Decimal(result.amount).eq(payment.amount)) {
      throw new BadRequestException('Gateway callback amount does not match the payment.');
    }
  }

  private async resolveInvoiceId(payment: {
    id: string;
    customerId: string;
    amount: Prisma.Decimal;
    currency: string;
    metadata: Prisma.JsonValue | null;
  }): Promise<string> {
    const metadata = this.record(payment.metadata);
    const automation = this.record(metadata.gatewayAutomation);
    const configuredInvoiceId =
      typeof automation.invoiceId === 'string' ? automation.invoiceId : undefined;

    if (configuredInvoiceId) {
      const invoice = await this.prisma.invoice.findFirst({
        where: {
          id: configuredInvoiceId,
          customerId: payment.customerId,
          currency: payment.currency,
          status: {
            in: [...payableInvoiceStatuses],
          },
        },
      });

      if (invoice && payment.amount.lte(invoice.outstandingAmount)) {
        return invoice.id;
      }
    }

    const fallback = await this.prisma.invoice.findFirst({
      where: {
        customerId: payment.customerId,
        currency: payment.currency,
        status: {
          in: [...payableInvoiceStatuses],
        },
        outstandingAmount: {
          gte: payment.amount,
        },
      },
      orderBy: [
        {
          dueDate: 'asc',
        },
        {
          createdAt: 'asc',
        },
      ],
    });

    if (!fallback) {
      throw new BadRequestException('No payable invoice can receive this payment.');
    }

    return fallback.id;
  }

  private automationGateway(gateway: PaymentGateway): AutomatedPaymentGateway {
    return this.gateway(gateway);
  }

  private gateway(value: string): AutomatedPaymentGateway {
    const normalized = value.trim().toUpperCase();

    if (!['OTHER', 'BKASH', 'NAGAD', 'SSLCOMMERZ'].includes(normalized)) {
      throw new BadRequestException('Unsupported payment gateway callback.');
    }

    return normalized as AutomatedPaymentGateway;
  }

  private record(value: unknown): Record<string, unknown> {
    return value !== null && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }
}
