import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { PaginationQueryDto } from '../../common/pagination-query.dto';

const customerStatuses = ['PENDING', 'ACTIVE', 'SUSPENDED', 'INACTIVE', 'ARCHIVED'] as const;

const customerTypes = ['INDIVIDUAL', 'ORGANIZATION'] as const;

export class CustomerQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: customerStatuses })
  @IsOptional()
  @IsIn(customerStatuses)
  status?: (typeof customerStatuses)[number];

  @ApiPropertyOptional({ enum: customerTypes })
  @IsOptional()
  @IsIn(customerTypes)
  customerType?: (typeof customerTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  managingDealerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerGroupId?: string;
}
