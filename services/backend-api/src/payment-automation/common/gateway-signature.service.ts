import { Injectable } from '@nestjs/common';
import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

@Injectable()
export class GatewaySignatureService {
  canonicalize(value: unknown): string {
    return JSON.stringify(this.sortValue(value));
  }

  hash(value: unknown): string {
    return createHash('sha256').update(this.canonicalize(value)).digest('hex');
  }

  sign(secret: string, value: unknown): string {
    return createHmac('sha256', secret).update(this.canonicalize(value)).digest('hex');
  }

  verify(secret: string, value: unknown, providedSignature?: string): boolean {
    if (!providedSignature) {
      return false;
    }

    const expected = Buffer.from(this.sign(secret, value), 'utf8');
    const provided = Buffer.from(providedSignature.trim().toLowerCase(), 'utf8');

    if (expected.length !== provided.length) {
      return false;
    }

    return timingSafeEqual(expected, provided);
  }

  private sortValue(value: unknown): unknown {
    if (Array.isArray(value)) {
      return value.map((item) => this.sortValue(item));
    }

    if (value !== null && typeof value === 'object') {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>)
          .sort(([left], [right]) => left.localeCompare(right))
          .map(([key, item]) => [key, this.sortValue(item)]),
      );
    }

    return value;
  }
}
