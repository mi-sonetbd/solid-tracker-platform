import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsDateString,
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

const commandTypes = [
  'REQUEST_POSITION',
  'RESTART_DEVICE',
  'SET_REPORTING_INTERVAL',
  'ACTIVATE_RELAY',
  'DEACTIVATE_RELAY',
  'ENGINE_CUTOFF',
  'ENGINE_RESTORE',
  'CHANGE_SERVER',
  'CUSTOM',
] as const;

export class CreateDeviceCommandDto {
  @ApiProperty()
  @IsUUID()
  deviceId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiProperty({ enum: commandTypes })
  @IsIn(commandTypes)
  commandType!: (typeof commandTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  parameters?: Record<string, unknown>;

  @ApiProperty()
  @IsString()
  @MinLength(3)
  @MaxLength(1000)
  reason!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  expiresAt?: string;
}
