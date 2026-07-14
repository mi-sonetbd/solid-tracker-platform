import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsOptional, IsString, IsUUID, Matches, MaxLength } from 'class-validator';

export class RegisterDeviceDto {
  @ApiProperty()
  @IsUUID()
  deviceModelId!: string;

  @ApiPropertyOptional({
    description: 'IMEI is stored as text and must contain 14 to 17 digits.',
  })
  @IsOptional()
  @IsString()
  @Matches(/^\d{14,17}$/)
  imei?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  serialNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  hardwareVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  firmwareVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  receivedAt?: string;
}
