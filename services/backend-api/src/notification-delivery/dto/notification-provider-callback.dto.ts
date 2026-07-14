import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsObject, IsOptional, IsString, Length } from 'class-validator';

export class NotificationProviderCallbackDto {
  @ApiProperty()
  @IsString()
  @Length(1, 160)
  externalEventId!: string;

  @ApiProperty()
  @IsString()
  @Length(1, 200)
  providerMessageId!: string;

  @ApiProperty({
    enum: ['SENT', 'DELIVERED', 'FAILED'],
  })
  @IsIn(['SENT', 'DELIVERED', 'FAILED'])
  status!: 'SENT' | 'DELIVERED' | 'FAILED';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  occurredAt?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  errorCode?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  errorMessage?: string;

  @ApiPropertyOptional({
    type: 'object',
    additionalProperties: true,
  })
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}
