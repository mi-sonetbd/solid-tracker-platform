import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';
import type { PaymentQueryDto } from '../common/billing-query.dto';
import { CommissionEngineService } from '../commissions/commission-engine.service';
import type { CompleteRefundDto, CreateRefundDto } from './dto/create-refund.dto';
import type { CreatePaymentDto } from './dto/create-payment.dto';
import type { ConfirmPaymentDto } from './dto/confirm-payment.dto';
import type { FailPaymentDto } from './dto/fail-payment.dto';
import type { GatewayEventDto } from './dto/gateway-event.dto';

@Injectable()
export class PaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly commissionEngine: CommissionEngineService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: PaymentQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.PaymentWhereInput = {
      AND: [
        this.access.paymentWhere(auth),
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
              OR: [
                {
                  paymentNumber: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  gatewayTransactionId: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  gatewayReference: {
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
      this.prisma.payment.findMany({
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
            },
          },
          allocations: {
            include: {
              invoice: true,
            },
          },
          refunds: {
            orderBy: {
              requestedAt: 'desc',
            },
          },
        },
      }),
      this.prisma.payment.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, paymentId: string) {
    await this.access.assertPayment(auth, paymentId);

    const payment = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
          },
        },
        allocations: {
          orderBy: {
            allocatedAt: 'desc',
          },
          include: {
            invoice: {
              include: {
                lines: {
                  orderBy: {
                    lineNumber: 'asc',
                  },
                },
              },
            },
          },
        },
        gatewayEvents: {
          orderBy: {
            receivedAt: 'desc',
          },
        },
        refunds: {
          orderBy: {
            requestedAt: 'desc',
          },
        },
        commissionEntries: {
          orderBy: {
            createdAt: 'desc',
          },
        },
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment was not found.');
    }

    return payment;
  }

  async create(auth: AuthContext, dto: CreatePaymentDto) {
    const customer = await this.access.assertCustomer(auth, dto.customerId);

    if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
      throw new BadRequestException('Payment initiation requires an active or pending customer.');
    }

    const amount = this.money.requirePositive(dto.amount, 'amount');

    const payment = await this.prisma.payment.create({
      data: {
        paymentNumber: this.codes.payment(),
        customerId: dto.customerId,
        amount,
        currency: dto.currency.trim().toUpperCase(),
        paymentMethod: dto.paymentMethod,
        paymentGateway: dto.paymentGateway,
        gatewayReference: this.optional(dto.gatewayReference),
        status: 'PENDING',
        metadata: dto.metadata as Prisma.InputJsonValue | undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment.created',
      resourceType: 'Payment',
      resourceId: payment.id,
      scopeType: 'CUSTOMER',
      scopeId: payment.customerId,
      afterData: payment,
    });

    return payment;
  }

  async confirm(auth: AuthContext, paymentId: string, dto: ConfirmPaymentDto) {
    await this.access.assertPayment(auth, paymentId);

    const before = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
    });

    if (!before) {
      throw new NotFoundException('Payment was not found.');
    }

    await this.access.assertFinancialOperator(auth, before.customerId);

    if (!['INITIATED', 'PENDING'].includes(before.status)) {
      throw new ConflictException('Only initiated or pending payments can be confirmed.');
    }

    const allocations = dto.allocations ?? [];
    const invoiceIds = allocations.map((allocation) => allocation.invoiceId);

    if (new Set(invoiceIds).size !== invoiceIds.length) {
      throw new BadRequestException('A payment may allocate to each invoice only once.');
    }

    const allocationAmounts = allocations.map((allocation) =>
      this.money.requirePositive(allocation.amount, 'allocation amount'),
    );
    const allocatedTotal = this.money.sum(allocationAmounts);

    if (allocatedTotal.gt(before.amount)) {
      throw new BadRequestException('Payment allocations exceed the payment amount.');
    }

    const now = new Date();

    const confirmed = await this.prisma.$transaction(async (transaction) => {
      const invoices =
        invoiceIds.length > 0
          ? await transaction.invoice.findMany({
              where: {
                id: {
                  in: invoiceIds,
                },
              },
            })
          : [];

      if (invoices.length !== invoiceIds.length) {
        throw new BadRequestException('One or more allocation invoices were not found.');
      }

      for (const invoice of invoices) {
        if (invoice.customerId !== before.customerId) {
          throw new BadRequestException('Payment and invoice customers must match.');
        }

        if (invoice.currency !== before.currency) {
          throw new BadRequestException('Payment and invoice currencies must match.');
        }

        if (!['ISSUED', 'PARTIALLY_PAID', 'OVERDUE'].includes(invoice.status)) {
          throw new ConflictException(`Invoice ${invoice.invoiceNumber} is not payable.`);
        }
      }

      const payment = await transaction.payment.update({
        where: {
          id: paymentId,
        },
        data: {
          status: 'SUCCEEDED',
          gatewayTransactionId: this.optional(dto.gatewayTransactionId),
          gatewayReference:
            dto.gatewayReference !== undefined ? this.optional(dto.gatewayReference) : undefined,
          confirmedAt: now,
          failedAt: null,
          failureReason: null,
        },
      });

      for (let index = 0; index < allocations.length; index++) {
        const allocation = allocations[index];
        const amount = allocationAmounts[index];

        await transaction.paymentAllocation.create({
          data: {
            paymentId,
            invoiceId: allocation.invoiceId,
            amount,
            allocatedAt: now,
          },
        });

        await this.commissionEngine.createForAllocation(transaction, {
          paymentId,
          invoiceId: allocation.invoiceId,
          allocationAmount: amount,
          occurredAt: now,
        });
      }

      return transaction.payment.findUniqueOrThrow({
        where: {
          id: payment.id,
        },
        include: {
          allocations: {
            include: {
              invoice: true,
            },
          },
          commissionEntries: true,
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment.confirmed',
      resourceType: 'Payment',
      resourceId: paymentId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: confirmed,
    });

    return confirmed;
  }

  async fail(auth: AuthContext, paymentId: string, dto: FailPaymentDto) {
    await this.access.assertPayment(auth, paymentId);

    const before = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
    });

    if (!before) {
      throw new NotFoundException('Payment was not found.');
    }

    await this.access.assertFinancialOperator(auth, before.customerId);

    if (!['INITIATED', 'PENDING'].includes(before.status)) {
      throw new ConflictException('Only initiated or pending payments can fail.');
    }

    const failed = await this.prisma.payment.update({
      where: {
        id: paymentId,
      },
      data: {
        status: 'FAILED',
        failedAt: new Date(),
        failureReason: dto.reason.trim(),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment.failed',
      resourceType: 'Payment',
      resourceId: paymentId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: failed,
    });

    return failed;
  }

  async createRefund(auth: AuthContext, paymentId: string, dto: CreateRefundDto) {
    await this.access.assertPayment(auth, paymentId);

    const payment = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
      include: {
        allocations: true,
        refunds: {
          where: {
            status: {
              in: ['REQUESTED', 'PENDING', 'SUCCEEDED'],
            },
          },
        },
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment was not found.');
    }

    await this.access.assertFinancialOperator(auth, payment.customerId);

    if (!['SUCCEEDED', 'PARTIALLY_REFUNDED', 'REFUNDED'].includes(payment.status)) {
      throw new ConflictException('Only confirmed payments can be refunded.');
    }

    if (
      dto.invoiceId &&
      !payment.allocations.some((allocation) => allocation.invoiceId === dto.invoiceId)
    ) {
      throw new BadRequestException('Refund invoice must be allocated to this payment.');
    }

    const amount = this.money.requirePositive(dto.amount, 'refund amount');
    const alreadyRefunded = this.money.sum(payment.refunds.map((refund) => refund.amount));

    if (alreadyRefunded.plus(amount).gt(payment.amount)) {
      throw new BadRequestException('Refund total exceeds the payment amount.');
    }

    const refund = await this.prisma.refund.create({
      data: {
        refundNumber: this.codes.refund(),
        paymentId,
        customerId: payment.customerId,
        invoiceId: dto.invoiceId,
        amount,
        currency: payment.currency,
        reason: dto.reason.trim(),
        status: 'REQUESTED',
        metadata: dto.metadata as Prisma.InputJsonValue | undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'refund.requested',
      resourceType: 'Refund',
      resourceId: refund.id,
      scopeType: 'CUSTOMER',
      scopeId: payment.customerId,
      afterData: refund,
    });

    return refund;
  }

  async completeRefund(auth: AuthContext, refundId: string, dto: CompleteRefundDto) {
    this.access.assertPlatform(auth);

    const refund = await this.prisma.refund.findUnique({
      where: {
        id: refundId,
      },
      include: {
        payment: true,
      },
    });

    if (!refund) {
      throw new NotFoundException('Refund was not found.');
    }

    if (!['REQUESTED', 'PENDING'].includes(refund.status)) {
      throw new ConflictException('Only requested or pending refunds can be completed.');
    }

    const now = new Date();

    const completed = await this.prisma.$transaction(async (transaction) => {
      const updated = await transaction.refund.update({
        where: {
          id: refund.id,
        },
        data: {
          status: 'SUCCEEDED',
          gatewayRefundId: this.optional(dto.gatewayRefundId),
          completedAt: now,
          failedAt: null,
          failureReason: null,
        },
      });

      const succeededRefunds = await transaction.refund.aggregate({
        where: {
          paymentId: refund.paymentId,
          status: 'SUCCEEDED',
        },
        _sum: {
          amount: true,
        },
      });

      const refundedTotal = succeededRefunds._sum.amount ?? new Prisma.Decimal(0);
      const paymentStatus = refundedTotal.gte(refund.payment.amount)
        ? 'REFUNDED'
        : 'PARTIALLY_REFUNDED';

      await transaction.payment.update({
        where: {
          id: refund.paymentId,
        },
        data: {
          status: paymentStatus,
        },
      });

      if (refund.invoiceId && paymentStatus === 'REFUNDED') {
        await transaction.invoice.update({
          where: {
            id: refund.invoiceId,
          },
          data: {
            status: 'REFUNDED',
          },
        });
      }

      await this.commissionEngine.reverseForRefund(transaction, {
        paymentId: refund.paymentId,
        refundId: refund.id,
        refundAmount: refund.amount,
        paymentAmount: refund.payment.amount,
        occurredAt: now,
        reason: refund.reason,
      });

      return updated;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'refund.completed',
      resourceType: 'Refund',
      resourceId: refund.id,
      scopeType: 'CUSTOMER',
      scopeId: refund.customerId,
      beforeData: refund,
      afterData: completed,
    });

    return completed;
  }

  async gatewayEvent(auth: AuthContext, dto: GatewayEventDto) {
    this.access.assertPlatform(auth);

    if (dto.paymentId) {
      const payment = await this.prisma.payment.findUnique({
        where: {
          id: dto.paymentId,
        },
        select: {
          id: true,
        },
      });

      if (!payment) {
        throw new BadRequestException('Gateway event payment was not found.');
      }
    }

    const payload = dto.payload as Prisma.InputJsonValue;
    const payloadHash = createHash('sha256').update(JSON.stringify(dto.payload)).digest('hex');

    const event = await this.prisma.paymentGatewayEvent.upsert({
      where: {
        gateway_externalEventId: {
          gateway: dto.gateway,
          externalEventId: dto.externalEventId,
        },
      },
      create: {
        paymentId: dto.paymentId,
        gateway: dto.gateway,
        externalEventId: dto.externalEventId,
        eventType: dto.eventType.trim(),
        payload,
        payloadHash,
        status: 'RECEIVED',
      },
      update: {},
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment-gateway-event.received',
      resourceType: 'PaymentGatewayEvent',
      resourceId: event.id,
      scopeType: 'PLATFORM',
      afterData: {
        id: event.id,
        paymentId: event.paymentId,
        gateway: event.gateway,
        externalEventId: event.externalEventId,
        eventType: event.eventType,
        payloadHash: event.payloadHash,
        status: event.status,
      },
    });

    return event;
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
