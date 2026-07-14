import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
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
import { NotificationQueryDto, NotificationRuleQueryDto } from '../common/tracking-query.dto';
import { CreateNotificationRuleDto } from './dto/create-notification-rule.dto';
import { UpdateNotificationDeliveryDto } from './dto/update-notification-delivery.dto';
import { UpdateNotificationRuleDto } from './dto/update-notification-rule.dto';
import { NotificationsService } from './notifications.service';

@ApiTags('Tracking - Notification Rules')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/notification-rules')
export class NotificationRulesController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get()
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'List notification rules' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: NotificationRuleQueryDto) {
    return this.notificationsService.listRules(auth, query);
  }

  @Post()
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Create a notification rule' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateNotificationRuleDto) {
    return this.notificationsService.createRule(auth, dto);
  }

  @Patch(':ruleId')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Update a notification rule' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('ruleId', new ParseUUIDPipe()) ruleId: string,
    @Body() dto: UpdateNotificationRuleDto,
  ) {
    return this.notificationsService.updateRule(auth, ruleId, dto);
  }

  @Post(':ruleId/archive')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Archive a notification rule' })
  archive(@CurrentAuth() auth: AuthContext, @Param('ruleId', new ParseUUIDPipe()) ruleId: string) {
    return this.notificationsService.archiveRule(auth, ruleId);
  }
}

@ApiTags('Tracking - Notifications')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get()
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'List generated tracking notifications' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: NotificationQueryDto) {
    return this.notificationsService.listNotifications(auth, query);
  }

  @Get(':notificationId')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'Read one tracking notification' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('notificationId', new ParseUUIDPipe())
    notificationId: string,
  ) {
    return this.notificationsService.getNotification(auth, notificationId);
  }

  @Post(':notificationId/delivery-status')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({
    summary: 'Update delivery status from an internal provider adapter',
  })
  updateDelivery(
    @CurrentAuth() auth: AuthContext,
    @Param('notificationId', new ParseUUIDPipe())
    notificationId: string,
    @Body() dto: UpdateNotificationDeliveryDto,
  ) {
    return this.notificationsService.updateDelivery(auth, notificationId, dto);
  }
}
