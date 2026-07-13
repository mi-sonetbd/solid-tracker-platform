import { Injectable } from '@nestjs/common';
import { HealthIndicatorService } from '@nestjs/terminus';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class RedisHealthIndicator {
  constructor(
    private readonly redisService: RedisService,
    private readonly healthIndicatorService: HealthIndicatorService,
  ) {}

  async isHealthy(key: string) {
    const indicator = this.healthIndicatorService.check(key);
    const startedAt = Date.now();

    try {
      await this.redisService.ping();
      return indicator.up({ latencyMs: Date.now() - startedAt });
    } catch (error: unknown) {
      return indicator.down({
        latencyMs: Date.now() - startedAt,
        message: error instanceof Error ? error.message : 'Unknown Redis error',
      });
    }
  }
}
