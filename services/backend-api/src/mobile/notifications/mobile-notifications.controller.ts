import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { MobileCursorQueryDto } from '../common/mobile-query.dto';
import { MobileNotificationsService } from './mobile-notifications.service';

@ApiTags('Mobile - Notifications')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile/notifications')
export class MobileNotificationsController {
  constructor(private readonly notifications: MobileNotificationsService) {}

  @Get()
  @RequirePermissions('customer.view')
  @ApiOperation({
    summary: 'List customer and user notifications',
  })
  list(@CurrentAuth() auth: AuthContext, @Query() query: MobileCursorQueryDto) {
    return this.notifications.list(auth, query);
  }
}
