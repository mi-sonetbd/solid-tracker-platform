import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { PaymentQueryDto } from '../common/billing-query.dto';
import { CompleteRefundDto, CreateRefundDto } from './dto/create-refund.dto';
import { CreatePaymentDto } from './dto/create-payment.dto';
import { ConfirmPaymentDto } from './dto/confirm-payment.dto';
import { FailPaymentDto } from './dto/fail-payment.dto';
import { GatewayEventDto } from './dto/gateway-event.dto';
import { PaymentsService } from './payments.service';

@ApiTags('Payments')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller()
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Get('payments')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'List payments within effective scope' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: PaymentQueryDto) {
    return this.paymentsService.list(auth, query);
  }

  @Post('payments')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'Initiate or record a pending payment' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreatePaymentDto) {
    return this.paymentsService.create(auth, dto);
  }

  @Get('payments/:paymentId')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'Read one payment and allocations' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', new ParseUUIDPipe()) paymentId: string,
  ) {
    return this.paymentsService.get(auth, paymentId);
  }

  @Post('payments/:paymentId/confirm')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary: 'Confirm a payment, allocate invoices, and calculate commissions',
  })
  confirm(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', new ParseUUIDPipe()) paymentId: string,
    @Body() dto: ConfirmPaymentDto,
  ) {
    return this.paymentsService.confirm(auth, paymentId, dto);
  }

  @Post('payments/:paymentId/fail')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'Mark an initiated payment failed' })
  fail(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', new ParseUUIDPipe()) paymentId: string,
    @Body() dto: FailPaymentDto,
  ) {
    return this.paymentsService.fail(auth, paymentId, dto);
  }

  @Post('payments/:paymentId/refunds')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'Request a refund against a payment' })
  createRefund(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', new ParseUUIDPipe()) paymentId: string,
    @Body() dto: CreateRefundDto,
  ) {
    return this.paymentsService.createRefund(auth, paymentId, dto);
  }

  @Post('refunds/:refundId/complete')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary: 'Complete a refund and append commission reversals',
  })
  completeRefund(
    @CurrentAuth() auth: AuthContext,
    @Param('refundId', new ParseUUIDPipe()) refundId: string,
    @Body() dto: CompleteRefundDto,
  ) {
    return this.paymentsService.completeRefund(auth, refundId, dto);
  }

  @Post('payment-gateway-events')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary: 'Record an idempotent provider event for a future gateway adapter',
  })
  gatewayEvent(@CurrentAuth() auth: AuthContext, @Body() dto: GatewayEventDto) {
    return this.paymentsService.gatewayEvent(auth, dto);
  }
}
