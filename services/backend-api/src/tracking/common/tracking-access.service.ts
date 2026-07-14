import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class TrackingAccessService {
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

  actorOrganizationId(auth: AuthContext): string | undefined {
    return this.dealerScopeIds(auth)[0] ?? auth.organizationIds[0];
  }

  assertPlatform(auth: AuthContext): void {
    if (!this.isPlatformScoped(auth)) {
      throw new ForbiddenException('This operation requires platform scope.');
    }
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

  vehicleWhere(auth: AuthContext): Prisma.VehicleWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  deviceWhere(auth: AuthContext): Prisma.DeviceWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      vehicleAssignments: {
        some: {
          status: 'ACTIVE',
          vehicle: this.vehicleWhere(auth),
        },
      },
    };
  }

  eventWhere(auth: AuthContext): Prisma.TrackingEventWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  geofenceWhere(auth: AuthContext): Prisma.GeofenceWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  notificationRuleWhere(auth: AuthContext): Prisma.NotificationRuleWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  notificationWhere(auth: AuthContext): Prisma.NotificationWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  commandWhere(auth: AuthContext): Prisma.DeviceCommandRequestWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      OR: [
        {
          vehicle: this.vehicleWhere(auth),
        },
        {
          device: this.deviceWhere(auth),
        },
      ],
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

  async assertVehicle(
    auth: AuthContext,
    vehicleId: string,
  ): Promise<{
    id: string;
    customerId: string;
    status: string;
    customer: {
      managingDealerId: string | null;
      status: string;
    };
  }> {
    const vehicle = await this.prisma.vehicle.findFirst({
      where: {
        AND: [
          {
            id: vehicleId,
          },
          this.vehicleWhere(auth),
        ],
      },
      select: {
        id: true,
        customerId: true,
        status: true,
        customer: {
          select: {
            managingDealerId: true,
            status: true,
          },
        },
      },
    });

    if (!vehicle) {
      throw new NotFoundException('Vehicle was not found within the authenticated scope.');
    }

    return vehicle;
  }

  async assertDevice(auth: AuthContext, deviceId: string): Promise<void> {
    const count = await this.prisma.device.count({
      where: {
        AND: [
          {
            id: deviceId,
          },
          this.deviceWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException('Device was not found within the authenticated scope.');
    }
  }

  async assertGeofence(auth: AuthContext, geofenceId: string): Promise<void> {
    const count = await this.prisma.geofence.count({
      where: {
        AND: [
          {
            id: geofenceId,
          },
          this.geofenceWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException('Geofence was not found within the authenticated scope.');
    }
  }

  async assertTrackingEvent(auth: AuthContext, eventId: string): Promise<void> {
    const count = await this.prisma.trackingEvent.count({
      where: {
        AND: [
          {
            id: eventId,
          },
          this.eventWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException('Tracking event was not found within the authenticated scope.');
    }
  }

  async assertNotification(auth: AuthContext, notificationId: string): Promise<void> {
    const count = await this.prisma.notification.count({
      where: {
        AND: [
          {
            id: notificationId,
          },
          this.notificationWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException('Notification was not found within the authenticated scope.');
    }
  }

  async assertCommand(auth: AuthContext, commandId: string): Promise<void> {
    const count = await this.prisma.deviceCommandRequest.count({
      where: {
        AND: [
          {
            id: commandId,
          },
          this.commandWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException('Command was not found within the authenticated scope.');
    }
  }
}
