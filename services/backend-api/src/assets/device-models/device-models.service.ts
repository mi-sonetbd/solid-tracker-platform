import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import type { PaginationQueryDto } from '../../management/common/pagination-query.dto';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import type { CreateDeviceModelDto } from './dto/create-device-model.dto';
import type { UpdateDeviceModelDto } from './dto/update-device-model.dto';

@Injectable()
export class DeviceModelsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: AssetAccessService,
    private readonly codes: AssetCodeService,
    private readonly auditService: AuditService,
  ) {}

  async list(query: PaginationQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.DeviceModelWhereInput = {
      status: {
        not: 'ARCHIVED',
      },
      ...(query.search
        ? {
            OR: [
              {
                modelCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                manufacturer: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                modelName: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                protocol: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.deviceModel.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          _count: {
            select: {
              devices: true,
            },
          },
        },
      }),
      this.prisma.deviceModel.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async create(auth: AuthContext, dto: CreateDeviceModelDto) {
    this.access.assertPlatform(auth);

    const duplicate = await this.prisma.deviceModel.findFirst({
      where: {
        manufacturer: {
          equals: dto.manufacturer.trim(),
          mode: 'insensitive',
        },
        modelName: {
          equals: dto.modelName.trim(),
          mode: 'insensitive',
        },
      },
      select: {
        id: true,
      },
    });

    if (duplicate) {
      throw new ConflictException('This manufacturer and device model already exist.');
    }

    const model = await this.prisma.deviceModel.create({
      data: {
        modelCode: this.codes.deviceModel(),
        manufacturer: dto.manufacturer.trim(),
        modelName: dto.modelName.trim(),
        protocol: dto.protocol.trim(),
        networkType: dto.networkType,
        capabilities: dto.capabilities as Prisma.InputJsonValue | undefined,
        status: 'ACTIVE',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device-model.created',
      resourceType: 'DeviceModel',
      resourceId: model.id,
      scopeType: 'PLATFORM',
      afterData: model,
    });

    return model;
  }

  async update(auth: AuthContext, deviceModelId: string, dto: UpdateDeviceModelDto) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.deviceModel.findUnique({
      where: {
        id: deviceModelId,
      },
    });

    if (!before) {
      throw new NotFoundException('Device model was not found.');
    }

    const updated = await this.prisma.deviceModel.update({
      where: {
        id: deviceModelId,
      },
      data: {
        manufacturer: dto.manufacturer?.trim(),
        modelName: dto.modelName?.trim(),
        protocol: dto.protocol?.trim(),
        networkType: dto.networkType,
        capabilities: dto.capabilities as Prisma.InputJsonValue | undefined,
        status: dto.status,
        archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device-model.updated',
      resourceType: 'DeviceModel',
      resourceId: deviceModelId,
      scopeType: 'PLATFORM',
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }
}
