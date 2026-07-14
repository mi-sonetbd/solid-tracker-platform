import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { MobileDashboardService } from '../dashboard/mobile-dashboard.service';
import { MobileProfileService } from './mobile-profile.service';

@ApiTags('Mobile')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile')
export class MobileProfileController {
  constructor(
    private readonly profileService: MobileProfileService,
    private readonly dashboardService: MobileDashboardService,
  ) {}

  @Get('profile')
  @RequirePermissions('customer.view')
  @ApiOperation({
    summary: 'Read the authenticated mobile customer profile',
  })
  profile(@CurrentAuth() auth: AuthContext) {
    return this.profileService.profile(auth);
  }

  @Get('dashboard')
  @RequirePermissions('vehicle.view')
  @ApiOperation({
    summary: 'Read the customer mobile dashboard',
  })
  dashboard(@CurrentAuth() auth: AuthContext) {
    return this.dashboardService.dashboard(auth);
  }
}
