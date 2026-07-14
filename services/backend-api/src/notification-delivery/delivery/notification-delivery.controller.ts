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
import { EnqueueTemplateNotificationDto } from '../dto/enqueue-template-notification.dto';
import { NotificationDeliveryQueryDto } from '../dto/notification-delivery-query.dto';
import { RetryNotificationDto } from '../dto/retry-notification.dto';
import { RunNotificationDeliveryDto } from '../dto/run-notification-delivery.dto';
import { NotificationDeliveryService } from './notification-delivery.service';

@ApiTags('Notification delivery')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('notification-delivery')
export class NotificationDeliveryController {
  constructor(private readonly delivery: NotificationDeliveryService) {}

  @Get()
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'List scoped notification outbox records',
  })
  list(@CurrentAuth() auth: AuthContext, @Query() query: NotificationDeliveryQueryDto) {
    return this.delivery.list(auth, query);
  }

  @Post('enqueue')
  @RequirePermissions('notification.delivery.manage')
  @ApiOperation({
    summary: 'Enqueue a rendered template notification',
  })
  enqueue(@CurrentAuth() auth: AuthContext, @Body() dto: EnqueueTemplateNotificationDto) {
    return this.delivery.enqueue(auth, dto);
  }

  @Post('run')
  @RequirePermissions('notification.delivery.manage')
  @ApiOperation({
    summary: 'Run one bounded notification delivery batch',
  })
  run(@CurrentAuth() auth: AuthContext, @Body() dto: RunNotificationDeliveryDto) {
    return this.delivery.run(auth, dto.batchSize);
  }

  @Get('metrics')
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'Read notification delivery operational metrics',
  })
  metrics(@CurrentAuth() auth: AuthContext) {
    return this.delivery.metrics(auth);
  }

  @Get('dead-letters')
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'List dead-lettered delivery attempts',
  })
  deadLetters(@CurrentAuth() auth: AuthContext, @Query() query: NotificationDeliveryQueryDto) {
    return this.delivery.deadLetters(auth, query);
  }

  @Get(':notificationId/attempts')
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'List immutable delivery attempts',
  })
  attempts(
    @CurrentAuth() auth: AuthContext,
    @Param('notificationId', new ParseUUIDPipe())
    notificationId: string,
  ) {
    return this.delivery.attempts(auth, notificationId);
  }

  @Post(':notificationId/retry')
  @RequirePermissions('notification.delivery.manage')
  @ApiOperation({
    summary: 'Manually retry a failed notification',
  })
  retry(
    @CurrentAuth() auth: AuthContext,
    @Param('notificationId', new ParseUUIDPipe())
    notificationId: string,
    @Body() dto: RetryNotificationDto,
  ) {
    return this.delivery.retry(auth, notificationId, dto);
  }
}
