import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';
import type { SettlementQueryDto } from '../common/billing-query.dto';
import type { CreateSettlementDto } from './dto/create-settlement.dto';
import type { CompleteSettlementDto, FailSettlementDto } from './dto/settlement-action.dto';

@Injectable()
export class SettlementsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: SettlementQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.DealerSettlementWhereInput = {
      AND: [
        this.access.settlementWhere(auth),
        query.dealerOrganizationId
          ? {
              dealerOrganizationId: query.dealerOrganizationId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  settlementNumber: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  providerReference: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.dealerSettlement.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          dealerOrganization: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          payoutAccount: {
            select: {
              id: true,
              accountCode: true,
              provider: true,
              maskedAccountNumber: true,
              verificationStatus: true,
              status: true,
            },
          },
          _count: {
            select: {
              items: true,
            },
          },
        },
      }),
      this.prisma.dealerSettlement.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, settlementId: string) {
    const settlement = await this.prisma.dealerSettlement.findFirst({
      where: {
        AND: [
          {
            id: settlementId,
          },
          this.access.settlementWhere(auth),
        ],
      },
      include: {
        dealerOrganization: true,
        payoutAccount: {
          select: {
            id: true,
            accountCode: true,
            provider: true,
            accountHolderName: true,
            maskedAccountNumber: true,
            verificationStatus: true,
            status: true,
          },
        },
        items: {
          include: {
            commissionEntry: {
              include: {
                invoice: true,
                payment: true,
                customer: {
                  include: {
                    individualProfile: true,
                    organizationProfile: true,
                  },
                },
              },
            },
          },
        },
      },
    });

    if (!settlement) {
      throw new NotFoundException('Settlement was not found within the authenticated scope.');
    }

    return settlement;
  }

  async create(auth: AuthContext, dto: CreateSettlementDto) {
    this.access.assertDealer(auth, dto.dealerOrganizationId);

    const uniqueEntryIds = Array.from(new Set(dto.commissionEntryIds));

    if (uniqueEntryIds.length !== dto.commissionEntryIds.length) {
      throw new BadRequestException('Settlement commission entries must be unique.');
    }

    const [payoutAccount, entries] = await Promise.all([
      this.prisma.dealerPayoutAccount.findFirst({
        where: {
          id: dto.payoutAccountId,
          dealerOrganizationId: dto.dealerOrganizationId,
          status: 'ACTIVE',
          verificationStatus: 'VERIFIED',
        },
      }),
      this.prisma.commissionEntry.findMany({
        where: {
          id: {
            in: uniqueEntryIds,
          },
          dealerOrganizationId: dto.dealerOrganizationId,
          status: 'AVAILABLE',
          commissionAmount: {
            gt: 0,
          },
        },
      }),
    ]);

    if (!payoutAccount) {
      throw new BadRequestException(
        'An active verified payout account owned by the dealer is required.',
      );
    }

    if (entries.length !== uniqueEntryIds.length) {
      throw new BadRequestException(
        'One or more commission entries are unavailable or outside the dealer.',
      );
    }

    const currencies = new Set(entries.map((entry) => entry.currency));

    if (currencies.size !== 1) {
      throw new BadRequestException('Settlement commission entries must use one currency.');
    }

    const grossCommissionAmount = this.money.sum(entries.map((entry) => entry.commissionAmount));
    const adjustmentAmount = this.money.money(dto.adjustmentAmount);
    const feeAmount = this.money.requireNonNegative(dto.feeAmount, 'feeAmount');
    const netSettlementAmount = grossCommissionAmount
      .plus(adjustmentAmount)
      .minus(feeAmount)
      .toDecimalPlaces(2);

    if (netSettlementAmount.isNegative()) {
      throw new BadRequestException('Settlement net amount cannot be negative.');
    }

    const settlement = await this.prisma.$transaction(async (transaction) => {
      const created = await transaction.dealerSettlement.create({
        data: {
          settlementNumber: this.codes.settlement(),
          dealerOrganizationId: dto.dealerOrganizationId,
          payoutAccountId: dto.payoutAccountId,
          grossCommissionAmount,
          adjustmentAmount,
          feeAmount,
          netSettlementAmount,
          currency: entries[0].currency,
          status: 'DRAFT',
        },
      });

      await transaction.dealerSettlementItem.createMany({
        data: entries.map((entry) => ({
          settlementId: created.id,
          commissionEntryId: entry.id,
          amount: entry.commissionAmount,
        })),
      });

      await transaction.commissionEntry.updateMany({
        where: {
          id: {
            in: uniqueEntryIds,
          },
        },
        data: {
          status: 'SETTLEMENT_PENDING',
        },
      });

      return transaction.dealerSettlement.findUniqueOrThrow({
        where: {
          id: created.id,
        },
        include: {
          payoutAccount: {
            select: {
              id: true,
              accountCode: true,
              provider: true,
              maskedAccountNumber: true,
              verificationStatus: true,
            },
          },
          items: {
            include: {
              commissionEntry: true,
            },
          },
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'settlement.created',
      resourceType: 'DealerSettlement',
      resourceId: settlement.id,
      scopeType: 'DEALER',
      scopeId: settlement.dealerOrganizationId,
      afterData: settlement,
    });

    return settlement;
  }

  async submit(auth: AuthContext, settlementId: string) {
    const before = await this.getForMutation(auth, settlementId);

    if (before.status !== 'DRAFT') {
      throw new ConflictException('Only draft settlements can be submitted.');
    }

    const submitted = await this.prisma.dealerSettlement.update({
      where: {
        id: settlementId,
      },
      data: {
        status: 'PENDING',
        initiatedAt: new Date(),
        failedAt: null,
        failureReason: null,
      },
      include: {
        payoutAccount: {
          select: {
            id: true,
            provider: true,
            maskedAccountNumber: true,
            verificationStatus: true,
          },
        },
        items: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'settlement.submitted',
      resourceType: 'DealerSettlement',
      resourceId: settlementId,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: before,
      afterData: submitted,
    });

    return submitted;
  }

  async complete(auth: AuthContext, settlementId: string, dto: CompleteSettlementDto) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.dealerSettlement.findUnique({
      where: {
        id: settlementId,
      },
      include: {
        items: true,
      },
    });

    if (!before) {
      throw new NotFoundException('Settlement was not found.');
    }

    if (!['PENDING', 'PROCESSING'].includes(before.status)) {
      throw new ConflictException('Only pending or processing settlements can be completed.');
    }

    const now = new Date();
    const commissionEntryIds = before.items.map((item) => item.commissionEntryId);

    const completed = await this.prisma.$transaction(async (transaction) => {
      const updated = await transaction.dealerSettlement.update({
        where: {
          id: settlementId,
        },
        data: {
          status: 'COMPLETED',
          providerReference: this.optional(dto.providerReference),
          completedAt: now,
          failedAt: null,
          failureReason: null,
        },
      });

      await transaction.commissionEntry.updateMany({
        where: {
          id: {
            in: commissionEntryIds,
          },
        },
        data: {
          status: 'SETTLED',
          settledAt: now,
        },
      });

      if (before.netSettlementAmount.gt(0)) {
        await transaction.dealerLedgerEntry.create({
          data: {
            ledgerNumber: this.codes.ledger(),
            dealerOrganizationId: before.dealerOrganizationId,
            entryType: 'SETTLEMENT',
            direction: 'DEBIT',
            amount: before.netSettlementAmount,
            currency: before.currency,
            referenceType: 'DealerSettlement',
            referenceId: before.id,
            description: `Settlement ${before.settlementNumber} completed`,
            occurredAt: now,
          },
        });
      }

      if (before.feeAmount.gt(0)) {
        await transaction.dealerLedgerEntry.create({
          data: {
            ledgerNumber: this.codes.ledger(),
            dealerOrganizationId: before.dealerOrganizationId,
            entryType: 'FEE',
            direction: 'DEBIT',
            amount: before.feeAmount,
            currency: before.currency,
            referenceType: 'DealerSettlement',
            referenceId: before.id,
            description: `Settlement fee for ${before.settlementNumber}`,
            occurredAt: now,
          },
        });
      }

      if (!before.adjustmentAmount.isZero()) {
        await transaction.dealerLedgerEntry.create({
          data: {
            ledgerNumber: this.codes.ledger(),
            dealerOrganizationId: before.dealerOrganizationId,
            entryType: 'MANUAL_ADJUSTMENT',
            direction: before.adjustmentAmount.isPositive() ? 'CREDIT' : 'DEBIT',
            amount: before.adjustmentAmount.abs(),
            currency: before.currency,
            referenceType: 'DealerSettlement',
            referenceId: before.id,
            description: `Settlement adjustment for ${before.settlementNumber}`,
            occurredAt: now,
          },
        });
      }

      return updated;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'settlement.completed',
      resourceType: 'DealerSettlement',
      resourceId: settlementId,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: before,
      afterData: completed,
    });

    return completed;
  }

  async fail(auth: AuthContext, settlementId: string, dto: FailSettlementDto) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.dealerSettlement.findUnique({
      where: {
        id: settlementId,
      },
      include: {
        items: true,
      },
    });

    if (!before) {
      throw new NotFoundException('Settlement was not found.');
    }

    if (!['PENDING', 'PROCESSING'].includes(before.status)) {
      throw new ConflictException('Only pending or processing settlements can fail.');
    }

    const failed = await this.prisma.$transaction(async (transaction) => {
      const updated = await transaction.dealerSettlement.update({
        where: {
          id: settlementId,
        },
        data: {
          status: 'FAILED',
          failedAt: new Date(),
          failureReason: dto.reason.trim(),
          completedAt: null,
        },
      });

      await transaction.commissionEntry.updateMany({
        where: {
          id: {
            in: before.items.map((item) => item.commissionEntryId),
          },
          status: 'SETTLEMENT_PENDING',
        },
        data: {
          status: 'AVAILABLE',
        },
      });

      return updated;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'settlement.failed',
      resourceType: 'DealerSettlement',
      resourceId: settlementId,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: before,
      afterData: failed,
    });

    return failed;
  }

  private async getForMutation(auth: AuthContext, settlementId: string) {
    const settlement = await this.prisma.dealerSettlement.findUnique({
      where: {
        id: settlementId,
      },
      include: {
        payoutAccount: true,
        items: true,
      },
    });

    if (!settlement) {
      throw new NotFoundException('Settlement was not found.');
    }

    this.access.assertDealer(auth, settlement.dealerOrganizationId);

    return settlement;
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
