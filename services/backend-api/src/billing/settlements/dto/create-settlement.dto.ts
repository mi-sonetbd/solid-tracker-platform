import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ArrayMinSize, IsArray, IsDecimal, IsOptional, IsUUID } from 'class-validator';

export class CreateSettlementDto {
  @ApiProperty()
  @IsUUID()
  dealerOrganizationId!: string;

  @ApiProperty()
  @IsUUID()
  payoutAccountId!: string;

  @ApiProperty({
    type: String,
    isArray: true,
  })
  @IsArray()
  @ArrayMinSize(1)
  @IsUUID('4', { each: true })
  commissionEntryIds!: string[];

  @ApiPropertyOptional({ default: '0.00' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  adjustmentAmount = '0.00';

  @ApiPropertyOptional({ default: '0.00' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  feeAmount = '0.00';
}
