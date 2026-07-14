import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Injectable()
export class ManagementCodeService {
  dealer(): string {
    return this.create('DLR');
  }

  dealerProfile(): string {
    return this.create('DEALER');
  }

  customer(): string {
    return this.create('CUS');
  }

  customerGroup(): string {
    return this.create('GRP');
  }

  user(): string {
    return this.create('USR');
  }

  private create(prefix: string): string {
    return `${prefix}-${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`;
  }
}
