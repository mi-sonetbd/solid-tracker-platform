import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUrl, IsUUID, MaxLength } from 'class-validator';

export class InitializeGatewayPaymentDto {
  @ApiProperty()
  @IsUUID()
  invoiceId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUrl({
    require_tld: false,
  })
  successUrl?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUrl({
    require_tld: false,
  })
  cancelUrl?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUrl({
    require_tld: false,
  })
  failureUrl?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  customerReference?: string;
}
