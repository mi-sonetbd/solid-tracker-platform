import { BillingDateService } from './billing-date.service';

describe('BillingDateService', () => {
  const service = new BillingDateService();

  it('preserves month-end semantics', () => {
    const result = service.addInterval(new Date('2026-01-31T00:00:00.000Z'), 'MONTH', 1);

    expect(result.toISOString()).toBe('2026-02-28T00:00:00.000Z');
  });
});
