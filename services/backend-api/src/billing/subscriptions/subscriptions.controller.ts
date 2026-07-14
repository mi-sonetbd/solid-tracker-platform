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
import { SubscriptionQueryDto } from '../common/billing-query.dto';
import { CreateSubscriptionDto } from './dto/create-subscription.dto';
import {
  GenerateSubscriptionInvoiceDto,
  SubscriptionReasonDto,
} from './dto/subscription-action.dto';
import { SubscriptionsService } from './subscriptions.service';

@ApiTags('Subscriptions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('subscriptions')
export class SubscriptionsController {
  constructor(private readonly subscriptionsService: SubscriptionsService) {}

  @Get()
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'List subscriptions within effective scope' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: SubscriptionQueryDto) {
    return this.subscriptionsService.list(auth, query);
  }

  @Post()
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Create a pending vehicle subscription' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateSubscriptionDto) {
    return this.subscriptionsService.create(auth, dto);
  }

  @Get(':subscriptionId')
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'Read one subscription and invoices' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
  ) {
    return this.subscriptionsService.get(auth, subscriptionId);
  }

  @Post(':subscriptionId/activate')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Activate a pending subscription' })
  activate(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
  ) {
    return this.subscriptionsService.activate(auth, subscriptionId);
  }

  @Post(':subscriptionId/suspend')
  @RequirePermissions('subscription.suspend')
  @ApiOperation({ summary: 'Suspend a current subscription' })
  suspend(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
    @Body() dto: SubscriptionReasonDto,
  ) {
    return this.subscriptionsService.suspend(auth, subscriptionId, dto);
  }

  @Post(':subscriptionId/resume')
  @RequirePermissions('subscription.suspend')
  @ApiOperation({ summary: 'Resume a suspended subscription' })
  resume(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
    @Body() dto: SubscriptionReasonDto,
  ) {
    return this.subscriptionsService.resume(auth, subscriptionId, dto);
  }

  @Post(':subscriptionId/cancel')
  @RequirePermissions('subscription.suspend')
  @ApiOperation({ summary: 'Cancel a current subscription' })
  cancel(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
    @Body() dto: SubscriptionReasonDto,
  ) {
    return this.subscriptionsService.cancel(auth, subscriptionId, dto);
  }

  @Post(':subscriptionId/generate-invoice')
  @RequirePermissions('subscription.create')
  @ApiOperation({
    summary: 'Generate one draft invoice for the current period',
  })
  generateInvoice(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
    @Body() dto: GenerateSubscriptionInvoiceDto,
  ) {
    return this.subscriptionsService.generateInvoice(auth, subscriptionId, dto);
  }
}
