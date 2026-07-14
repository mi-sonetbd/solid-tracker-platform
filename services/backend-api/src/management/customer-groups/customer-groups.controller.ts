import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { CustomerGroupsService } from './customer-groups.service';
import { CreateCustomerGroupDto } from './dto/create-customer-group.dto';
import { UpdateCustomerGroupDto } from './dto/update-customer-group.dto';

@ApiTags('Customer Groups')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('dealers/:dealerId/customer-groups')
export class CustomerGroupsController {
  constructor(private readonly customerGroupsService: CustomerGroupsService) {}

  @Get()
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'List customer groups for a dealer' })
  list(@CurrentAuth() auth: AuthContext, @Param('dealerId', new ParseUUIDPipe()) dealerId: string) {
    return this.customerGroupsService.list(auth, dealerId);
  }

  @Post()
  @RequirePermissions('customer.create')
  @ApiOperation({ summary: 'Create a dealer customer group' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Body() dto: CreateCustomerGroupDto,
  ) {
    return this.customerGroupsService.create(auth, dealerId, dto);
  }

  @Patch(':groupId')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Update or archive a customer group' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Param('groupId', new ParseUUIDPipe()) groupId: string,
    @Body() dto: UpdateCustomerGroupDto,
  ) {
    return this.customerGroupsService.update(auth, dealerId, groupId, dto);
  }
}
