import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsDecimal,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateNested,
} from 'class-validator';

const itemTypes = [
  'DEVICE_SALE',
  'INSTALLATION',
  'SUBSCRIPTION',
  'SIM_FEE',
  'REPLACEMENT',
  'ADD_ON',
  'DISCOUNT',
  'OTHER',
] as const;

export class CreateInvoiceLineDto {
  @ApiProperty({ enum: itemTypes })
  @IsIn(itemTypes)
  itemType!: (typeof itemTypes)[number];

  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  description!: string;

  @ApiPropertyOptional({ default: '1.000' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,3', force_decimal: false })
  quantity = '1.000';

  @ApiProperty()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  unitPrice!: string;

  @ApiPropertyOptional({ default: '0.00' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  discountAmount = '0.00';

  @ApiPropertyOptional({ default: '0.00' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  taxAmount = '0.00';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  referenceType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  referenceId?: string;
}

export class CreateInvoiceDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @ApiProperty()
  @IsDateString()
  issueDate!: string;

  @ApiProperty()
  @IsDateString()
  dueDate!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  billingPeriodStart?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  billingPeriodEnd?: string;

  @ApiProperty({
    type: CreateInvoiceLineDto,
    isArray: true,
  })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateInvoiceLineDto)
  lines!: CreateInvoiceLineDto[];
}
