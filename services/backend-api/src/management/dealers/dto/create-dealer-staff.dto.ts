import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

const dealerRoleCodes = [
  'DEALER_OWNER',
  'DEALER_MANAGER',
  'DEALER_INSTALLER',
  'DEALER_ACCOUNTS',
] as const;

export class CreateDealerStaffDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  fullName!: string;

  @ApiProperty({ example: '01812345678' })
  @IsString()
  @MaxLength(30)
  mobileNumber!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  email?: string;

  @ApiPropertyOptional({
    description: 'Required only when the mobile number does not belong to an existing user.',
  })
  @IsOptional()
  @IsString()
  @MinLength(12)
  @MaxLength(200)
  password?: string;

  @ApiProperty({ enum: dealerRoleCodes })
  @IsIn(dealerRoleCodes)
  roleCode!: (typeof dealerRoleCodes)[number];
}
