import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class ManagementContextService {
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

  async assertDealerExists(dealerId: string): Promise<void> {
    const dealer = await this.prisma.organization.findFirst({
      where: {
        id: dealerId,
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
      throw new NotFoundException('Dealer was not found.');
    }
  }

  dealerWhere(auth: AuthContext): Prisma.OrganizationWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {
        type: 'DEALER',
      };
    }

    return {
      type: 'DEALER',
      id: {
        in: this.dealerScopeIds(auth),
      },
    };
  }

  customerWhere(auth: AuthContext): Prisma.CustomerWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);
    const scopes: Prisma.CustomerWhereInput[] = [];

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

    if (scopes.length === 0) {
      return {
        id: {
          in: [],
        },
      };
    }

    return {
      OR: scopes,
    };
  }

  async assertCustomer(
    auth: AuthContext,
    customerId: string,
  ): Promise<{
    id: string;
    managingDealerId: string | null;
    customerGroupId: string | null;
    status: string;
  }> {
    const customer = await this.prisma.customer.findUnique({
      where: {
        id: customerId,
      },
      select: {
        id: true,
        managingDealerId: true,
        customerGroupId: true,
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

  async assertCustomerManagedByDealer(
    auth: AuthContext,
    customerId: string,
  ): Promise<{
    id: string;
    managingDealerId: string | null;
    customerGroupId: string | null;
    status: string;
  }> {
    const customer = await this.assertCustomer(auth, customerId);

    if (this.isPlatformScoped(auth)) {
      return customer;
    }

    if (
      !customer.managingDealerId ||
      !this.dealerScopeIds(auth).includes(customer.managingDealerId)
    ) {
      throw new ForbiddenException('Customer administration requires matching dealer scope.');
    }

    return customer;
  }

  actorOrganizationId(auth: AuthContext): string | undefined {
    const dealerId = this.dealerScopeIds(auth)[0];

    return dealerId ?? auth.organizationIds[0];
  }
}
