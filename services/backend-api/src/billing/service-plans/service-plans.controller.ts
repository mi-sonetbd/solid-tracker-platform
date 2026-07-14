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
import { ServicePlanQueryDto } from '../common/billing-query.dto';
import { CreatePlanVersionDto } from './dto/create-plan-version.dto';
import { CreateServicePlanDto } from './dto/create-service-plan.dto';
import { UpdateServicePlanDto } from './dto/update-service-plan.dto';
import { ServicePlansService } from './service-plans.service';

@ApiTags('Service Plans')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('service-plans')
export class ServicePlansController {
  constructor(private readonly servicePlansService: ServicePlansService) {}

  @Get()
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'List service-plan versions' })
  list(@Query() query: ServicePlanQueryDto) {
    return this.servicePlansService.list(query);
  }

  @Post()
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Create a new service-plan family' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateServicePlanDto) {
    return this.servicePlansService.create(auth, dto);
  }

  @Get(':planId')
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'Read one service-plan version' })
  get(@Param('planId', new ParseUUIDPipe()) planId: string) {
    return this.servicePlansService.get(planId);
  }

  @Patch(':planId')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Update a draft or lifecycle state' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('planId', new ParseUUIDPipe()) planId: string,
    @Body() dto: UpdateServicePlanDto,
  ) {
    return this.servicePlansService.update(auth, planId, dto);
  }

  @Post(':planId/activate')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Activate a plan version' })
  activate(@CurrentAuth() auth: AuthContext, @Param('planId', new ParseUUIDPipe()) planId: string) {
    return this.servicePlansService.activate(auth, planId);
  }

  @Post(':planId/versions')
  @RequirePermissions('subscription.create')
  @ApiOperation({
    summary: 'Create the next immutable version in a plan family',
  })
  createVersion(
    @CurrentAuth() auth: AuthContext,
    @Param('planId', new ParseUUIDPipe()) planId: string,
    @Body() dto: CreatePlanVersionDto,
  ) {
    return this.servicePlansService.createVersion(auth, planId, dto);
  }
}
