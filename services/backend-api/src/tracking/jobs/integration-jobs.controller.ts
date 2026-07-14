import { Controller, Get, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { IntegrationJobQueryDto } from '../common/tracking-query.dto';
import { IntegrationJobsService } from './integration-jobs.service';

@ApiTags('Tracking - Integration Jobs')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/integration-jobs')
export class IntegrationJobsController {
  constructor(private readonly integrationJobsService: IntegrationJobsService) {}

  @Get()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'List Traccar integration jobs' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: IntegrationJobQueryDto) {
    return this.integrationJobsService.list(auth, query);
  }

  @Get(':jobId')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Read one Traccar integration job' })
  get(@CurrentAuth() auth: AuthContext, @Param('jobId', new ParseUUIDPipe()) jobId: string) {
    return this.integrationJobsService.get(auth, jobId);
  }

  @Post(':jobId/retry')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Queue a failed integration job again' })
  retry(@CurrentAuth() auth: AuthContext, @Param('jobId', new ParseUUIDPipe()) jobId: string) {
    return this.integrationJobsService.retry(auth, jobId);
  }

  @Post(':jobId/cancel')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Cancel an integration job' })
  cancel(@CurrentAuth() auth: AuthContext, @Param('jobId', new ParseUUIDPipe()) jobId: string) {
    return this.integrationJobsService.cancel(auth, jobId);
  }
}
