import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class AssetAccessService {
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

  vehicleWhere(auth: AuthContext): Prisma.VehicleWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);
    const scopes: Prisma.VehicleWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push({
        customer: {
          managingDealerId: {
            in: dealerIds,
          },
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

  deviceWhere(auth: AuthContext): Prisma.DeviceWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);
    const scopes: Prisma.DeviceWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push(
        {
          dealerAllocations: {
            some: {
              dealerOrganizationId: {
                in: dealerIds,
              },
              status: {
                in: ['ALLOCATED', 'AVAILABLE', 'INSTALLED'],
              },
            },
          },
        },
        {
          vehicleAssignments: {
            some: {
              status: 'ACTIVE',
              vehicle: {
                customer: {
                  managingDealerId: {
                    in: dealerIds,
                  },
                },
              },
            },
          },
        },
      );
    }

    if (customerIds.length > 0) {
      scopes.push({
        vehicleAssignments: {
          some: {
            status: 'ACTIVE',
            vehicle: {
              customerId: {
                in: customerIds,
              },
            },
          },
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
    const vehicle = await this.prisma.vehicle.findUnique({
      where: {
        id: vehicleId,
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
      throw new NotFoundException('Vehicle was not found.');
    }

    if (this.isPlatformScoped(auth)) {
      return vehicle;
    }

    const dealerAllowed =
      vehicle.customer.managingDealerId !== null &&
      this.dealerScopeIds(auth).includes(vehicle.customer.managingDealerId);

    const customerAllowed = this.customerScopeIds(auth).includes(vehicle.customerId);

    if (!dealerAllowed && !customerAllowed) {
      throw new ForbiddenException('The selected vehicle is outside the authenticated scope.');
    }

    return vehicle;
  }

  async assertVehicleMutation(
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
    const vehicle = await this.assertVehicle(auth, vehicleId);

    if (this.isPlatformScoped(auth)) {
      return vehicle;
    }

    if (
      !vehicle.customer.managingDealerId ||
      !this.dealerScopeIds(auth).includes(vehicle.customer.managingDealerId)
    ) {
      throw new ForbiddenException('Vehicle administration requires matching dealer scope.');
    }

    return vehicle;
  }

  async assertCustomerMutation(
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

    if (
      !customer.managingDealerId ||
      !this.dealerScopeIds(auth).includes(customer.managingDealerId)
    ) {
      throw new ForbiddenException('Customer administration requires matching dealer scope.');
    }

    return customer;
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

  actorOrganizationId(auth: AuthContext): string | undefined {
    return this.dealerScopeIds(auth)[0] ?? auth.organizationIds[0];
  }

  async platformOrganizationId(): Promise<string> {
    const platform = await this.prisma.organization.findUnique({
      where: {
        code: 'ORG-PLATFORM',
      },
      select: {
        id: true,
      },
    });

    if (!platform) {
      throw new NotFoundException('Solid Tracker platform organization was not found.');
    }

    return platform.id;
  }
}
