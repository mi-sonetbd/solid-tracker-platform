import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma, TraccarServer } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type { GeofenceQueryDto } from '../common/tracking-query.dto';
import { jsonSafe, toInputJson } from '../common/tracking-json.util';
import { TraccarClientService } from '../common/traccar-client.service';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import { TraccarServersService } from '../servers/traccar-servers.service';
import type { AssignGeofenceDto } from './dto/assign-geofence.dto';
import type { CreateGeofenceDto } from './dto/create-geofence.dto';
import type { SyncGeofenceDto } from './dto/sync-geofence.dto';
import type { UpdateGeofenceDto } from './dto/update-geofence.dto';

interface Coordinate {
  latitude: number;
  longitude: number;
}

@Injectable()
export class GeofencesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly client: TraccarClientService,
    private readonly servers: TraccarServersService,
    private readonly jobs: IntegrationJobsService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: GeofenceQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.geofenceWhere(auth);
    const where: Prisma.GeofenceWhereInput = {
      AND: [
        scopeWhere,
        query.customerId
          ? {
              customerId: query.customerId,
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
        query.search
          ? {
              OR: [
                {
                  geofenceCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  name: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  description: {
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
      this.prisma.geofence.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          customer: true,
          traccarServer: {
            select: {
              id: true,
              serverCode: true,
              name: true,
              status: true,
            },
          },
          assignments: {
            where: {
              status: 'ACTIVE',
            },
            include: {
              vehicle: true,
            },
          },
        },
      }),
      this.prisma.geofence.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async get(auth: AuthContext, geofenceId: string) {
    await this.access.assertGeofence(auth, geofenceId);

    const geofence = await this.prisma.geofence.findUnique({
      where: {
        id: geofenceId,
      },
      include: {
        customer: true,
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
            status: true,
          },
        },
        createdBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
        assignments: {
          orderBy: {
            createdAt: 'desc',
          },
          include: {
            vehicle: true,
          },
        },
      },
    });

    return jsonSafe(geofence);
  }

  async create(auth: AuthContext, dto: CreateGeofenceDto) {
    await this.access.assertCustomer(auth, dto.customerId);
    this.validateGeometry(dto.geometryType, dto.geometryData);
    const normalizedName = this.normalizeName(dto.name);

    const duplicate = await this.prisma.geofence.findUnique({
      where: {
        customerId_normalizedName: {
          customerId: dto.customerId,
          normalizedName,
        },
      },
      select: {
        id: true,
      },
    });

    if (duplicate) {
      throw new ConflictException('A geofence with this name already exists for the customer.');
    }

    const geometryData = toInputJson(dto.geometryData);

    if (!geometryData) {
      throw new BadRequestException('Geofence geometry data is required.');
    }

    const geofence = await this.prisma.geofence.create({
      data: {
        geofenceCode: this.codes.geofence(),
        customerId: dto.customerId,
        name: dto.name.trim(),
        normalizedName,
        description: dto.description?.trim() || null,
        geometryType: dto.geometryType,
        geometryData,
        status: dto.status ?? 'DRAFT',
        syncStatus: 'PENDING',
        createdByUserId: auth.userId,
      },
      include: {
        customer: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.created',
      resourceType: 'Geofence',
      resourceId: geofence.id,
      scopeType: 'CUSTOMER',
      scopeId: geofence.customerId,
      afterData: jsonSafe(geofence),
    });

    return jsonSafe(geofence);
  }

  async update(auth: AuthContext, geofenceId: string, dto: UpdateGeofenceDto) {
    await this.access.assertGeofence(auth, geofenceId);
    const before = await this.prisma.geofence.findUnique({
      where: {
        id: geofenceId,
      },
    });

    if (!before) {
      throw new NotFoundException('Geofence was not found.');
    }

    const geometryType = dto.geometryType ?? before.geometryType;
    const geometryData = dto.geometryData ?? (before.geometryData as Record<string, unknown>);

    this.validateGeometry(geometryType, geometryData);

    const updated = await this.prisma.geofence.update({
      where: {
        id: geofenceId,
      },
      data: {
        name: dto.name?.trim(),
        normalizedName: dto.name !== undefined ? this.normalizeName(dto.name) : undefined,
        description: dto.description !== undefined ? dto.description.trim() || null : undefined,
        geometryType: dto.geometryType,
        geometryData: dto.geometryData !== undefined ? toInputJson(dto.geometryData) : undefined,
        status: dto.status,
        syncStatus:
          dto.name !== undefined ||
          dto.description !== undefined ||
          dto.geometryType !== undefined ||
          dto.geometryData !== undefined
            ? 'PENDING'
            : undefined,
        lastSyncError:
          dto.name !== undefined ||
          dto.description !== undefined ||
          dto.geometryType !== undefined ||
          dto.geometryData !== undefined
            ? null
            : undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.updated',
      resourceType: 'Geofence',
      resourceId: geofenceId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async archive(auth: AuthContext, geofenceId: string) {
    await this.access.assertGeofence(auth, geofenceId);

    const activeAssignments = await this.prisma.vehicleGeofenceAssignment.count({
      where: {
        geofenceId,
        status: 'ACTIVE',
      },
    });

    if (activeAssignments > 0) {
      throw new ConflictException('End active vehicle assignments before archiving the geofence.');
    }

    const before = await this.prisma.geofence.findUniqueOrThrow({
      where: {
        id: geofenceId,
      },
    });

    const updated = await this.prisma.geofence.update({
      where: {
        id: geofenceId,
      },
      data: {
        status: 'ARCHIVED',
        archivedAt: new Date(),
        syncStatus: 'DISABLED',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.archived',
      resourceType: 'Geofence',
      resourceId: geofenceId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async assign(auth: AuthContext, geofenceId: string, dto: AssignGeofenceDto) {
    await this.access.assertGeofence(auth, geofenceId);
    const vehicle = await this.access.assertVehicle(auth, dto.vehicleId);
    const geofence = await this.prisma.geofence.findUniqueOrThrow({
      where: {
        id: geofenceId,
      },
      include: {
        traccarServer: true,
      },
    });

    if (geofence.customerId !== vehicle.customerId) {
      throw new BadRequestException('Geofence and vehicle must belong to the same customer.');
    }

    const activeFrom = dto.activeFrom ? new Date(dto.activeFrom) : new Date();
    const activeUntil = dto.activeUntil ? new Date(dto.activeUntil) : null;

    if (activeUntil && activeUntil <= activeFrom) {
      throw new BadRequestException('Geofence assignment end must be after its start.');
    }

    const existing = await this.prisma.vehicleGeofenceAssignment.findFirst({
      where: {
        geofenceId,
        vehicleId: dto.vehicleId,
        status: 'ACTIVE',
      },
    });

    if (existing) {
      throw new ConflictException('This vehicle already has an active assignment to the geofence.');
    }

    const assignment = await this.prisma.vehicleGeofenceAssignment.create({
      data: {
        geofenceId,
        vehicleId: dto.vehicleId,
        monitorEntry: dto.monitorEntry ?? true,
        monitorExit: dto.monitorExit ?? true,
        activeFrom,
        activeUntil,
        status: 'ACTIVE',
      },
      include: {
        geofence: true,
        vehicle: true,
      },
    });

    if (geofence.traccarServer && geofence.traccarGeofenceId && geofence.syncStatus === 'SYNCED') {
      await this.linkVehicle(dto.vehicleId, geofence.traccarServer, geofence.traccarGeofenceId);
    }

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.assigned',
      resourceType: 'VehicleGeofenceAssignment',
      resourceId: assignment.id,
      scopeType: 'VEHICLE',
      scopeId: dto.vehicleId,
      afterData: jsonSafe(assignment),
    });

    return jsonSafe(assignment);
  }

  async unassign(auth: AuthContext, geofenceId: string, vehicleId: string) {
    await this.access.assertGeofence(auth, geofenceId);
    await this.access.assertVehicle(auth, vehicleId);

    const assignment = await this.prisma.vehicleGeofenceAssignment.findFirst({
      where: {
        geofenceId,
        vehicleId,
        status: 'ACTIVE',
      },
      include: {
        geofence: {
          include: {
            traccarServer: true,
          },
        },
      },
    });

    if (!assignment) {
      throw new NotFoundException('Active geofence assignment was not found.');
    }

    if (
      assignment.geofence.traccarServer &&
      assignment.geofence.traccarGeofenceId &&
      assignment.geofence.syncStatus === 'SYNCED'
    ) {
      await this.unlinkVehicle(
        vehicleId,
        assignment.geofence.traccarServer,
        assignment.geofence.traccarGeofenceId,
      );
    }

    const updated = await this.prisma.vehicleGeofenceAssignment.update({
      where: {
        id: assignment.id,
      },
      data: {
        status: 'ENDED',
        activeUntil: new Date(),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.unassigned',
      resourceType: 'VehicleGeofenceAssignment',
      resourceId: assignment.id,
      scopeType: 'VEHICLE',
      scopeId: vehicleId,
      beforeData: jsonSafe(assignment),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async sync(auth: AuthContext, geofenceId: string, dto: SyncGeofenceDto) {
    this.access.assertPlatform(auth);

    const geofence = await this.prisma.geofence.findUnique({
      where: {
        id: geofenceId,
      },
      include: {
        assignments: {
          where: {
            status: 'ACTIVE',
          },
        },
      },
    });

    if (!geofence || geofence.status === 'ARCHIVED') {
      throw new NotFoundException('Active geofence was not found.');
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
      throw new NotFoundException('The selected Traccar server was not found.');
    }

    const job = await this.jobs.create({
      jobType: 'SYNC_GEOFENCE',
      traccarServerId: server.id,
      entityType: 'Geofence',
      entityId: geofenceId,
      idempotencyKey: `sync-geofence:${geofenceId}:${server.id}:${geofence.updatedAt.toISOString()}`,
      payload: {
        geometryType: geofence.geometryType,
      },
    });

    if (job.status === 'SUCCEEDED') {
      return jsonSafe({
        geofence,
        job,
        reused: true,
      });
    }

    await this.jobs.processing(job.id);

    try {
      const area = this.toTraccarArea(
        geofence.geometryType,
        geofence.geometryData as Record<string, unknown>,
      );

      const external =
        geofence.traccarGeofenceId && geofence.traccarServerId === server.id
          ? await this.client.updateGeofence(server, geofence.traccarGeofenceId, {
              id: Number(geofence.traccarGeofenceId),
              name: geofence.name,
              description: geofence.description ?? undefined,
              area,
              attributes: {
                solidTrackerGeofenceId: geofence.id,
                solidTrackerGeofenceCode: geofence.geofenceCode,
              },
            })
          : await this.client.createGeofence(server, {
              name: geofence.name,
              description: geofence.description ?? undefined,
              area,
              attributes: {
                solidTrackerGeofenceId: geofence.id,
                solidTrackerGeofenceCode: geofence.geofenceCode,
              },
            });

      const updated = await this.prisma.geofence.update({
        where: {
          id: geofenceId,
        },
        data: {
          traccarServerId: server.id,
          traccarGeofenceId: BigInt(external.id),
          syncStatus: 'SYNCED',
          lastSyncAttemptAt: new Date(),
          lastSyncedAt: new Date(),
          lastSyncError: null,
        },
        include: {
          traccarServer: true,
        },
      });

      for (const assignment of geofence.assignments) {
        await this.linkVehicle(assignment.vehicleId, server, BigInt(external.id));
      }

      await this.jobs.succeeded(job.id, {
        traccarGeofenceId: external.id,
      });

      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId: this.access.actorOrganizationId(auth),
        action: 'tracking.geofence.synchronized',
        resourceType: 'Geofence',
        resourceId: geofenceId,
        scopeType: 'CUSTOMER',
        scopeId: geofence.customerId,
        afterData: jsonSafe(updated),
      });

      return jsonSafe({
        geofence: updated,
        jobId: job.id,
        reused: false,
      });
    } catch (error) {
      await this.jobs.failed(job.id, error);

      await this.prisma.geofence.update({
        where: {
          id: geofenceId,
        },
        data: {
          syncStatus: 'FAILED',
          lastSyncAttemptAt: new Date(),
          lastSyncError:
            error instanceof Error ? error.message : 'Unknown geofence synchronization error',
        },
      });

      throw error;
    }
  }

  private validateGeometry(
    geometryType: 'CIRCLE' | 'POLYGON' | 'POLYLINE',
    data: Record<string, unknown>,
  ): void {
    if (geometryType === 'CIRCLE') {
      const center = this.coordinate(data.center);
      const radius = Number(data.radius);

      if (!center || !Number.isFinite(radius) || radius <= 0) {
        throw new BadRequestException(
          'Circle geometry requires a valid center and positive radius.',
        );
      }

      return;
    }

    const points = this.points(data.points);
    const minimum = geometryType === 'POLYGON' ? 3 : 2;

    if (points.length < minimum) {
      throw new BadRequestException(
        `${geometryType} geometry requires at least ${minimum} valid points.`,
      );
    }
  }

  private toTraccarArea(
    geometryType: 'CIRCLE' | 'POLYGON' | 'POLYLINE',
    data: Record<string, unknown>,
  ): string {
    if (geometryType === 'CIRCLE') {
      const center = this.coordinate(data.center);
      const radius = Number(data.radius);

      if (!center) {
        throw new BadRequestException('Circle center is invalid.');
      }

      return `CIRCLE (${center.latitude} ${center.longitude}, ${radius})`;
    }

    const points = this.points(data.points);
    const serialized = points.map((point) => `${point.latitude} ${point.longitude}`).join(', ');

    return geometryType === 'POLYGON' ? `POLYGON ((${serialized}))` : `LINESTRING (${serialized})`;
  }

  private points(value: unknown): Coordinate[] {
    if (!Array.isArray(value)) {
      return [];
    }

    return value
      .map((point) => this.coordinate(point))
      .filter((point): point is Coordinate => point !== null);
  }

  private coordinate(value: unknown): Coordinate | null {
    if (!value || typeof value !== 'object') {
      return null;
    }

    const record = value as Record<string, unknown>;
    const latitude = Number(record.latitude);
    const longitude = Number(record.longitude);

    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return null;
    }

    return {
      latitude,
      longitude,
    };
  }

  private normalizeName(value: string): string {
    return value.trim().replace(/\s+/g, ' ').toLowerCase();
  }

  private async linkVehicle(
    vehicleId: string,
    server: TraccarServer,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    const mapping = await this.vehicleMapping(vehicleId, server.id);

    if (mapping) {
      await this.client.linkDeviceGeofence(server, mapping.traccarDeviceId, traccarGeofenceId);
    }
  }

  private async unlinkVehicle(
    vehicleId: string,
    server: TraccarServer,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    const mapping = await this.vehicleMapping(vehicleId, server.id);

    if (mapping) {
      await this.client.unlinkDeviceGeofence(server, mapping.traccarDeviceId, traccarGeofenceId);
    }
  }

  private vehicleMapping(vehicleId: string, serverId: string) {
    return this.prisma.traccarDeviceMapping.findFirst({
      where: {
        traccarServerId: serverId,
        isActive: true,
        isPrimary: true,
        syncStatus: 'SYNCED',
        device: {
          vehicleAssignments: {
            some: {
              vehicleId,
              status: 'ACTIVE',
              assignmentType: 'PRIMARY',
            },
          },
        },
      },
    });
  }
}
