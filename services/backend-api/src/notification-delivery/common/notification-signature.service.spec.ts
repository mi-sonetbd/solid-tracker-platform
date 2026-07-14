import { UnauthorizedException } from '@nestjs/common';
import { NotificationSignatureService } from './notification-signature.service';

describe('NotificationSignatureService', () => {
  const service = new NotificationSignatureService();
  const secret = 'notification-secret-that-is-long-enough-for-tests';

  it('signs canonical payloads deterministically', () => {
    const timestamp = Date.now().toString();
    const first = service.sign(secret, timestamp, 'evt-1', { b: 2, a: 1 });
    const second = service.sign(secret, timestamp, 'evt-1', { a: 1, b: 2 });

    expect(first).toBe(second);
  });

  it('matches JSON transport when optional DTO fields are undefined', () => {
    const timestamp = Date.now().toString();
    const dtoLikePayload = {
      externalEventId: 'evt-transport',
      providerMessageId: 'msg-transport',
      status: 'DELIVERED',
      occurredAt: new Date().toISOString(),
      errorCode: undefined,
      errorMessage: undefined,
      metadata: { source: 'e2e' },
    };
    const transportedPayload = JSON.parse(JSON.stringify(dtoLikePayload)) as unknown;

    expect(service.sign(secret, timestamp, 'evt-transport', dtoLikePayload)).toBe(
      service.sign(secret, timestamp, 'evt-transport', transportedPayload),
    );
  });
  it('rejects an invalid signature', () => {
    expect(() =>
      service.verify({
        secret,
        timestamp: Date.now().toString(),
        eventId: 'evt-2',
        signature: '00'.repeat(32),
        payload: { status: 'DELIVERED' },
      }),
    ).toThrow(UnauthorizedException);
  });
});
