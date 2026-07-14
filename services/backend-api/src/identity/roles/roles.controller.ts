import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { RolesService } from './roles.service';

@ApiTags('Roles')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('roles')
export class RolesController {
  constructor(private readonly rolesService: RolesService) {}

  @Get('me')
  @ApiOperation({ summary: 'List role assignments for the user' })
  listMine(@CurrentAuth() auth: AuthContext) {
    return this.rolesService.listMine(auth);
  }
}
