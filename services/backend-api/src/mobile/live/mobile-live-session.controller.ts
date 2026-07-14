import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { CreateLiveSessionDto } from './dto/create-live-session.dto';
import { MobileLiveSessionService } from './mobile-live-session.service';

@ApiTags('Mobile - Live tracking')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile/live-sessions')
export class MobileLiveSessionController {
  constructor(private readonly sessions: MobileLiveSessionService) {}

  @Post()
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Create a bounded live tracking session',
  })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateLiveSessionDto) {
    return this.sessions.create(auth, dto);
  }

  @Get(':sessionToken')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Read live tracking session metadata',
  })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('sessionToken', new ParseUUIDPipe())
    sessionToken: string,
  ) {
    return this.sessions.get(auth, sessionToken);
  }

  @Get(':sessionToken/position')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Read the current position for a live session',
  })
  position(
    @CurrentAuth() auth: AuthContext,
    @Param('sessionToken', new ParseUUIDPipe())
    sessionToken: string,
  ) {
    return this.sessions.position(auth, sessionToken);
  }

  @Delete(':sessionToken')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Close a live tracking session',
  })
  close(
    @CurrentAuth() auth: AuthContext,
    @Param('sessionToken', new ParseUUIDPipe())
    sessionToken: string,
  ) {
    return this.sessions.close(auth, sessionToken);
  }
}
