import { Controller, Get, Param, ParseUUIDPipe, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import { PermissionsGuard } from '../access-control/permissions.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { RequirePermissions } from '../common/permissions.decorator';
import { UsersService } from './users.service';

@ApiTags('Users')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('me')
  @ApiOperation({ summary: 'Return the authenticated user profile' })
  me(@CurrentAuth() auth: AuthContext) {
    return this.usersService.findPublicProfile(auth.userId);
  }

  @Get(':userId')
  @RequirePermissions('user.view')
  @ApiOperation({ summary: 'Return a user profile when permitted' })
  findOne(@Param('userId', new ParseUUIDPipe()) userId: string) {
    return this.usersService.findPublicProfile(userId);
  }
}
