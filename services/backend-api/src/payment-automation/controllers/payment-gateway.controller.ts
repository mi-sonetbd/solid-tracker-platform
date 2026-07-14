import { Body, Controller, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { InitializeGatewayPaymentDto } from '../dto/initialize-gateway-payment.dto';
import { ReconcilePaymentsDto } from '../dto/reconcile-payments.dto';
import { GatewayPaymentService } from '../services/gateway-payment.service';
import { PaymentReconciliationService } from '../services/payment-reconciliation.service';

@ApiTags('Payment Gateway Operations')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller()
export class PaymentGatewayController {
  constructor(
    private readonly gateways: GatewayPaymentService,
    private readonly reconciliation: PaymentReconciliationService,
  ) {}

  @Post('payments/:paymentId/gateway/initialize')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary: 'Initialize an existing pending payment with its configured gateway',
  })
  initialize(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', ParseUUIDPipe)
    paymentId: string,
    @Body() dto: InitializeGatewayPaymentDto,
  ) {
    return this.gateways.initialize(auth, paymentId, dto);
  }

  @Post('payments/:paymentId/gateway/reconcile')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary: 'Reconcile one pending gateway payment',
  })
  reconcile(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', ParseUUIDPipe)
    paymentId: string,
  ) {
    return this.gateways.reconcile(auth, paymentId);
  }

  @Post('payment-gateway-events/:eventId/retry')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary: 'Retry one failed, previously verified gateway event',
  })
  retry(
    @CurrentAuth() auth: AuthContext,
    @Param('eventId', ParseUUIDPipe)
    eventId: string,
  ) {
    return this.gateways.retryEvent(auth, eventId);
  }

  @Post('payment-gateways/reconcile')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary: 'Reconcile a bounded batch of pending gateway payments',
  })
  reconcileBatch(@CurrentAuth() auth: AuthContext, @Body() dto: ReconcilePaymentsDto) {
    return this.reconciliation.batch(auth, dto);
  }
}
