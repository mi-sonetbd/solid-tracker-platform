import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
} from 'class-validator';

const removalReasons = [
  'CUSTOMER_REQUEST',
  'VEHICLE_SOLD',
  'DEVICE_FAILURE',
  'WARRANTY_REPLACEMENT',
  'SUBSCRIPTION_CANCELLED',
  'TRANSFER_TO_ANOTHER_VEHICLE',
  'LOST',
  'OTHER',
] as const;

export class ReplaceDeviceDto {
  @ApiProperty()
  @IsUUID()
  replacementDeviceId!: string;

  @ApiProperty({ enum: removalReasons })
  @IsIn(removalReasons)
  removalReason!: (typeof removalReasons)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  installedAt?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsLatitude()
  latitude?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsLongitude()
  longitude?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  odometerReading?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  powerConnectionType?: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  ignitionConnected?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  relayConnected?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  sosConnected?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  notes?: string;
}
