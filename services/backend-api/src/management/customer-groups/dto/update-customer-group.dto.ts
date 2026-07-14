import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

const groupStatuses = ['ACTIVE', 'INACTIVE', 'ARCHIVED'] as const;

export class UpdateCustomerGroupDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @ApiPropertyOptional({ enum: groupStatuses })
  @IsOptional()
  @IsIn(groupStatuses)
  status?: (typeof groupStatuses)[number];
}
