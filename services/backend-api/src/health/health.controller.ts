import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { HealthCheck, HealthCheckService } from '@nestjs/terminus';
import { DatabaseHealthIndicator } from './database.health';
import { RedisHealthIndicator } from './redis.health';

@ApiTags('Health')
@Controller('health')
export class HealthController {
  constructor(
    private readonly healthCheckService: HealthCheckService,
    private readonly databaseHealthIndicator: DatabaseHealthIndicator,
    private readonly redisHealthIndicator: RedisHealthIndicator,
  ) {}

  @Get('live')
  @ApiOperation({ summary: 'Check whether the API process is alive' })
  live() {
    return {
      status: 'ok',
      service: 'solid-tracker-backend-api',
      uptimeSeconds: Math.floor(process.uptime()),
      timestamp: new Date().toISOString(),
    };
  }

  @Get('ready')
  @HealthCheck()
  @ApiOperation({ summary: 'Check PostgreSQL and Redis readiness' })
  ready() {
    return this.healthCheckService.check([
      () => this.databaseHealthIndicator.isHealthy('postgresql'),
      () => this.redisHealthIndicator.isHealthy('redis'),
    ]);
  }
}
