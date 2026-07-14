import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import type { Payment } from '../../generated/prisma/client';
import { GatewaySignatureService } from '../common/gateway-signature.service';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
  PaymentGatewayAdapter,
} from '../common/gateway-types';

@Injectable()
export class SandboxGatewayAdapter implements PaymentGatewayAdapter {
  readonly gateway = 'OTHER' as const;
  private readonly secret: string;

  constructor(
    configService: ConfigService,
    private readonly signatures: GatewaySignatureService,
  ) {
    this.secret = configService.get<string>('PAYMENT_SANDBOX_WEBHOOK_SECRET') ?? '';
  }

  async initialize(context: GatewayPaymentContext): Promise<GatewayInitializationResult> {
    this.assertConfigured();

    const gatewayReference = `SANDBOX-${context.paymentNumber}-${randomUUID()}`;

    return {
      gatewayReference,
      redirectUrl: undefined,
      raw: {
        mode: 'sandbox',
        gatewayReference,
        callbackUrl: context.callbackUrl,
      },
    };
  }

  async verifyWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<boolean> {
    this.assertConfigured();

    return this.signatures.verify(this.secret, payload, headers.signature);
  }

  async parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult> {
    const paymentReference = this.requiredString(payload.paymentReference, 'paymentReference');
    const status = this.status(payload.status);
    const transactionId = this.optionalString(payload.transactionId);
    const eventId =
      headers.eventId ??
      this.optionalString(payload.eventId) ??
      `${paymentReference}:${status}:${transactionId ?? 'none'}`;

    return {
      externalEventId: eventId,
      eventType: `SANDBOX_${status}`,
      paymentReference,
      gatewayTransactionId: transactionId,
      gatewayReference: paymentReference,
      status,
      amount: this.optionalString(payload.amount),
      currency: this.optionalString(payload.currency),
      failureReason: this.optionalString(payload.failureReason),
      raw: payload,
    };
  }

  async query(payment: Payment): Promise<GatewayResult> {
    return {
      externalEventId: `sandbox-query:${payment.id}:${payment.updatedAt.toISOString()}`,
      eventType: 'SANDBOX_QUERY',
      paymentReference: payment.gatewayReference ?? payment.paymentNumber,
      gatewayTransactionId: payment.gatewayTransactionId ?? undefined,
      gatewayReference: payment.gatewayReference ?? undefined,
      status:
        payment.status === 'SUCCEEDED'
          ? 'SUCCEEDED'
          : payment.status === 'FAILED'
            ? 'FAILED'
            : 'PENDING',
      amount: payment.amount.toString(),
      currency: payment.currency,
      failureReason: payment.failureReason ?? undefined,
      raw: {
        localStatus: payment.status,
      },
    };
  }

  private assertConfigured(): void {
    if (this.secret.length < 32) {
      throw new ServiceUnavailableException('Sandbox gateway secret is not configured.');
    }
  }

  private status(value: unknown): GatewayResult['status'] {
    const normalized = this.requiredString(value, 'status').toUpperCase();

    if (normalized === 'SUCCEEDED' || normalized === 'SUCCESS' || normalized === 'VALID') {
      return 'SUCCEEDED';
    }

    if (normalized === 'FAILED' || normalized === 'FAILURE') {
      return 'FAILED';
    }

    if (normalized === 'CANCELLED' || normalized === 'CANCELED') {
      return 'CANCELLED';
    }

    return 'PENDING';
  }

  private requiredString(value: unknown, field: string): string {
    const parsed = this.optionalString(value);

    if (!parsed) {
      throw new Error(`Sandbox callback is missing ${field}.`);
    }

    return parsed;
  }

  private optionalString(value: unknown): string | undefined {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : typeof value === 'number'
        ? value.toString()
        : undefined;
  }
}
