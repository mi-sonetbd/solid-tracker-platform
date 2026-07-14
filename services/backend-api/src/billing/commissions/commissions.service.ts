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
import type { PaginationQueryDto } from '../../management/common/pagination-query.dto';
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';
import type { CommissionQueryDto } from '../common/billing-query.dto';
import type { CreateCommissionRuleDto } from './dto/create-commission-rule.dto';
import type { ReverseCommissionDto } from './dto/reverse-commission.dto';
import type { UpdateCommissionRuleDto } from './dto/update-commission-rule.dto';

@Injectable()
export class CommissionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly auditService: AuditService,
  ) {}

  async listRules(auth: AuthContext, query: PaginationQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.CommissionRuleWhereInput = {
      ...(this.access.isPlatformScoped(auth)
        ? {}
        : {
            dealerOrganizationId: {
              in: this.access.dealerScopeIds(auth),
            },
          }),
      status: {
        not: 'ARCHIVED',
      },
      ...(query.search
        ? {
            OR: [
              {
                ruleCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                dealerOrganization: {
                  name: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.commissionRule.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: [
          {
            priority: 'asc',
          },
          {
            effectiveFrom: 'desc',
          },
        ],
        include: {
          dealerOrganization: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          servicePlan: true,
          _count: {
            select: {
              entries: true,
            },
          },
        },
      }),
      this.prisma.commissionRule.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async createRule(auth: AuthContext, dto: CreateCommissionRuleDto) {
    this.access.assertPlatform(auth);
    await this.assertDealerAndPlan(dto.dealerOrganizationId, dto.servicePlanId);
    this.assertCalculation(dto);

    const rule = await this.prisma.commissionRule.create({
      data: {
        ruleCode: this.codes.commissionRule(),
        dealerOrganizationId: dto.dealerOrganizationId,
        servicePlanId: dto.servicePlanId,
        transactionType: dto.transactionType,
        calculationType: dto.calculationType,
        percentageRate: dto.percentageRate,
        fixedAmount: dto.fixedAmount,
        tierDefinition: dto.tierDefinition as Prisma.InputJsonValue | undefined,
        minimumAmount: dto.minimumAmount,
        maximumAmount: dto.maximumAmount,
        priority: dto.priority,
        effectiveFrom: new Date(dto.effectiveFrom),
        effectiveUntil: dto.effectiveUntil ? new Date(dto.effectiveUntil) : null,
        status: 'DRAFT',
      },
      include: {
        dealerOrganization: true,
        servicePlan: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'commission-rule.created',
      resourceType: 'CommissionRule',
      resourceId: rule.id,
      scopeType: 'DEALER',
      scopeId: rule.dealerOrganizationId,
      afterData: rule,
    });

    return rule;
  }

  async updateRule(auth: AuthContext, ruleId: string, dto: UpdateCommissionRuleDto) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.commissionRule.findUnique({
      where: {
        id: ruleId,
      },
    });

    if (!before) {
      throw new NotFoundException('Commission rule was not found.');
    }

    const calculationType = dto.calculationType ?? before.calculationType;

    this.assertCalculation({
      calculationType,
      percentageRate: dto.percentageRate ?? before.percentageRate?.toString(),
      fixedAmount: dto.fixedAmount ?? before.fixedAmount?.toString(),
      tierDefinition:
        dto.tierDefinition ?? (before.tierDefinition as Record<string, unknown> | undefined),
    });

    const updated = await this.prisma.commissionRule.update({
      where: {
        id: ruleId,
      },
      data: {
        calculationType: dto.calculationType,
        percentageRate:
          calculationType === 'PERCENTAGE' ? (dto.percentageRate ?? before.percentageRate) : null,
        fixedAmount:
          calculationType === 'FIXED_AMOUNT' ? (dto.fixedAmount ?? before.fixedAmount) : null,
        tierDefinition:
          calculationType === 'TIERED'
            ? ((dto.tierDefinition ?? before.tierDefinition) as Prisma.InputJsonValue | undefined)
            : Prisma.DbNull,
        minimumAmount: dto.minimumAmount,
        maximumAmount: dto.maximumAmount,
        priority: dto.priority,
        effectiveFrom: dto.effectiveFrom ? new Date(dto.effectiveFrom) : undefined,
        effectiveUntil: dto.effectiveUntil !== undefined ? new Date(dto.effectiveUntil) : undefined,
        status: dto.status,
        archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
      },
      include: {
        dealerOrganization: true,
        servicePlan: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'commission-rule.updated',
      resourceType: 'CommissionRule',
      resourceId: ruleId,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async listEntries(auth: AuthContext, query: CommissionQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.CommissionEntryWhereInput = {
      AND: [
        this.access.commissionWhere(auth),
        query.dealerOrganizationId
          ? {
              dealerOrganizationId: query.dealerOrganizationId,
            }
          : {},
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
        query.search
          ? {
              commissionNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.commissionEntry.findMany({
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
          customer: {
            include: {
              individualProfile: true,
              organizationProfile: true,
            },
          },
          invoice: true,
          payment: true,
          commissionRule: true,
          reversalOf: true,
          settlementItem: {
            include: {
              settlement: true,
            },
          },
        },
      }),
      this.prisma.commissionEntry.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async reverseEntry(auth: AuthContext, commissionEntryId: string, dto: ReverseCommissionDto) {
    this.access.assertPlatform(auth);

    const original = await this.prisma.commissionEntry.findUnique({
      where: {
        id: commissionEntryId,
      },
    });

    if (!original) {
      throw new NotFoundException('Commission entry was not found.');
    }

    if (
      original.reversalOfEntryId ||
      original.commissionAmount.lte(0) ||
      ['REVERSED', 'CANCELLED'].includes(original.status)
    ) {
      throw new ConflictException('Only a positive unreversed commission can be reversed.');
    }

    const now = new Date();
    const reversal = await this.prisma.$transaction(async (transaction) => {
      const created = await transaction.commissionEntry.create({
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
          commissionAmount: original.commissionAmount.negated(),
          currency: original.currency,
          status: 'REVERSED',
          earnedAt: now,
          availableAt: now,
          holdReason: dto.reason.trim(),
        },
      });

      if (original.status === 'AVAILABLE') {
        await transaction.commissionEntry.update({
          where: {
            id: original.id,
          },
          data: {
            status: 'REVERSED',
          },
        });
      }

      await transaction.dealerLedgerEntry.create({
        data: {
          ledgerNumber: this.codes.ledger(),
          dealerOrganizationId: original.dealerOrganizationId,
          entryType: 'COMMISSION_REVERSAL',
          direction: 'DEBIT',
          amount: original.commissionAmount,
          currency: original.currency,
          referenceType: 'CommissionEntry',
          referenceId: created.id,
          description: dto.reason.trim(),
          occurredAt: now,
        },
      });

      return created;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'commission.reversed',
      resourceType: 'CommissionEntry',
      resourceId: reversal.id,
      scopeType: 'DEALER',
      scopeId: original.dealerOrganizationId,
      beforeData: original,
      afterData: reversal,
    });

    return reversal;
  }

  async ledger(auth: AuthContext, dealerOrganizationId: string, query: PaginationQueryDto) {
    this.access.assertDealer(auth, dealerOrganizationId);
    const skip = (query.page - 1) * query.pageSize;

    const [items, total, aggregates] = await Promise.all([
      this.prisma.dealerLedgerEntry.findMany({
        where: {
          dealerOrganizationId,
        },
        skip,
        take: query.pageSize,
        orderBy: {
          occurredAt: 'desc',
        },
      }),
      this.prisma.dealerLedgerEntry.count({
        where: {
          dealerOrganizationId,
        },
      }),
      this.prisma.dealerLedgerEntry.groupBy({
        by: ['direction'],
        where: {
          dealerOrganizationId,
        },
        _sum: {
          amount: true,
        },
      }),
    ]);

    const credit =
      aggregates.find((item) => item.direction === 'CREDIT')?._sum.amount ?? new Prisma.Decimal(0);
    const debit =
      aggregates.find((item) => item.direction === 'DEBIT')?._sum.amount ?? new Prisma.Decimal(0);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
      balance: credit.minus(debit).toDecimalPlaces(2),
      credit,
      debit,
    };
  }

  private async assertDealerAndPlan(
    dealerOrganizationId: string,
    servicePlanId?: string,
  ): Promise<void> {
    const dealer = await this.prisma.organization.findFirst({
      where: {
        id: dealerOrganizationId,
        type: 'DEALER',
        status: {
          not: 'ARCHIVED',
        },
      },
      select: {
        id: true,
      },
    });

    if (!dealer) {
      throw new BadRequestException('An active dealer organization is required.');
    }

    if (servicePlanId) {
      const plan = await this.prisma.servicePlan.findUnique({
        where: {
          id: servicePlanId,
        },
        select: {
          id: true,
        },
      });

      if (!plan) {
        throw new BadRequestException('Commission service plan was not found.');
      }
    }
  }

  private assertCalculation(input: {
    calculationType: string;
    percentageRate?: string;
    fixedAmount?: string;
    tierDefinition?: Record<string, unknown>;
  }): void {
    if (input.calculationType === 'PERCENTAGE') {
      if (!input.percentageRate) {
        throw new BadRequestException('percentageRate is required for percentage commission.');
      }

      const rate = this.money.decimal(input.percentageRate);

      if (rate.lt(0) || rate.gt(100)) {
        throw new BadRequestException('percentageRate must be between 0 and 100.');
      }

      return;
    }

    if (input.calculationType === 'FIXED_AMOUNT') {
      if (!input.fixedAmount) {
        throw new BadRequestException('fixedAmount is required for fixed commission.');
      }

      this.money.requireNonNegative(input.fixedAmount, 'fixedAmount');
      return;
    }

    if (input.calculationType === 'TIERED' && !input.tierDefinition) {
      throw new BadRequestException('tierDefinition is required for tiered commission.');
    }
  }
}
