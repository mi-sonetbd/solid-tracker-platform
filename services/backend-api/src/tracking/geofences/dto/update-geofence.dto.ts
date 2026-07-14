import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsObject, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

const geometryTypes = ['CIRCLE', 'POLYGON', 'POLYLINE'] as const;
const statuses = ['DRAFT', 'ACTIVE', 'INACTIVE'] as const;

export class UpdateGeofenceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiPropertyOptional({ enum: geometryTypes })
  @IsOptional()
  @IsIn(geometryTypes)
  geometryType?: (typeof geometryTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  geometryData?: Record<string, unknown>;

  @ApiPropertyOptional({ enum: statuses })
  @IsOptional()
  @IsIn(statuses)
  status?: (typeof statuses)[number];
}
