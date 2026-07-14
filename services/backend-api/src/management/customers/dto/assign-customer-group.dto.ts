import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsUUID } from 'class-validator';

export class AssignCustomerGroupDto {
  @ApiPropertyOptional({
    nullable: true,
    description: 'Send null or omit to remove the customer from a group.',
  })
  @IsOptional()
  @IsUUID()
  customerGroupId?: string | null;
}
