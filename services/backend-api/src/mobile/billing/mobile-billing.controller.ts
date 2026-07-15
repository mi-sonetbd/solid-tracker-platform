import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { MobileCursorQueryDto } from '../common/mobile-query.dto';
import { MobileBillingService } from './mobile-billing.service';

@ApiTags('Mobile - Billing')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile/billing')
export class MobileBillingController {
  constructor(private readonly billing: MobileBillingService) {}

  @Get('subscriptions')
  @RequirePermissions('subscription.view')
  @ApiOperation({
    summary: 'List customer subscriptions for the mobile app',
  })
  subscriptions(@CurrentAuth() auth: AuthContext, @Query() query: MobileCursorQueryDto) {
    return this.billing.subscriptions(auth, query);
  }

  @Get('invoices')
  @RequirePermissions('invoice.view')
  @ApiOperation({
    summary: 'List customer invoices for the mobile app',
  })
  invoices(@CurrentAuth() auth: AuthContext, @Query() query: MobileCursorQueryDto) {
    return this.billing.invoices(auth, query);
  }
}
