import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

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

export class UpdateVehicleDto {
  @ApiPropertyOptional({ enum: vehicleTypes })
  @IsOptional()
  @IsIn(vehicleTypes)
  vehicleType?: (typeof vehicleTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  registrationNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  manufacturer?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  modelName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  @Min(1886)
  @Max(2100)
  manufacturingYear?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  color?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  chassisNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  engineNumber?: string;

  @ApiPropertyOptional({ enum: vehicleStatuses })
  @IsOptional()
  @IsIn(vehicleStatuses)
  status?: (typeof vehicleStatuses)[number];
}
