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
import { CreateNotificationTemplateDto } from '../dto/create-notification-template.dto';
import { NotificationTemplateQueryDto } from '../dto/notification-template-query.dto';
import { PreviewNotificationTemplateDto } from '../dto/preview-notification-template.dto';
import { NotificationTemplatesService } from './notification-templates.service';

@ApiTags('Notification templates')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('notification-templates')
export class NotificationTemplatesController {
  constructor(private readonly templates: NotificationTemplatesService) {}

  @Get()
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'List versioned notification templates',
  })
  list(@CurrentAuth() auth: AuthContext, @Query() query: NotificationTemplateQueryDto) {
    return this.templates.list(auth, query);
  }

  @Post()
  @RequirePermissions('notification.template.manage')
  @ApiOperation({
    summary: 'Create a new immutable template version',
  })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateNotificationTemplateDto) {
    return this.templates.createVersion(auth, dto);
  }

  @Post(':templateId/activate')
  @RequirePermissions('notification.template.manage')
  @ApiOperation({
    summary: 'Activate one template version',
  })
  activate(
    @CurrentAuth() auth: AuthContext,
    @Param('templateId', new ParseUUIDPipe())
    templateId: string,
  ) {
    return this.templates.activate(auth, templateId);
  }

  @Post(':templateId/archive')
  @RequirePermissions('notification.template.manage')
  @ApiOperation({
    summary: 'Archive a template version',
  })
  archive(
    @CurrentAuth() auth: AuthContext,
    @Param('templateId', new ParseUUIDPipe())
    templateId: string,
  ) {
    return this.templates.archive(auth, templateId);
  }

  @Post(':templateId/preview')
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'Preview rendered template content',
  })
  preview(
    @CurrentAuth() auth: AuthContext,
    @Param('templateId', new ParseUUIDPipe())
    templateId: string,
    @Body() dto: PreviewNotificationTemplateDto,
  ) {
    return this.templates.preview(auth, templateId, dto.variables);
  }
}
