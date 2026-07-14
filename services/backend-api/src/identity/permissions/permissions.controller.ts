import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';

@ApiTags('Permissions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('permissions')
export class PermissionsController {
  @Get('me')
  @ApiOperation({ summary: 'List effective permission codes for the user' })
  listMine(@CurrentAuth() auth: AuthContext) {
    return {
      permissions: auth.permissions,
    };
  }
}
