import { GatewaySignatureService } from './gateway-signature.service';

describe('GatewaySignatureService', () => {
  const service = new GatewaySignatureService();

  it('creates stable signatures regardless of object key order', () => {
    const secret = '12345678901234567890123456789012';
    const left = {
      status: 'SUCCEEDED',
      nested: {
        amount: '500.00',
        currency: 'BDT',
      },
    };
    const right = {
      nested: {
        currency: 'BDT',
        amount: '500.00',
      },
      status: 'SUCCEEDED',
    };

    const signature = service.sign(secret, left);

    expect(service.sign(secret, right)).toBe(signature);
    expect(service.verify(secret, right, signature)).toBe(true);
    expect(service.verify(secret, right, `${signature.slice(0, -1)}0`)).toBe(false);
  });
});
