import type { Payment, PaymentGateway } from '../../generated/prisma/client';

export type AutomatedPaymentGateway = 'OTHER' | 'BKASH' | 'NAGAD' | 'SSLCOMMERZ';

export type GatewayOutcome = 'PENDING' | 'SUCCEEDED' | 'FAILED' | 'CANCELLED';

export interface GatewayPaymentContext {
  paymentId: string;
  paymentNumber: string;
  gateway: PaymentGateway;
  amount: string;
  currency: string;
  customerName: string;
  customerMobile?: string;
  customerEmail?: string;
  invoiceId: string;
  invoiceNumber: string;
  callbackUrl: string;
  successUrl?: string;
  cancelUrl?: string;
  failureUrl?: string;
}

export interface GatewayInitializationResult {
  gatewayReference: string;
  gatewayTransactionId?: string;
  redirectUrl?: string;
  raw: Record<string, unknown>;
}

export interface GatewayResult {
  externalEventId: string;
  eventType: string;
  paymentReference: string;
  gatewayTransactionId?: string;
  gatewayReference?: string;
  status: GatewayOutcome;
  amount?: string;
  currency?: string;
  failureReason?: string;
  raw: Record<string, unknown>;
}

export interface GatewayWebhookHeaders {
  signature?: string;
  eventId?: string;
  authorization?: string;
}

export interface PaymentGatewayAdapter {
  readonly gateway: PaymentGateway;

  initialize(context: GatewayPaymentContext): Promise<GatewayInitializationResult>;

  verifyWebhook(headers: GatewayWebhookHeaders, payload: Record<string, unknown>): Promise<boolean>;

  parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult>;

  query(payment: Payment): Promise<GatewayResult>;
}
