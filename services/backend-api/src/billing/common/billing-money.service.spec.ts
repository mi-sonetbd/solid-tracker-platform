import { BillingMoneyService } from './billing-money.service';

describe('BillingMoneyService', () => {
  const service = new BillingMoneyService();

  it('calculates invoice lines with decimal precision', () => {
    const line = service.invoiceLine({
      quantity: '2.500',
      unitPrice: '100.00',
      discountAmount: '10.00',
      taxAmount: '5.00',
    });

    expect(line.grossAmount.toFixed(2)).toBe('250.00');
    expect(line.lineTotal.toFixed(2)).toBe('245.00');
  });

  it('sums monetary values without binary floating-point drift', () => {
    expect(service.sum(['0.10', '0.20']).toFixed(2)).toBe('0.30');
  });
});
