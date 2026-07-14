import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

const geometryTypes = ['CIRCLE', 'POLYGON', 'POLYLINE'] as const;
const statuses = ['DRAFT', 'ACTIVE', 'INACTIVE'] as const;

export class CreateGeofenceDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiProperty({ enum: geometryTypes })
  @IsIn(geometryTypes)
  geometryType!: (typeof geometryTypes)[number];

  @ApiProperty({
    description:
      'CIRCLE uses {center:{latitude,longitude},radius}; POLYGON and POLYLINE use {points:[{latitude,longitude}]}',
  })
  @IsObject()
  geometryData!: Record<string, unknown>;

  @ApiPropertyOptional({ enum: statuses, default: 'DRAFT' })
  @IsOptional()
  @IsIn(statuses)
  status?: (typeof statuses)[number];
}
