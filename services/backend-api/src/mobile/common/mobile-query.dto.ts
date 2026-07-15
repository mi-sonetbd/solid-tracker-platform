import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
} from 'class-validator';
import { TrackingEventSeverity } from '../../generated/prisma/client';

export class MobileCursorQueryDto {
  @ApiPropertyOptional({
    description: 'Opaque continuation cursor returned by the previous page',
  })
  @IsOptional()
  @IsUUID()
  cursor?: string;

  @ApiPropertyOptional({
    minimum: 1,
    maximum: 100,
    default: 20,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 20;
}

export class MobileEventQueryDto extends MobileCursorQueryDto {
  @ApiPropertyOptional({ enum: TrackingEventSeverity })
  @IsOptional()
  @IsEnum(TrackingEventSeverity)
  severity?: TrackingEventSeverity;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  eventType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  to?: string;
}

export class MobileHistoryQueryDto {
  @ApiPropertyOptional({
    description: 'ISO-8601 range start; defaults to 24 hours before to',
  })
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional({
    description: 'ISO-8601 range end; defaults to the current time',
  })
  @IsOptional()
  @IsDateString()
  to?: string;
}
