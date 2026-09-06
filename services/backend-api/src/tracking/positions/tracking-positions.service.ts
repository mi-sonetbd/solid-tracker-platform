import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import type { PositionHistoryQueryDto } from '../common/tracking-query.dto';
import { TraccarClientService } from '../common/traccar-client.service';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import { TrackingLiveStateService } from './tracking-live-state.service';

@Injectable()
export class TrackingPositionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly client: TraccarClientService,
    private readonly jobs: IntegrationJobsService,
    private readonly liveState: TrackingLiveStateService,
  ) {}

  async livePosition(auth: AuthContext, vehicleId: string) {
    await this.access.assertVehicle(auth, vehicleId);
    const assignment = await this.activePrimaryMapping(vehicleId);
    const mapping = assignment.device.traccarMappings[0];
    const projected = await this.liveState.read(vehicleId, mapping.id);

    if (projected) {
      return {
        vehicleId,
        deviceId: assignment.deviceId,
        mappingId: mapping.id,
        traccarServerId: mapping.traccarServerId,
        position: this.liveState.publicPosition(projected),
      };
    }

    const job = await this.jobs.create({
      jobType: 'FETCH_LATEST_POSITION',
      traccarServerId: mapping.traccarServerId,
      entityType: 'Vehicle',
      entityId: vehicleId,
      idempotencyKey: undefined,
      payload: {
        deviceId: assignment.deviceId,
      },
      maximumAttempts: 3,
    });

    await this.jobs.processing(job.id);

    try {
      const positions = await this.client.latestPositions(
        mapping.traccarServer,
        mapping.traccarDeviceId,
      );
      const latest = [...positions].sort((left, right) => {
        const leftTime = Date.parse(left.fixTime ?? left.deviceTime ?? left.serverTime ?? '0');
        const rightTime = Date.parse(right.fixTime ?? right.deviceTime ?? right.serverTime ?? '0');

        return rightTime - leftTime;
      })[0];

      await this.jobs.succeeded(job.id, {
        positionId: latest?.id,
      });

      return {
        vehicleId,
        deviceId: assignment.deviceId,
        mappingId: mapping.id,
        traccarServerId: mapping.traccarServerId,
        position: latest ?? null,
      };
    } catch (error) {
      await this.jobs.failed(job.id, error);
      throw error;
    }
  }

  async history(auth: AuthContext, vehicleId: string, query: PositionHistoryQueryDto) {
    await this.access.assertVehicle(auth, vehicleId);
    const assignment = await this.activePrimaryMapping(vehicleId);
    const { from, to } = this.range(query);
    const mapping = assignment.device.traccarMappings[0];
    const positions = await this.client.positionHistory(
      mapping.traccarServer,
      mapping.traccarDeviceId,
      from,
      to,
    );

    return {
      vehicleId,
      deviceId: assignment.deviceId,
      mappingId: mapping.id,
      from,
      to,
      positions,
    };
  }

  private async activePrimaryMapping(vehicleId: string) {
    const assignment = await this.prisma.vehicleDeviceAssignment.findFirst({
      where: {
        vehicleId,
        status: 'ACTIVE',
        assignmentType: 'PRIMARY',
      },
      include: {
        device: {
          include: {
            traccarMappings: {
              where: {
                isActive: true,
                isPrimary: true,
                syncStatus: 'SYNCED',
              },
              include: {
                traccarServer: true,
              },
              take: 1,
            },
          },
        },
      },
    });

    if (!assignment) {
      throw new NotFoundException('The vehicle has no active primary tracker.');
    }

    if (assignment.device.traccarMappings.length === 0) {
      throw new NotFoundException('The active tracker has no synchronized Traccar mapping.');
    }

    return assignment;
  }

  private range(query: PositionHistoryQueryDto): {
    from: Date;
    to: Date;
  } {
    const to = query.to ? new Date(query.to) : new Date();
    const from = query.from ? new Date(query.from) : new Date(to.getTime() - 24 * 60 * 60 * 1000);

    if (from >= to) {
      throw new BadRequestException('Position-history from must be earlier than to.');
    }

    const maximumRangeMs = 31 * 24 * 60 * 60 * 1000;

    if (to.getTime() - from.getTime() > maximumRangeMs) {
      throw new BadRequestException('Position-history range cannot exceed 31 days.');
    }

    return {
      from,
      to,
    };
  }
}
