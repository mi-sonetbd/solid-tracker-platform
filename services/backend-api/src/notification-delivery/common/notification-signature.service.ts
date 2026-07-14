import { Injectable, UnauthorizedException } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';

@Injectable()
export class NotificationSignatureService {
  sign(secret: string, timestamp: string, eventId: string, payload: unknown): string {
    return createHmac('sha256', secret)
      .update(this.message(timestamp, eventId, payload))
      .digest('hex');
  }

  verify(input: {
    secret: string;
    timestamp?: string;
    eventId?: string;
    signature?: string;
    payload: unknown;
    toleranceSeconds?: number;
  }): void {
    const { secret, timestamp, eventId, signature, payload, toleranceSeconds = 300 } = input;

    if (!timestamp || !eventId || !signature) {
      throw new UnauthorizedException('Notification callback signature headers are required.');
    }

    const timestampValue = Number(timestamp);

    if (!Number.isFinite(timestampValue)) {
      throw new UnauthorizedException('Notification callback timestamp is invalid.');
    }

    const timestampMilliseconds =
      timestampValue < 10_000_000_000 ? timestampValue * 1000 : timestampValue;
    const age = Math.abs(Date.now() - timestampMilliseconds);

    if (age > toleranceSeconds * 1000) {
      throw new UnauthorizedException(
        'Notification callback timestamp is outside the accepted window.',
      );
    }

    const expected = this.sign(secret, timestamp, eventId, payload);
    const expectedBuffer = Buffer.from(expected, 'hex');
    const actualBuffer = Buffer.from(signature, 'hex');

    if (
      expectedBuffer.length !== actualBuffer.length ||
      !timingSafeEqual(expectedBuffer, actualBuffer)
    ) {
      throw new UnauthorizedException('Notification callback signature is invalid.');
    }
  }

  canonicalize(value: unknown): string {
    const serialized = JSON.stringify(value);

    if (serialized === undefined) {
      return 'null';
    }

    return this.canonicalizeJson(JSON.parse(serialized) as unknown);
  }

  private canonicalizeJson(value: unknown): string {
    if (value === null || typeof value !== 'object') {
      return JSON.stringify(value);
    }

    if (Array.isArray(value)) {
      return `[${value.map((item) => this.canonicalizeJson(item)).join(',')}]`;
    }

    const record = value as Record<string, unknown>;
    const entries = Object.keys(record)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${this.canonicalizeJson(record[key])}`);

    return `{${entries.join(',')}}`;
  }
  private message(timestamp: string, eventId: string, payload: unknown): string {
    return `${timestamp}.${eventId}.${this.canonicalize(payload)}`;
  }
}
