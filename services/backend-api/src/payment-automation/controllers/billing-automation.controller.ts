import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { RunBillingAutomationDto } from '../dto/run-billing-automation.dto';
import { RecurringBillingService } from '../services/recurring-billing.service';

@ApiTags('Billing Automation')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('billing-automation')
export class BillingAutomationController {
  constructor(private readonly recurringBilling: RecurringBillingService) {}

  @Get('status')
  @RequirePermissions('subscription.view')
  @ApiOperation({
    summary: 'Inspect recurring billing worker configuration and recent runs',
  })
  status() {
    return this.recurringBilling.status();
  }

  @Post('run')
  @RequirePermissions('subscription.create')
  @ApiOperation({
    summary: 'Run one idempotent recurring invoice and overdue cycle',
  })
  run(@CurrentAuth() auth: AuthContext, @Body() dto: RunBillingAutomationDto) {
    return this.recurringBilling.run(auth, dto);
  }
}
