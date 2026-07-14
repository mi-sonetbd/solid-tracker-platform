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
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';
import { DeviceModelsService } from './device-models.service';
import { CreateDeviceModelDto } from './dto/create-device-model.dto';
import { UpdateDeviceModelDto } from './dto/update-device-model.dto';

@ApiTags('Device Models')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('device-models')
export class DeviceModelsController {
  constructor(private readonly deviceModelsService: DeviceModelsService) {}

  @Get()
  @RequirePermissions('device.view')
  @ApiOperation({ summary: 'List active device models' })
  list(@Query() query: PaginationQueryDto) {
    return this.deviceModelsService.list(query);
  }

  @Post()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Create a platform device model' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateDeviceModelDto) {
    return this.deviceModelsService.create(auth, dto);
  }

  @Patch(':deviceModelId')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Update a platform device model' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceModelId', new ParseUUIDPipe())
    deviceModelId: string,
    @Body() dto: UpdateDeviceModelDto,
  ) {
    return this.deviceModelsService.update(auth, deviceModelId, dto);
  }
}
