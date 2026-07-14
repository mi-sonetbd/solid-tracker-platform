import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsDecimal,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

const intervalUnits = ['DAY', 'MONTH', 'YEAR'] as const;
const taxBehaviors = ['NONE', 'INCLUSIVE', 'EXCLUSIVE'] as const;
const statuses = ['DRAFT', 'INACTIVE', 'ARCHIVED'] as const;

export class UpdateServicePlanDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiPropertyOptional({ enum: intervalUnits })
  @IsOptional()
  @IsIn(intervalUnits)
  billingIntervalUnit?: (typeof intervalUnits)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(120)
  billingIntervalCount?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  basePrice?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(3)
  currency?: string;

  @ApiPropertyOptional({ enum: taxBehaviors })
  @IsOptional()
  @IsIn(taxBehaviors)
  taxBehavior?: (typeof taxBehaviors)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(365)
  trialDays?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  features?: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  deviceLimit?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  historyRetentionDays?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveUntil?: string;

  @ApiPropertyOptional({ enum: statuses })
  @IsOptional()
  @IsIn(statuses)
  status?: (typeof statuses)[number];
}
