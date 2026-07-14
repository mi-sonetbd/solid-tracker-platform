import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { OrganizationsService } from './organizations.service';

@ApiTags('Organizations')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('organizations')
export class OrganizationsController {
  constructor(private readonly organizationsService: OrganizationsService) {}

  @Get('me')
  @ApiOperation({ summary: 'List organizations linked to the user' })
  listMine(@CurrentAuth() auth: AuthContext) {
    return this.organizationsService.listMine(auth);
  }
}
