import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

const customerRoleCodes = ['CUSTOMER_OWNER', 'CUSTOMER_ADMIN', 'CUSTOMER_VIEWER'] as const;

export class CreateCustomerMemberDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  fullName!: string;

  @ApiProperty({ example: '01712345678' })
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

  @ApiProperty({ enum: customerRoleCodes })
  @IsIn(customerRoleCodes)
  roleCode!: (typeof customerRoleCodes)[number];

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  isPrimary?: boolean;
}
