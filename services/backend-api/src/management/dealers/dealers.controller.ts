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
import { PaginationQueryDto } from '../common/pagination-query.dto';
import { CreateDealerDto } from './dto/create-dealer.dto';
import { CreateDealerStaffDto } from './dto/create-dealer-staff.dto';
import { UpdateDealerDto } from './dto/update-dealer.dto';
import { UpdateDealerStaffDto } from './dto/update-dealer-staff.dto';
import { DealersService } from './dealers.service';

@ApiTags('Dealers')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('dealers')
export class DealersController {
  constructor(private readonly dealersService: DealersService) {}

  @Get()
  @RequirePermissions('dealer.view')
  @ApiOperation({ summary: 'List dealers within the authenticated scope' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: PaginationQueryDto) {
    return this.dealersService.list(auth, query);
  }

  @Post()
  @RequirePermissions('dealer.manage')
  @ApiOperation({ summary: 'Create a dealer organization' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateDealerDto) {
    return this.dealersService.create(auth, dto);
  }

  @Get(':dealerId')
  @RequirePermissions('dealer.view')
  @ApiOperation({ summary: 'Read one dealer within scope' })
  get(@CurrentAuth() auth: AuthContext, @Param('dealerId', new ParseUUIDPipe()) dealerId: string) {
    return this.dealersService.get(auth, dealerId);
  }

  @Patch(':dealerId')
  @RequirePermissions('dealer.manage')
  @ApiOperation({ summary: 'Update a dealer organization' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Body() dto: UpdateDealerDto,
  ) {
    return this.dealersService.update(auth, dealerId, dto);
  }

  @Get(':dealerId/staff')
  @RequirePermissions('dealer.staff.manage')
  @ApiOperation({ summary: 'List dealer staff and scoped roles' })
  listStaff(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
  ) {
    return this.dealersService.listStaff(auth, dealerId);
  }

  @Post(':dealerId/staff')
  @RequirePermissions('dealer.staff.manage')
  @ApiOperation({ summary: 'Provision or attach a dealer staff user' })
  createStaff(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Body() dto: CreateDealerStaffDto,
  ) {
    return this.dealersService.createStaff(auth, dealerId, dto);
  }

  @Patch(':dealerId/staff/:userId')
  @RequirePermissions('dealer.staff.manage')
  @ApiOperation({ summary: 'Activate or suspend dealer staff access' })
  updateStaff(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Param('userId', new ParseUUIDPipe()) userId: string,
    @Body() dto: UpdateDealerStaffDto,
  ) {
    return this.dealersService.updateStaff(auth, dealerId, userId, dto);
  }
}
