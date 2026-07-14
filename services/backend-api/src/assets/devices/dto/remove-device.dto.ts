import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

const assignmentEndReasons = [
  'DEVICE_FAILURE',
  'DEVICE_REPLACEMENT',
  'VEHICLE_TRANSFER',
  'VEHICLE_SOLD',
  'CUSTOMER_REQUEST',
  'SUBSCRIPTION_CANCELLED',
  'TRANSFER_TO_ANOTHER_VEHICLE',
  'LOST',
  'OTHER',
] as const;

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

export class RemoveDeviceDto {
  @ApiProperty({ enum: assignmentEndReasons })
  @IsIn(assignmentEndReasons)
  assignmentEndReason!: (typeof assignmentEndReasons)[number];

  @ApiProperty({ enum: removalReasons })
  @IsIn(removalReasons)
  removalReason!: (typeof removalReasons)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  notes?: string;
}
