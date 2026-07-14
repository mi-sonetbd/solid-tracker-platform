import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';

const planStatuses = ['DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED'] as const;

const subscriptionStatuses = [
  'PENDING',
  'TRIALING',
  'ACTIVE',
  'PAST_DUE',
  'SUSPENDED',
  'CANCELLED',
  'EXPIRED',
] as const;

const invoiceStatuses = [
  'DRAFT',
  'ISSUED',
  'PARTIALLY_PAID',
  'PAID',
  'OVERDUE',
  'VOID',
  'REFUNDED',
] as const;

const paymentStatuses = [
  'INITIATED',
  'PENDING',
  'SUCCEEDED',
  'FAILED',
  'CANCELLED',
  'REFUNDED',
  'PARTIALLY_REFUNDED',
] as const;

const commissionStatuses = [
  'PENDING',
  'EARNED',
  'ON_HOLD',
  'AVAILABLE',
  'SETTLEMENT_PENDING',
  'SETTLED',
  'REVERSED',
  'CANCELLED',
] as const;

const settlementStatuses = [
  'DRAFT',
  'PENDING',
  'PROCESSING',
  'COMPLETED',
  'FAILED',
  'CANCELLED',
  'REVERSED',
] as const;

export class ServicePlanQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: planStatuses })
  @IsOptional()
  @IsIn(planStatuses)
  status?: (typeof planStatuses)[number];
}

export class SubscriptionQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiPropertyOptional({ enum: subscriptionStatuses })
  @IsOptional()
  @IsIn(subscriptionStatuses)
  status?: (typeof subscriptionStatuses)[number];
}

export class InvoiceQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @ApiPropertyOptional({ enum: invoiceStatuses })
  @IsOptional()
  @IsIn(invoiceStatuses)
  status?: (typeof invoiceStatuses)[number];
}

export class PaymentQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ enum: paymentStatuses })
  @IsOptional()
  @IsIn(paymentStatuses)
  status?: (typeof paymentStatuses)[number];
}

export class CommissionQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dealerOrganizationId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ enum: commissionStatuses })
  @IsOptional()
  @IsIn(commissionStatuses)
  status?: (typeof commissionStatuses)[number];
}

export class SettlementQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dealerOrganizationId?: string;

  @ApiPropertyOptional({ enum: settlementStatuses })
  @IsOptional()
  @IsIn(settlementStatuses)
  status?: (typeof settlementStatuses)[number];
}
