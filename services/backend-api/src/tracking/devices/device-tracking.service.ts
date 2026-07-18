import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { jsonSafe } from '../common/tracking-json.util';
import { TraccarClientService } from '../common/traccar-client.service';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import { TraccarServersService } from '../servers/traccar-servers.service';
import type { SyncTrackingDeviceDto } from './dto/sync-tracking-device.dto';

@Injectable()
export class DeviceTrackingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly client: TraccarClientService,
    private readonly servers: TraccarServersService,
    private readonly jobs: IntegrationJobsService,
    private readonly auditService: AuditService,
  ) {}

  async mapping(auth: AuthContext, deviceId: string) {
    await this.access.assertDevice(auth, deviceId);

    const mappings = await this.prisma.traccarDeviceMapping.findMany({
      where: {
        deviceId,
      },
      orderBy: [
        {
          isActive: 'desc',
        },
        {
          isPrimary: 'desc',
        },
        {
          createdAt: 'desc',
        },
      ],
      include: {
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
            baseUrl: true,
            status: true,
            lastHealthStatus: true,
          },
        },
      },
    });

    return jsonSafe(mappings);
  }

  async sync(auth: AuthContext, deviceId: string, dto: SyncTrackingDeviceDto) {
    this.access.assertPlatform(auth);
    return this.synchronize(auth, deviceId, dto);
  }

  syncAfterInstallation(auth: AuthContext, deviceId: string) {
    return this.synchronize(auth, deviceId, {});
  }

  private async synchronize(auth: AuthContext, deviceId: string, dto: SyncTrackingDeviceDto) {
    const device = await this.prisma.device.findUnique({
      where: {
        id: deviceId,
      },
      include: {
        deviceModel: true,
        vehicleAssignments: {
          where: {
            status: 'ACTIVE',
          },
          include: {
            vehicle: true,
          },
          take: 1,
        },
      },
    });

    if (!device) {
      throw new NotFoundException('Device was not found.');
    }

    if (['LOST', 'DAMAGED', 'RETIRED'].includes(device.lifecycleStatus)) {
      throw new ConflictException('This device lifecycle state cannot be synchronized.');
    }

    const uniqueId = device.imei ?? device.serialNumber;

    if (!uniqueId) {
      throw new BadRequestException(
        'The device requires an IMEI or serial number before Traccar synchronization.',
      );
    }

    const server = dto.serverId
      ? await this.prisma.traccarServer.findFirst({
          where: {
            id: dto.serverId,
            status: {
              in: ['ACTIVE', 'DEGRADED'],
            },
          },
        })
      : await this.servers.defaultActive();

    if (!server) {
      throw new NotFoundException('The selected active Traccar server was not found.');
    }

    const job = await this.jobs.create({
      jobType: 'SYNC_DEVICE',
      traccarServerId: server.id,
      entityType: 'Device',
      entityId: deviceId,
      idempotencyKey: dto.forceUpdate
        ? undefined
        : `sync-device:${deviceId}:${server.id}:${device.updatedAt.toISOString()}`,
      payload: {
        uniqueId,
        forceUpdate: dto.forceUpdate ?? false,
      },
    });

    if (job.status === 'SUCCEEDED') {
      const existing = await this.prisma.traccarDeviceMapping.findUnique({
        where: {
          deviceId_traccarServerId: {
            deviceId,
            traccarServerId: server.id,
          },
        },
        include: {
          traccarServer: true,
        },
      });

      return jsonSafe({
        mapping: existing,
        job,
        reused: true,
      });
    }

    await this.jobs.processing(job.id);

    try {
      const matches = await this.client.findDeviceByUniqueId(server, uniqueId);
      const assignedVehicle = device.vehicleAssignments[0]?.vehicle;
      const name =
        assignedVehicle?.registrationNumber ?? assignedVehicle?.vehicleCode ?? device.deviceCode;

      let externalDevice = matches[0];

      if (externalDevice) {
        externalDevice = await this.client.updateDevice(server, BigInt(externalDevice.id), {
          id: externalDevice.id,
          name,
          uniqueId,
          disabled: false,
          category: device.deviceModel.modelName.toLowerCase().includes('motor')
            ? 'motorcycle'
            : 'car',
          attributes: {
            solidTrackerDeviceId: device.id,
            solidTrackerDeviceCode: device.deviceCode,
            hardwareVersion: device.hardwareVersion,
            firmwareVersion: device.firmwareVersion,
          },
        });
      } else {
        externalDevice = await this.client.createDevice(server, {
          name,
          uniqueId,
          disabled: false,
          category: device.deviceModel.modelName.toLowerCase().includes('motor')
            ? 'motorcycle'
            : 'car',
          attributes: {
            solidTrackerDeviceId: device.id,
            solidTrackerDeviceCode: device.deviceCode,
            hardwareVersion: device.hardwareVersion,
            firmwareVersion: device.firmwareVersion,
          },
        });
      }

      const now = new Date();

      const mapping = await this.prisma.$transaction(async (transaction) => {
        await transaction.traccarDeviceMapping.updateMany({
          where: {
            deviceId,
            isActive: true,
            isPrimary: true,
            NOT: {
              traccarServerId: server.id,
            },
          },
          data: {
            isActive: false,
            isPrimary: false,
            syncStatus: 'DISABLED',
            disabledAt: now,
          },
        });

        return transaction.traccarDeviceMapping.upsert({
          where: {
            deviceId_traccarServerId: {
              deviceId,
              traccarServerId: server.id,
            },
          },
          create: {
            deviceId,
            traccarServerId: server.id,
            traccarDeviceId: BigInt(externalDevice.id),
            traccarUniqueId: externalDevice.uniqueId,
            syncStatus: 'SYNCED',
            isPrimary: true,
            isActive: true,
            lastSyncAttemptAt: now,
            lastSyncedAt: now,
            lastSyncError: null,
          },
          update: {
            traccarDeviceId: BigInt(externalDevice.id),
            traccarUniqueId: externalDevice.uniqueId,
            syncStatus: 'SYNCED',
            isPrimary: true,
            isActive: true,
            lastSyncAttemptAt: now,
            lastSyncedAt: now,
            lastSyncError: null,
            disabledAt: null,
          },
          include: {
            traccarServer: true,
          },
        });
      });

      await this.jobs.succeeded(job.id, {
        traccarDeviceId: externalDevice.id,
        mappingId: mapping.id,
      });

      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId: this.access.actorOrganizationId(auth),
        action: 'tracking.device.synchronized',
        resourceType: 'TraccarDeviceMapping',
        resourceId: mapping.id,
        scopeType: 'PLATFORM',
        afterData: jsonSafe(mapping),
      });

      return jsonSafe({
        mapping,
        jobId: job.id,
        reused: false,
      });
    } catch (error) {
      await this.jobs.failed(job.id, error);

      await this.prisma.traccarDeviceMapping.updateMany({
        where: {
          deviceId,
          traccarServerId: server.id,
        },
        data: {
          syncStatus: 'FAILED',
          lastSyncAttemptAt: new Date(),
          lastSyncError: error instanceof Error ? error.message : 'Unknown synchronization error',
        },
      });

      throw error;
    }
  }

  async disable(auth: AuthContext, deviceId: string) {
    this.access.assertPlatform(auth);

    const mapping = await this.prisma.traccarDeviceMapping.findFirst({
      where: {
        deviceId,
        isActive: true,
        isPrimary: true,
      },
      include: {
        traccarServer: true,
        device: {
          include: {
            vehicleAssignments: {
              where: {
                status: 'ACTIVE',
              },
              include: {
                vehicle: true,
              },
              take: 1,
            },
          },
        },
      },
    });

    if (!mapping) {
      throw new NotFoundException('An active primary Traccar mapping was not found.');
    }

    const job = await this.jobs.create({
      jobType: 'DISABLE_DEVICE',
      traccarServerId: mapping.traccarServerId,
      entityType: 'Device',
      entityId: deviceId,
      idempotencyKey: `disable-device:${mapping.id}:${mapping.updatedAt.toISOString()}`,
    });

    await this.jobs.processing(job.id);

    try {
      const assignedVehicle = mapping.device.vehicleAssignments[0]?.vehicle;

      await this.client.updateDevice(mapping.traccarServer, mapping.traccarDeviceId, {
        id: Number(mapping.traccarDeviceId),
        name:
          assignedVehicle?.registrationNumber ??
          assignedVehicle?.vehicleCode ??
          mapping.device.deviceCode,
        uniqueId: mapping.traccarUniqueId,
        disabled: true,
        attributes: {
          solidTrackerDeviceId: deviceId,
        },
      });

      const updated = await this.prisma.traccarDeviceMapping.update({
        where: {
          id: mapping.id,
        },
        data: {
          syncStatus: 'DISABLED',
          isActive: false,
          isPrimary: false,
          disabledAt: new Date(),
          lastSyncAttemptAt: new Date(),
          lastSyncedAt: new Date(),
          lastSyncError: null,
        },
      });

      await this.jobs.succeeded(job.id, {
        mappingId: mapping.id,
      });

      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId: this.access.actorOrganizationId(auth),
        action: 'tracking.device.disabled',
        resourceType: 'TraccarDeviceMapping',
        resourceId: mapping.id,
        scopeType: 'PLATFORM',
        afterData: jsonSafe(updated),
      });

      return jsonSafe(updated);
    } catch (error) {
      await this.jobs.failed(job.id, error);
      throw error;
    }
  }
}
