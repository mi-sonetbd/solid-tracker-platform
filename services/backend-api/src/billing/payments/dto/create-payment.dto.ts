import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsDecimal,
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

const methods = ['BKASH', 'NAGAD', 'BANK_TRANSFER', 'CARD', 'CASH', 'MANUAL_ADJUSTMENT'] as const;

const gateways = ['NONE', 'BKASH', 'NAGAD', 'SSLCOMMERZ', 'BANK', 'MANUAL', 'OTHER'] as const;

export class CreatePaymentDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiProperty()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  amount!: string;

  @ApiPropertyOptional({ default: 'BDT' })
  @IsOptional()
  @IsString()
  @MaxLength(3)
  currency = 'BDT';

  @ApiProperty({ enum: methods })
  @IsIn(methods)
  paymentMethod!: (typeof methods)[number];

  @ApiPropertyOptional({ enum: gateways, default: 'NONE' })
  @IsOptional()
  @IsIn(gateways)
  paymentGateway: (typeof gateways)[number] = 'NONE';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  gatewayReference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}
