import { Injectable } from '@nestjs/common';
import type { Payment } from '../../generated/prisma/client';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
  PaymentGatewayAdapter,
} from '../common/gateway-types';
import { SignedProxyClientService } from './signed-proxy-client.service';

@Injectable()
export class NagadGatewayAdapter implements PaymentGatewayAdapter {
  readonly gateway = 'NAGAD' as const;
  private readonly configuration = {
    urlKey: 'NAGAD_GATEWAY_PROXY_URL',
    secretKey: 'NAGAD_GATEWAY_PROXY_SECRET',
  };

  constructor(private readonly proxy: SignedProxyClientService) {}

  initialize(context: GatewayPaymentContext): Promise<GatewayInitializationResult> {
    return this.proxy.initialize(this.gateway, this.configuration, context);
  }

  verifyWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<boolean> {
    return Promise.resolve(this.proxy.verifyWebhook(this.configuration, headers, payload));
  }

  parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult> {
    return Promise.resolve(this.proxy.parseWebhook(this.gateway, headers, payload));
  }

  query(payment: Payment): Promise<GatewayResult> {
    return this.proxy.query(this.gateway, this.configuration, payment);
  }
}
