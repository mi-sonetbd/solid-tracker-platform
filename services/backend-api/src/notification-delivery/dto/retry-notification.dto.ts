import { ApiProperty } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';

export class RetryNotificationDto {
  @ApiProperty()
  @IsString()
  @Length(3, 500)
  reason!: string;
}
