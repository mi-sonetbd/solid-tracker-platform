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
import type { ServicePlanQueryDto } from '../common/billing-query.dto';
import type { CreatePlanVersionDto } from './dto/create-plan-version.dto';
import type { CreateServicePlanDto } from './dto/create-service-plan.dto';
import type { UpdateServicePlanDto } from './dto/update-service-plan.dto';

@Injectable()
export class ServicePlansService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly auditService: AuditService,
  ) {}

  async list(query: ServicePlanQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.ServicePlanWhereInput = {
      ...(query.status
        ? {
            status: query.status,
          }
        : {
            status: {
              not: 'ARCHIVED',
            },
          }),
      ...(query.search
        ? {
            OR: [
              {
                planCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                planFamilyCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                name: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.servicePlan.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: [
          {
            planFamilyCode: 'asc',
          },
          {
            version: 'desc',
          },
        ],
        include: {
          _count: {
            select: {
              subscriptions: true,
              commissionRules: true,
            },
          },
        },
      }),
      this.prisma.servicePlan.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(planId: string) {
    const plan = await this.prisma.servicePlan.findUnique({
      where: {
        id: planId,
      },
      include: {
        subscriptions: {
          orderBy: {
            createdAt: 'desc',
          },
          take: 20,
        },
        commissionRules: {
          orderBy: [
            {
              priority: 'asc',
            },
            {
              effectiveFrom: 'desc',
            },
          ],
        },
      },
    });

    if (!plan) {
      throw new NotFoundException('Service plan was not found.');
    }

    return plan;
  }

  async create(auth: AuthContext, dto: CreateServicePlanDto) {
    this.access.assertPlatform(auth);

    const familyCode = dto.planFamilyCode.trim().toUpperCase();
    const basePrice = this.money.requireNonNegative(dto.basePrice, 'basePrice');
    const effectiveFrom = new Date(dto.effectiveFrom);
    const effectiveUntil = dto.effectiveUntil ? new Date(dto.effectiveUntil) : null;

    this.assertDateRange(effectiveFrom, effectiveUntil);

    const existingFamily = await this.prisma.servicePlan.findFirst({
      where: {
        planFamilyCode: familyCode,
      },
      select: {
        id: true,
      },
    });

    if (existingFamily) {
      throw new ConflictException('Plan family already exists. Create a new version instead.');
    }

    const plan = await this.prisma.servicePlan.create({
      data: {
        planCode: this.codes.plan(),
        planFamilyCode: familyCode,
        version: 1,
        name: dto.name.trim(),
        description: this.optional(dto.description),
        billingIntervalUnit: dto.billingIntervalUnit,
        billingIntervalCount: dto.billingIntervalCount,
        basePrice,
        currency: dto.currency.trim().toUpperCase(),
        taxBehavior: dto.taxBehavior,
        trialDays: dto.trialDays,
        features: dto.features as Prisma.InputJsonValue | undefined,
        deviceLimit: dto.deviceLimit,
        historyRetentionDays: dto.historyRetentionDays,
        status: 'DRAFT',
        effectiveFrom,
        effectiveUntil,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'service-plan.created',
      resourceType: 'ServicePlan',
      resourceId: plan.id,
      scopeType: 'PLATFORM',
      afterData: plan,
    });

    return plan;
  }

  async update(auth: AuthContext, planId: string, dto: UpdateServicePlanDto) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.servicePlan.findUnique({
      where: {
        id: planId,
      },
    });

    if (!before) {
      throw new NotFoundException('Service plan was not found.');
    }

    if (before.status !== 'DRAFT' && this.containsCommercialChanges(dto)) {
      throw new ConflictException(
        'Commercial fields of an activated plan version are immutable. Create a new version.',
      );
    }

    const effectiveFrom = dto.effectiveFrom ? new Date(dto.effectiveFrom) : before.effectiveFrom;
    const effectiveUntil =
      dto.effectiveUntil !== undefined ? new Date(dto.effectiveUntil) : before.effectiveUntil;

    this.assertDateRange(effectiveFrom, effectiveUntil);

    const updated = await this.prisma.servicePlan.update({
      where: {
        id: planId,
      },
      data: {
        name: dto.name?.trim(),
        description: dto.description !== undefined ? this.optional(dto.description) : undefined,
        billingIntervalUnit: dto.billingIntervalUnit,
        billingIntervalCount: dto.billingIntervalCount,
        basePrice:
          dto.basePrice !== undefined
            ? this.money.requireNonNegative(dto.basePrice, 'basePrice')
            : undefined,
        currency: dto.currency?.trim().toUpperCase(),
        taxBehavior: dto.taxBehavior,
        trialDays: dto.trialDays,
        features: dto.features as Prisma.InputJsonValue | undefined,
        deviceLimit: dto.deviceLimit,
        historyRetentionDays: dto.historyRetentionDays,
        effectiveFrom: dto.effectiveFrom !== undefined ? effectiveFrom : undefined,
        effectiveUntil: dto.effectiveUntil !== undefined ? effectiveUntil : undefined,
        status: dto.status,
        archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'service-plan.updated',
      resourceType: 'ServicePlan',
      resourceId: planId,
      scopeType: 'PLATFORM',
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async activate(auth: AuthContext, planId: string) {
    this.access.assertPlatform(auth);

    const plan = await this.prisma.servicePlan.findUnique({
      where: {
        id: planId,
      },
    });

    if (!plan) {
      throw new NotFoundException('Service plan was not found.');
    }

    if (plan.status === 'ARCHIVED') {
      throw new ConflictException('Archived plan versions cannot be activated.');
    }

    const activated = await this.prisma.$transaction(async (transaction) => {
      await transaction.servicePlan.updateMany({
        where: {
          planFamilyCode: plan.planFamilyCode,
          id: {
            not: plan.id,
          },
          status: 'ACTIVE',
        },
        data: {
          status: 'INACTIVE',
        },
      });

      return transaction.servicePlan.update({
        where: {
          id: plan.id,
        },
        data: {
          status: 'ACTIVE',
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'service-plan.activated',
      resourceType: 'ServicePlan',
      resourceId: plan.id,
      scopeType: 'PLATFORM',
      beforeData: plan,
      afterData: activated,
    });

    return activated;
  }

  async createVersion(auth: AuthContext, planId: string, dto: CreatePlanVersionDto) {
    this.access.assertPlatform(auth);

    const source = await this.prisma.servicePlan.findUnique({
      where: {
        id: planId,
      },
    });

    if (!source) {
      throw new NotFoundException('Source service plan was not found.');
    }

    const latest = await this.prisma.servicePlan.findFirst({
      where: {
        planFamilyCode: source.planFamilyCode,
      },
      orderBy: {
        version: 'desc',
      },
      select: {
        version: true,
      },
    });

    const effectiveFrom = dto.effectiveFrom ? new Date(dto.effectiveFrom) : new Date();
    const effectiveUntil = dto.effectiveUntil ? new Date(dto.effectiveUntil) : null;

    this.assertDateRange(effectiveFrom, effectiveUntil);

    const version = await this.prisma.servicePlan.create({
      data: {
        planCode: this.codes.plan(),
        planFamilyCode: source.planFamilyCode,
        version: (latest?.version ?? source.version) + 1,
        name: dto.name?.trim() ?? source.name,
        description:
          dto.description !== undefined ? this.optional(dto.description) : source.description,
        billingIntervalUnit: dto.billingIntervalUnit ?? source.billingIntervalUnit,
        billingIntervalCount: dto.billingIntervalCount ?? source.billingIntervalCount,
        basePrice:
          dto.basePrice !== undefined
            ? this.money.requireNonNegative(dto.basePrice, 'basePrice')
            : source.basePrice,
        currency: dto.currency?.trim().toUpperCase() ?? source.currency,
        taxBehavior: dto.taxBehavior ?? source.taxBehavior,
        trialDays: dto.trialDays ?? source.trialDays,
        features:
          dto.features !== undefined
            ? (dto.features as Prisma.InputJsonValue)
            : source.features === null
              ? Prisma.JsonNull
              : (source.features as Prisma.InputJsonValue),
        deviceLimit: dto.deviceLimit ?? source.deviceLimit,
        historyRetentionDays: dto.historyRetentionDays ?? source.historyRetentionDays,
        status: 'DRAFT',
        effectiveFrom,
        effectiveUntil,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'service-plan.version-created',
      resourceType: 'ServicePlan',
      resourceId: version.id,
      scopeType: 'PLATFORM',
      beforeData: source,
      afterData: version,
    });

    return version;
  }

  private containsCommercialChanges(dto: UpdateServicePlanDto): boolean {
    return [
      dto.billingIntervalUnit,
      dto.billingIntervalCount,
      dto.basePrice,
      dto.currency,
      dto.taxBehavior,
      dto.trialDays,
      dto.features,
      dto.deviceLimit,
      dto.historyRetentionDays,
      dto.effectiveFrom,
      dto.effectiveUntil,
    ].some((value) => value !== undefined);
  }

  private assertDateRange(effectiveFrom: Date, effectiveUntil: Date | null): void {
    if (
      Number.isNaN(effectiveFrom.getTime()) ||
      (effectiveUntil && Number.isNaN(effectiveUntil.getTime()))
    ) {
      throw new BadRequestException('Service-plan effective dates are invalid.');
    }

    if (effectiveUntil && effectiveUntil <= effectiveFrom) {
      throw new BadRequestException('effectiveUntil must be later than effectiveFrom.');
    }
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
