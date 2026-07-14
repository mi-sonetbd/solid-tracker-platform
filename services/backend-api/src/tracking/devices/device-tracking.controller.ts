import { Body, Controller, Get, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { DeviceTrackingService } from './device-tracking.service';
import { SyncTrackingDeviceDto } from './dto/sync-tracking-device.dto';

@ApiTags('Tracking - Device Synchronization')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/devices')
export class DeviceTrackingController {
  constructor(private readonly deviceTrackingService: DeviceTrackingService) {}

  @Get(':deviceId/mappings')
  @RequirePermissions('device.view')
  @ApiOperation({ summary: 'Read Traccar mappings for a device' })
  mapping(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
  ) {
    return this.deviceTrackingService.mapping(auth, deviceId);
  }

  @Post(':deviceId/sync')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Synchronize a device with Traccar' })
  sync(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: SyncTrackingDeviceDto,
  ) {
    return this.deviceTrackingService.sync(auth, deviceId, dto);
  }

  @Post(':deviceId/disable')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Disable a device in Traccar' })
  disable(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
  ) {
    return this.deviceTrackingService.disable(auth, deviceId);
  }
}
