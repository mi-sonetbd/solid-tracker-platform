import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';

const eventSeverities = ['INFO', 'WARNING', 'CRITICAL'] as const;
const eventProcessingStatuses = [
  'RECEIVED',
  'PROCESSING',
  'PROCESSED',
  'FAILED',
  'IGNORED',
] as const;
const geofenceStatuses = ['DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED'] as const;
const notificationStatuses = [
  'QUEUED',
  'PROCESSING',
  'SENT',
  'DELIVERED',
  'FAILED',
  'CANCELLED',
] as const;
const commandStatuses = [
  'PENDING_APPROVAL',
  'QUEUED',
  'SENT',
  'ACKNOWLEDGED',
  'COMPLETED',
  'FAILED',
  'CANCELLED',
  'EXPIRED',
] as const;
const integrationJobStatuses = [
  'PENDING',
  'PROCESSING',
  'SUCCEEDED',
  'FAILED',
  'CANCELLED',
  'DEAD_LETTER',
] as const;

export class PositionHistoryQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  to?: string;
}

export class TrackingEventQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  deviceId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  eventType?: string;

  @ApiPropertyOptional({ enum: eventSeverities })
  @IsOptional()
  @IsIn(eventSeverities)
  severity?: (typeof eventSeverities)[number];

  @ApiPropertyOptional({ enum: eventProcessingStatuses })
  @IsOptional()
  @IsIn(eventProcessingStatuses)
  processingStatus?: (typeof eventProcessingStatuses)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  to?: string;
}

export class GeofenceQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ enum: geofenceStatuses })
  @IsOptional()
  @IsIn(geofenceStatuses)
  status?: (typeof geofenceStatuses)[number];
}

export class NotificationRuleQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;
}

export class NotificationQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  trackingEventId?: string;

  @ApiPropertyOptional({ enum: notificationStatuses })
  @IsOptional()
  @IsIn(notificationStatuses)
  status?: (typeof notificationStatuses)[number];
}

export class CommandQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  deviceId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiPropertyOptional({ enum: commandStatuses })
  @IsOptional()
  @IsIn(commandStatuses)
  status?: (typeof commandStatuses)[number];
}

export class IntegrationJobQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: integrationJobStatuses })
  @IsOptional()
  @IsIn(integrationJobStatuses)
  status?: (typeof integrationJobStatuses)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  entityType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  entityId?: string;

  @ApiPropertyOptional({ default: 100, minimum: 1, maximum: 1000 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1000)
  priority?: number;
}
