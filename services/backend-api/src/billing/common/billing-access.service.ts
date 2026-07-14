import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class BillingAccessService {
  constructor(private readonly prisma: PrismaService) {}

  isPlatformScoped(auth: AuthContext): boolean {
    return auth.roles.some((role) => role.scopeType === 'PLATFORM');
  }

  dealerScopeIds(auth: AuthContext): string[] {
    return Array.from(
      new Set(auth.roles.filter((role) => role.scopeType === 'DEALER').map((role) => role.scopeId)),
    );
  }

  customerScopeIds(auth: AuthContext): string[] {
    return Array.from(
      new Set([
        ...auth.customerIds,
        ...auth.roles.filter((role) => role.scopeType === 'CUSTOMER').map((role) => role.scopeId),
      ]),
    );
  }

  assertPlatform(auth: AuthContext): void {
    if (!this.isPlatformScoped(auth)) {
      throw new ForbiddenException('This operation requires platform scope.');
    }
  }

  assertDealer(auth: AuthContext, dealerId: string): void {
    if (this.isPlatformScoped(auth)) {
      return;
    }

    if (!this.dealerScopeIds(auth).includes(dealerId)) {
      throw new ForbiddenException('The selected dealer is outside the authenticated scope.');
    }
  }

  actorOrganizationId(auth: AuthContext): string | undefined {
    return this.dealerScopeIds(auth)[0] ?? auth.organizationIds[0];
  }

  customerWhere(auth: AuthContext): Prisma.CustomerWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const scopes: Prisma.CustomerWhereInput[] = [];
    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);

    if (dealerIds.length > 0) {
      scopes.push({
        managingDealerId: {
          in: dealerIds,
        },
      });
    }

    if (customerIds.length > 0) {
      scopes.push({
        id: {
          in: customerIds,
        },
      });
    }

    return scopes.length > 0
      ? {
          OR: scopes,
        }
      : {
          id: {
            in: [],
          },
        };
  }

  subscriptionWhere(auth: AuthContext): Prisma.SubscriptionWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  invoiceWhere(auth: AuthContext): Prisma.InvoiceWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);
    const scopes: Prisma.InvoiceWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push(
        {
          managingDealerIdAtIssue: {
            in: dealerIds,
          },
        },
        {
          customer: {
            managingDealerId: {
              in: dealerIds,
            },
          },
        },
      );
    }

    if (customerIds.length > 0) {
      scopes.push({
        customerId: {
          in: customerIds,
        },
      });
    }

    return scopes.length > 0
      ? {
          OR: scopes,
        }
      : {
          id: {
            in: [],
          },
        };
  }

  paymentWhere(auth: AuthContext): Prisma.PaymentWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  commissionWhere(auth: AuthContext): Prisma.CommissionEntryWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const scopes: Prisma.CommissionEntryWhereInput[] = [];
    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);

    if (dealerIds.length > 0) {
      scopes.push({
        dealerOrganizationId: {
          in: dealerIds,
        },
      });
    }

    if (customerIds.length > 0) {
      scopes.push({
        customerId: {
          in: customerIds,
        },
      });
    }

    return scopes.length > 0
      ? {
          OR: scopes,
        }
      : {
          id: {
            in: [],
          },
        };
  }

  settlementWhere(auth: AuthContext): Prisma.DealerSettlementWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      dealerOrganizationId: {
        in: this.dealerScopeIds(auth),
      },
    };
  }

  async assertCustomer(
    auth: AuthContext,
    customerId: string,
  ): Promise<{
    id: string;
    managingDealerId: string | null;
    status: string;
  }> {
    const customer = await this.prisma.customer.findUnique({
      where: {
        id: customerId,
      },
      select: {
        id: true,
        managingDealerId: true,
        status: true,
      },
    });

    if (!customer) {
      throw new NotFoundException('Customer was not found.');
    }

    if (this.isPlatformScoped(auth)) {
      return customer;
    }

    const dealerAllowed =
      customer.managingDealerId !== null &&
      this.dealerScopeIds(auth).includes(customer.managingDealerId);
    const customerAllowed = this.customerScopeIds(auth).includes(customer.id);

    if (!dealerAllowed && !customerAllowed) {
      throw new ForbiddenException('The selected customer is outside the authenticated scope.');
    }

    return customer;
  }

  async assertFinancialOperator(auth: AuthContext, customerId: string): Promise<void> {
    const customer = await this.assertCustomer(auth, customerId);

    if (this.isPlatformScoped(auth)) {
      return;
    }

    if (
      !customer.managingDealerId ||
      !this.dealerScopeIds(auth).includes(customer.managingDealerId)
    ) {
      throw new ForbiddenException(
        'Financial confirmation requires platform or matching dealer scope.',
      );
    }
  }

  async assertSubscription(auth: AuthContext, subscriptionId: string): Promise<void> {
    const count = await this.prisma.subscription.count({
      where: {
        AND: [
          {
            id: subscriptionId,
          },
          this.subscriptionWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException('Subscription was not found within the authenticated scope.');
    }
  }

  async assertInvoice(auth: AuthContext, invoiceId: string): Promise<void> {
    const count = await this.prisma.invoice.count({
      where: {
        AND: [
          {
            id: invoiceId,
          },
          this.invoiceWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException('Invoice was not found within the authenticated scope.');
    }
  }

  async assertPayment(auth: AuthContext, paymentId: string): Promise<void> {
    const count = await this.prisma.payment.count({
      where: {
        AND: [
          {
            id: paymentId,
          },
          this.paymentWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException('Payment was not found within the authenticated scope.');
    }
  }
}
