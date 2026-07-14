import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Injectable()
export class TrackingCodeService {
  server(): string {
    return this.create('TRS');
  }

  event(): string {
    return this.create('EVT');
  }

  geofence(): string {
    return this.create('GEO');
  }

  notificationRule(): string {
    return this.create('NTR');
  }

  notification(): string {
    return this.create('NTF');
  }

  command(): string {
    return this.create('CMD');
  }

  job(): string {
    return this.create('JOB');
  }

  private create(prefix: string): string {
    return `${prefix}-${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`;
  }
}
