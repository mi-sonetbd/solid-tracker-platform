import { Controller, Get, Param, ParseUUIDPipe, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import {
  MobileCursorQueryDto,
  MobileEventQueryDto,
  MobileHistoryQueryDto,
} from '../common/mobile-query.dto';
import { MobileVehiclesService } from './mobile-vehicles.service';

@ApiTags('Mobile - Vehicles')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile/vehicles')
export class MobileVehiclesController {
  constructor(private readonly vehicles: MobileVehiclesService) {}

  @Get()
  @RequirePermissions('vehicle.view')
  @ApiOperation({
    summary: 'List vehicles available to the customer app',
  })
  list(@CurrentAuth() auth: AuthContext, @Query() query: MobileCursorQueryDto) {
    return this.vehicles.list(auth, query);
  }

  @Get(':vehicleId')
  @RequirePermissions('vehicle.view')
  @ApiOperation({
    summary: 'Read a mobile-ready vehicle detail contract',
  })
  detail(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
  ) {
    return this.vehicles.detail(auth, vehicleId);
  }

  @Get(':vehicleId/live-position')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Read the current vehicle position',
  })
  livePosition(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
  ) {
    return this.vehicles.livePosition(auth, vehicleId);
  }

  @Get(':vehicleId/position-history')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({
    summary: 'Read bounded position history for the mobile app',
  })
  history(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
    @Query() query: MobileHistoryQueryDto,
  ) {
    return this.vehicles.history(auth, vehicleId, query);
  }

  @Get(':vehicleId/trips')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({
    summary: 'Read a derived trip feed',
  })
  trips(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
    @Query() query: MobileHistoryQueryDto,
  ) {
    return this.vehicles.tripFeed(auth, vehicleId, query);
  }

  @Get(':vehicleId/events')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({
    summary: 'Read the paginated vehicle event feed',
  })
  events(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
    @Query() query: MobileEventQueryDto,
  ) {
    return this.vehicles.eventFeed(auth, vehicleId, query);
  }
}
