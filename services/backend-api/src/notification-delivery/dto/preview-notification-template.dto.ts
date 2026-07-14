import { ApiProperty } from '@nestjs/swagger';
import { IsObject } from 'class-validator';

export class PreviewNotificationTemplateDto {
  @ApiProperty({
    type: 'object',
    additionalProperties: true,
  })
  @IsObject()
  variables!: Record<string, unknown>;
}
