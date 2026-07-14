import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { CreateTraccarServerDto } from './dto/create-traccar-server.dto';
import { UpdateTraccarServerDto } from './dto/update-traccar-server.dto';
import { TraccarServersService } from './traccar-servers.service';

@ApiTags('Tracking - Traccar Servers')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/traccar-servers')
export class TraccarServersController {
  constructor(private readonly traccarServersService: TraccarServersService) {}

  @Get()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'List configured Traccar servers' })
  list(@CurrentAuth() auth: AuthContext) {
    return this.traccarServersService.list(auth);
  }

  @Post()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Register a Traccar server securely' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateTraccarServerDto) {
    return this.traccarServersService.create(auth, dto);
  }

  @Get(':serverId')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Read one Traccar server' })
  get(@CurrentAuth() auth: AuthContext, @Param('serverId', new ParseUUIDPipe()) serverId: string) {
    return this.traccarServersService.get(auth, serverId);
  }

  @Patch(':serverId')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Update a Traccar server' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('serverId', new ParseUUIDPipe()) serverId: string,
    @Body() dto: UpdateTraccarServerDto,
  ) {
    return this.traccarServersService.update(auth, serverId, dto);
  }

  @Post(':serverId/health-check')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Check Traccar server health' })
  health(
    @CurrentAuth() auth: AuthContext,
    @Param('serverId', new ParseUUIDPipe()) serverId: string,
  ) {
    return this.traccarServersService.health(auth, serverId);
  }
}
