import { Injectable } from '@nestjs/common';
import { HealthIndicatorService } from '@nestjs/terminus';
import { DatabaseService } from '../database/database.service';

@Injectable()
export class DatabaseHealthIndicator {
  constructor(
    private readonly databaseService: DatabaseService,
    private readonly healthIndicatorService: HealthIndicatorService,
  ) {}

  async isHealthy(key: string) {
    const indicator = this.healthIndicatorService.check(key);
    const startedAt = Date.now();

    try {
      await this.databaseService.ping();
      return indicator.up({ latencyMs: Date.now() - startedAt });
    } catch (error: unknown) {
      return indicator.down({
        latencyMs: Date.now() - startedAt,
        message: error instanceof Error ? error.message : 'Unknown database error',
      });
    }
  }
}
