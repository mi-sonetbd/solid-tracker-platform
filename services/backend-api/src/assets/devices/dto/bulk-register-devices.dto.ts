import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class BulkRegisterDevicesDto {
  @ApiProperty()
  @IsUUID()
  deviceModelId!: string;

  @ApiProperty({
    type: String,
    isArray: true,
    description: 'One IMEI per item. Each line is validated independently.',
  })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(250)
  @IsString({ each: true })
  @MaxLength(32, { each: true })
  imeis!: string[];

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
