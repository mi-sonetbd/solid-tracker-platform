import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsDecimal,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateNested,
} from 'class-validator';

export class PaymentAllocationDto {
  @ApiProperty()
  @IsUUID()
  invoiceId!: string;

  @ApiProperty()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  amount!: string;
}

export class ConfirmPaymentDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  gatewayTransactionId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  gatewayReference?: string;

  @ApiPropertyOptional({
    type: PaymentAllocationDto,
    isArray: true,
  })
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PaymentAllocationDto)
  allocations?: PaymentAllocationDto[];
}
