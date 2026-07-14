import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class MobileAccessService {
  constructor(private readonly prisma: PrismaService) {}

  customerIds(auth: AuthContext): string[] {
    const customerIds = Array.from(new Set(auth.customerIds));

    if (customerIds.length === 0) {
      throw new ForbiddenException('An active customer membership is required for the mobile API.');
    }

    return customerIds;
  }

  vehicleWhere(auth: AuthContext): Prisma.VehicleWhereInput {
    return {
      customerId: {
        in: this.customerIds(auth),
      },
      archivedAt: null,
    };
  }

  async assertVehicle(
    auth: AuthContext,
    vehicleId: string,
  ): Promise<{
    id: string;
    customerId: string;
    status: string;
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
      },
    });

    if (!vehicle) {
      throw new NotFoundException('Vehicle was not found within the authenticated customer scope.');
    }

    return vehicle;
  }
}
