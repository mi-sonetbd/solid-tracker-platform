import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsDecimal, IsObject, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class CreateRefundDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  invoiceId?: string;

  @ApiProperty()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  amount!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  reason!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

export class CompleteRefundDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  gatewayRefundId?: string;
}
