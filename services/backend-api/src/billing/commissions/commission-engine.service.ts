import { Injectable } from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';

type TransactionClient = Prisma.TransactionClient;

@Injectable()
export class CommissionEngineService {
  constructor(
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
  ) {}

  async createForAllocation(
    transaction: TransactionClient,
    input: {
      paymentId: string;
      invoiceId: string;
      allocationAmount: Prisma.Decimal;
      occurredAt: Date;
    },
  ): Promise<void> {
    const invoice = await transaction.invoice.findUnique({
      where: {
        id: input.invoiceId,
      },
      include: {
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
        subscription: true,
      },
    });

    if (!invoice || !invoice.managingDealerIdAtIssue || invoice.totalAmount.lte(0)) {
      return;
    }

    const ratio = input.allocationAmount.div(invoice.totalAmount).toDecimalPlaces(8);

    for (const line of invoice.lines) {
      const transactionType = await this.resolveTransactionType(
        transaction,
        invoice.subscriptionId,
        invoice.id,
        line.itemType,
      );

      if (!transactionType) {
        continue;
      }

      const duplicate = await transaction.commissionEntry.findFirst({
        where: {
          paymentId: input.paymentId,
          invoiceLineId: line.id,
          reversalOfEntryId: null,
          status: {
            not: 'CANCELLED',
          },
        },
        select: {
          id: true,
        },
      });

      if (duplicate) {
        continue;
      }

      const rule = await this.findRule(transaction, {
        dealerOrganizationId: invoice.managingDealerIdAtIssue,
        servicePlanId: invoice.subscription?.servicePlanId ?? null,
        transactionType,
        occurredAt: input.occurredAt,
      });

      if (!rule || rule.calculationType === 'NONE') {
        continue;
      }

      const baseAmount = line.lineTotal.mul(ratio).toDecimalPlaces(2);

      if (baseAmount.lte(0)) {
        continue;
      }

      const calculated = this.calculate(rule, baseAmount, ratio);

      if (calculated.amount.lte(0)) {
        continue;
      }

      const entry = await transaction.commissionEntry.create({
        data: {
          commissionNumber: this.codes.commission(),
          dealerOrganizationId: invoice.managingDealerIdAtIssue,
          customerId: invoice.customerId,
          invoiceId: invoice.id,
          invoiceLineId: line.id,
          paymentId: input.paymentId,
          commissionRuleId: rule.id,
          transactionType,
          calculationType: rule.calculationType,
          baseAmount,
          percentageRateSnapshot: calculated.percentageRateSnapshot,
          fixedAmountSnapshot: calculated.fixedAmountSnapshot,
          commissionAmount: calculated.amount,
          currency: invoice.currency,
          status: 'AVAILABLE',
          earnedAt: input.occurredAt,
          availableAt: input.occurredAt,
        },
      });

      await transaction.dealerLedgerEntry.create({
        data: {
          ledgerNumber: this.codes.ledger(),
          dealerOrganizationId: invoice.managingDealerIdAtIssue,
          entryType: 'COMMISSION_EARNED',
          direction: 'CREDIT',
          amount: calculated.amount,
          currency: invoice.currency,
          referenceType: 'CommissionEntry',
          referenceId: entry.id,
          description: `Commission earned from invoice ${invoice.invoiceNumber}`,
          occurredAt: input.occurredAt,
        },
      });
    }
  }

  async reverseForRefund(
    transaction: TransactionClient,
    input: {
      paymentId: string;
      refundId: string;
      refundAmount: Prisma.Decimal;
      paymentAmount: Prisma.Decimal;
      occurredAt: Date;
      reason: string;
    },
  ): Promise<void> {
    if (input.paymentAmount.lte(0)) {
      return;
    }

    const originals = await transaction.commissionEntry.findMany({
      where: {
        paymentId: input.paymentId,
        reversalOfEntryId: null,
        commissionAmount: {
          gt: 0,
        },
        status: {
          notIn: ['CANCELLED', 'REVERSED'],
        },
      },
    });

    const ratio = input.refundAmount.div(input.paymentAmount).toDecimalPlaces(8);

    for (const original of originals) {
      const reversalAmount = original.commissionAmount.mul(ratio).toDecimalPlaces(2);

      if (reversalAmount.lte(0)) {
        continue;
      }

      const reversal = await transaction.commissionEntry.create({
        data: {
          commissionNumber: this.codes.commission(),
          dealerOrganizationId: original.dealerOrganizationId,
          customerId: original.customerId,
          invoiceId: original.invoiceId,
          invoiceLineId: original.invoiceLineId,
          paymentId: original.paymentId,
          commissionRuleId: original.commissionRuleId,
          reversalOfEntryId: original.id,
          transactionType: original.transactionType,
          calculationType: original.calculationType,
          baseAmount: original.baseAmount,
          percentageRateSnapshot: original.percentageRateSnapshot,
          fixedAmountSnapshot: original.fixedAmountSnapshot,
          commissionAmount: reversalAmount.negated(),
          currency: original.currency,
          status: 'AVAILABLE',
          earnedAt: input.occurredAt,
          availableAt: input.occurredAt,
          holdReason: input.reason,
        },
      });

      await transaction.dealerLedgerEntry.create({
        data: {
          ledgerNumber: this.codes.ledger(),
          dealerOrganizationId: original.dealerOrganizationId,
          entryType: 'COMMISSION_REVERSAL',
          direction: 'DEBIT',
          amount: reversalAmount,
          currency: original.currency,
          referenceType: 'Refund',
          referenceId: input.refundId,
          description: `Commission reversal for refund: ${input.reason}`,
          occurredAt: input.occurredAt,
        },
      });

      if (ratio.gte(1) && original.status === 'AVAILABLE') {
        await transaction.commissionEntry.update({
          where: {
            id: original.id,
          },
          data: {
            status: 'REVERSED',
          },
        });

        await transaction.commissionEntry.update({
          where: {
            id: reversal.id,
          },
          data: {
            status: 'REVERSED',
          },
        });
      }
    }
  }

  private async findRule(
    transaction: TransactionClient,
    input: {
      dealerOrganizationId: string;
      servicePlanId: string | null;
      transactionType:
        | 'DEVICE_SALE'
        | 'INSTALLATION'
        | 'INITIAL_SUBSCRIPTION'
        | 'SUBSCRIPTION_RENEWAL'
        | 'UPGRADE'
        | 'ADD_ON_SERVICE';
      occurredAt: Date;
    },
  ) {
    const baseWhere: Prisma.CommissionRuleWhereInput = {
      dealerOrganizationId: input.dealerOrganizationId,
      transactionType: input.transactionType,
      status: 'ACTIVE',
      effectiveFrom: {
        lte: input.occurredAt,
      },
      OR: [
        {
          effectiveUntil: null,
        },
        {
          effectiveUntil: {
            gte: input.occurredAt,
          },
        },
      ],
    };

    if (input.servicePlanId) {
      const specific = await transaction.commissionRule.findFirst({
        where: {
          ...baseWhere,
          servicePlanId: input.servicePlanId,
        },
        orderBy: [
          {
            priority: 'asc',
          },
          {
            effectiveFrom: 'desc',
          },
        ],
      });

      if (specific) {
        return specific;
      }
    }

    return transaction.commissionRule.findFirst({
      where: {
        ...baseWhere,
        servicePlanId: null,
      },
      orderBy: [
        {
          priority: 'asc',
        },
        {
          effectiveFrom: 'desc',
        },
      ],
    });
  }

  private calculate(
    rule: {
      calculationType: 'PERCENTAGE' | 'FIXED_AMOUNT' | 'TIERED' | 'NONE';
      percentageRate: Prisma.Decimal | null;
      fixedAmount: Prisma.Decimal | null;
      tierDefinition: Prisma.JsonValue | null;
      minimumAmount: Prisma.Decimal | null;
      maximumAmount: Prisma.Decimal | null;
    },
    baseAmount: Prisma.Decimal,
    allocationRatio: Prisma.Decimal,
  ): {
    amount: Prisma.Decimal;
    percentageRateSnapshot: Prisma.Decimal | null;
    fixedAmountSnapshot: Prisma.Decimal | null;
  } {
    let amount = new Prisma.Decimal(0);
    let percentageRateSnapshot: Prisma.Decimal | null = null;
    let fixedAmountSnapshot: Prisma.Decimal | null = null;

    if (rule.calculationType === 'PERCENTAGE' && rule.percentageRate) {
      percentageRateSnapshot = rule.percentageRate;
      amount = baseAmount.mul(rule.percentageRate).div(100);
    } else if (rule.calculationType === 'FIXED_AMOUNT' && rule.fixedAmount) {
      fixedAmountSnapshot = rule.fixedAmount;
      amount = rule.fixedAmount.mul(allocationRatio);
    } else if (rule.calculationType === 'TIERED') {
      const tier = this.selectTier(rule.tierDefinition, baseAmount);

      if (tier?.percentageRate !== undefined) {
        percentageRateSnapshot = this.money.decimal(tier.percentageRate);
        amount = baseAmount.mul(percentageRateSnapshot).div(100);
      } else if (tier?.fixedAmount !== undefined) {
        fixedAmountSnapshot = this.money.decimal(tier.fixedAmount);
        amount = fixedAmountSnapshot.mul(allocationRatio);
      }
    }

    amount = amount.toDecimalPlaces(2);

    if (rule.minimumAmount && amount.lt(rule.minimumAmount)) {
      amount = rule.minimumAmount;
    }

    if (rule.maximumAmount && amount.gt(rule.maximumAmount)) {
      amount = rule.maximumAmount;
    }

    return {
      amount: amount.toDecimalPlaces(2),
      percentageRateSnapshot,
      fixedAmountSnapshot,
    };
  }

  private selectTier(
    tierDefinition: Prisma.JsonValue | null,
    baseAmount: Prisma.Decimal,
  ):
    | {
        percentageRate?: string | number;
        fixedAmount?: string | number;
      }
    | undefined {
    const tiers =
      tierDefinition &&
      typeof tierDefinition === 'object' &&
      !Array.isArray(tierDefinition) &&
      'tiers' in tierDefinition &&
      Array.isArray(tierDefinition.tiers)
        ? tierDefinition.tiers
        : [];

    return tiers.find((candidate) => {
      if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate)) {
        return false;
      }

      const min =
        'minAmount' in candidate && candidate.minAmount !== undefined
          ? this.money.decimal(candidate.minAmount as string | number)
          : new Prisma.Decimal(0);
      const max =
        'maxAmount' in candidate && candidate.maxAmount !== undefined
          ? this.money.decimal(candidate.maxAmount as string | number)
          : null;

      return baseAmount.gte(min) && (!max || baseAmount.lte(max));
    }) as
      | {
          percentageRate?: string | number;
          fixedAmount?: string | number;
        }
      | undefined;
  }

  private async resolveTransactionType(
    transaction: TransactionClient,
    subscriptionId: string | null,
    invoiceId: string,
    itemType: string,
  ): Promise<
    | 'DEVICE_SALE'
    | 'INSTALLATION'
    | 'INITIAL_SUBSCRIPTION'
    | 'SUBSCRIPTION_RENEWAL'
    | 'UPGRADE'
    | 'ADD_ON_SERVICE'
    | null
  > {
    if (itemType === 'DEVICE_SALE') {
      return 'DEVICE_SALE';
    }

    if (itemType === 'INSTALLATION') {
      return 'INSTALLATION';
    }

    if (itemType === 'REPLACEMENT') {
      return 'UPGRADE';
    }

    if (itemType === 'ADD_ON') {
      return 'ADD_ON_SERVICE';
    }

    if (itemType !== 'SUBSCRIPTION' || !subscriptionId) {
      return null;
    }

    const previousInvoiceCount = await transaction.invoice.count({
      where: {
        subscriptionId,
        id: {
          not: invoiceId,
        },
        status: {
          not: 'VOID',
        },
      },
    });

    return previousInvoiceCount === 0 ? 'INITIAL_SUBSCRIPTION' : 'SUBSCRIPTION_RENEWAL';
  }
}
