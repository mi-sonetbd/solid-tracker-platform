import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class TransferCustomerDto {
  @ApiPropertyOptional({
    nullable: true,
    description: 'Send null or omit to transfer the customer to platform management.',
  })
  @IsOptional()
  @IsUUID()
  targetDealerId?: string | null;

  @ApiPropertyOptional({
    nullable: true,
    description: 'Optional group belonging to the target dealer.',
  })
  @IsOptional()
  @IsUUID()
  targetCustomerGroupId?: string | null;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}
