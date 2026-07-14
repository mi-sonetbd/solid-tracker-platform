import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import { randomUUID } from 'node:crypto';

@Injectable()
export class NotificationRateLimiterService implements OnModuleDestroy {
  private readonly client: Redis;

  constructor(config: ConfigService) {
    this.client = new Redis(config.getOrThrow<string>('REDIS_URL'), {
      lazyConnect: true,
      maxRetriesPerRequest: 2,
      enableReadyCheck: true,
    });
  }

  async acquireLock(key: string, ttlMilliseconds: number): Promise<string | null> {
    await this.ensureConnected();
    const token = randomUUID();
    const result = await this.client.set(key, token, 'PX', ttlMilliseconds, 'NX');

    return result === 'OK' ? token : null;
  }

  async releaseLock(key: string, token: string): Promise<void> {
    await this.ensureConnected();
    await this.client.eval(
      `
      if redis.call('get', KEYS[1]) == ARGV[1] then
        return redis.call('del', KEYS[1])
      end
      return 0
      `,
      1,
      key,
      token,
    );
  }

  async consume(input: { key: string; limit: number; windowSeconds: number }): Promise<boolean> {
    await this.ensureConnected();
    const count = await this.client.incr(input.key);

    if (count === 1) {
      await this.client.expire(input.key, input.windowSeconds);
    }

    return count <= input.limit;
  }

  async onModuleDestroy(): Promise<void> {
    if (this.client.status !== 'end') {
      await this.client.quit();
    }
  }

  private async ensureConnected(): Promise<void> {
    if (this.client.status === 'wait') {
      await this.client.connect();
    }
  }
}
