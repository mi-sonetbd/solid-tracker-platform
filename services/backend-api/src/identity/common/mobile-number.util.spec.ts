import { normalizeMobileNumber } from './mobile-number.util';

describe('normalizeMobileNumber', () => {
  it('normalizes Bangladeshi local and international formats', () => {
    expect(normalizeMobileNumber('01712-345678')).toBe('+8801712345678');
    expect(normalizeMobileNumber('8801712345678')).toBe('+8801712345678');
    expect(normalizeMobileNumber('+8801712345678')).toBe('+8801712345678');
  });

  it('rejects malformed values', () => {
    expect(() => normalizeMobileNumber('123')).toThrow('Mobile number format is invalid');
  });
});
