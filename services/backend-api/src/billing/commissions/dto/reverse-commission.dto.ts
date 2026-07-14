import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength } from 'class-validator';

export class ReverseCommissionDto {
  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  reason!: string;
}
