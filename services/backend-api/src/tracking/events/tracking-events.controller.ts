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
import { ApiBearerAuth, ApiHeader, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { TrackingEventQueryDto } from '../common/tracking-query.dto';
import { TraccarWebhookDto } from './dto/traccar-webhook.dto';
import { TrackingEventsService } from './tracking-events.service';
import { TrackingWebhookGuard } from './tracking-webhook.guard';

@ApiTags('Tracking - Events')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/events')
export class TrackingEventsController {
  constructor(private readonly trackingEventsService: TrackingEventsService) {}

  @Get()
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'List normalized tracking events' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: TrackingEventQueryDto) {
    return this.trackingEventsService.list(auth, query);
  }

  @Get(':eventId')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'Read one normalized tracking event' })
  get(@CurrentAuth() auth: AuthContext, @Param('eventId', new ParseUUIDPipe()) eventId: string) {
    return this.trackingEventsService.get(auth, eventId);
  }

  @Post(':eventId/acknowledge')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'Acknowledge a tracking event' })
  acknowledge(
    @CurrentAuth() auth: AuthContext,
    @Param('eventId', new ParseUUIDPipe()) eventId: string,
  ) {
    return this.trackingEventsService.acknowledge(auth, eventId);
  }
}

@ApiTags('Tracking - Webhooks')
@Controller('tracking/webhooks')
export class TrackingWebhooksController {
  constructor(private readonly trackingEventsService: TrackingEventsService) {}

  @Post('traccar')
  @UseGuards(TrackingWebhookGuard)
  @ApiHeader({
    name: 'X-Tracking-Webhook-Secret',
    required: true,
  })
  @ApiOperation({
    summary: 'Receive and normalize a Traccar event webhook securely',
  })
  ingest(@Body() dto: TraccarWebhookDto) {
    return this.trackingEventsService.ingest(dto);
  }
}
