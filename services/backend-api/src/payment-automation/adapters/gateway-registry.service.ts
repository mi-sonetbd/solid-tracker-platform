import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import type { PaymentGateway } from '../../generated/prisma/client';
import type { PaymentGatewayAdapter } from '../common/gateway-types';
import { BkashGatewayAdapter } from './bkash-gateway.adapter';
import { NagadGatewayAdapter } from './nagad-gateway.adapter';
import { SandboxGatewayAdapter } from './sandbox-gateway.adapter';
import { SslCommerzGatewayAdapter } from './sslcommerz-gateway.adapter';

@Injectable()
export class GatewayRegistryService {
  constructor(
    private readonly sandbox: SandboxGatewayAdapter,
    private readonly bkash: BkashGatewayAdapter,
    private readonly nagad: NagadGatewayAdapter,
    private readonly sslcommerz: SslCommerzGatewayAdapter,
  ) {}

  get(gateway: PaymentGateway): PaymentGatewayAdapter {
    switch (gateway) {
      case 'OTHER':
        return this.sandbox;
      case 'BKASH':
        return this.bkash;
      case 'NAGAD':
        return this.nagad;
      case 'SSLCOMMERZ':
        return this.sslcommerz;
      default:
        throw new ServiceUnavailableException(`Gateway ${gateway} is not supported by automation.`);
    }
  }
}
