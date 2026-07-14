import { Injectable } from '@nestjs/common';

@Injectable()
export class BillingDateService {
  addInterval(value: Date, unit: 'DAY' | 'MONTH' | 'YEAR', count: number): Date {
    const result = new Date(value);

    if (unit === 'DAY') {
      result.setUTCDate(result.getUTCDate() + count);
      return result;
    }

    if (unit === 'MONTH') {
      const day = result.getUTCDate();
      result.setUTCDate(1);
      result.setUTCMonth(result.getUTCMonth() + count);
      const lastDay = new Date(
        Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0),
      ).getUTCDate();
      result.setUTCDate(Math.min(day, lastDay));
      return result;
    }

    const month = result.getUTCMonth();
    const day = result.getUTCDate();
    result.setUTCDate(1);
    result.setUTCFullYear(result.getUTCFullYear() + count);
    result.setUTCMonth(month);
    const lastDay = new Date(
      Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0),
    ).getUTCDate();
    result.setUTCDate(Math.min(day, lastDay));
    return result;
  }

  addDays(value: Date, days: number): Date {
    return this.addInterval(value, 'DAY', days);
  }
}
