import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingDateService } from '../common/billing-date.service';
import type { SubscriptionQueryDto } from '../common/billing-query.dto';
import { InvoicesService } from '../invoices/invoices.service';
import type { CreateSubscriptionDto } from './dto/create-subscription.dto';
import type {
  GenerateSubscriptionInvoiceDto,
  SubscriptionReasonDto,
} from './dto/subscription-action.dto';

@Injectable()
export class SubscriptionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly dates: BillingDateService,
    private readonly invoicesService: InvoicesService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: SubscriptionQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.subscriptionWhere(auth);
    const searchWhere: Prisma.SubscriptionWhereInput = query.search
      ? {
          OR: [
            {
              subscriptionCode: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              vehicle: {
                vehicleCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            },
          ],
        }
      : {};

    const where: Prisma.SubscriptionWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.vehicleId
          ? {
              vehicleId: query.vehicleId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.subscription.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          customer: {
            include: {
              individualProfile: true,
              organizationProfile: true,
              managingDealer: {
                select: {
                  id: true,
                  code: true,
                  name: true,
                },
              },
            },
          },
          vehicle: true,
          servicePlan: true,
          _count: {
            select: {
              invoices: true,
            },
          },
        },
      }),
      this.prisma.subscription.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, subscriptionId: string) {
    await this.access.assertSubscription(auth, subscriptionId);

    const subscription = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
            managingDealer: true,
          },
        },
        vehicle: true,
        servicePlan: true,
        invoices: {
          orderBy: {
            createdAt: 'desc',
          },
          include: {
            lines: {
              orderBy: {
                lineNumber: 'asc',
              },
            },
          },
        },
      },
    });

    if (!subscription) {
      throw new NotFoundException('Subscription was not found.');
    }

    return subscription;
  }

  async create(auth: AuthContext, dto: CreateSubscriptionDto) {
    const customer = await this.access.assertCustomer(auth, dto.customerId);

    if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
      throw new BadRequestException(
        'Subscription creation requires an active or pending customer.',
      );
    }

    const [vehicle, plan] = await Promise.all([
      this.prisma.vehicle.findUnique({
        where: {
          id: dto.vehicleId,
        },
      }),
      this.prisma.servicePlan.findUnique({
        where: {
          id: dto.servicePlanId,
        },
      }),
    ]);

    if (!vehicle || vehicle.customerId !== dto.customerId) {
      throw new BadRequestException('Subscription vehicle must belong to the selected customer.');
    }

    if (vehicle.status === 'ARCHIVED') {
      throw new ConflictException('Archived vehicles cannot receive subscriptions.');
    }

    if (!plan || plan.status !== 'ACTIVE') {
      throw new BadRequestException('An active service plan is required.');
    }

    const now = new Date();

    if (plan.effectiveFrom > now || (plan.effectiveUntil && plan.effectiveUntil < now)) {
      throw new ConflictException('The selected plan is outside its effective date range.');
    }

    const subscription = await this.prisma.subscription.create({
      data: {
        subscriptionCode: this.codes.subscription(),
        customerId: dto.customerId,
        vehicleId: dto.vehicleId,
        servicePlanId: dto.servicePlanId,
        status: 'PENDING',
        autoRenew: dto.autoRenew,
      },
      include: {
        customer: true,
        vehicle: true,
        servicePlan: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'subscription.created',
      resourceType: 'Subscription',
      resourceId: subscription.id,
      scopeType: 'CUSTOMER',
      scopeId: subscription.customerId,
      afterData: subscription,
    });

    return subscription;
  }

  async activate(auth: AuthContext, subscriptionId: string) {
    await this.access.assertSubscription(auth, subscriptionId);

    const before = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
      include: {
        servicePlan: true,
      },
    });

    if (!before) {
      throw new NotFoundException('Subscription was not found.');
    }

    await this.access.assertFinancialOperator(auth, before.customerId);

    if (before.status !== 'PENDING') {
      throw new ConflictException('Only pending subscriptions can be activated.');
    }

    const now = new Date();
    const periodEnd = this.dates.addInterval(
      now,
      before.servicePlan.billingIntervalUnit,
      before.servicePlan.billingIntervalCount,
    );
    const trialEndsAt =
      before.servicePlan.trialDays > 0
        ? this.dates.addDays(now, before.servicePlan.trialDays)
        : null;

    const activated = await this.prisma.subscription.update({
      where: {
        id: subscriptionId,
      },
      data: {
        status: trialEndsAt ? 'TRIALING' : 'ACTIVE',
        startedAt: now,
        currentPeriodStart: now,
        currentPeriodEnd: periodEnd,
        nextBillingAt: trialEndsAt ?? periodEnd,
        trialEndsAt,
      },
      include: {
        customer: true,
        vehicle: true,
        servicePlan: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'subscription.activated',
      resourceType: 'Subscription',
      resourceId: subscriptionId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: activated,
    });

    return activated;
  }

  async suspend(auth: AuthContext, subscriptionId: string, dto: SubscriptionReasonDto) {
    return this.transition(
      auth,
      subscriptionId,
      ['TRIALING', 'ACTIVE', 'PAST_DUE'],
      'SUSPENDED',
      'subscription.suspended',
      dto.reason,
    );
  }

  async resume(auth: AuthContext, subscriptionId: string, dto: SubscriptionReasonDto) {
    return this.transition(
      auth,
      subscriptionId,
      ['SUSPENDED'],
      'ACTIVE',
      'subscription.resumed',
      dto.reason,
    );
  }

  async cancel(auth: AuthContext, subscriptionId: string, dto: SubscriptionReasonDto) {
    await this.access.assertSubscription(auth, subscriptionId);

    const before = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
    });

    if (!before) {
      throw new NotFoundException('Subscription was not found.');
    }

    await this.access.assertFinancialOperator(auth, before.customerId);

    if (['CANCELLED', 'EXPIRED'].includes(before.status)) {
      throw new ConflictException('Subscription is already closed.');
    }

    const cancelled = await this.prisma.subscription.update({
      where: {
        id: subscriptionId,
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: new Date(),
        cancellationReason: dto.reason?.trim() ?? 'Cancelled by authorized operator',
        autoRenew: false,
        nextBillingAt: null,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'subscription.cancelled',
      resourceType: 'Subscription',
      resourceId: subscriptionId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: cancelled,
    });

    return cancelled;
  }

  async generateInvoice(
    auth: AuthContext,
    subscriptionId: string,
    dto: GenerateSubscriptionInvoiceDto,
  ) {
    return this.invoicesService.createFromSubscription(auth, subscriptionId, dto.dueInDays);
  }

  private async transition(
    auth: AuthContext,
    subscriptionId: string,
    allowedStatuses: string[],
    targetStatus: 'SUSPENDED' | 'ACTIVE',
    action: string,
    reason?: string,
  ) {
    await this.access.assertSubscription(auth, subscriptionId);

    const before = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
    });

    if (!before) {
      throw new NotFoundException('Subscription was not found.');
    }

    await this.access.assertFinancialOperator(auth, before.customerId);

    if (!allowedStatuses.includes(before.status)) {
      throw new ConflictException(
        `Subscription cannot move from ${before.status} to ${targetStatus}.`,
      );
    }

    const updated = await this.prisma.subscription.update({
      where: {
        id: subscriptionId,
      },
      data: {
        status: targetStatus,
        cancellationReason: targetStatus === 'SUSPENDED' ? this.optional(reason) : null,
        nextBillingAt: targetStatus === 'ACTIVE' ? before.currentPeriodEnd : null,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action,
      resourceType: 'Subscription',
      resourceId: subscriptionId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: updated,
      metadata: {
        reason,
      },
    });

    return updated;
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
