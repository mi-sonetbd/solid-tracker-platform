import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Payment } from '../../generated/prisma/client';
import { GatewayHttpService } from '../common/gateway-http.service';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
  PaymentGatewayAdapter,
} from '../common/gateway-types';

interface SslCommerzInitializationResponse {
  status?: string;
  failedreason?: string;
  sessionkey?: string;
  GatewayPageURL?: string;
}

interface SslCommerzValidationResponse {
  status?: string;
  tran_id?: string;
  val_id?: string;
  bank_tran_id?: string;
  amount?: string;
  currency?: string;
  error?: string;
}

@Injectable()
export class SslCommerzGatewayAdapter implements PaymentGatewayAdapter {
  readonly gateway = 'SSLCOMMERZ' as const;

  constructor(
    private readonly config: ConfigService,
    private readonly http: GatewayHttpService,
  ) {}

  async initialize(context: GatewayPaymentContext): Promise<GatewayInitializationResult> {
    const settings = this.settings();
    const response = await this.http.form<SslCommerzInitializationResponse>(
      `${settings.baseUrl}/gwprocess/v4/api.php`,
      {
        store_id: settings.storeId,
        store_passwd: settings.storePassword,
        total_amount: context.amount,
        currency: context.currency,
        tran_id: context.paymentNumber,
        success_url: context.successUrl ?? context.callbackUrl,
        fail_url: context.failureUrl ?? context.callbackUrl,
        cancel_url: context.cancelUrl ?? context.callbackUrl,
        ipn_url: context.callbackUrl,
        cus_name: context.customerName,
        cus_email: context.customerEmail ?? 'billing@solid-tracker.local',
        cus_add1: 'Bangladesh',
        cus_city: 'Dhaka',
        cus_country: 'Bangladesh',
        cus_phone: context.customerMobile ?? '00000000000',
        shipping_method: 'NO',
        product_name: `Solid Tracker ${context.invoiceNumber}`,
        product_category: 'GPS Tracking',
        product_profile: 'general',
      },
    );

    if (
      response.status?.toUpperCase() !== 'SUCCESS' ||
      !response.sessionkey ||
      !response.GatewayPageURL
    ) {
      throw new ServiceUnavailableException(
        response.failedreason ?? 'SSLCOMMERZ did not create a payment session.',
      );
    }

    return {
      gatewayReference: response.sessionkey,
      redirectUrl: response.GatewayPageURL,
      raw: response as unknown as Record<string, unknown>,
    };
  }

  async verifyWebhook(
    _headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<boolean> {
    const validation = await this.validatePayload(payload);

    return ['VALID', 'VALIDATED'].includes(validation.status?.toUpperCase() ?? '');
  }

  async parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult> {
    const validation = await this.validatePayload(payload);
    const rawStatus = (
      validation.status ??
      this.optional(payload.status) ??
      'PENDING'
    ).toUpperCase();
    const status: GatewayResult['status'] = ['VALID', 'VALIDATED'].includes(rawStatus)
      ? 'SUCCEEDED'
      : ['FAILED', 'INVALID_TRANSACTION'].includes(rawStatus)
        ? 'FAILED'
        : ['CANCELLED', 'CANCELED'].includes(rawStatus)
          ? 'CANCELLED'
          : 'PENDING';
    const paymentReference = validation.tran_id ?? this.required(payload.tran_id, 'tran_id');
    const validationId = validation.val_id ?? this.optional(payload.val_id);
    const transactionId = validation.bank_tran_id ?? this.optional(payload.bank_tran_id);
    const externalEventId =
      headers.eventId ?? validationId ?? transactionId ?? `${paymentReference}:${rawStatus}`;

    return {
      externalEventId,
      eventType: `SSLCOMMERZ_${rawStatus}`,
      paymentReference,
      gatewayTransactionId: transactionId,
      gatewayReference: validationId ?? paymentReference,
      status,
      amount: validation.amount ?? this.optional(payload.amount),
      currency: validation.currency ?? this.optional(payload.currency),
      failureReason: validation.error ?? this.optional(payload.error),
      raw: {
        callback: payload,
        validation,
      },
    };
  }

  async query(payment: Payment): Promise<GatewayResult> {
    if (!payment.gatewayReference) {
      return this.pending(payment);
    }

    const validation = await this.validate(payment.gatewayReference);
    const rawStatus = validation.status?.toUpperCase() ?? 'PENDING';
    const status: GatewayResult['status'] = ['VALID', 'VALIDATED'].includes(rawStatus)
      ? 'SUCCEEDED'
      : rawStatus === 'FAILED'
        ? 'FAILED'
        : 'PENDING';

    return {
      externalEventId: `sslcommerz-query:${payment.id}:${validation.val_id ?? payment.gatewayReference}`,
      eventType: `SSLCOMMERZ_QUERY_${rawStatus}`,
      paymentReference: validation.tran_id ?? payment.paymentNumber,
      gatewayTransactionId: validation.bank_tran_id ?? undefined,
      gatewayReference: validation.val_id ?? payment.gatewayReference,
      status,
      amount: validation.amount ?? payment.amount.toString(),
      currency: validation.currency ?? payment.currency,
      failureReason: validation.error,
      raw: validation as unknown as Record<string, unknown>,
    };
  }

  private async validatePayload(
    payload: Record<string, unknown>,
  ): Promise<SslCommerzValidationResponse> {
    const validationId = this.required(payload.val_id, 'val_id');

    return this.validate(validationId);
  }

  private validate(validationId: string): Promise<SslCommerzValidationResponse> {
    const settings = this.settings();
    const query = new URLSearchParams({
      val_id: validationId,
      store_id: settings.storeId,
      store_passwd: settings.storePassword,
      v: '1',
      format: 'json',
    });

    return this.http.json<SslCommerzValidationResponse>(
      `${settings.baseUrl}/validator/api/validationserverAPI.php?${query.toString()}`,
    );
  }

  private pending(payment: Payment): GatewayResult {
    return {
      externalEventId: `sslcommerz-query:${payment.id}:pending`,
      eventType: 'SSLCOMMERZ_QUERY_PENDING',
      paymentReference: payment.paymentNumber,
      gatewayReference: payment.gatewayReference ?? undefined,
      gatewayTransactionId: payment.gatewayTransactionId ?? undefined,
      status: 'PENDING',
      amount: payment.amount.toString(),
      currency: payment.currency,
      raw: {},
    };
  }

  private settings(): {
    baseUrl: string;
    storeId: string;
    storePassword: string;
  } {
    const baseUrl = (this.config.get<string>('SSLCOMMERZ_BASE_URL') ?? '').replace(/\/+$/, '');
    const storeId = this.config.get<string>('SSLCOMMERZ_STORE_ID') ?? '';
    const storePassword = this.config.get<string>('SSLCOMMERZ_STORE_PASSWORD') ?? '';

    if (!baseUrl || !storeId || !storePassword) {
      throw new ServiceUnavailableException('SSLCOMMERZ credentials are not configured.');
    }

    return {
      baseUrl,
      storeId,
      storePassword,
    };
  }

  private required(value: unknown, field: string): string {
    const parsed = this.optional(value);

    if (!parsed) {
      throw new Error(`SSLCOMMERZ payload is missing ${field}.`);
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
