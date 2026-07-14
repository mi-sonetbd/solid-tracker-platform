import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

const statuses = ['PROCESSING', 'SENT', 'DELIVERED', 'FAILED', 'CANCELLED'] as const;

export class UpdateNotificationDeliveryDto {
  @ApiProperty({ enum: statuses })
  @IsIn(statuses)
  status!: (typeof statuses)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  provider?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  providerMessageId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  failureReason?: string;
}
