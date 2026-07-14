import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength } from 'class-validator';

export class CompleteSettlementDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  providerReference?: string;
}

export class FailSettlementDto {
  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  reason!: string;
}
