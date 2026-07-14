import { Controller, Get, Param, ParseUUIDPipe, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { PositionHistoryQueryDto } from '../common/tracking-query.dto';
import { TrackingPositionsService } from './tracking-positions.service';

@ApiTags('Tracking - Positions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/vehicles')
export class TrackingPositionsController {
  constructor(private readonly trackingPositionsService: TrackingPositionsService) {}

  @Get(':vehicleId/live-position')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({ summary: 'Read the latest Traccar position' })
  livePosition(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
  ) {
    return this.trackingPositionsService.livePosition(auth, vehicleId);
  }

  @Get(':vehicleId/position-history')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'Read Traccar position history' })
  history(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
    @Query() query: PositionHistoryQueryDto,
  ) {
    return this.trackingPositionsService.history(auth, vehicleId, query);
  }
}
