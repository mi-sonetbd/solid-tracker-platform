import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
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
import { CommandQueryDto } from '../common/tracking-query.dto';
import { DeviceCommandsService } from './device-commands.service';
import { ApproveDeviceCommandDto } from './dto/approve-device-command.dto';
import { CreateDeviceCommandDto } from './dto/create-device-command.dto';

@ApiTags('Tracking - Device Commands')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/commands')
export class DeviceCommandsController {
  constructor(private readonly deviceCommandsService: DeviceCommandsService) {}

  @Get()
  @RequirePermissions('command.send')
  @ApiOperation({ summary: 'List device command requests' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: CommandQueryDto) {
    return this.deviceCommandsService.list(auth, query);
  }

  @Post()
  @RequirePermissions('command.send')
  @ApiOperation({ summary: 'Request a device command' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateDeviceCommandDto) {
    return this.deviceCommandsService.create(auth, dto);
  }

  @Get(':commandId')
  @RequirePermissions('command.send')
  @ApiOperation({ summary: 'Read one device command request' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('commandId', new ParseUUIDPipe())
    commandId: string,
  ) {
    return this.deviceCommandsService.get(auth, commandId);
  }

  @Post(':commandId/approve')
  @RequirePermissions('command.send', 'command.engine_cutoff')
  @ApiOperation({
    summary: 'Approve and send a high-risk engine-control command',
  })
  approve(
    @CurrentAuth() auth: AuthContext,
    @Param('commandId', new ParseUUIDPipe())
    commandId: string,
    @Body() dto: ApproveDeviceCommandDto,
  ) {
    return this.deviceCommandsService.approve(auth, commandId, dto);
  }

  @Post(':commandId/cancel')
  @RequirePermissions('command.send')
  @ApiOperation({ summary: 'Cancel a pending device command' })
  cancel(
    @CurrentAuth() auth: AuthContext,
    @Param('commandId', new ParseUUIDPipe())
    commandId: string,
  ) {
    return this.deviceCommandsService.cancel(auth, commandId);
  }
}
