import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Injectable()
export class BillingCodeService {
  plan(): string {
    return this.create('PLN');
  }

  subscription(): string {
    return this.create('SUB');
  }

  invoice(): string {
    return this.create('INV');
  }

  payment(): string {
    return this.create('PAY');
  }

  refund(): string {
    return this.create('RFD');
  }

  commissionRule(): string {
    return this.create('CMR');
  }

  commission(): string {
    return this.create('COM');
  }

  payoutAccount(): string {
    return this.create('PAC');
  }

  settlement(): string {
    return this.create('SET');
  }

  ledger(): string {
    return this.create('LED');
  }

  private create(prefix: string): string {
    return `${prefix}-${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`;
  }
}
