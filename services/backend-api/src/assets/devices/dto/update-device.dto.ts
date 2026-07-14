import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

const lifecycleStatuses = [
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

export class UpdateDeviceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  hardwareVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  firmwareVersion?: string;

  @ApiPropertyOptional({ enum: lifecycleStatuses })
  @IsOptional()
  @IsIn(lifecycleStatuses)
  lifecycleStatus?: (typeof lifecycleStatuses)[number];

  @ApiPropertyOptional({
    description: 'Required when lifecycleStatus is RETIRED; cleared for all other statuses.',
  })
  @IsOptional()
  @IsDateString()
  retiredAt?: string;
}
