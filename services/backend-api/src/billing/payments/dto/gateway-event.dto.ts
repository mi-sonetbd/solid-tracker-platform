import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsObject, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

const gateways = ['BKASH', 'NAGAD', 'SSLCOMMERZ', 'BANK', 'OTHER'] as const;

export class GatewayEventDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  paymentId?: string;

  @ApiProperty({ enum: gateways })
  @IsIn(gateways)
  gateway!: (typeof gateways)[number];

  @ApiProperty()
  @IsString()
  @MaxLength(200)
  externalEventId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(120)
  eventType!: string;

  @ApiProperty()
  @IsObject()
  payload!: Record<string, unknown>;
}
