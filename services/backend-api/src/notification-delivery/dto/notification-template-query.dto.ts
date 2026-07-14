import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export class NotificationTemplateQueryDto {
  @ApiPropertyOptional({ default: 1 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @ApiPropertyOptional({ default: 25 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize = 25;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({
    enum: ['PUSH', 'SMS', 'EMAIL', 'IN_APP', 'WHATSAPP', 'VOICE_CALL'],
  })
  @IsOptional()
  @IsIn(['PUSH', 'SMS', 'EMAIL', 'IN_APP', 'WHATSAPP', 'VOICE_CALL'])
  channel?: string;

  @ApiPropertyOptional({
    enum: ['DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED'],
  })
  @IsOptional()
  @IsIn(['DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED'])
  status?: string;
}
