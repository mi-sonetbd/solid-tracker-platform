import { Body, Controller, Headers, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { NotificationProviderCallbackDto } from '../dto/notification-provider-callback.dto';
import { NotificationDeliveryService } from './notification-delivery.service';

@ApiTags('Notification provider callbacks')
@Controller('notification-delivery/callbacks')
export class NotificationProviderCallbackController {
  constructor(private readonly delivery: NotificationDeliveryService) {}

  @Post(':provider')
  @ApiOperation({
    summary: 'Process a signed provider delivery callback',
  })
  callback(
    @Param('provider') provider: string,
    @Headers('x-solid-timestamp')
    timestamp: string | undefined,
    @Headers('x-solid-event-id')
    eventId: string | undefined,
    @Headers('x-solid-signature')
    signature: string | undefined,
    @Body() dto: NotificationProviderCallbackDto,
  ) {
    return this.delivery.callback({
      provider,
      timestamp,
      eventId,
      signature,
      dto,
    });
  }
}
