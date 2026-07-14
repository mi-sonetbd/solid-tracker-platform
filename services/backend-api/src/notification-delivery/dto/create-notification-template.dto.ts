import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  Length,
  Matches,
  MaxLength,
} from 'class-validator';

const channels = ['PUSH', 'SMS', 'EMAIL', 'IN_APP', 'WHATSAPP', 'VOICE_CALL'] as const;

export class CreateNotificationTemplateDto {
  @ApiProperty({ example: 'tracking.critical-alert' })
  @IsString()
  @Length(3, 120)
  @Matches(/^[a-z0-9][a-z0-9._-]+$/)
  templateKey!: string;

  @ApiProperty({ enum: channels })
  @IsIn(channels)
  channel!: (typeof channels)[number];

  @ApiPropertyOptional({ default: 'en' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  locale?: string;

  @ApiProperty()
  @IsString()
  @Length(3, 160)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(240)
  subjectTemplate?: string;

  @ApiProperty()
  @IsString()
  @Length(1, 20000)
  bodyTemplate!: string;

  @ApiPropertyOptional({
    type: 'object',
    additionalProperties: true,
  })
  @IsOptional()
  @IsObject()
  variableSchema?: Record<string, unknown>;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  activate?: boolean;
}
