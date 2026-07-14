import { ApiProperty } from '@nestjs/swagger';
import { IsObject, IsString, MaxLength } from 'class-validator';

export class TraccarWebhookDto {
  @ApiProperty()
  @IsString()
  @MaxLength(60)
  serverCode!: string;

  @ApiProperty()
  @IsObject()
  event!: Record<string, unknown>;

  @ApiProperty()
  @IsObject()
  device!: Record<string, unknown>;

  @ApiProperty()
  @IsObject()
  position!: Record<string, unknown>;
}
