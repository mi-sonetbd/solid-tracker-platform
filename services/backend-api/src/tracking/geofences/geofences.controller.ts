import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { GeofenceQueryDto } from '../common/tracking-query.dto';
import { AssignGeofenceDto } from './dto/assign-geofence.dto';
import { CreateGeofenceDto } from './dto/create-geofence.dto';
import { SyncGeofenceDto } from './dto/sync-geofence.dto';
import { UpdateGeofenceDto } from './dto/update-geofence.dto';
import { GeofencesService } from './geofences.service';

@ApiTags('Tracking - Geofences')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/geofences')
export class GeofencesController {
  constructor(private readonly geofencesService: GeofencesService) {}

  @Get()
  @RequirePermissions('vehicle.view')
  @ApiOperation({ summary: 'List geofences within scope' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: GeofenceQueryDto) {
    return this.geofencesService.list(auth, query);
  }

  @Post()
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Create a customer geofence' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateGeofenceDto) {
    return this.geofencesService.create(auth, dto);
  }

  @Get(':geofenceId')
  @RequirePermissions('vehicle.view')
  @ApiOperation({ summary: 'Read one geofence' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
  ) {
    return this.geofencesService.get(auth, geofenceId);
  }

  @Patch(':geofenceId')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Update a geofence' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
    @Body() dto: UpdateGeofenceDto,
  ) {
    return this.geofencesService.update(auth, geofenceId, dto);
  }

  @Post(':geofenceId/archive')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Archive a geofence' })
  archive(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
  ) {
    return this.geofencesService.archive(auth, geofenceId);
  }

  @Post(':geofenceId/sync')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Synchronize a geofence to Traccar' })
  sync(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
    @Body() dto: SyncGeofenceDto,
  ) {
    return this.geofencesService.sync(auth, geofenceId, dto);
  }

  @Post(':geofenceId/assignments')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Assign a vehicle to a geofence' })
  assign(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
    @Body() dto: AssignGeofenceDto,
  ) {
    return this.geofencesService.assign(auth, geofenceId, dto);
  }

  @Post(':geofenceId/assignments/:vehicleId/end')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'End a vehicle geofence assignment' })
  unassign(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
  ) {
    return this.geofencesService.unassign(auth, geofenceId, vehicleId);
  }
}
