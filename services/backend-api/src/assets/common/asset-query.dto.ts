import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';

const vehicleStatuses = ['PENDING', 'ACTIVE', 'INACTIVE', 'SUSPENDED', 'ARCHIVED'] as const;

const vehicleTypes = [
  'CAR',
  'MOTORCYCLE',
  'BUS',
  'TRUCK',
  'CNG',
  'PICKUP',
  'MICROBUS',
  'AMBULANCE',
  'CONSTRUCTION_EQUIPMENT',
  'OTHER',
] as const;

const deviceStatuses = [
  'RECEIVED',
  'IN_STOCK',
  'RESERVED',
  'ALLOCATED',
  'INSTALLED',
  'UNDER_REPAIR',
  'LOST',
  'DAMAGED',
  'RETIRED',
] as const;

export class VehicleQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ enum: vehicleStatuses })
  @IsOptional()
  @IsIn(vehicleStatuses)
  status?: (typeof vehicleStatuses)[number];

  @ApiPropertyOptional({ enum: vehicleTypes })
  @IsOptional()
  @IsIn(vehicleTypes)
  vehicleType?: (typeof vehicleTypes)[number];
}

export class DeviceQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  deviceModelId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dealerOrganizationId?: string;

  @ApiPropertyOptional({ enum: deviceStatuses })
  @IsOptional()
  @IsIn(deviceStatuses)
  lifecycleStatus?: (typeof deviceStatuses)[number];
}
