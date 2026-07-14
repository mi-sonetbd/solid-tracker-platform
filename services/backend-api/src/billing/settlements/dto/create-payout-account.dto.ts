import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

const accountTypes = [
  'BANK_ACCOUNT',
  'MOBILE_FINANCIAL_SERVICE',
  'PAYMENT_GATEWAY_ACCOUNT',
] as const;

const providers = ['BANK', 'BKASH', 'NAGAD', 'OTHER'] as const;

export class CreatePayoutAccountDto {
  @ApiProperty()
  @IsUUID()
  dealerOrganizationId!: string;

  @ApiProperty({ enum: accountTypes })
  @IsIn(accountTypes)
  accountType!: (typeof accountTypes)[number];

  @ApiProperty({ enum: providers })
  @IsIn(providers)
  provider!: (typeof providers)[number];

  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  accountHolderName!: string;

  @ApiProperty({
    description: 'Sensitive account number or provider reference. It is encrypted before storage.',
  })
  @IsString()
  @MinLength(4)
  @MaxLength(300)
  accountReference!: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  isDefault = false;
}
