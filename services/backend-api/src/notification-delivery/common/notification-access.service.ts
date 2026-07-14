import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class NotificationDeliveryAccessService {
  constructor(private readonly prisma: PrismaService) {}

  isPlatformScoped(auth: AuthContext): boolean {
    return auth.roles.some((role) => role.scopeType === 'PLATFORM');
  }

  assertPlatform(auth: AuthContext): void {
    if (!this.isPlatformScoped(auth)) {
      throw new ForbiddenException('This notification operation requires platform scope.');
    }
  }

  actorOrganizationId(auth: AuthContext): string | undefined {
    return (
      auth.roles.find((role) => role.scopeType === 'DEALER')?.scopeId ?? auth.organizationIds[0]
    );
  }

  customerWhere(auth: AuthContext): Prisma.CustomerWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = auth.roles
      .filter((role) => role.scopeType === 'DEALER')
      .map((role) => role.scopeId);
    const customerIds = Array.from(
      new Set([
        ...auth.customerIds,
        ...auth.roles.filter((role) => role.scopeType === 'CUSTOMER').map((role) => role.scopeId),
      ]),
    );
    const scopes: Prisma.CustomerWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push({
        managingDealerId: { in: dealerIds },
      });
    }

    if (customerIds.length > 0) {
      scopes.push({ id: { in: customerIds } });
    }

    return scopes.length > 0 ? { OR: scopes } : { id: { in: [] } };
  }

  notificationWhere(auth: AuthContext): Prisma.NotificationWhereInput {
    return this.isPlatformScoped(auth) ? {} : { customer: this.customerWhere(auth) };
  }

  async assertCustomer(auth: AuthContext, customerId: string): Promise<void> {
    const customer = await this.prisma.customer.findFirst({
      where: {
        AND: [{ id: customerId }, this.customerWhere(auth)],
      },
      select: { id: true },
    });

    if (!customer) {
      throw new ForbiddenException('The customer is outside the authenticated scope.');
    }
  }

  async assertNotification(
    auth: AuthContext,
    notificationId: string,
  ): Promise<{
    id: string;
    customerId: string;
    status: string;
  }> {
    const notification = await this.prisma.notification.findFirst({
      where: {
        AND: [{ id: notificationId }, this.notificationWhere(auth)],
      },
      select: {
        id: true,
        customerId: true,
        status: true,
      },
    });

    if (!notification) {
      throw new NotFoundException('Notification was not found within the authenticated scope.');
    }

    return notification;
  }
}
