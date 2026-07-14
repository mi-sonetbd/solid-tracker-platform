import { Body, Controller, Headers, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { GatewayPaymentService } from '../services/gateway-payment.service';

@ApiTags('Payment Gateway Webhooks')
@Controller('payment-gateways/webhooks')
export class PaymentGatewayWebhookController {
  constructor(private readonly gateways: GatewayPaymentService) {}

  @Post(':gateway')
  @ApiOperation({
    summary: 'Receive a verified and idempotent payment gateway callback',
  })
  webhook(
    @Param('gateway') gateway: string,
    @Headers('x-solid-signature')
    signature: string | undefined,
    @Headers('x-solid-event-id')
    eventId: string | undefined,
    @Headers('authorization')
    authorization: string | undefined,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.gateways.webhook(
      gateway,
      {
        signature,
        eventId,
        authorization,
      },
      payload,
    );
  }
}
