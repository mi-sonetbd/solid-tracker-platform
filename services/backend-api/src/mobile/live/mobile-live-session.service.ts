import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingPositionsService } from '../../tracking/positions/tracking-positions.service';
import { MobileAccessService } from '../common/mobile-access.service';
import { MobileCacheService } from '../common/mobile-cache.service';
import { mobileJsonSafe } from '../common/mobile-json.util';
import type { CreateLiveSessionDto } from './dto/create-live-session.dto';

export interface StoredLiveSession {
  token: string;
  userId: string;
  vehicleId: string;
  customerId: string;
  createdAt: string;
  expiresAt: string;
  pollAfterSeconds: number;
}

@Injectable()
export class MobileLiveSessionService {
  private readonly defaultTtlSeconds: number;
  private readonly positionCacheTtlSeconds: number;

  constructor(
    private readonly access: MobileAccessService,
    private readonly cache: MobileCacheService,
    private readonly trackingPositions: TrackingPositionsService,
    config: ConfigService,
  ) {
    this.defaultTtlSeconds = Number(config.get('MOBILE_LIVE_SESSION_TTL_SECONDS', 300));
    this.positionCacheTtlSeconds = Number(config.get('MOBILE_LIVE_POSITION_CACHE_TTL_SECONDS', 5));
  }

  async create(auth: AuthContext, dto: CreateLiveSessionDto) {
    const vehicle = await this.access.assertVehicle(auth, dto.vehicleId);
    const ttlSeconds = dto.ttlSeconds ?? this.defaultTtlSeconds;
    const createdAt = new Date();
    const token = randomUUID();
    const session: StoredLiveSession = {
      token,
      userId: auth.userId,
      vehicleId: vehicle.id,
      customerId: vehicle.customerId,
      createdAt: createdAt.toISOString(),
      expiresAt: new Date(createdAt.getTime() + ttlSeconds * 1000).toISOString(),
      pollAfterSeconds: Math.max(2, this.positionCacheTtlSeconds),
    };

    await this.cache.setJson(this.sessionKey(token), session, ttlSeconds);

    return {
      data: session,
      meta: {
        ttlSeconds,
      },
    };
  }

  async get(auth: AuthContext, token: string) {
    const session = await this.authorizedSession(auth, token);

    return {
      data: session,
    };
  }

  async position(auth: AuthContext, token: string) {
    const session = await this.authorizedSession(auth, token);
    await this.access.assertVehicle(auth, session.vehicleId);
    const cacheKey = `mobile:live-position:${session.vehicleId}`;
    const cached = await this.cache.getJson<unknown>(cacheKey);

    if (cached !== null) {
      return {
        data: cached,
        meta: {
          sessionToken: token,
          cacheHit: true,
          pollAfterSeconds: session.pollAfterSeconds,
        },
      };
    }

    const latest = await this.trackingPositions.livePosition(auth, session.vehicleId);
    const safeLatest = mobileJsonSafe(latest);

    await this.cache.setJson(cacheKey, safeLatest, this.positionCacheTtlSeconds);

    return {
      data: safeLatest,
      meta: {
        sessionToken: token,
        cacheHit: false,
        pollAfterSeconds: session.pollAfterSeconds,
      },
    };
  }

  async close(auth: AuthContext, token: string) {
    await this.authorizedSession(auth, token);
    await this.cache.delete(this.sessionKey(token));

    return {
      data: {
        token,
        closed: true,
      },
    };
  }

  private async authorizedSession(auth: AuthContext, token: string): Promise<StoredLiveSession> {
    const session = await this.cache.getJson<StoredLiveSession>(this.sessionKey(token));

    if (!session) {
      throw new NotFoundException('Live tracking session was not found or has expired.');
    }

    if (session.userId !== auth.userId) {
      throw new ForbiddenException('This live tracking session belongs to another user.');
    }

    return session;
  }

  private sessionKey(token: string): string {
    return `mobile:live-session:${token}`;
  }
}
