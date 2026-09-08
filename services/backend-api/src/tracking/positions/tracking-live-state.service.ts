import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { RedisService } from '../../redis/redis.service';
import type {
  TraccarPositionDto,
  TraccarPositionWebhookDto,
} from './dto/traccar-position-webhook.dto';

const LIVE_STATE_TTL_SECONDS = 30 * 24 * 60 * 60;

export type TrackingLiveState = {
  vehicleId: string;
  deviceId: string;
  mappingId: string;
  traccarServerId: string;
  sourcePositionId: number | null;
  sourceTimeMs: number;
  lastReportedAt: string;
  lastValidFixAt: string | null;
  hasValidFix: boolean;
  lastValidLatitude: number | null;
  lastValidLongitude: number | null;
  position: TraccarPositionDto;
};

type ProjectionResult = {
  status: 'accepted' | 'duplicate' | 'stale';
  state: TrackingLiveState;
};

@Injectable()
export class TrackingLiveStateService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  async ingest(serverCode: string, dto: TraccarPositionWebhookDto) {
    const position = dto.position;
    const server = await this.prisma.traccarServer.findFirst({
      where: {
        serverCode,
        status: {
          in: ['ACTIVE', 'DEGRADED', 'MAINTENANCE'],
        },
      },
    });

    if (!server) {
      throw new NotFoundException('Webhook Traccar server was not found.');
    }

    const mapping = await this.prisma.traccarDeviceMapping.findFirst({
      where: {
        traccarServerId: server.id,
        traccarDeviceId: BigInt(position.deviceId),
        isActive: true,
        syncStatus: 'SYNCED',
      },
    });

    if (!mapping) {
      throw new NotFoundException(
        'Webhook device does not have an active synchronized Solid Tracker mapping.',
      );
    }

    const assignment = await this.prisma.vehicleDeviceAssignment.findFirst({
      where: {
        deviceId: mapping.deviceId,
        status: 'ACTIVE',
        assignmentType: 'PRIMARY',
      },
    });

    if (!assignment) {
      throw new BadRequestException(
        'Webhook device is not actively assigned as a primary vehicle tracker.',
      );
    }

    const sourceTime = this.sourceTime(position);
    const state: TrackingLiveState = {
      vehicleId: assignment.vehicleId,
      deviceId: mapping.deviceId,
      mappingId: mapping.id,
      traccarServerId: server.id,
      sourcePositionId: position.id ?? null,
      sourceTimeMs: sourceTime.getTime(),
      lastReportedAt: new Date().toISOString(),
      lastValidFixAt: position.valid ? sourceTime.toISOString() : null,
      hasValidFix: position.valid,
      lastValidLatitude: position.valid ? position.latitude : null,
      lastValidLongitude: position.valid ? position.longitude : null,
      position,
    };

    const result = await this.project(state);

    return {
      accepted: result.status === 'accepted',
      duplicate: result.status === 'duplicate',
      stale: result.status === 'stale',
      vehicleId: result.state.vehicleId,
      deviceId: result.state.deviceId,
      mappingId: result.state.mappingId,
      traccarServerId: result.state.traccarServerId,
      position: this.publicPosition(result.state),
    };
  }

  async read(vehicleId: string, mappingId: string): Promise<TrackingLiveState | null> {
    const raw = await this.redis.get(this.key(vehicleId));

    if (!raw) {
      return null;
    }

    let state: TrackingLiveState;

    try {
      state = JSON.parse(raw) as TrackingLiveState;
    } catch {
      await this.redis.delete(this.key(vehicleId));
      return null;
    }

    if (state.mappingId !== mappingId) {
      return null;
    }

    return state;
  }

  publicPosition(state: TrackingLiveState): TraccarPositionDto | null {
    return state.hasValidFix ? state.position : null;
  }

  private async project(state: TrackingLiveState): Promise<ProjectionResult> {
    const script = `
      local key = KEYS[1]
      local incoming = cjson.decode(ARGV[1])
      local ttl = tonumber(ARGV[2])
      local existingRaw = redis.call('GET', key)

      if existingRaw then
        local existing = cjson.decode(existingRaw)

        if existing.mappingId == incoming.mappingId then
          local existingTime = tonumber(existing.sourceTimeMs)
          local incomingTime = tonumber(incoming.sourceTimeMs)

          if incomingTime < existingTime then
            return cjson.encode({ status = 'stale', state = existing })
          end

          if incomingTime == existingTime then
            local existingId = existing.sourcePositionId
            local incomingId = incoming.sourcePositionId

            if existingId == incomingId or incomingId == cjson.null then
              return cjson.encode({ status = 'duplicate', state = existing })
            end

            if existingId ~= cjson.null and tonumber(incomingId) <= tonumber(existingId) then
              return cjson.encode({ status = 'stale', state = existing })
            end
          end

          if incoming.position.valid == false and existing.hasValidFix == true then
            incoming.hasValidFix = true
            incoming.lastValidFixAt = existing.lastValidFixAt
            incoming.lastValidLatitude = existing.lastValidLatitude
            incoming.lastValidLongitude = existing.lastValidLongitude
            incoming.position.latitude = existing.lastValidLatitude
            incoming.position.longitude = existing.lastValidLongitude
          end
        end
      end

      redis.call('SET', key, cjson.encode(incoming), 'EX', ttl)
      return cjson.encode({ status = 'accepted', state = incoming })
    `;

    const raw = await this.redis.eval(
      script,
      [this.key(state.vehicleId)],
      [JSON.stringify(state), LIVE_STATE_TTL_SECONDS.toString()],
    );

    if (typeof raw !== 'string') {
      throw new Error('Unexpected Redis live-state projection result.');
    }

    return JSON.parse(raw) as ProjectionResult;
  }

  private sourceTime(position: TraccarPositionDto): Date {
    const value = position.fixTime ?? position.deviceTime ?? position.serverTime;

    if (!value) {
      throw new BadRequestException(
        'Traccar position must contain fixTime, deviceTime, or serverTime.',
      );
    }

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
      throw new BadRequestException('Traccar position timestamp is invalid.');
    }

    return date;
  }

  private key(vehicleId: string): string {
    return `tracking:live:vehicle:${vehicleId}`;
  }
}
