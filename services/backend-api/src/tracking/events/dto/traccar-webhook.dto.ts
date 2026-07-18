import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsObject, IsOptional } from 'class-validator';

export class TraccarWebhookDto {
  @ApiProperty()
  @IsObject()
  event!: Record<string, unknown>;

  @ApiProperty()
  @IsObject()
  device!: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  position?: Record<string, unknown>;
}
