import { BadRequestException } from '@nestjs/common';
import type { PrismaService } from '../../database/prisma.service';
import type { RedisService } from '../../redis/redis.service';
import type { TraccarPositionWebhookDto } from './dto/traccar-position-webhook.dto';
import { TrackingLiveStateService, type TrackingLiveState } from './tracking-live-state.service';

describe('TrackingLiveStateService', () => {
  const server = {
    id: 'server-1',
  };
  const mapping = {
    id: 'mapping-1',
    deviceId: 'device-1',
  };
  const assignment = {
    vehicleId: 'vehicle-1',
  };

  let prisma: {
    traccarServer: { findFirst: jest.Mock };
    traccarDeviceMapping: { findFirst: jest.Mock };
    vehicleDeviceAssignment: { findFirst: jest.Mock };
  };
  let redis: {
    get: jest.Mock;
    eval: jest.Mock;
    delete: jest.Mock;
  };
  let service: TrackingLiveStateService;

  beforeEach(() => {
    prisma = {
      traccarServer: {
        findFirst: jest.fn().mockResolvedValue(server),
      },
      traccarDeviceMapping: {
        findFirst: jest.fn().mockResolvedValue(mapping),
      },
      vehicleDeviceAssignment: {
        findFirst: jest.fn().mockResolvedValue(assignment),
      },
    };
    redis = {
      get: jest.fn(),
      eval: jest.fn().mockImplementation(async (_script, _keys, args: string[]) => {
        const state = JSON.parse(args[0]) as TrackingLiveState;
        return JSON.stringify({ status: 'accepted', state });
      }),
      delete: jest.fn(),
    };
    service = new TrackingLiveStateService(
      prisma as unknown as PrismaService,
      redis as unknown as RedisService,
    );
  });

  it('accepts the current Traccar JSON forwarding envelope and projects its position', async () => {
    const dto = forwardedPosition({
      id: 5001,
      deviceId: 101,
      fixTime: '2026-09-06T08:30:00.000Z',
      valid: true,
      latitude: 23.8103,
      longitude: 90.4125,
      attributes: {
        ignition: true,
      },
    });

    const result = await service.ingest('TRK-PRIMARY', dto);

    expect(prisma.traccarDeviceMapping.findFirst).toHaveBeenCalledWith({
      where: expect.objectContaining({
        traccarServerId: 'server-1',
        traccarDeviceId: 101n,
        isActive: true,
        syncStatus: 'SYNCED',
      }),
    });
    expect(result).toMatchObject({
      accepted: true,
      duplicate: false,
      stale: false,
      vehicleId: 'vehicle-1',
      deviceId: 'device-1',
      mappingId: 'mapping-1',
      traccarServerId: 'server-1',
      position: {
        id: 5001,
        latitude: 23.8103,
        longitude: 90.4125,
        valid: true,
      },
    });
    expect(redis.eval).toHaveBeenCalledTimes(1);
  });

  it('rejects a forwarded position without a usable timestamp', async () => {
    const dto = forwardedPosition({
      deviceId: 101,
      valid: true,
      latitude: 23.8103,
      longitude: 90.4125,
    });

    await expect(service.ingest('TRK-PRIMARY', dto)).rejects.toBeInstanceOf(BadRequestException);
    expect(redis.eval).not.toHaveBeenCalled();
  });

  it('ignores a cached projection that belongs to an old tracker mapping', async () => {
    redis.get.mockResolvedValue(
      JSON.stringify({
        vehicleId: 'vehicle-1',
        deviceId: 'old-device',
        mappingId: 'old-mapping',
        traccarServerId: 'server-1',
        sourcePositionId: 1,
        sourceTimeMs: 1,
        lastReportedAt: '2026-09-06T08:30:00.000Z',
        lastValidFixAt: '2026-09-06T08:30:00.000Z',
        hasValidFix: true,
        lastValidLatitude: 23.8,
        lastValidLongitude: 90.4,
        position: {
          deviceId: 99,
          valid: true,
          latitude: 23.8,
          longitude: 90.4,
        },
      } satisfies TrackingLiveState),
    );

    await expect(service.read('vehicle-1', 'mapping-1')).resolves.toBeNull();
  });

  it('does not expose coordinates before the first valid GPS fix', () => {
    const state = {
      vehicleId: 'vehicle-1',
      deviceId: 'device-1',
      mappingId: 'mapping-1',
      traccarServerId: 'server-1',
      sourcePositionId: 1,
      sourceTimeMs: 1,
      lastReportedAt: '2026-09-06T08:30:00.000Z',
      lastValidFixAt: null,
      hasValidFix: false,
      lastValidLatitude: null,
      lastValidLongitude: null,
      position: {
        deviceId: 101,
        valid: false,
        latitude: 0,
        longitude: 0,
      },
    } satisfies TrackingLiveState;

    expect(service.publicPosition(state)).toBeNull();
  });

  function forwardedPosition(
    position: TraccarPositionWebhookDto['position'],
  ): TraccarPositionWebhookDto {
    return {
      position,
      device: {
        id: position.deviceId,
        uniqueId: '860000000000001',
        name: 'Test tracker',
      },
    };
  }
});
