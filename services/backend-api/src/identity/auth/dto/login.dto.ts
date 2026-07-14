import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { SessionPlatform } from '../../../generated/prisma/client';

export class LoginDto {
  @ApiProperty({ example: '+8801712345678' })
  @IsString()
  @MaxLength(30)
  mobileNumber!: string;

  @ApiProperty({ minLength: 8 })
  @IsString()
  @MinLength(8)
  @MaxLength(200)
  password!: string;

  @ApiProperty({ enum: SessionPlatform, example: SessionPlatform.WEB })
  @IsEnum(SessionPlatform)
  platform!: SessionPlatform;

  @ApiPropertyOptional({ example: 'Chrome on Windows' })
  @IsOptional()
  @IsString()
  @MaxLength(160)
  deviceName?: string;

  @ApiPropertyOptional({ example: '0.1.0' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  appVersion?: string;
}
