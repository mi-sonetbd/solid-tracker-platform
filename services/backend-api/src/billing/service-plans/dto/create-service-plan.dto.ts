import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
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

export class CreateServicePlanDto {
  @ApiProperty({ example: 'STANDARD_MONTHLY' })
  @IsString()
  @MinLength(2)
  @MaxLength(60)
  planFamilyCode!: string;

  @ApiProperty({ example: 'Standard Monthly' })
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiProperty({ enum: intervalUnits })
  @IsIn(intervalUnits)
  billingIntervalUnit!: (typeof intervalUnits)[number];

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(120)
  billingIntervalCount = 1;

  @ApiProperty({ example: '500.00' })
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  basePrice!: string;

  @ApiPropertyOptional({ default: 'BDT' })
  @IsOptional()
  @IsString()
  @MaxLength(3)
  currency = 'BDT';

  @ApiPropertyOptional({ enum: taxBehaviors, default: 'NONE' })
  @IsOptional()
  @IsIn(taxBehaviors)
  taxBehavior: (typeof taxBehaviors)[number] = 'NONE';

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(365)
  trialDays = 0;

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

  @ApiProperty()
  @IsDateString()
  effectiveFrom!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveUntil?: string;
}
