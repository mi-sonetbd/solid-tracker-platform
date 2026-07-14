import { Injectable } from '@nestjs/common';

@Injectable()
export class AutomationRunKeyService {
  key(asOf: Date, intervalMs: number): string {
    const safeInterval = Math.max(intervalMs, 60_000);
    const bucket = Math.floor(asOf.getTime() / safeInterval);

    return `billing-automation:${bucket}`;
  }
}
