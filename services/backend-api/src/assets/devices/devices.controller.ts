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
import { DeviceQueryDto } from '../common/asset-query.dto';
import { DevicesService } from './devices.service';
import { AllocateDeviceDto } from './dto/allocate-device.dto';
import { BulkRegisterDevicesDto } from './dto/bulk-register-devices.dto';
import { InstallDeviceDto } from './dto/install-device.dto';
import { RegisterDeviceDto } from './dto/register-device.dto';
import { RemoveDeviceDto } from './dto/remove-device.dto';
import { ReplaceDeviceDto } from './dto/replace-device.dto';
import { ReturnDeviceDto } from './dto/return-device.dto';
import { TransferDevicesDto } from './dto/transfer-devices.dto';
import { UpdateDeviceDto } from './dto/update-device.dto';

@ApiTags('Devices')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('devices')
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Get()
  @RequirePermissions('device.view')
  @ApiOperation({ summary: 'List devices within effective scope' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: DeviceQueryDto) {
    return this.devicesService.list(auth, query);
  }

  @Post()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Register platform device inventory' })
  register(@CurrentAuth() auth: AuthContext, @Body() dto: RegisterDeviceDto) {
    return this.devicesService.register(auth, dto);
  }

  @Post('bulk')
  @RequirePermissions('device.register')
  @ApiOperation({
    summary: 'Register multiple platform stock devices with per-IMEI results',
  })
  bulkRegister(@CurrentAuth() auth: AuthContext, @Body() dto: BulkRegisterDevicesDto) {
    return this.devicesService.bulkRegister(auth, dto);
  }

  @Post('transfer')
  @RequirePermissions('device.remove')
  @ApiOperation({
    summary: 'Sell or move eligible devices to a scoped Dealer or Customer',
  })
  transfer(@CurrentAuth() auth: AuthContext, @Body() dto: TransferDevicesDto) {
    return this.devicesService.transfer(auth, dto);
  }
  @Get(':deviceId')
  @RequirePermissions('device.view')
  @ApiOperation({ summary: 'Read one device within scope' })
  get(@CurrentAuth() auth: AuthContext, @Param('deviceId', new ParseUUIDPipe()) deviceId: string) {
    return this.devicesService.get(auth, deviceId);
  }

  @Patch(':deviceId')
  @RequirePermissions('device.register')
  @ApiOperation({
    summary: 'Update non-identity inventory metadata and controlled lifecycle state',
  })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: UpdateDeviceDto,
  ) {
    return this.devicesService.update(auth, deviceId, dto);
  }

  @Post(':deviceId/allocate')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Allocate platform inventory to a dealer' })
  allocate(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: AllocateDeviceDto,
  ) {
    return this.devicesService.allocate(auth, deviceId, dto);
  }

  @Post(':deviceId/return')
  @RequirePermissions('device.remove')
  @ApiOperation({
    summary: 'Return uninstalled dealer inventory to the platform',
  })
  returnToPlatform(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: ReturnDeviceDto,
  ) {
    return this.devicesService.returnToPlatform(auth, deviceId, dto);
  }

  @Post(':deviceId/install')
  @RequirePermissions('device.install')
  @ApiOperation({
    summary: 'Install an available device as the primary tracker',
  })
  install(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: InstallDeviceDto,
  ) {
    return this.devicesService.install(auth, deviceId, dto);
  }

  @Post(':deviceId/remove')
  @RequirePermissions('device.remove')
  @ApiOperation({
    summary: 'Remove a currently installed device from its vehicle',
  })
  remove(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: RemoveDeviceDto,
  ) {
    return this.devicesService.remove(auth, deviceId, dto);
  }

  @Post(':deviceId/replace')
  @RequirePermissions('device.replace')
  @ApiOperation({
    summary: 'Transactionally replace the current primary tracker with another device',
  })
  replace(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: ReplaceDeviceDto,
  ) {
    return this.devicesService.replace(auth, deviceId, dto);
  }

  @Get(':deviceId/history')
  @RequirePermissions('device.view')
  @ApiOperation({
    summary: 'Read ownership, custody, allocation, installation, and assignment history',
  })
  history(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
  ) {
    return this.devicesService.history(auth, deviceId);
  }
}
