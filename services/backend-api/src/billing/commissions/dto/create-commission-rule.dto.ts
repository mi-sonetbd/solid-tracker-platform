import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsDecimal,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsUUID,
  Max,
  Min,
} from 'class-validator';

const transactionTypes = [
  'DEVICE_SALE',
  'INSTALLATION',
  'INITIAL_SUBSCRIPTION',
  'SUBSCRIPTION_RENEWAL',
  'UPGRADE',
  'ADD_ON_SERVICE',
] as const;

const calculationTypes = ['PERCENTAGE', 'FIXED_AMOUNT', 'TIERED', 'NONE'] as const;

export class CreateCommissionRuleDto {
  @ApiProperty()
  @IsUUID()
  dealerOrganizationId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  servicePlanId?: string;

  @ApiProperty({ enum: transactionTypes })
  @IsIn(transactionTypes)
  transactionType!: (typeof transactionTypes)[number];

  @ApiProperty({ enum: calculationTypes })
  @IsIn(calculationTypes)
  calculationType!: (typeof calculationTypes)[number];

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

  @ApiPropertyOptional({ default: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10000)
  priority = 100;

  @ApiProperty()
  @IsDateString()
  effectiveFrom!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveUntil?: string;
}
