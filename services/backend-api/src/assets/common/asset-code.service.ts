import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Injectable()
export class AssetCodeService {
  vehicle(): string {
    return this.create('VEH');
  }

  deviceModel(): string {
    return this.create('DVM');
  }

  device(): string {
    return this.create('DEV');
  }

  allocation(): string {
    return this.create('ALC');
  }

  installation(): string {
    return this.create('INS');
  }

  private create(prefix: string): string {
    return `${prefix}-${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`;
  }
}
