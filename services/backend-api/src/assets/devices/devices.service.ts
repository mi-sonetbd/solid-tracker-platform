import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { DeviceTrackingService } from '../../tracking/devices/device-tracking.service';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import type { DeviceQueryDto } from '../common/asset-query.dto';
import type { AllocateDeviceDto } from './dto/allocate-device.dto';
import type { BulkRegisterDevicesDto } from './dto/bulk-register-devices.dto';
import type { InstallDeviceDto } from './dto/install-device.dto';
import type { RegisterDeviceDto } from './dto/register-device.dto';
import type { RemoveDeviceDto } from './dto/remove-device.dto';
import type { ReplaceDeviceDto } from './dto/replace-device.dto';
import type { ReturnDeviceDto } from './dto/return-device.dto';
import type { TransferDevicesDto } from './dto/transfer-devices.dto';
import type { UpdateDeviceDto } from './dto/update-device.dto';

type TransactionClient = Prisma.TransactionClient;

const activeAllocationStatuses = ['ALLOCATED', 'AVAILABLE', 'INSTALLED'] as const;

@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly access: AssetAccessService,
    private readonly codes: AssetCodeService,
    private readonly auditService: AuditService,
    private readonly deviceTrackingService: DeviceTrackingService,
  ) {}

  async list(auth: AuthContext, query: DeviceQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.deviceWhere(auth);
    const searchWhere: Prisma.DeviceWhereInput = query.search
      ? {
          OR: [
            {
              deviceCode: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              imei: {
                contains: query.search,
              },
            },
            {
              serialNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
          ],
        }
      : {};

    const where: Prisma.DeviceWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.deviceModelId
          ? {
              deviceModelId: query.deviceModelId,
            }
          : {},
        query.lifecycleStatus
          ? {
              lifecycleStatus: query.lifecycleStatus,
            }
          : {},
        this.listScopeWhere(query),
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.device.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          deviceModel: true,
          ownershipHistory: {
            where: {
              endedAt: null,
            },
          },
          custodyHistory: {
            where: {
              endedAt: null,
            },
          },
          dealerAllocations: {
            where: {
              status: {
                in: [...activeAllocationStatuses],
              },
            },
            include: {
              dealerOrganization: {
                select: {
                  id: true,
                  code: true,
                  name: true,
                },
              },
            },
          },
          vehicleAssignments: {
            where: {
              status: 'ACTIVE',
            },
            include: {
              vehicle: true,
            },
          },
        },
      }),
      this.prisma.device.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, deviceId: string) {
    await this.access.assertDevice(auth, deviceId);

    const device = await this.prisma.device.findUnique({
      where: {
        id: deviceId,
      },
      include: {
        deviceModel: true,
        ownershipHistory: {
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            ownerOrganization: true,
            ownerCustomer: true,
            changedBy: {
              select: {
                id: true,
                userCode: true,
                fullName: true,
              },
            },
          },
        },
        custodyHistory: {
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            custodianOrganization: true,
            custodianCustomer: true,
            custodianUser: {
              select: {
                id: true,
                userCode: true,
                fullName: true,
              },
            },
            changedBy: {
              select: {
                id: true,
                userCode: true,
                fullName: true,
              },
            },
          },
        },
        dealerAllocations: {
          orderBy: {
            allocatedAt: 'desc',
          },
          include: {
            dealerOrganization: true,
          },
        },
        installations: {
          orderBy: {
            createdAt: 'desc',
          },
          include: {
            vehicle: true,
          },
        },
        vehicleAssignments: {
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            vehicle: true,
            installation: true,
          },
        },
        traccarMappings: {
          orderBy: {
            createdAt: 'desc',
          },
        },
      },
    });

    if (!device) {
      throw new NotFoundException('Device was not found.');
    }

    return device;
  }

  async register(auth: AuthContext, dto: RegisterDeviceDto) {
    this.access.assertPlatform(auth);

    const model = await this.prisma.deviceModel.findFirst({
      where: {
        id: dto.deviceModelId,
        status: 'ACTIVE',
      },
      select: {
        id: true,
      },
    });

    if (!model) {
      throw new BadRequestException('An active device model is required.');
    }

    const imei = this.optional(dto.imei);
    const serialNumber = this.optionalUpper(dto.serialNumber);

    if (!imei && !serialNumber) {
      throw new BadRequestException(
        'At least one device identity, IMEI or serial number, is required.',
      );
    }

    const identityConditions: Prisma.DeviceWhereInput[] = [];

    if (imei) {
      identityConditions.push({ imei });
    }

    if (serialNumber) {
      identityConditions.push({ serialNumber });
    }

    const duplicate = await this.prisma.device.findFirst({
      where: {
        OR: identityConditions,
      },
      select: {
        id: true,
      },
    });
    if (duplicate) {
      throw new ConflictException('Device IMEI or serial number already exists.');
    }

    const platformOrganizationId = await this.access.platformOrganizationId();
    const receivedAt = dto.receivedAt ? new Date(dto.receivedAt) : new Date();

    const device = await this.prisma.$transaction(async (transaction) => {
      const created = await transaction.device.create({
        data: {
          deviceCode: this.codes.device(),
          deviceModelId: dto.deviceModelId,
          imei,
          serialNumber,
          hardwareVersion: this.optional(dto.hardwareVersion),
          firmwareVersion: this.optional(dto.firmwareVersion),
          lifecycleStatus: 'IN_STOCK',
          receivedAt,
        },
      });

      await transaction.deviceOwnershipHistory.create({
        data: {
          deviceId: created.id,
          ownerType: 'PLATFORM',
          ownerOrganizationId: platformOrganizationId,
          reason: 'INITIAL_STOCK',
          changedByUserId: auth.userId,
        },
      });

      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId: created.id,
          custodianType: 'PLATFORM',
          custodianOrganizationId: platformOrganizationId,
          reason: 'RECEIVED',
          changedByUserId: auth.userId,
        },
      });

      return transaction.device.findUniqueOrThrow({
        where: {
          id: created.id,
        },
        include: {
          deviceModel: true,
          ownershipHistory: true,
          custodyHistory: true,
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.registered',
      resourceType: 'Device',
      resourceId: device.id,
      scopeType: 'PLATFORM',
      afterData: device,
    });

    return device;
  }

  async update(auth: AuthContext, deviceId: string, dto: UpdateDeviceDto) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.device.findUnique({
      where: {
        id: deviceId,
      },
    });

    if (!before) {
      throw new NotFoundException('Device was not found.');
    }

    if (dto.lifecycleStatus === 'RETIRED' && !dto.retiredAt) {
      throw new BadRequestException('retiredAt is required when retiring a device.');
    }

    if (dto.lifecycleStatus && ['INSTALLED', 'ALLOCATED'].includes(dto.lifecycleStatus)) {
      throw new BadRequestException(
        'Installed and allocated states are controlled by lifecycle operations.',
      );
    }

    const activeAssignment = await this.prisma.vehicleDeviceAssignment.count({
      where: {
        deviceId,
        status: 'ACTIVE',
      },
    });

    if (activeAssignment > 0 && dto.lifecycleStatus && dto.lifecycleStatus !== 'INSTALLED') {
      throw new ConflictException(
        'Remove the active vehicle assignment before changing this lifecycle state.',
      );
    }

    const updated = await this.prisma.device.update({
      where: {
        id: deviceId,
      },
      data: {
        hardwareVersion:
          dto.hardwareVersion !== undefined ? this.optional(dto.hardwareVersion) : undefined,
        firmwareVersion:
          dto.firmwareVersion !== undefined ? this.optional(dto.firmwareVersion) : undefined,
        lifecycleStatus: dto.lifecycleStatus,
        retiredAt:
          dto.lifecycleStatus === 'RETIRED'
            ? new Date(dto.retiredAt as string)
            : dto.lifecycleStatus
              ? null
              : undefined,
      },
      include: {
        deviceModel: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.updated',
      resourceType: 'Device',
      resourceId: deviceId,
      scopeType: 'PLATFORM',
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async bulkRegister(auth: AuthContext, dto: BulkRegisterDevicesDto) {
    this.access.assertPlatform(auth);

    const seen = new Set<string>();
    const results: Array<{
      imei: string;
      status: 'CREATED' | 'ERROR';
      device?: unknown;
      message?: string;
    }> = [];

    for (const rawImei of dto.imeis) {
      const imei = rawImei.trim();

      if (!/^\d{14,17}$/.test(imei)) {
        results.push({
          imei,
          status: 'ERROR',
          message: 'IMEI must contain 14 to 17 digits.',
        });
        continue;
      }

      if (seen.has(imei)) {
        results.push({
          imei,
          status: 'ERROR',
          message: 'Duplicate IMEI exists in this request.',
        });
        continue;
      }

      seen.add(imei);

      try {
        const device = await this.register(auth, {
          deviceModelId: dto.deviceModelId,
          imei,
          hardwareVersion: dto.hardwareVersion,
          firmwareVersion: dto.firmwareVersion,
          receivedAt: dto.receivedAt,
        });

        results.push({
          imei,
          status: 'CREATED',
          device,
        });
      } catch (error) {
        results.push({
          imei,
          status: 'ERROR',
          message: error instanceof Error ? error.message : 'Device registration failed.',
        });
      }
    }

    const created = results.filter((result) => result.status === 'CREATED').length;

    return {
      total: results.length,
      created,
      failed: results.length - created,
      results,
    };
  }

  async transfer(auth: AuthContext, dto: TransferDevicesDto) {
    const deviceIds = Array.from(new Set(dto.deviceIds));

    if (deviceIds.length !== dto.deviceIds.length) {
      throw new BadRequestException('The transfer request contains duplicate Device identifiers.');
    }

    let targetCustomer: {
      id: string;
      status: string;
      managingDealerId: string | null;
    } | null = null;

    if (dto.targetType === 'DEALER') {
      this.access.assertDealer(auth, dto.targetId);

      const dealer = await this.prisma.organization.findFirst({
        where: {
          id: dto.targetId,
          type: 'DEALER',
          status: 'ACTIVE',
        },
        select: {
          id: true,
        },
      });

      if (!dealer) {
        throw new BadRequestException('An active destination Dealer is required.');
      }
    } else {
      const customer = await this.access.assertCustomerMutation(auth, dto.targetId);

      if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
        throw new BadRequestException('The destination Customer must be active or pending.');
      }

      targetCustomer = {
        id: customer.id,
        status: customer.status,
        managingDealerId: customer.managingDealerId,
      };
    }

    const devices = await this.prisma.device.findMany({
      where: {
        AND: [
          {
            id: {
              in: deviceIds,
            },
          },
          this.access.deviceWhere(auth),
        ],
      },
      include: {
        vehicleAssignments: {
          where: {
            status: 'ACTIVE',
          },
        },
      },
    });

    if (devices.length !== deviceIds.length) {
      throw new NotFoundException(
        'One or more Devices were not found within the authenticated scope.',
      );
    }

    const blocked = devices.filter(
      (device) =>
        device.vehicleAssignments.length > 0 ||
        !['RECEIVED', 'IN_STOCK', 'ALLOCATED'].includes(device.lifecycleStatus),
    );

    if (blocked.length > 0) {
      throw new ConflictException(
        'Installed, assigned, damaged, lost, repaired, or retired Devices cannot be moved.',
      );
    }

    const now = new Date();
    const notes = this.optional(dto.notes);

    await this.prisma.$transaction(async (transaction) => {
      for (const device of devices) {
        await transaction.dealerDeviceAllocation.updateMany({
          where: {
            deviceId: device.id,
            status: {
              in: [...activeAllocationStatuses],
            },
          },
          data: {
            status: 'RETURNED',
            returnedAt: now,
            returnedByUserId: auth.userId,
          },
        });

        await this.endCurrentOwnership(transaction, device.id, now);

        await this.endCurrentCustody(transaction, device.id, now);

        if (dto.targetType === 'DEALER') {
          await transaction.deviceOwnershipHistory.create({
            data: {
              deviceId: device.id,
              ownerType: 'DEALER',
              ownerOrganizationId: dto.targetId,
              reason: 'TRANSFER',
              changedByUserId: auth.userId,
              notes,
              startedAt: now,
            },
          });

          await transaction.deviceCustodyHistory.create({
            data: {
              deviceId: device.id,
              custodianType: 'DEALER',
              custodianOrganizationId: dto.targetId,
              reason: 'TRANSFER',
              changedByUserId: auth.userId,
              notes,
              startedAt: now,
            },
          });

          await transaction.dealerDeviceAllocation.create({
            data: {
              allocationCode: this.codes.allocation(),
              dealerOrganizationId: dto.targetId,
              deviceId: device.id,
              status: 'AVAILABLE',
              allocatedAt: now,
              availableAt: now,
              allocatedByUserId: auth.userId,
              notes,
            },
          });
        } else {
          await transaction.deviceOwnershipHistory.create({
            data: {
              deviceId: device.id,
              ownerType: 'CUSTOMER',
              ownerCustomerId: dto.targetId,
              reason: 'TRANSFER',
              changedByUserId: auth.userId,
              notes,
              startedAt: now,
            },
          });

          await transaction.deviceCustodyHistory.create({
            data: {
              deviceId: device.id,
              custodianType: 'CUSTOMER',
              custodianCustomerId: dto.targetId,
              reason: 'TRANSFER',
              changedByUserId: auth.userId,
              notes,
              startedAt: now,
            },
          });

          if (targetCustomer?.managingDealerId) {
            await transaction.dealerDeviceAllocation.create({
              data: {
                allocationCode: this.codes.allocation(),
                dealerOrganizationId: targetCustomer.managingDealerId,
                deviceId: device.id,
                status: 'AVAILABLE',
                allocatedAt: now,
                availableAt: now,
                allocatedByUserId: auth.userId,
                notes,
              },
            });
          }
        }

        await transaction.device.update({
          where: {
            id: device.id,
          },
          data: {
            lifecycleStatus: 'ALLOCATED',
          },
        });
      }
    });

    const moved = await this.prisma.device.findMany({
      where: {
        id: {
          in: deviceIds,
        },
      },
      include: {
        deviceModel: true,
        ownershipHistory: {
          where: {
            endedAt: null,
          },
        },
        custodyHistory: {
          where: {
            endedAt: null,
          },
        },
        dealerAllocations: {
          where: {
            status: {
              in: [...activeAllocationStatuses],
            },
          },
          include: {
            dealerOrganization: {
              select: {
                id: true,
                code: true,
                name: true,
              },
            },
          },
        },
        vehicleAssignments: {
          where: {
            status: 'ACTIVE',
          },
          include: {
            vehicle: true,
          },
        },
      },
    });

    for (const device of moved) {
      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId: this.access.actorOrganizationId(auth),
        action: 'device.transferred',
        resourceType: 'Device',
        resourceId: device.id,
        scopeType: dto.targetType,
        scopeId: dto.targetId,
        afterData: device,
      });
    }

    return {
      items: moved,
      total: moved.length,
      targetType: dto.targetType,
      targetId: dto.targetId,
    };
  }
  async allocate(auth: AuthContext, deviceId: string, dto: AllocateDeviceDto) {
    this.access.assertPlatform(auth);

    const [device, dealer, activeAllocation, activeAssignment] = await Promise.all([
      this.prisma.device.findUnique({
        where: {
          id: deviceId,
        },
      }),
      this.prisma.organization.findFirst({
        where: {
          id: dto.dealerOrganizationId,
          type: 'DEALER',
          status: 'ACTIVE',
        },
      }),
      this.prisma.dealerDeviceAllocation.findFirst({
        where: {
          deviceId,
          status: {
            in: [...activeAllocationStatuses],
          },
        },
      }),
      this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          deviceId,
          status: 'ACTIVE',
        },
      }),
    ]);

    if (!device) {
      throw new NotFoundException('Device was not found.');
    }

    if (!dealer) {
      throw new BadRequestException('An active dealer organization is required.');
    }

    if (activeAllocation) {
      throw new ConflictException('Device already has an active dealer allocation.');
    }

    if (activeAssignment) {
      throw new ConflictException('An installed device cannot be allocated.');
    }

    if (!['RECEIVED', 'IN_STOCK'].includes(device.lifecycleStatus)) {
      throw new ConflictException('Only received or in-stock devices may be allocated.');
    }

    const now = new Date();

    const allocation = await this.prisma.$transaction(async (transaction) => {
      await this.endCurrentCustody(transaction, deviceId, now);

      const created = await transaction.dealerDeviceAllocation.create({
        data: {
          allocationCode: this.codes.allocation(),
          dealerOrganizationId: dto.dealerOrganizationId,
          deviceId,
          status: 'AVAILABLE',
          allocatedAt: now,
          availableAt: now,
          allocatedByUserId: auth.userId,
          notes: this.optional(dto.notes),
        },
        include: {
          dealerOrganization: true,
          device: {
            include: {
              deviceModel: true,
            },
          },
        },
      });

      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId,
          custodianType: 'DEALER',
          custodianOrganizationId: dto.dealerOrganizationId,
          reason: 'ALLOCATION',
          changedByUserId: auth.userId,
          notes: this.optional(dto.notes),
        },
      });

      await transaction.device.update({
        where: {
          id: deviceId,
        },
        data: {
          lifecycleStatus: 'ALLOCATED',
        },
      });

      return created;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.allocated',
      resourceType: 'DealerDeviceAllocation',
      resourceId: allocation.id,
      scopeType: 'DEALER',
      scopeId: dto.dealerOrganizationId,
      afterData: allocation,
    });

    return allocation;
  }

  async returnToPlatform(auth: AuthContext, deviceId: string, dto: ReturnDeviceDto) {
    const allocation = await this.prisma.dealerDeviceAllocation.findFirst({
      where: {
        deviceId,
        status: {
          in: [...activeAllocationStatuses],
        },
      },
      include: {
        dealerOrganization: true,
      },
    });

    if (!allocation) {
      throw new NotFoundException('Active dealer allocation was not found.');
    }

    this.access.assertDealer(auth, allocation.dealerOrganizationId);

    const activeAssignment = await this.prisma.vehicleDeviceAssignment.count({
      where: {
        deviceId,
        status: 'ACTIVE',
      },
    });

    if (activeAssignment > 0) {
      throw new ConflictException('Remove the device from its vehicle before returning it.');
    }

    const platformOrganizationId = await this.access.platformOrganizationId();
    const now = new Date();

    const returned = await this.prisma.$transaction(async (transaction) => {
      const updated = await transaction.dealerDeviceAllocation.update({
        where: {
          id: allocation.id,
        },
        data: {
          status: 'RETURNED',
          returnedAt: now,
          returnedByUserId: auth.userId,
          notes: this.optional(dto.notes) ?? allocation.notes,
        },
        include: {
          dealerOrganization: true,
          device: true,
        },
      });

      await this.endCurrentCustody(transaction, deviceId, now);

      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId,
          custodianType: 'PLATFORM',
          custodianOrganizationId: platformOrganizationId,
          reason: 'RETURN',
          changedByUserId: auth.userId,
          notes: this.optional(dto.notes),
        },
      });

      await transaction.device.update({
        where: {
          id: deviceId,
        },
        data: {
          lifecycleStatus: 'IN_STOCK',
        },
      });

      return updated;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.returned-to-platform',
      resourceType: 'DealerDeviceAllocation',
      resourceId: allocation.id,
      scopeType: 'DEALER',
      scopeId: allocation.dealerOrganizationId,
      afterData: returned,
    });

    return returned;
  }

  async install(auth: AuthContext, deviceId: string, dto: InstallDeviceDto) {
    const vehicle = await this.access.assertVehicleMutation(auth, dto.vehicleId);

    if (vehicle.status === 'ARCHIVED' || vehicle.customer.status === 'ARCHIVED') {
      throw new BadRequestException('Archived vehicles or customers cannot receive installations.');
    }

    const device = await this.prisma.device.findUnique({
      where: {
        id: deviceId,
      },
    });

    if (!device) {
      throw new NotFoundException('Device was not found.');
    }

    const dealerId = vehicle.customer.managingDealerId;
    const allocation = await this.resolveInstallAllocation(auth, deviceId, dealerId);

    await this.assertInstallationAvailability(deviceId, dto.vehicleId, device.lifecycleStatus);

    const installedAt = dto.installedAt ? new Date(dto.installedAt) : new Date();

    const installation = await this.prisma.$transaction(async (transaction) => {
      return this.installWithinTransaction(transaction, auth, {
        deviceId,
        vehicleId: dto.vehicleId,
        customerId: vehicle.customerId,
        dealerId,
        allocationId: allocation?.id,
        installedAt,
        latitude: dto.latitude,
        longitude: dto.longitude,
        odometerReading: dto.odometerReading,
        powerConnectionType: this.optional(dto.powerConnectionType),
        ignitionConnected: dto.ignitionConnected ?? false,
        relayConnected: dto.relayConnected ?? false,
        sosConnected: dto.sosConnected ?? false,
        notes: this.optional(dto.installationNotes),
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.installed',
      resourceType: 'DeviceInstallation',
      resourceId: installation.id,
      scopeType: 'VEHICLE',
      scopeId: dto.vehicleId,
      afterData: installation,
    });

    try {
      const trackingSynchronization = await this.deviceTrackingService.syncAfterInstallation(
        auth,
        deviceId,
      );

      return {
        ...installation,
        trackingSynchronization,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown synchronization error';

      this.logger.warn(
        `Device ${deviceId} was installed, but automatic Traccar synchronization failed: ${message}`,
      );

      return {
        ...installation,
        trackingSynchronization: {
          status: 'FAILED',
          message,
        },
      };
    }
  }

  async remove(auth: AuthContext, deviceId: string, dto: RemoveDeviceDto) {
    const activeAssignment = await this.prisma.vehicleDeviceAssignment.findFirst({
      where: {
        deviceId,
        status: 'ACTIVE',
      },
      include: {
        vehicle: {
          include: {
            customer: true,
          },
        },
        installation: true,
      },
    });

    if (!activeAssignment) {
      throw new NotFoundException('Active vehicle assignment was not found.');
    }

    await this.access.assertVehicleMutation(auth, activeAssignment.vehicleId);

    const allocation = await this.prisma.dealerDeviceAllocation.findFirst({
      where: {
        deviceId,
        status: {
          in: [...activeAllocationStatuses],
        },
      },
    });

    const now = new Date();
    const result = await this.prisma.$transaction(async (transaction) => {
      return this.removeWithinTransaction(transaction, auth, {
        assignmentId: activeAssignment.id,
        installationId: activeAssignment.installationId,
        deviceId,
        dealerId: activeAssignment.vehicle.customer.managingDealerId,
        allocationId: allocation?.id,
        assignmentEndReason: dto.assignmentEndReason,
        removalReason: dto.removalReason,
        notes: this.optional(dto.notes),
        now,
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.removed',
      resourceType: 'VehicleDeviceAssignment',
      resourceId: activeAssignment.id,
      scopeType: 'VEHICLE',
      scopeId: activeAssignment.vehicleId,
      afterData: result,
    });

    return result;
  }

  async replace(auth: AuthContext, currentDeviceId: string, dto: ReplaceDeviceDto) {
    if (currentDeviceId === dto.replacementDeviceId) {
      throw new BadRequestException(
        'Replacement device must be different from the current device.',
      );
    }

    const activeAssignment = await this.prisma.vehicleDeviceAssignment.findFirst({
      where: {
        deviceId: currentDeviceId,
        status: 'ACTIVE',
        assignmentType: 'PRIMARY',
      },
      include: {
        vehicle: {
          include: {
            customer: true,
          },
        },
        installation: true,
      },
    });

    if (!activeAssignment) {
      throw new NotFoundException('Current active primary assignment was not found.');
    }

    await this.access.assertVehicleMutation(auth, activeAssignment.vehicleId);

    const replacementDevice = await this.prisma.device.findUnique({
      where: {
        id: dto.replacementDeviceId,
      },
    });

    if (!replacementDevice) {
      throw new NotFoundException('Replacement device was not found.');
    }

    const dealerId = activeAssignment.vehicle.customer.managingDealerId;

    const [currentAllocation, replacementAllocation] = await Promise.all([
      this.prisma.dealerDeviceAllocation.findFirst({
        where: {
          deviceId: currentDeviceId,
          status: {
            in: [...activeAllocationStatuses],
          },
        },
      }),
      this.resolveInstallAllocation(auth, dto.replacementDeviceId, dealerId),
    ]);

    await this.assertInstallationAvailability(
      dto.replacementDeviceId,
      activeAssignment.vehicleId,
      replacementDevice.lifecycleStatus,
      activeAssignment.id,
    );

    const now = new Date();
    const installedAt = dto.installedAt ? new Date(dto.installedAt) : now;

    const replacement = await this.prisma.$transaction(async (transaction) => {
      const removed = await this.removeWithinTransaction(transaction, auth, {
        assignmentId: activeAssignment.id,
        installationId: activeAssignment.installationId,
        deviceId: currentDeviceId,
        dealerId,
        allocationId: currentAllocation?.id,
        assignmentEndReason: 'DEVICE_REPLACEMENT',
        removalReason: dto.removalReason,
        notes: this.optional(dto.notes),
        now,
      });

      const installed = await this.installWithinTransaction(transaction, auth, {
        deviceId: dto.replacementDeviceId,
        vehicleId: activeAssignment.vehicleId,
        customerId: activeAssignment.vehicle.customerId,
        dealerId,
        allocationId: replacementAllocation?.id,
        installedAt,
        latitude: dto.latitude,
        longitude: dto.longitude,
        odometerReading: dto.odometerReading,
        powerConnectionType: this.optional(dto.powerConnectionType),
        ignitionConnected: dto.ignitionConnected ?? false,
        relayConnected: dto.relayConnected ?? false,
        sosConnected: dto.sosConnected ?? false,
        notes: this.optional(dto.notes),
      });

      return {
        removed,
        installed,
      };
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.replaced',
      resourceType: 'Vehicle',
      resourceId: activeAssignment.vehicleId,
      scopeType: 'VEHICLE',
      scopeId: activeAssignment.vehicleId,
      beforeData: {
        deviceId: currentDeviceId,
        assignmentId: activeAssignment.id,
      },
      afterData: {
        deviceId: dto.replacementDeviceId,
        assignmentId: replacement.installed.assignment.id,
      },
      metadata: {
        removalReason: dto.removalReason,
        notes: dto.notes,
      },
    });

    return replacement;
  }

  async history(auth: AuthContext, deviceId: string) {
    await this.access.assertDevice(auth, deviceId);

    const [ownership, custody, allocations, installations, assignments] = await Promise.all([
      this.prisma.deviceOwnershipHistory.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          startedAt: 'desc',
        },
        include: {
          ownerOrganization: true,
          ownerCustomer: true,
        },
      }),
      this.prisma.deviceCustodyHistory.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          startedAt: 'desc',
        },
        include: {
          custodianOrganization: true,
          custodianCustomer: true,
          custodianUser: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
        },
      }),
      this.prisma.dealerDeviceAllocation.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          allocatedAt: 'desc',
        },
        include: {
          dealerOrganization: true,
        },
      }),
      this.prisma.deviceInstallation.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          vehicle: true,
        },
      }),
      this.prisma.vehicleDeviceAssignment.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          startedAt: 'desc',
        },
        include: {
          vehicle: true,
          installation: true,
        },
      }),
    ]);

    return {
      ownership,
      custody,
      allocations,
      installations,
      assignments,
    };
  }

  private async resolveInstallAllocation(
    auth: AuthContext,
    deviceId: string,
    dealerId: string | null,
  ) {
    const allocation = await this.prisma.dealerDeviceAllocation.findFirst({
      where: {
        deviceId,
        status: {
          in: ['ALLOCATED', 'AVAILABLE'],
        },
      },
    });

    if (dealerId) {
      if (!allocation || allocation.dealerOrganizationId !== dealerId) {
        throw new ForbiddenException(
          'Dealer-managed installation requires an available allocation to that dealer.',
        );
      }

      this.access.assertDealer(auth, dealerId);

      return allocation;
    }

    if (!this.access.isPlatformScoped(auth)) {
      throw new ForbiddenException('Direct-customer installation requires platform scope.');
    }

    if (allocation) {
      throw new ConflictException(
        'Dealer-allocated stock cannot be installed for a direct customer.',
      );
    }

    return null;
  }

  private async assertInstallationAvailability(
    deviceId: string,
    vehicleId: string,
    lifecycleStatus: string,
    ignoredVehicleAssignmentId?: string,
  ): Promise<void> {
    if (!['IN_STOCK', 'ALLOCATED'].includes(lifecycleStatus)) {
      throw new ConflictException('Device lifecycle state is not available for installation.');
    }

    const [deviceAssignment, vehiclePrimary] = await Promise.all([
      this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          deviceId,
          status: 'ACTIVE',
        },
        select: {
          id: true,
        },
      }),
      this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          id: ignoredVehicleAssignmentId
            ? {
                not: ignoredVehicleAssignmentId,
              }
            : undefined,
          vehicleId,
          assignmentType: 'PRIMARY',
          status: 'ACTIVE',
        },
        select: {
          id: true,
        },
      }),
    ]);

    if (deviceAssignment) {
      throw new ConflictException('Device already has an active vehicle assignment.');
    }

    if (vehiclePrimary) {
      throw new ConflictException('Vehicle already has an active primary device. Use replacement.');
    }
  }
  private async installWithinTransaction(
    transaction: TransactionClient,
    auth: AuthContext,
    input: {
      deviceId: string;
      vehicleId: string;
      customerId: string;
      dealerId: string | null;
      allocationId?: string;
      installedAt: Date;
      latitude?: number;
      longitude?: number;
      odometerReading?: number;
      powerConnectionType: string | null;
      ignitionConnected: boolean;
      relayConnected: boolean;
      sosConnected: boolean;
      notes: string | null;
    },
  ) {
    const installation = await transaction.deviceInstallation.create({
      data: {
        installationCode: this.codes.installation(),
        deviceId: input.deviceId,
        vehicleId: input.vehicleId,
        dealerOrganizationId: input.dealerId,
        installedByUserId: auth.userId,
        installedAt: input.installedAt,
        installationLocation:
          input.latitude !== undefined && input.longitude !== undefined
            ? {
                latitude: input.latitude,
                longitude: input.longitude,
              }
            : undefined,
        odometerReading: input.odometerReading,
        powerConnectionType: input.powerConnectionType,
        ignitionConnected: input.ignitionConnected,
        relayConnected: input.relayConnected,
        sosConnected: input.sosConnected,
        installationNotes: input.notes,
        status: 'COMPLETED',
      },
    });

    const assignment = await transaction.vehicleDeviceAssignment.create({
      data: {
        vehicleId: input.vehicleId,
        deviceId: input.deviceId,
        installationId: installation.id,
        assignmentType: 'PRIMARY',
        status: 'ACTIVE',
        startedAt: input.installedAt,
        assignedByUserId: auth.userId,
      },
    });

    await this.endCurrentCustody(transaction, input.deviceId, input.installedAt);

    await transaction.deviceCustodyHistory.create({
      data: {
        deviceId: input.deviceId,
        custodianType: 'CUSTOMER',
        custodianCustomerId: input.customerId,
        reason: 'INSTALLATION',
        changedByUserId: auth.userId,
        notes: input.notes,
        startedAt: input.installedAt,
      },
    });

    await transaction.device.update({
      where: {
        id: input.deviceId,
      },
      data: {
        lifecycleStatus: 'INSTALLED',
      },
    });

    await transaction.vehicle.update({
      where: {
        id: input.vehicleId,
      },
      data: {
        status: 'ACTIVE',
      },
    });

    if (input.allocationId) {
      await transaction.dealerDeviceAllocation.update({
        where: {
          id: input.allocationId,
        },
        data: {
          status: 'INSTALLED',
          installedAt: input.installedAt,
        },
      });
    }

    return {
      ...installation,
      assignment,
    };
  }

  private async removeWithinTransaction(
    transaction: TransactionClient,
    auth: AuthContext,
    input: {
      assignmentId: string;
      installationId: string | null;
      deviceId: string;
      dealerId: string | null;
      allocationId?: string;
      assignmentEndReason:
        | 'DEVICE_FAILURE'
        | 'DEVICE_REPLACEMENT'
        | 'VEHICLE_TRANSFER'
        | 'VEHICLE_SOLD'
        | 'CUSTOMER_REQUEST'
        | 'SUBSCRIPTION_CANCELLED'
        | 'TRANSFER_TO_ANOTHER_VEHICLE'
        | 'LOST'
        | 'OTHER';
      removalReason:
        | 'CUSTOMER_REQUEST'
        | 'VEHICLE_SOLD'
        | 'DEVICE_FAILURE'
        | 'WARRANTY_REPLACEMENT'
        | 'SUBSCRIPTION_CANCELLED'
        | 'TRANSFER_TO_ANOTHER_VEHICLE'
        | 'LOST'
        | 'OTHER';
      notes: string | null;
      now: Date;
    },
  ) {
    const assignment = await transaction.vehicleDeviceAssignment.update({
      where: {
        id: input.assignmentId,
      },
      data: {
        status: 'ENDED',
        endedAt: input.now,
        endedByUserId: auth.userId,
        endReason: input.assignmentEndReason,
        endNotes: input.notes,
      },
    });

    let installation = null;

    if (input.installationId) {
      installation = await transaction.deviceInstallation.update({
        where: {
          id: input.installationId,
        },
        data: {
          status: 'REMOVED',
          removedAt: input.now,
          removalReason: input.removalReason,
        },
      });
    }

    await this.endCurrentCustody(transaction, input.deviceId, input.now);

    if (input.dealerId && input.allocationId) {
      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId: input.deviceId,
          custodianType: 'DEALER',
          custodianOrganizationId: input.dealerId,
          reason: 'REMOVAL',
          changedByUserId: auth.userId,
          notes: input.notes,
          startedAt: input.now,
        },
      });

      await transaction.dealerDeviceAllocation.update({
        where: {
          id: input.allocationId,
        },
        data: {
          status: 'AVAILABLE',
          availableAt: input.now,
        },
      });

      await transaction.device.update({
        where: {
          id: input.deviceId,
        },
        data: {
          lifecycleStatus: 'ALLOCATED',
        },
      });
    } else {
      const platformOrganizationId =
        await this.platformOrganizationIdWithinTransaction(transaction);

      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId: input.deviceId,
          custodianType: 'PLATFORM',
          custodianOrganizationId: platformOrganizationId,
          reason: 'REMOVAL',
          changedByUserId: auth.userId,
          notes: input.notes,
          startedAt: input.now,
        },
      });

      await transaction.device.update({
        where: {
          id: input.deviceId,
        },
        data: {
          lifecycleStatus: 'IN_STOCK',
        },
      });
    }

    return {
      assignment,
      installation,
    };
  }

  private listScopeWhere(query: DeviceQueryDto): Prisma.DeviceWhereInput {
    if (query.customerId) {
      return {
        OR: [
          {
            ownershipHistory: {
              some: {
                endedAt: null,
                ownerCustomerId: query.customerId,
              },
            },
          },
          {
            custodyHistory: {
              some: {
                endedAt: null,
                custodianCustomerId: query.customerId,
              },
            },
          },
          {
            vehicleAssignments: {
              some: {
                status: 'ACTIVE',
                vehicle: {
                  customerId: query.customerId,
                },
              },
            },
          },
        ],
      };
    }

    if (query.directCustomers) {
      return {
        OR: [
          {
            ownershipHistory: {
              some: {
                endedAt: null,
                ownerCustomer: {
                  is: {
                    managingDealerId: null,
                  },
                },
              },
            },
          },
          {
            custodyHistory: {
              some: {
                endedAt: null,
                custodianCustomer: {
                  is: {
                    managingDealerId: null,
                  },
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
                    managingDealerId: null,
                  },
                },
              },
            },
          },
        ],
      };
    }

    if (query.dealerOrganizationId) {
      return {
        dealerAllocations: {
          some: {
            dealerOrganizationId: query.dealerOrganizationId,
            status: {
              in: [...activeAllocationStatuses],
            },
          },
        },
      };
    }

    return {};
  }

  private async endCurrentOwnership(
    transaction: TransactionClient,
    deviceId: string,
    endedAt: Date,
  ): Promise<void> {
    await transaction.deviceOwnershipHistory.updateMany({
      where: {
        deviceId,
        endedAt: null,
      },
      data: {
        endedAt,
      },
    });
  }
  private async endCurrentCustody(
    transaction: TransactionClient,
    deviceId: string,
    endedAt: Date,
  ): Promise<void> {
    await transaction.deviceCustodyHistory.updateMany({
      where: {
        deviceId,
        endedAt: null,
      },
      data: {
        endedAt,
      },
    });
  }

  private async platformOrganizationIdWithinTransaction(
    transaction: TransactionClient,
  ): Promise<string> {
    const platform = await transaction.organization.findUnique({
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

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }

  private optionalUpper(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed.toUpperCase() : null;
  }
}
