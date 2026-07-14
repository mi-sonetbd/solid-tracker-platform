import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type { CommandQueryDto } from '../common/tracking-query.dto';
import { jsonSafe, toInputJson } from '../common/tracking-json.util';
import { TraccarClientService } from '../common/traccar-client.service';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import type { ApproveDeviceCommandDto } from './dto/approve-device-command.dto';
import type { CreateDeviceCommandDto } from './dto/create-device-command.dto';

@Injectable()
export class DeviceCommandsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly client: TraccarClientService,
    private readonly jobs: IntegrationJobsService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: CommandQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.commandWhere(auth);
    const where: Prisma.DeviceCommandRequestWhereInput = {
      AND: [
        scopeWhere,
        query.deviceId
          ? {
              deviceId: query.deviceId,
            }
          : {},
        query.vehicleId
          ? {
              vehicleId: query.vehicleId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  commandCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  reason: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.deviceCommandRequest.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          requestedAt: 'desc',
        },
        include: {
          device: true,
          vehicle: true,
          traccarServer: {
            select: {
              id: true,
              serverCode: true,
              name: true,
            },
          },
          requestedBy: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
          approvedBy: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
        },
      }),
      this.prisma.deviceCommandRequest.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async get(auth: AuthContext, commandId: string) {
    await this.access.assertCommand(auth, commandId);

    const command = await this.prisma.deviceCommandRequest.findUnique({
      where: {
        id: commandId,
      },
      include: {
        device: true,
        vehicle: true,
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
          },
        },
        requestedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
        approvedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
      },
    });

    return jsonSafe(command);
  }

  async create(auth: AuthContext, dto: CreateDeviceCommandDto) {
    await this.access.assertDevice(auth, dto.deviceId);

    const engineControl = ['ENGINE_CUTOFF', 'ENGINE_RESTORE'].includes(dto.commandType);

    if (engineControl && !auth.permissions.includes('command.engine_cutoff')) {
      throw new ForbiddenException('Engine-control permission is required.');
    }

    const mapping = await this.prisma.traccarDeviceMapping.findFirst({
      where: {
        deviceId: dto.deviceId,
        isActive: true,
        isPrimary: true,
        syncStatus: 'SYNCED',
      },
      include: {
        traccarServer: true,
      },
    });

    if (!mapping) {
      throw new NotFoundException('The device has no active synchronized Traccar mapping.');
    }

    let vehicleId = dto.vehicleId;

    if (vehicleId) {
      await this.access.assertVehicle(auth, vehicleId);
      const assignment = await this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          deviceId: dto.deviceId,
          vehicleId,
          status: 'ACTIVE',
        },
        select: {
          id: true,
        },
      });

      if (!assignment) {
        throw new BadRequestException(
          'Command device must be actively assigned to the selected vehicle.',
        );
      }
    } else if (engineControl) {
      const assignment = await this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          deviceId: dto.deviceId,
          status: 'ACTIVE',
        },
        select: {
          vehicleId: true,
        },
      });

      vehicleId = assignment?.vehicleId;

      if (!vehicleId) {
        throw new BadRequestException(
          'Engine-control commands require an active vehicle assignment.',
        );
      }
    }

    const expiresAt = dto.expiresAt
      ? new Date(dto.expiresAt)
      : new Date(Date.now() + 15 * 60 * 1000);

    if (expiresAt <= new Date()) {
      throw new BadRequestException('Command expiry must be in the future.');
    }

    const command = await this.prisma.deviceCommandRequest.create({
      data: {
        commandCode: this.codes.command(),
        deviceId: dto.deviceId,
        vehicleId,
        traccarServerId: mapping.traccarServerId,
        requestedByUserId: auth.userId,
        commandType: dto.commandType,
        parameters: toInputJson(dto.parameters),
        reason: dto.reason.trim(),
        status: engineControl ? 'PENDING_APPROVAL' : 'QUEUED',
        requiresApproval: engineControl,
        expiresAt,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.command.requested',
      resourceType: 'DeviceCommandRequest',
      resourceId: command.id,
      scopeType: command.vehicleId
        ? 'VEHICLE'
        : this.access.isPlatformScoped(auth)
          ? 'PLATFORM'
          : undefined,
      scopeId: command.vehicleId ?? undefined,
      afterData: jsonSafe(command),
    });

    if (engineControl) {
      return jsonSafe(command);
    }

    return this.send(command.id);
  }

  async approve(auth: AuthContext, commandId: string, dto: ApproveDeviceCommandDto) {
    if (!auth.permissions.includes('command.engine_cutoff')) {
      throw new ForbiddenException('Engine-control permission is required.');
    }

    const command = await this.prisma.deviceCommandRequest.findUnique({
      where: {
        id: commandId,
      },
    });

    if (!command) {
      throw new NotFoundException('Device command was not found.');
    }

    if (command.status !== 'PENDING_APPROVAL') {
      throw new BadRequestException('Only pending-approval commands may be approved.');
    }

    if (command.requestedByUserId === auth.userId) {
      throw new ForbiddenException(
        'The command requester cannot approve the same high-risk command.',
      );
    }

    if (command.expiresAt && command.expiresAt <= new Date()) {
      await this.prisma.deviceCommandRequest.update({
        where: {
          id: commandId,
        },
        data: {
          status: 'EXPIRED',
        },
      });

      throw new BadRequestException('The command approval window has expired.');
    }

    const approved = await this.prisma.deviceCommandRequest.update({
      where: {
        id: commandId,
      },
      data: {
        approvedByUserId: auth.userId,
        approvedAt: new Date(),
        status: 'QUEUED',
        parameters: toInputJson({
          ...(command.parameters && typeof command.parameters === 'object'
            ? command.parameters
            : {}),
          approvalNote: dto.approvalNote,
        }),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.command.approved',
      resourceType: 'DeviceCommandRequest',
      resourceId: commandId,
      scopeType: command.vehicleId
        ? 'VEHICLE'
        : this.access.isPlatformScoped(auth)
          ? 'PLATFORM'
          : undefined,
      scopeId: command.vehicleId ?? undefined,
      beforeData: jsonSafe(command),
      afterData: jsonSafe(approved),
    });

    return this.send(commandId);
  }

  async cancel(auth: AuthContext, commandId: string) {
    await this.access.assertCommand(auth, commandId);

    const command = await this.prisma.deviceCommandRequest.findUnique({
      where: {
        id: commandId,
      },
    });

    if (!command) {
      throw new NotFoundException('Device command was not found.');
    }

    if (!['PENDING_APPROVAL', 'QUEUED'].includes(command.status)) {
      throw new BadRequestException('The command cannot be cancelled in its current state.');
    }

    if (command.requestedByUserId !== auth.userId && !this.access.isPlatformScoped(auth)) {
      throw new ForbiddenException(
        'Only the requester or platform operator may cancel the command.',
      );
    }

    const updated = await this.prisma.deviceCommandRequest.update({
      where: {
        id: commandId,
      },
      data: {
        status: 'CANCELLED',
        failureReason: 'Cancelled by an authorized user.',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.command.cancelled',
      resourceType: 'DeviceCommandRequest',
      resourceId: commandId,
      scopeType: command.vehicleId
        ? 'VEHICLE'
        : this.access.isPlatformScoped(auth)
          ? 'PLATFORM'
          : undefined,
      scopeId: command.vehicleId ?? undefined,
      beforeData: jsonSafe(command),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  private async send(commandId: string) {
    const command = await this.prisma.deviceCommandRequest.findUniqueOrThrow({
      where: {
        id: commandId,
      },
      include: {
        traccarServer: true,
        device: {
          include: {
            traccarMappings: {
              where: {
                isActive: true,
                isPrimary: true,
                syncStatus: 'SYNCED',
              },
              take: 1,
            },
          },
        },
      },
    });

    if (!command.traccarServer) {
      throw new NotFoundException('Command Traccar server was not found.');
    }

    const mapping = command.device.traccarMappings[0];

    if (!mapping) {
      throw new NotFoundException('Command device mapping was not found.');
    }

    const job = await this.jobs.create({
      jobType: 'SEND_COMMAND',
      traccarServerId: command.traccarServerId ?? undefined,
      entityType: 'DeviceCommandRequest',
      entityId: command.id,
      idempotencyKey: `send-command:${command.id}`,
      payload: {
        commandType: command.commandType,
        parameters: command.parameters,
      },
      maximumAttempts: 3,
    });

    if (job.status === 'SUCCEEDED' && command.status === 'COMPLETED') {
      return jsonSafe(command);
    }

    await this.jobs.processing(job.id);

    try {
      await this.prisma.deviceCommandRequest.update({
        where: {
          id: command.id,
        },
        data: {
          status: 'SENT',
          sentAt: new Date(),
        },
      });

      const response = await this.client.sendCommand(
        command.traccarServer,
        mapping.traccarDeviceId,
        {
          type: this.traccarCommandType(command.commandType),
          attributes:
            command.parameters && typeof command.parameters === 'object'
              ? (command.parameters as Record<string, unknown>)
              : {},
        },
      );

      const completed = await this.prisma.deviceCommandRequest.update({
        where: {
          id: command.id,
        },
        data: {
          status: 'COMPLETED',
          traccarCommandId: response.id !== undefined ? BigInt(response.id) : undefined,
          acknowledgedAt: new Date(),
          completedAt: new Date(),
          failureReason: null,
        },
      });

      await this.jobs.succeeded(job.id, response);

      return jsonSafe(completed);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown command error';

      await this.prisma.deviceCommandRequest.update({
        where: {
          id: command.id,
        },
        data: {
          status: 'FAILED',
          failedAt: new Date(),
          failureReason: message,
        },
      });

      await this.jobs.failed(job.id, error);
      throw error;
    }
  }

  private traccarCommandType(
    commandType:
      | 'REQUEST_POSITION'
      | 'RESTART_DEVICE'
      | 'SET_REPORTING_INTERVAL'
      | 'ACTIVATE_RELAY'
      | 'DEACTIVATE_RELAY'
      | 'ENGINE_CUTOFF'
      | 'ENGINE_RESTORE'
      | 'CHANGE_SERVER'
      | 'CUSTOM',
  ): string {
    const mapping: Record<string, string> = {
      REQUEST_POSITION: 'positionSingle',
      RESTART_DEVICE: 'rebootDevice',
      SET_REPORTING_INTERVAL: 'custom',
      ACTIVATE_RELAY: 'custom',
      DEACTIVATE_RELAY: 'custom',
      ENGINE_CUTOFF: 'engineStop',
      ENGINE_RESTORE: 'engineResume',
      CHANGE_SERVER: 'custom',
      CUSTOM: 'custom',
    };

    return mapping[commandType];
  }
}
