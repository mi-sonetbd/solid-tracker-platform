import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsObject, IsOptional, IsString, IsUUID, Length, MaxLength } from 'class-validator';

export class EnqueueTemplateNotificationDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  userId?: string;

  @ApiProperty({
    enum: ['PUSH', 'SMS', 'EMAIL', 'IN_APP', 'WHATSAPP', 'VOICE_CALL'],
  })
  @IsIn(['PUSH', 'SMS', 'EMAIL', 'IN_APP', 'WHATSAPP', 'VOICE_CALL'])
  channel!: 'PUSH' | 'SMS' | 'EMAIL' | 'IN_APP' | 'WHATSAPP' | 'VOICE_CALL';

  @ApiProperty()
  @IsString()
  @Length(1, 320)
  recipient!: string;

  @ApiProperty()
  @IsString()
  @Length(3, 120)
  templateKey!: string;

  @ApiPropertyOptional({ default: 'en' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  locale?: string;

  @ApiProperty({
    type: 'object',
    additionalProperties: true,
  })
  @IsObject()
  variables!: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  trackingEventId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  notificationRuleId?: string;
}
