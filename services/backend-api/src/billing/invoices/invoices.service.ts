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
import { BillingMoneyService } from '../common/billing-money.service';
import type { InvoiceQueryDto } from '../common/billing-query.dto';
import type { CreateInvoiceDto, CreateInvoiceLineDto } from './dto/create-invoice.dto';
import type { IssueInvoiceDto, VoidInvoiceDto } from './dto/invoice-action.dto';

@Injectable()
export class InvoicesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly dates: BillingDateService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: InvoiceQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.invoiceWhere(auth);
    const searchWhere: Prisma.InvoiceWhereInput = query.search
      ? {
          invoiceNumber: {
            contains: query.search,
            mode: 'insensitive',
          },
        }
      : {};

    const where: Prisma.InvoiceWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.subscriptionId
          ? {
              subscriptionId: query.subscriptionId,
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
      this.prisma.invoice.findMany({
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
          subscription: {
            include: {
              servicePlan: true,
              vehicle: true,
            },
          },
          managingDealerAtIssue: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          lines: {
            orderBy: {
              lineNumber: 'asc',
            },
          },
        },
      }),
      this.prisma.invoice.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, invoiceId: string) {
    await this.access.assertInvoice(auth, invoiceId);

    const invoice = await this.prisma.invoice.findUnique({
      where: {
        id: invoiceId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
          },
        },
        subscription: {
          include: {
            servicePlan: true,
            vehicle: true,
          },
        },
        managingDealerAtIssue: true,
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
        paymentAllocations: {
          orderBy: {
            allocatedAt: 'desc',
          },
          include: {
            payment: true,
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

    if (!invoice) {
      throw new NotFoundException('Invoice was not found.');
    }

    return invoice;
  }

  async create(auth: AuthContext, dto: CreateInvoiceDto) {
    const customer = await this.access.assertCustomer(auth, dto.customerId);

    if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
      throw new BadRequestException('Invoice creation requires an active or pending customer.');
    }

    if (!this.access.isPlatformScoped(auth)) {
      await this.access.assertFinancialOperator(auth, dto.customerId);
    }

    if (dto.subscriptionId) {
      const subscription = await this.prisma.subscription.findUnique({
        where: {
          id: dto.subscriptionId,
        },
        select: {
          customerId: true,
        },
      });

      if (!subscription || subscription.customerId !== dto.customerId) {
        throw new BadRequestException('Invoice subscription must belong to the selected customer.');
      }
    }

    const issueDate = new Date(dto.issueDate);
    const dueDate = new Date(dto.dueDate);

    this.assertInvoiceDates(issueDate, dueDate);

    const invoice = await this.prisma.$transaction(async (transaction) =>
      this.createRecord(transaction, {
        customerId: dto.customerId,
        subscriptionId: dto.subscriptionId ?? null,
        managingDealerIdAtIssue: customer.managingDealerId,
        billingPeriodStart: dto.billingPeriodStart ? new Date(dto.billingPeriodStart) : null,
        billingPeriodEnd: dto.billingPeriodEnd ? new Date(dto.billingPeriodEnd) : null,
        issueDate,
        dueDate,
        currency: 'BDT',
        lines: dto.lines,
      }),
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'invoice.created',
      resourceType: 'Invoice',
      resourceId: invoice.id,
      scopeType: 'CUSTOMER',
      scopeId: invoice.customerId,
      afterData: invoice,
    });

    return invoice;
  }

  async createFromSubscription(auth: AuthContext, subscriptionId: string, dueInDays: number) {
    await this.access.assertSubscription(auth, subscriptionId);

    const subscription = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
      include: {
        customer: true,
        vehicle: true,
        servicePlan: true,
      },
    });

    if (!subscription) {
      throw new NotFoundException('Subscription was not found.');
    }

    if (!['TRIALING', 'ACTIVE', 'PAST_DUE', 'SUSPENDED'].includes(subscription.status)) {
      throw new ConflictException('Only a current subscription can generate an invoice.');
    }

    const periodStart = subscription.currentPeriodStart ?? new Date();
    const periodEnd =
      subscription.currentPeriodEnd ??
      this.dates.addInterval(
        periodStart,
        subscription.servicePlan.billingIntervalUnit,
        subscription.servicePlan.billingIntervalCount,
      );

    const duplicate = await this.prisma.invoice.findFirst({
      where: {
        subscriptionId,
        billingPeriodStart: periodStart,
        billingPeriodEnd: periodEnd,
        status: {
          not: 'VOID',
        },
      },
      select: {
        id: true,
        invoiceNumber: true,
      },
    });

    if (duplicate) {
      throw new ConflictException(
        `Invoice ${duplicate.invoiceNumber} already exists for this billing period.`,
      );
    }

    const issueDate = new Date();
    const dueDate = this.dates.addDays(issueDate, dueInDays);

    const invoice = await this.prisma.$transaction(async (transaction) => {
      const created = await this.createRecord(transaction, {
        customerId: subscription.customerId,
        subscriptionId: subscription.id,
        managingDealerIdAtIssue: subscription.customer.managingDealerId,
        billingPeriodStart: periodStart,
        billingPeriodEnd: periodEnd,
        issueDate,
        dueDate,
        currency: subscription.servicePlan.currency,
        lines: [
          {
            itemType: 'SUBSCRIPTION',
            description:
              `${subscription.servicePlan.name} ` +
              `(${periodStart.toISOString()} - ${periodEnd.toISOString()})`,
            quantity: '1.000',
            unitPrice: subscription.servicePlan.basePrice.toString(),
            discountAmount: '0.00',
            taxAmount: '0.00',
            referenceType: 'ServicePlan',
            referenceId: subscription.servicePlanId,
          },
        ],
      });

      await transaction.subscription.update({
        where: {
          id: subscription.id,
        },
        data: {
          nextBillingAt: periodEnd,
        },
      });

      return created;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'invoice.generated-from-subscription',
      resourceType: 'Invoice',
      resourceId: invoice.id,
      scopeType: 'CUSTOMER',
      scopeId: invoice.customerId,
      afterData: invoice,
      metadata: {
        subscriptionId,
      },
    });

    return invoice;
  }

  async issue(auth: AuthContext, invoiceId: string, dto: IssueInvoiceDto) {
    await this.access.assertInvoice(auth, invoiceId);

    const before = await this.prisma.invoice.findUnique({
      where: {
        id: invoiceId,
      },
    });

    if (!before) {
      throw new NotFoundException('Invoice was not found.');
    }

    await this.access.assertFinancialOperator(auth, before.customerId);

    if (before.status !== 'DRAFT') {
      throw new ConflictException('Only draft invoices can be issued.');
    }

    const issueDate = dto.issueDate ? new Date(dto.issueDate) : before.issueDate;
    const dueDate = dto.dueDate ? new Date(dto.dueDate) : before.dueDate;

    this.assertInvoiceDates(issueDate, dueDate);

    const issued = await this.prisma.invoice.update({
      where: {
        id: invoiceId,
      },
      data: {
        issueDate,
        dueDate,
        status: 'ISSUED',
        issuedAt: new Date(),
      },
      include: {
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'invoice.issued',
      resourceType: 'Invoice',
      resourceId: invoiceId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: issued,
    });

    return issued;
  }

  async void(auth: AuthContext, invoiceId: string, dto: VoidInvoiceDto) {
    await this.access.assertInvoice(auth, invoiceId);

    const before = await this.prisma.invoice.findUnique({
      where: {
        id: invoiceId,
      },
      include: {
        _count: {
          select: {
            paymentAllocations: true,
          },
        },
      },
    });

    if (!before) {
      throw new NotFoundException('Invoice was not found.');
    }

    await this.access.assertFinancialOperator(auth, before.customerId);

    if (
      before.status === 'PAID' ||
      before.status === 'REFUNDED' ||
      before._count.paymentAllocations > 0
    ) {
      throw new ConflictException('Paid or allocated invoices cannot be voided.');
    }

    if (before.status === 'VOID') {
      throw new ConflictException('Invoice is already void.');
    }

    const voided = await this.prisma.invoice.update({
      where: {
        id: invoiceId,
      },
      data: {
        status: 'VOID',
        voidedAt: new Date(),
        voidReason: dto.reason.trim(),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'invoice.voided',
      resourceType: 'Invoice',
      resourceId: invoiceId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: voided,
    });

    return voided;
  }

  private async createRecord(
    transaction: Prisma.TransactionClient,
    input: {
      customerId: string;
      subscriptionId: string | null;
      managingDealerIdAtIssue: string | null;
      billingPeriodStart: Date | null;
      billingPeriodEnd: Date | null;
      issueDate: Date;
      dueDate: Date;
      currency: string;
      lines: CreateInvoiceLineDto[];
    },
  ) {
    const calculatedLines = input.lines.map((line) => ({
      input: line,
      calculated: this.money.invoiceLine(line),
    }));

    const subtotal = this.money.sum(calculatedLines.map((line) => line.calculated.grossAmount));
    const discountAmount = this.money.sum(
      calculatedLines.map((line) => line.calculated.discountAmount),
    );
    const taxAmount = this.money.sum(calculatedLines.map((line) => line.calculated.taxAmount));
    const totalAmount = subtotal.minus(discountAmount).plus(taxAmount).toDecimalPlaces(2);

    if (totalAmount.isNegative()) {
      throw new BadRequestException('Invoice total cannot be negative.');
    }

    return transaction.invoice.create({
      data: {
        invoiceNumber: this.codes.invoice(),
        customerId: input.customerId,
        subscriptionId: input.subscriptionId,
        managingDealerIdAtIssue: input.managingDealerIdAtIssue,
        billingPeriodStart: input.billingPeriodStart,
        billingPeriodEnd: input.billingPeriodEnd,
        issueDate: input.issueDate,
        dueDate: input.dueDate,
        subtotal,
        discountAmount,
        taxAmount,
        totalAmount,
        paidAmount: 0,
        outstandingAmount: totalAmount,
        currency: input.currency.trim().toUpperCase(),
        status: 'DRAFT',
        lines: {
          create: calculatedLines.map(({ input: line, calculated }, index) => ({
            lineNumber: index + 1,
            itemType: line.itemType,
            description: line.description.trim(),
            quantity: calculated.quantity,
            unitPrice: calculated.unitPrice,
            discountAmount: calculated.discountAmount,
            taxAmount: calculated.taxAmount,
            lineTotal: calculated.lineTotal,
            referenceType: this.optional(line.referenceType),
            referenceId: this.optional(line.referenceId),
          })),
        },
      },
      include: {
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
      },
    });
  }

  private assertInvoiceDates(issueDate: Date, dueDate: Date): void {
    if (Number.isNaN(issueDate.getTime()) || Number.isNaN(dueDate.getTime())) {
      throw new BadRequestException('Invoice dates are invalid.');
    }

    if (dueDate < issueDate) {
      throw new BadRequestException('Invoice due date cannot be earlier than issue date.');
    }
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
