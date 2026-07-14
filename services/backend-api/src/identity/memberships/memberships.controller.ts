import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { MembershipsService } from './memberships.service';

@ApiTags('Memberships')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('memberships')
export class MembershipsController {
  constructor(private readonly membershipsService: MembershipsService) {}

  @Get('me')
  @ApiOperation({ summary: 'List the user organization and customer memberships' })
  listMine(@CurrentAuth() auth: AuthContext) {
    return this.membershipsService.listMine(auth);
  }
}
