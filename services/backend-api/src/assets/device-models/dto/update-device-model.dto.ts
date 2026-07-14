import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsObject, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

const networkTypes = [
  'GSM_2G',
  'UMTS_3G',
  'LTE_4G',
  'LTE_5G',
  'LORA',
  'SATELLITE',
  'OTHER',
] as const;

const modelStatuses = ['ACTIVE', 'INACTIVE', 'ARCHIVED'] as const;

export class UpdateDeviceModelDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  manufacturer?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  modelName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  protocol?: string;

  @ApiPropertyOptional({ enum: networkTypes })
  @IsOptional()
  @IsIn(networkTypes)
  networkType?: (typeof networkTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  capabilities?: Record<string, unknown>;

  @ApiPropertyOptional({ enum: modelStatuses })
  @IsOptional()
  @IsIn(modelStatuses)
  status?: (typeof modelStatuses)[number];
}
