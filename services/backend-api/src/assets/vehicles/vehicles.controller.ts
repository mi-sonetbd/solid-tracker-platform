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
import { VehicleQueryDto } from '../common/asset-query.dto';
import { CreateVehicleDto } from './dto/create-vehicle.dto';
import { UpdateVehicleDto } from './dto/update-vehicle.dto';
import { VehiclesService } from './vehicles.service';

@ApiTags('Vehicles')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('vehicles')
export class VehiclesController {
  constructor(private readonly vehiclesService: VehiclesService) {}

  @Get()
  @RequirePermissions('vehicle.view')
  @ApiOperation({ summary: 'List vehicles within effective scope' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: VehicleQueryDto) {
    return this.vehiclesService.list(auth, query);
  }

  @Post()
  @RequirePermissions('vehicle.create')
  @ApiOperation({ summary: 'Register a vehicle for a customer' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateVehicleDto) {
    return this.vehiclesService.create(auth, dto);
  }

  @Get(':vehicleId')
  @RequirePermissions('vehicle.view')
  @ApiOperation({ summary: 'Read one scoped vehicle' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
  ) {
    return this.vehiclesService.get(auth, vehicleId);
  }

  @Patch(':vehicleId')
  @RequirePermissions('vehicle.update')
  @ApiOperation({ summary: 'Update a scoped vehicle' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
    @Body() dto: UpdateVehicleDto,
  ) {
    return this.vehiclesService.update(auth, vehicleId, dto);
  }

  @Get(':vehicleId/device-history')
  @RequirePermissions('vehicle.view')
  @ApiOperation({
    summary: 'Read historical tracker assignments for a vehicle',
  })
  history(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
  ) {
    return this.vehiclesService.history(auth, vehicleId);
  }
}
