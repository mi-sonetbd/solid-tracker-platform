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
import { AssignCustomerGroupDto } from './dto/assign-customer-group.dto';
import { CreateCustomerMemberDto } from './dto/create-customer-member.dto';
import { CreateIndividualCustomerDto } from './dto/create-individual-customer.dto';
import { CreateOrganizationCustomerDto } from './dto/create-organization-customer.dto';
import { CustomerQueryDto } from './dto/customer-query.dto';
import { TransferCustomerDto } from './dto/transfer-customer.dto';
import { CustomersService } from './customers.service';

@ApiTags('Customers')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('customers')
export class CustomersController {
  constructor(private readonly customersService: CustomersService) {}

  @Get()
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'List customers within effective scope' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: CustomerQueryDto) {
    return this.customersService.list(auth, query);
  }

  @Post('individual')
  @RequirePermissions('customer.create')
  @ApiOperation({ summary: 'Create an individual customer' })
  createIndividual(@CurrentAuth() auth: AuthContext, @Body() dto: CreateIndividualCustomerDto) {
    return this.customersService.createIndividual(auth, dto);
  }

  @Post('organization')
  @RequirePermissions('customer.create')
  @ApiOperation({ summary: 'Create an organization customer' })
  createOrganization(@CurrentAuth() auth: AuthContext, @Body() dto: CreateOrganizationCustomerDto) {
    return this.customersService.createOrganization(auth, dto);
  }

  @Get(':customerId')
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'Read one customer within scope' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
  ) {
    return this.customersService.get(auth, customerId);
  }

  @Patch(':customerId/group')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Assign or clear a customer group' })
  assignGroup(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
    @Body() dto: AssignCustomerGroupDto,
  ) {
    return this.customersService.assignGroup(auth, customerId, dto);
  }

  @Post(':customerId/transfer')
  @RequirePermissions('customer.transfer')
  @ApiOperation({
    summary: 'Transfer a customer to another dealer or platform management',
  })
  transfer(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
    @Body() dto: TransferCustomerDto,
  ) {
    return this.customersService.transfer(auth, customerId, dto);
  }

  @Get(':customerId/members')
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'List customer account members' })
  listMembers(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
  ) {
    return this.customersService.listMembers(auth, customerId);
  }

  @Post(':customerId/members')
  @RequirePermissions('customer.update')
  @ApiOperation({
    summary: 'Provision or attach a customer account member',
  })
  createMember(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
    @Body() dto: CreateCustomerMemberDto,
  ) {
    return this.customersService.createMember(auth, customerId, dto);
  }
}
