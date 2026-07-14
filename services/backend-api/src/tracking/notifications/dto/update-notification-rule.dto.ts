import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

const severities = ['INFO', 'WARNING', 'CRITICAL'] as const;
const channels = ['PUSH', 'SMS', 'EMAIL', 'IN_APP', 'WHATSAPP', 'VOICE_CALL'] as const;
const recipientTypes = ['USER', 'CUSTOMER_OWNER', 'CUSTOMER_ADMIN', 'CUSTOM_ADDRESS'] as const;

export class UpdateNotificationRuleDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  eventType?: string;

  @ApiPropertyOptional({ enum: severities })
  @IsOptional()
  @IsIn(severities)
  minimumSeverity?: (typeof severities)[number];

  @ApiPropertyOptional({ enum: channels })
  @IsOptional()
  @IsIn(channels)
  channel?: (typeof channels)[number];

  @ApiPropertyOptional({ enum: recipientTypes })
  @IsOptional()
  @IsIn(recipientTypes)
  recipientType?: (typeof recipientTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  recipientUserId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(320)
  recipientAddress?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @ApiPropertyOptional({ minimum: 0, maximum: 1439 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(1439)
  quietHoursStartMinute?: number;

  @ApiPropertyOptional({ minimum: 0, maximum: 1439 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(1439)
  quietHoursEndMinute?: number;

  @ApiPropertyOptional({ minimum: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  cooldownSeconds?: number;

  @ApiPropertyOptional({ minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  dailyLimit?: number;
}
