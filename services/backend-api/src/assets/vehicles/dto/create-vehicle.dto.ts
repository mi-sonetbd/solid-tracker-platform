import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';

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

export class CreateVehicleDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiProperty({ enum: vehicleTypes })
  @IsIn(vehicleTypes)
  vehicleType!: (typeof vehicleTypes)[number];

  @ApiPropertyOptional({ example: 'DHAKA-METRO-GA-12-3456' })
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
}
