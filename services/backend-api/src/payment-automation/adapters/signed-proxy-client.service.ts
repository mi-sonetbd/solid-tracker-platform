import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Payment, PaymentGateway } from '../../generated/prisma/client';
import { GatewayHttpService } from '../common/gateway-http.service';
import { GatewaySignatureService } from '../common/gateway-signature.service';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
} from '../common/gateway-types';

interface ProxyConfiguration {
  urlKey: string;
  secretKey: string;
}

@Injectable()
export class SignedProxyClientService {
  constructor(
    private readonly config: ConfigService,
    private readonly http: GatewayHttpService,
    private readonly signatures: GatewaySignatureService,
  ) {}

  async initialize(
    gateway: PaymentGateway,
    configuration: ProxyConfiguration,
    context: GatewayPaymentContext,
  ): Promise<GatewayInitializationResult> {
    const { baseUrl, secret } = this.configuration(configuration);

    return this.http.json<GatewayInitializationResult>(`${baseUrl}/payments`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${secret}`,
        'x-solid-gateway': gateway,
      },
      body: JSON.stringify(context),
    });
  }

  verifyWebhook(
    configuration: ProxyConfiguration,
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): boolean {
    const { secret } = this.configuration(configuration);

    return this.signatures.verify(secret, payload, headers.signature);
  }

  parseWebhook(
    gateway: PaymentGateway,
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): GatewayResult {
    const paymentReference = this.required(payload.paymentReference, 'paymentReference');
    const rawStatus = this.required(payload.status, 'status').toUpperCase();
    const status: GatewayResult['status'] = ['SUCCEEDED', 'SUCCESS', 'COMPLETED'].includes(
      rawStatus,
    )
      ? 'SUCCEEDED'
      : ['FAILED', 'FAILURE'].includes(rawStatus)
        ? 'FAILED'
        : ['CANCELLED', 'CANCELED'].includes(rawStatus)
          ? 'CANCELLED'
          : 'PENDING';
    const transactionId = this.optional(payload.transactionId);
    const eventId =
      headers.eventId ??
      this.optional(payload.eventId) ??
      `${gateway}:${paymentReference}:${status}:${transactionId ?? 'none'}`;

    return {
      externalEventId: eventId,
      eventType: `${gateway}_${status}`,
      paymentReference,
      gatewayTransactionId: transactionId,
      gatewayReference: this.optional(payload.gatewayReference) ?? paymentReference,
      status,
      amount: this.optional(payload.amount),
      currency: this.optional(payload.currency),
      failureReason: this.optional(payload.failureReason),
      raw: payload,
    };
  }

  async query(
    gateway: PaymentGateway,
    configuration: ProxyConfiguration,
    payment: Payment,
  ): Promise<GatewayResult> {
    const { baseUrl, secret } = this.configuration(configuration);
    const reference = encodeURIComponent(payment.gatewayReference ?? payment.paymentNumber);

    return this.http.json<GatewayResult>(`${baseUrl}/payments/${reference}`, {
      headers: {
        authorization: `Bearer ${secret}`,
        'x-solid-gateway': gateway,
      },
    });
  }

  private configuration(configuration: ProxyConfiguration): {
    baseUrl: string;
    secret: string;
  } {
    const baseUrl = (this.config.get<string>(configuration.urlKey) ?? '').replace(/\/+$/, '');
    const secret = this.config.get<string>(configuration.secretKey) ?? '';

    if (!baseUrl || secret.length < 32) {
      throw new ServiceUnavailableException(
        `${configuration.urlKey} and ${configuration.secretKey} must be configured.`,
      );
    }

    return {
      baseUrl,
      secret,
    };
  }

  private required(value: unknown, field: string): string {
    const parsed = this.optional(value);

    if (!parsed) {
      throw new Error(`Gateway proxy payload is missing ${field}.`);
    }

    return parsed;
  }

  private optional(value: unknown): string | undefined {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : typeof value === 'number'
        ? value.toString()
        : undefined;
  }
}
