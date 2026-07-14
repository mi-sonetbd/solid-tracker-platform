import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';

type DecimalInput = Prisma.Decimal | string | number;

@Injectable()
export class BillingMoneyService {
  decimal(value: DecimalInput): Prisma.Decimal {
    return new Prisma.Decimal(value);
  }

  money(value: DecimalInput): Prisma.Decimal {
    return this.decimal(value).toDecimalPlaces(2);
  }

  quantity(value: DecimalInput): Prisma.Decimal {
    return this.decimal(value).toDecimalPlaces(3);
  }

  requireNonNegative(value: DecimalInput, field: string): Prisma.Decimal {
    const decimal = this.money(value);

    if (decimal.isNegative()) {
      throw new BadRequestException(`${field} cannot be negative.`);
    }

    return decimal;
  }

  requirePositive(value: DecimalInput, field: string): Prisma.Decimal {
    const decimal = this.money(value);

    if (!decimal.isPositive()) {
      throw new BadRequestException(`${field} must be greater than zero.`);
    }

    return decimal;
  }

  sum(values: DecimalInput[]): Prisma.Decimal {
    return values.reduce<Prisma.Decimal>(
      (total, value) => total.plus(this.decimal(value)),
      new Prisma.Decimal(0),
    );
  }

  invoiceLine(input: {
    quantity: DecimalInput;
    unitPrice: DecimalInput;
    discountAmount?: DecimalInput;
    taxAmount?: DecimalInput;
  }): {
    quantity: Prisma.Decimal;
    unitPrice: Prisma.Decimal;
    grossAmount: Prisma.Decimal;
    discountAmount: Prisma.Decimal;
    taxAmount: Prisma.Decimal;
    lineTotal: Prisma.Decimal;
  } {
    const quantity = this.quantity(input.quantity);
    const unitPrice = this.requireNonNegative(input.unitPrice, 'unitPrice');
    const discountAmount = this.requireNonNegative(input.discountAmount ?? 0, 'discountAmount');
    const taxAmount = this.requireNonNegative(input.taxAmount ?? 0, 'taxAmount');
    const grossAmount = quantity.mul(unitPrice).toDecimalPlaces(2);
    const lineTotal = grossAmount.minus(discountAmount).plus(taxAmount).toDecimalPlaces(2);

    if (quantity.lte(0)) {
      throw new BadRequestException('Invoice line quantity must be greater than zero.');
    }

    if (discountAmount.gt(grossAmount)) {
      throw new BadRequestException('Invoice line discount cannot exceed its gross amount.');
    }

    if (lineTotal.isNegative()) {
      throw new BadRequestException('Invoice line total cannot be negative.');
    }

    return {
      quantity,
      unitPrice,
      grossAmount,
      discountAmount,
      taxAmount,
      lineTotal,
    };
  }
}
