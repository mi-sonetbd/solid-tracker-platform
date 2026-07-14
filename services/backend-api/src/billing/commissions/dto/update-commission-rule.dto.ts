import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsDecimal,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  Max,
  Min,
} from 'class-validator';

const calculationTypes = ['PERCENTAGE', 'FIXED_AMOUNT', 'TIERED', 'NONE'] as const;

const statuses = ['DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED'] as const;

export class UpdateCommissionRuleDto {
  @ApiPropertyOptional({ enum: calculationTypes })
  @IsOptional()
  @IsIn(calculationTypes)
  calculationType?: (typeof calculationTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,4', force_decimal: false })
  percentageRate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  fixedAmount?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  tierDefinition?: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  minimumAmount?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  maximumAmount?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10000)
  priority?: number;

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
