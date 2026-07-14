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
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import type { VehicleQueryDto } from '../common/asset-query.dto';
import type { CreateVehicleDto } from './dto/create-vehicle.dto';
import type { UpdateVehicleDto } from './dto/update-vehicle.dto';

@Injectable()
export class VehiclesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: AssetAccessService,
    private readonly codes: AssetCodeService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: VehicleQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.vehicleWhere(auth);
    const searchWhere: Prisma.VehicleWhereInput = query.search
      ? {
          OR: [
            {
              vehicleCode: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              registrationNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              chassisNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              engineNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
          ],
        }
      : {};

    const where: Prisma.VehicleWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.vehicleType
          ? {
              vehicleType: query.vehicleType,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {
              status: {
                not: 'ARCHIVED',
              },
            },
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.vehicle.findMany({
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
          deviceAssignments: {
            where: {
              status: 'ACTIVE',
            },
            include: {
              device: {
                include: {
                  deviceModel: true,
                },
              },
            },
          },
        },
      }),
      this.prisma.vehicle.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, vehicleId: string) {
    await this.access.assertVehicle(auth, vehicleId);

    const vehicle = await this.prisma.vehicle.findUnique({
      where: {
        id: vehicleId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
            managingDealer: true,
          },
        },
        installations: {
          orderBy: {
            createdAt: 'desc',
          },
          include: {
            device: {
              include: {
                deviceModel: true,
              },
            },
          },
        },
        deviceAssignments: {
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            device: {
              include: {
                deviceModel: true,
              },
            },
            installation: true,
          },
        },
      },
    });

    if (!vehicle) {
      throw new NotFoundException('Vehicle was not found.');
    }

    return vehicle;
  }

  async create(auth: AuthContext, dto: CreateVehicleDto) {
    const customer = await this.access.assertCustomerMutation(auth, dto.customerId);

    if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
      throw new BadRequestException('Vehicle creation requires an active or pending customer.');
    }

    const normalizedRegistrationNumber = this.normalizeRegistration(dto.registrationNumber);

    await this.assertUniqueIdentity({
      normalizedRegistrationNumber,
      chassisNumber: this.optionalUpper(dto.chassisNumber),
      engineNumber: this.optionalUpper(dto.engineNumber),
    });

    const vehicle = await this.prisma.vehicle.create({
      data: {
        vehicleCode: this.codes.vehicle(),
        customerId: dto.customerId,
        registrationNumber: this.optional(dto.registrationNumber),
        normalizedRegistrationNumber,
        vehicleType: dto.vehicleType,
        manufacturer: this.optional(dto.manufacturer),
        modelName: this.optional(dto.modelName),
        manufacturingYear: dto.manufacturingYear,
        color: this.optional(dto.color),
        chassisNumber: this.optionalUpper(dto.chassisNumber),
        engineNumber: this.optionalUpper(dto.engineNumber),
        status: 'PENDING',
        createdByUserId: auth.userId,
      },
      include: {
        customer: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'vehicle.created',
      resourceType: 'Vehicle',
      resourceId: vehicle.id,
      scopeType: 'VEHICLE',
      scopeId: vehicle.id,
      afterData: vehicle,
    });

    return vehicle;
  }

  async update(auth: AuthContext, vehicleId: string, dto: UpdateVehicleDto) {
    await this.access.assertVehicleMutation(auth, vehicleId);

    const before = await this.prisma.vehicle.findUnique({
      where: {
        id: vehicleId,
      },
    });

    if (!before) {
      throw new NotFoundException('Vehicle was not found.');
    }

    if (dto.status === 'ARCHIVED') {
      const [activeAssignments, activeSubscriptions] = await Promise.all([
        this.prisma.vehicleDeviceAssignment.count({
          where: {
            vehicleId,
            status: 'ACTIVE',
          },
        }),
        this.prisma.subscription.count({
          where: {
            vehicleId,
            status: {
              in: ['PENDING', 'TRIALING', 'ACTIVE', 'PAST_DUE', 'SUSPENDED'],
            },
          },
        }),
      ]);

      if (activeAssignments > 0 || activeSubscriptions > 0) {
        throw new ConflictException(
          'Remove active trackers and close active subscriptions before archiving the vehicle.',
        );
      }
    }

    const normalizedRegistrationNumber =
      dto.registrationNumber !== undefined
        ? this.normalizeRegistration(dto.registrationNumber)
        : undefined;

    await this.assertUniqueIdentity(
      {
        normalizedRegistrationNumber,
        chassisNumber:
          dto.chassisNumber !== undefined ? this.optionalUpper(dto.chassisNumber) : undefined,
        engineNumber:
          dto.engineNumber !== undefined ? this.optionalUpper(dto.engineNumber) : undefined,
      },
      vehicleId,
    );

    const updated = await this.prisma.vehicle.update({
      where: {
        id: vehicleId,
      },
      data: {
        vehicleType: dto.vehicleType,
        registrationNumber:
          dto.registrationNumber !== undefined ? this.optional(dto.registrationNumber) : undefined,
        normalizedRegistrationNumber,
        manufacturer: dto.manufacturer !== undefined ? this.optional(dto.manufacturer) : undefined,
        modelName: dto.modelName !== undefined ? this.optional(dto.modelName) : undefined,
        manufacturingYear: dto.manufacturingYear,
        color: dto.color !== undefined ? this.optional(dto.color) : undefined,
        chassisNumber:
          dto.chassisNumber !== undefined ? this.optionalUpper(dto.chassisNumber) : undefined,
        engineNumber:
          dto.engineNumber !== undefined ? this.optionalUpper(dto.engineNumber) : undefined,
        status: dto.status,
        archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
      },
      include: {
        customer: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'vehicle.updated',
      resourceType: 'Vehicle',
      resourceId: vehicleId,
      scopeType: 'VEHICLE',
      scopeId: vehicleId,
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async history(auth: AuthContext, vehicleId: string) {
    await this.access.assertVehicle(auth, vehicleId);

    return this.prisma.vehicleDeviceAssignment.findMany({
      where: {
        vehicleId,
      },
      orderBy: {
        startedAt: 'desc',
      },
      include: {
        device: {
          include: {
            deviceModel: true,
          },
        },
        installation: true,
        assignedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
        endedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
      },
    });
  }

  private normalizeRegistration(value?: string): string | null {
    const trimmed = value?.trim();

    if (!trimmed) {
      return null;
    }

    return trimmed.toUpperCase().replace(/[\s-]+/g, '');
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }

  private optionalUpper(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed.toUpperCase() : null;
  }

  private async assertUniqueIdentity(
    identity: {
      normalizedRegistrationNumber?: string | null;
      chassisNumber?: string | null;
      engineNumber?: string | null;
    },
    excludedVehicleId?: string,
  ): Promise<void> {
    const identityConditions: Prisma.VehicleWhereInput[] = [];

    if (identity.normalizedRegistrationNumber) {
      identityConditions.push({
        normalizedRegistrationNumber: identity.normalizedRegistrationNumber,
      });
    }

    if (identity.chassisNumber) {
      identityConditions.push({
        chassisNumber: identity.chassisNumber,
      });
    }

    if (identity.engineNumber) {
      identityConditions.push({
        engineNumber: identity.engineNumber,
      });
    }

    if (identityConditions.length === 0) {
      return;
    }

    const duplicate = await this.prisma.vehicle.findFirst({
      where: {
        id: excludedVehicleId
          ? {
              not: excludedVehicleId,
            }
          : undefined,
        OR: identityConditions,
      },
      select: {
        id: true,
      },
    });

    if (duplicate) {
      throw new ConflictException(
        'Vehicle registration, chassis, or engine identity already exists.',
      );
    }
  }
}
