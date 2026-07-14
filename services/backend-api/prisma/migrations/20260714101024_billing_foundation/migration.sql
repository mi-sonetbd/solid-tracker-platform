-- CreateEnum
CREATE TYPE "BillingIntervalUnit" AS ENUM ('DAY', 'MONTH', 'YEAR');

-- CreateEnum
CREATE TYPE "TaxBehavior" AS ENUM ('NONE', 'INCLUSIVE', 'EXCLUSIVE');

-- CreateEnum
CREATE TYPE "ServicePlanStatus" AS ENUM ('DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('PENDING', 'TRIALING', 'ACTIVE', 'PAST_DUE', 'SUSPENDED', 'CANCELLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "InvoiceStatus" AS ENUM ('DRAFT', 'ISSUED', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'VOID', 'REFUNDED');

-- CreateEnum
CREATE TYPE "InvoiceLineItemType" AS ENUM ('DEVICE_SALE', 'INSTALLATION', 'SUBSCRIPTION', 'SIM_FEE', 'REPLACEMENT', 'ADD_ON', 'DISCOUNT', 'OTHER');

-- CreateEnum
CREATE TYPE "PaymentMethod" AS ENUM ('BKASH', 'NAGAD', 'BANK_TRANSFER', 'CARD', 'CASH', 'MANUAL_ADJUSTMENT');

-- CreateEnum
CREATE TYPE "PaymentGateway" AS ENUM ('NONE', 'BKASH', 'NAGAD', 'SSLCOMMERZ', 'BANK', 'MANUAL', 'OTHER');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('INITIATED', 'PENDING', 'SUCCEEDED', 'FAILED', 'CANCELLED', 'REFUNDED', 'PARTIALLY_REFUNDED');

-- CreateEnum
CREATE TYPE "PaymentGatewayEventStatus" AS ENUM ('RECEIVED', 'PROCESSING', 'PROCESSED', 'FAILED', 'IGNORED');

-- CreateEnum
CREATE TYPE "RefundStatus" AS ENUM ('REQUESTED', 'PENDING', 'SUCCEEDED', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "CommissionTransactionType" AS ENUM ('DEVICE_SALE', 'INSTALLATION', 'INITIAL_SUBSCRIPTION', 'SUBSCRIPTION_RENEWAL', 'UPGRADE', 'ADD_ON_SERVICE');

-- CreateEnum
CREATE TYPE "CommissionCalculationType" AS ENUM ('PERCENTAGE', 'FIXED_AMOUNT', 'TIERED', 'NONE');

-- CreateEnum
CREATE TYPE "CommissionRuleStatus" AS ENUM ('DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "CommissionEntryStatus" AS ENUM ('PENDING', 'EARNED', 'ON_HOLD', 'AVAILABLE', 'SETTLEMENT_PENDING', 'SETTLED', 'REVERSED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "PayoutAccountType" AS ENUM ('BANK_ACCOUNT', 'MOBILE_FINANCIAL_SERVICE', 'PAYMENT_GATEWAY_ACCOUNT');

-- CreateEnum
CREATE TYPE "PayoutProvider" AS ENUM ('BANK', 'BKASH', 'NAGAD', 'OTHER');

-- CreateEnum
CREATE TYPE "PayoutVerificationStatus" AS ENUM ('UNVERIFIED', 'PENDING', 'VERIFIED', 'REJECTED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "PayoutAccountStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "SettlementStatus" AS ENUM ('DRAFT', 'PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED', 'REVERSED');

-- CreateEnum
CREATE TYPE "LedgerEntryType" AS ENUM ('COMMISSION_EARNED', 'COMMISSION_REVERSAL', 'SETTLEMENT', 'SETTLEMENT_REVERSAL', 'MANUAL_ADJUSTMENT', 'FEE');

-- CreateEnum
CREATE TYPE "LedgerDirection" AS ENUM ('CREDIT', 'DEBIT');

-- CreateTable
CREATE TABLE "service_plans" (
    "id" UUID NOT NULL,
    "planCode" VARCHAR(60) NOT NULL,
    "planFamilyCode" VARCHAR(60) NOT NULL,
    "version" INTEGER NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "description" TEXT,
    "billingIntervalUnit" "BillingIntervalUnit" NOT NULL,
    "billingIntervalCount" INTEGER NOT NULL DEFAULT 1,
    "basePrice" DECIMAL(14,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'BDT',
    "taxBehavior" "TaxBehavior" NOT NULL DEFAULT 'NONE',
    "trialDays" INTEGER NOT NULL DEFAULT 0,
    "features" JSONB,
    "deviceLimit" INTEGER,
    "historyRetentionDays" INTEGER,
    "status" "ServicePlanStatus" NOT NULL DEFAULT 'DRAFT',
    "effectiveFrom" TIMESTAMPTZ(3) NOT NULL,
    "effectiveUntil" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "service_plans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscriptions" (
    "id" UUID NOT NULL,
    "subscriptionCode" VARCHAR(60) NOT NULL,
    "customerId" UUID NOT NULL,
    "vehicleId" UUID NOT NULL,
    "servicePlanId" UUID NOT NULL,
    "status" "SubscriptionStatus" NOT NULL DEFAULT 'PENDING',
    "startedAt" TIMESTAMPTZ(3),
    "currentPeriodStart" TIMESTAMPTZ(3),
    "currentPeriodEnd" TIMESTAMPTZ(3),
    "nextBillingAt" TIMESTAMPTZ(3),
    "trialEndsAt" TIMESTAMPTZ(3),
    "cancelledAt" TIMESTAMPTZ(3),
    "cancellationReason" TEXT,
    "autoRenew" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invoices" (
    "id" UUID NOT NULL,
    "invoiceNumber" VARCHAR(60) NOT NULL,
    "customerId" UUID NOT NULL,
    "subscriptionId" UUID,
    "managingDealerIdAtIssue" UUID,
    "billingPeriodStart" TIMESTAMPTZ(3),
    "billingPeriodEnd" TIMESTAMPTZ(3),
    "issueDate" DATE NOT NULL,
    "dueDate" DATE NOT NULL,
    "subtotal" DECIMAL(14,2) NOT NULL,
    "discountAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "taxAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "totalAmount" DECIMAL(14,2) NOT NULL,
    "paidAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "outstandingAmount" DECIMAL(14,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'BDT',
    "status" "InvoiceStatus" NOT NULL DEFAULT 'DRAFT',
    "issuedAt" TIMESTAMPTZ(3),
    "voidedAt" TIMESTAMPTZ(3),
    "voidReason" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "invoices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invoice_lines" (
    "id" UUID NOT NULL,
    "invoiceId" UUID NOT NULL,
    "lineNumber" INTEGER NOT NULL,
    "itemType" "InvoiceLineItemType" NOT NULL,
    "description" TEXT NOT NULL,
    "quantity" DECIMAL(12,3) NOT NULL DEFAULT 1,
    "unitPrice" DECIMAL(14,2) NOT NULL,
    "discountAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "taxAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "lineTotal" DECIMAL(14,2) NOT NULL,
    "referenceType" VARCHAR(100),
    "referenceId" VARCHAR(100),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "invoice_lines_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payments" (
    "id" UUID NOT NULL,
    "paymentNumber" VARCHAR(60) NOT NULL,
    "customerId" UUID NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'BDT',
    "paymentMethod" "PaymentMethod" NOT NULL,
    "paymentGateway" "PaymentGateway" NOT NULL DEFAULT 'NONE',
    "gatewayTransactionId" VARCHAR(160),
    "gatewayReference" VARCHAR(160),
    "status" "PaymentStatus" NOT NULL DEFAULT 'INITIATED',
    "initiatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "confirmedAt" TIMESTAMPTZ(3),
    "failedAt" TIMESTAMPTZ(3),
    "failureReason" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_allocations" (
    "id" UUID NOT NULL,
    "paymentId" UUID NOT NULL,
    "invoiceId" UUID NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "allocatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payment_allocations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_gateway_events" (
    "id" UUID NOT NULL,
    "paymentId" UUID,
    "gateway" "PaymentGateway" NOT NULL,
    "externalEventId" VARCHAR(200) NOT NULL,
    "eventType" VARCHAR(120) NOT NULL,
    "payload" JSONB NOT NULL,
    "payloadHash" VARCHAR(128) NOT NULL,
    "status" "PaymentGatewayEventStatus" NOT NULL DEFAULT 'RECEIVED',
    "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processedAt" TIMESTAMPTZ(3),
    "errorMessage" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "payment_gateway_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refunds" (
    "id" UUID NOT NULL,
    "refundNumber" VARCHAR(60) NOT NULL,
    "paymentId" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "invoiceId" UUID,
    "amount" DECIMAL(14,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'BDT',
    "gatewayRefundId" VARCHAR(160),
    "reason" TEXT NOT NULL,
    "status" "RefundStatus" NOT NULL DEFAULT 'REQUESTED',
    "requestedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMPTZ(3),
    "failedAt" TIMESTAMPTZ(3),
    "failureReason" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "refunds_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "commission_rules" (
    "id" UUID NOT NULL,
    "ruleCode" VARCHAR(60) NOT NULL,
    "dealerOrganizationId" UUID NOT NULL,
    "servicePlanId" UUID,
    "transactionType" "CommissionTransactionType" NOT NULL,
    "calculationType" "CommissionCalculationType" NOT NULL,
    "percentageRate" DECIMAL(7,4),
    "fixedAmount" DECIMAL(14,2),
    "tierDefinition" JSONB,
    "minimumAmount" DECIMAL(14,2),
    "maximumAmount" DECIMAL(14,2),
    "priority" INTEGER NOT NULL DEFAULT 100,
    "effectiveFrom" TIMESTAMPTZ(3) NOT NULL,
    "effectiveUntil" TIMESTAMPTZ(3),
    "status" "CommissionRuleStatus" NOT NULL DEFAULT 'DRAFT',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "commission_rules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "commission_entries" (
    "id" UUID NOT NULL,
    "commissionNumber" VARCHAR(60) NOT NULL,
    "dealerOrganizationId" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "invoiceId" UUID,
    "invoiceLineId" UUID,
    "paymentId" UUID,
    "commissionRuleId" UUID,
    "reversalOfEntryId" UUID,
    "transactionType" "CommissionTransactionType" NOT NULL,
    "calculationType" "CommissionCalculationType" NOT NULL,
    "baseAmount" DECIMAL(14,2) NOT NULL,
    "percentageRateSnapshot" DECIMAL(7,4),
    "fixedAmountSnapshot" DECIMAL(14,2),
    "commissionAmount" DECIMAL(14,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'BDT',
    "status" "CommissionEntryStatus" NOT NULL DEFAULT 'PENDING',
    "earnedAt" TIMESTAMPTZ(3),
    "availableAt" TIMESTAMPTZ(3),
    "settledAt" TIMESTAMPTZ(3),
    "holdReason" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "commission_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dealer_payout_accounts" (
    "id" UUID NOT NULL,
    "accountCode" VARCHAR(60) NOT NULL,
    "dealerOrganizationId" UUID NOT NULL,
    "accountType" "PayoutAccountType" NOT NULL,
    "provider" "PayoutProvider" NOT NULL,
    "accountHolderName" VARCHAR(160) NOT NULL,
    "maskedAccountNumber" VARCHAR(80) NOT NULL,
    "encryptedAccountReference" TEXT NOT NULL,
    "verificationStatus" "PayoutVerificationStatus" NOT NULL DEFAULT 'UNVERIFIED',
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "status" "PayoutAccountStatus" NOT NULL DEFAULT 'ACTIVE',
    "verifiedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "dealer_payout_accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dealer_settlements" (
    "id" UUID NOT NULL,
    "settlementNumber" VARCHAR(60) NOT NULL,
    "dealerOrganizationId" UUID NOT NULL,
    "payoutAccountId" UUID NOT NULL,
    "grossCommissionAmount" DECIMAL(14,2) NOT NULL,
    "adjustmentAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "feeAmount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "netSettlementAmount" DECIMAL(14,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'BDT',
    "status" "SettlementStatus" NOT NULL DEFAULT 'DRAFT',
    "providerReference" VARCHAR(160),
    "initiatedAt" TIMESTAMPTZ(3),
    "completedAt" TIMESTAMPTZ(3),
    "failedAt" TIMESTAMPTZ(3),
    "failureReason" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "dealer_settlements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dealer_settlement_items" (
    "id" UUID NOT NULL,
    "settlementId" UUID NOT NULL,
    "commissionEntryId" UUID NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "dealer_settlement_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dealer_ledger_entries" (
    "id" UUID NOT NULL,
    "ledgerNumber" VARCHAR(60) NOT NULL,
    "dealerOrganizationId" UUID NOT NULL,
    "entryType" "LedgerEntryType" NOT NULL,
    "direction" "LedgerDirection" NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'BDT',
    "referenceType" VARCHAR(100) NOT NULL,
    "referenceId" VARCHAR(100) NOT NULL,
    "description" TEXT NOT NULL,
    "occurredAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "dealer_ledger_entries_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "service_plans_planCode_key" ON "service_plans"("planCode");

-- CreateIndex
CREATE INDEX "service_plans_status_effectiveFrom_idx" ON "service_plans"("status", "effectiveFrom");

-- CreateIndex
CREATE UNIQUE INDEX "service_plans_planFamilyCode_version_key" ON "service_plans"("planFamilyCode", "version");

-- CreateIndex
CREATE UNIQUE INDEX "subscriptions_subscriptionCode_key" ON "subscriptions"("subscriptionCode");

-- CreateIndex
CREATE INDEX "subscriptions_customerId_status_idx" ON "subscriptions"("customerId", "status");

-- CreateIndex
CREATE INDEX "subscriptions_vehicleId_status_idx" ON "subscriptions"("vehicleId", "status");

-- CreateIndex
CREATE INDEX "subscriptions_servicePlanId_status_idx" ON "subscriptions"("servicePlanId", "status");

-- CreateIndex
CREATE INDEX "subscriptions_nextBillingAt_idx" ON "subscriptions"("nextBillingAt");

-- CreateIndex
CREATE UNIQUE INDEX "invoices_invoiceNumber_key" ON "invoices"("invoiceNumber");

-- CreateIndex
CREATE INDEX "invoices_customerId_status_idx" ON "invoices"("customerId", "status");

-- CreateIndex
CREATE INDEX "invoices_subscriptionId_idx" ON "invoices"("subscriptionId");

-- CreateIndex
CREATE INDEX "invoices_managingDealerIdAtIssue_status_idx" ON "invoices"("managingDealerIdAtIssue", "status");

-- CreateIndex
CREATE INDEX "invoices_dueDate_status_idx" ON "invoices"("dueDate", "status");

-- CreateIndex
CREATE INDEX "invoice_lines_referenceType_referenceId_idx" ON "invoice_lines"("referenceType", "referenceId");

-- CreateIndex
CREATE UNIQUE INDEX "invoice_lines_invoiceId_lineNumber_key" ON "invoice_lines"("invoiceId", "lineNumber");

-- CreateIndex
CREATE UNIQUE INDEX "payments_paymentNumber_key" ON "payments"("paymentNumber");

-- CreateIndex
CREATE INDEX "payments_customerId_status_idx" ON "payments"("customerId", "status");

-- CreateIndex
CREATE INDEX "payments_status_initiatedAt_idx" ON "payments"("status", "initiatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "payments_paymentGateway_gatewayTransactionId_key" ON "payments"("paymentGateway", "gatewayTransactionId");

-- CreateIndex
CREATE INDEX "payment_allocations_invoiceId_allocatedAt_idx" ON "payment_allocations"("invoiceId", "allocatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "payment_allocations_paymentId_invoiceId_key" ON "payment_allocations"("paymentId", "invoiceId");

-- CreateIndex
CREATE INDEX "payment_gateway_events_paymentId_status_idx" ON "payment_gateway_events"("paymentId", "status");

-- CreateIndex
CREATE INDEX "payment_gateway_events_status_receivedAt_idx" ON "payment_gateway_events"("status", "receivedAt");

-- CreateIndex
CREATE UNIQUE INDEX "payment_gateway_events_gateway_externalEventId_key" ON "payment_gateway_events"("gateway", "externalEventId");

-- CreateIndex
CREATE UNIQUE INDEX "refunds_refundNumber_key" ON "refunds"("refundNumber");

-- CreateIndex
CREATE INDEX "refunds_paymentId_status_idx" ON "refunds"("paymentId", "status");

-- CreateIndex
CREATE INDEX "refunds_customerId_status_idx" ON "refunds"("customerId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "commission_rules_ruleCode_key" ON "commission_rules"("ruleCode");

-- CreateIndex
CREATE INDEX "commission_rules_dealerOrganizationId_status_idx" ON "commission_rules"("dealerOrganizationId", "status");

-- CreateIndex
CREATE INDEX "commission_rules_servicePlanId_transactionType_status_idx" ON "commission_rules"("servicePlanId", "transactionType", "status");

-- CreateIndex
CREATE INDEX "commission_rules_effectiveFrom_effectiveUntil_idx" ON "commission_rules"("effectiveFrom", "effectiveUntil");

-- CreateIndex
CREATE UNIQUE INDEX "commission_entries_commissionNumber_key" ON "commission_entries"("commissionNumber");

-- CreateIndex
CREATE INDEX "commission_entries_dealerOrganizationId_status_idx" ON "commission_entries"("dealerOrganizationId", "status");

-- CreateIndex
CREATE INDEX "commission_entries_customerId_status_idx" ON "commission_entries"("customerId", "status");

-- CreateIndex
CREATE INDEX "commission_entries_invoiceId_idx" ON "commission_entries"("invoiceId");

-- CreateIndex
CREATE INDEX "commission_entries_paymentId_idx" ON "commission_entries"("paymentId");

-- CreateIndex
CREATE INDEX "commission_entries_reversalOfEntryId_idx" ON "commission_entries"("reversalOfEntryId");

-- CreateIndex
CREATE UNIQUE INDEX "dealer_payout_accounts_accountCode_key" ON "dealer_payout_accounts"("accountCode");

-- CreateIndex
CREATE INDEX "dealer_payout_accounts_dealerOrganizationId_status_idx" ON "dealer_payout_accounts"("dealerOrganizationId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "dealer_settlements_settlementNumber_key" ON "dealer_settlements"("settlementNumber");

-- CreateIndex
CREATE INDEX "dealer_settlements_dealerOrganizationId_status_idx" ON "dealer_settlements"("dealerOrganizationId", "status");

-- CreateIndex
CREATE INDEX "dealer_settlements_payoutAccountId_status_idx" ON "dealer_settlements"("payoutAccountId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "dealer_settlement_items_commissionEntryId_key" ON "dealer_settlement_items"("commissionEntryId");

-- CreateIndex
CREATE INDEX "dealer_settlement_items_settlementId_idx" ON "dealer_settlement_items"("settlementId");

-- CreateIndex
CREATE UNIQUE INDEX "dealer_ledger_entries_ledgerNumber_key" ON "dealer_ledger_entries"("ledgerNumber");

-- CreateIndex
CREATE INDEX "dealer_ledger_entries_dealerOrganizationId_occurredAt_idx" ON "dealer_ledger_entries"("dealerOrganizationId", "occurredAt");

-- CreateIndex
CREATE INDEX "dealer_ledger_entries_referenceType_referenceId_idx" ON "dealer_ledger_entries"("referenceType", "referenceId");

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_servicePlanId_fkey" FOREIGN KEY ("servicePlanId") REFERENCES "service_plans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoices" ADD CONSTRAINT "invoices_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoices" ADD CONSTRAINT "invoices_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES "subscriptions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoices" ADD CONSTRAINT "invoices_managingDealerIdAtIssue_fkey" FOREIGN KEY ("managingDealerIdAtIssue") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invoice_lines" ADD CONSTRAINT "invoice_lines_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "invoices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_allocations" ADD CONSTRAINT "payment_allocations_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "payments"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_allocations" ADD CONSTRAINT "payment_allocations_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "invoices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_gateway_events" ADD CONSTRAINT "payment_gateway_events_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "payments"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refunds" ADD CONSTRAINT "refunds_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "payments"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refunds" ADD CONSTRAINT "refunds_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refunds" ADD CONSTRAINT "refunds_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "invoices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_rules" ADD CONSTRAINT "commission_rules_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_rules" ADD CONSTRAINT "commission_rules_servicePlanId_fkey" FOREIGN KEY ("servicePlanId") REFERENCES "service_plans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_entries" ADD CONSTRAINT "commission_entries_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_entries" ADD CONSTRAINT "commission_entries_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_entries" ADD CONSTRAINT "commission_entries_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "invoices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_entries" ADD CONSTRAINT "commission_entries_invoiceLineId_fkey" FOREIGN KEY ("invoiceLineId") REFERENCES "invoice_lines"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_entries" ADD CONSTRAINT "commission_entries_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "payments"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_entries" ADD CONSTRAINT "commission_entries_commissionRuleId_fkey" FOREIGN KEY ("commissionRuleId") REFERENCES "commission_rules"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commission_entries" ADD CONSTRAINT "commission_entries_reversalOfEntryId_fkey" FOREIGN KEY ("reversalOfEntryId") REFERENCES "commission_entries"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_payout_accounts" ADD CONSTRAINT "dealer_payout_accounts_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_settlements" ADD CONSTRAINT "dealer_settlements_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_settlements" ADD CONSTRAINT "dealer_settlements_payoutAccountId_fkey" FOREIGN KEY ("payoutAccountId") REFERENCES "dealer_payout_accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_settlement_items" ADD CONSTRAINT "dealer_settlement_items_settlementId_fkey" FOREIGN KEY ("settlementId") REFERENCES "dealer_settlements"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_settlement_items" ADD CONSTRAINT "dealer_settlement_items_commissionEntryId_fkey" FOREIGN KEY ("commissionEntryId") REFERENCES "commission_entries"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_ledger_entries" ADD CONSTRAINT "dealer_ledger_entries_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Solid Tracker Phase 3 billing invariants.

ALTER TABLE "service_plans"
ADD CONSTRAINT "service_plans_values_valid"
CHECK (
  "version" > 0
  AND "billingIntervalCount" > 0
  AND "basePrice" >= 0
  AND "trialDays" >= 0
  AND ("deviceLimit" IS NULL OR "deviceLimit" > 0)
  AND (
    "historyRetentionDays" IS NULL
    OR "historyRetentionDays" > 0
  )
  AND (
    "effectiveUntil" IS NULL
    OR "effectiveUntil" > "effectiveFrom"
  )
);

ALTER TABLE "subscriptions"
ADD CONSTRAINT "subscriptions_period_valid"
CHECK (
  (
    "currentPeriodStart" IS NULL
    AND "currentPeriodEnd" IS NULL
  )
  OR
  (
    "currentPeriodStart" IS NOT NULL
    AND "currentPeriodEnd" IS NOT NULL
    AND "currentPeriodEnd" > "currentPeriodStart"
  )
);

ALTER TABLE "subscriptions"
ADD CONSTRAINT "subscriptions_cancellation_valid"
CHECK (
  (
    "status" = 'CANCELLED'
    AND "cancelledAt" IS NOT NULL
  )
  OR
  (
    "status" <> 'CANCELLED'
  )
);

ALTER TABLE "invoices"
ADD CONSTRAINT "invoices_dates_valid"
CHECK (
  "dueDate" >= "issueDate"
  AND (
    "billingPeriodStart" IS NULL
    AND "billingPeriodEnd" IS NULL
    OR
    "billingPeriodStart" IS NOT NULL
    AND "billingPeriodEnd" IS NOT NULL
    AND "billingPeriodEnd" > "billingPeriodStart"
  )
);

ALTER TABLE "invoices"
ADD CONSTRAINT "invoices_amounts_valid"
CHECK (
  "subtotal" >= 0
  AND "discountAmount" >= 0
  AND "taxAmount" >= 0
  AND "totalAmount" >= 0
  AND "paidAmount" >= 0
  AND "outstandingAmount" >= 0
  AND "discountAmount" <= "subtotal"
  AND "totalAmount" =
    "subtotal" - "discountAmount" + "taxAmount"
  AND "paidAmount" + "outstandingAmount" = "totalAmount"
);

ALTER TABLE "invoice_lines"
ADD CONSTRAINT "invoice_lines_amounts_valid"
CHECK (
  "lineNumber" > 0
  AND "quantity" > 0
  AND "unitPrice" >= 0
  AND "discountAmount" >= 0
  AND "taxAmount" >= 0
  AND "lineTotal" >= 0
  AND "lineTotal" =
    ROUND(
      ("quantity" * "unitPrice")
      - "discountAmount"
      + "taxAmount",
      2
    )
);

ALTER TABLE "payments"
ADD CONSTRAINT "payments_amount_valid"
CHECK ("amount" > 0);

ALTER TABLE "payments"
ADD CONSTRAINT "payments_status_timestamps_valid"
CHECK (
  (
    "status" IN (
      'SUCCEEDED',
      'REFUNDED',
      'PARTIALLY_REFUNDED'
    )
    AND "confirmedAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'FAILED'
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" IN ('INITIATED', 'PENDING', 'CANCELLED')
  )
);

ALTER TABLE "payment_allocations"
ADD CONSTRAINT "payment_allocations_amount_valid"
CHECK ("amount" > 0);

ALTER TABLE "refunds"
ADD CONSTRAINT "refunds_amount_valid"
CHECK ("amount" > 0);

ALTER TABLE "refunds"
ADD CONSTRAINT "refunds_status_timestamps_valid"
CHECK (
  (
    "status" = 'SUCCEEDED'
    AND "completedAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'FAILED'
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" IN ('REQUESTED', 'PENDING', 'CANCELLED')
  )
);

ALTER TABLE "commission_rules"
ADD CONSTRAINT "commission_rules_effective_period_valid"
CHECK (
  "priority" >= 0
  AND (
    "effectiveUntil" IS NULL
    OR "effectiveUntil" > "effectiveFrom"
  )
  AND (
    "minimumAmount" IS NULL
    OR "minimumAmount" >= 0
  )
  AND (
    "maximumAmount" IS NULL
    OR "maximumAmount" >= 0
  )
  AND (
    "minimumAmount" IS NULL
    OR "maximumAmount" IS NULL
    OR "maximumAmount" >= "minimumAmount"
  )
);

ALTER TABLE "commission_rules"
ADD CONSTRAINT "commission_rules_calculation_valid"
CHECK (
  (
    "calculationType" = 'PERCENTAGE'
    AND "percentageRate" IS NOT NULL
    AND "percentageRate" >= 0
    AND "percentageRate" <= 100
    AND "fixedAmount" IS NULL
    AND "tierDefinition" IS NULL
  )
  OR
  (
    "calculationType" = 'FIXED_AMOUNT'
    AND "fixedAmount" IS NOT NULL
    AND "fixedAmount" >= 0
    AND "percentageRate" IS NULL
    AND "tierDefinition" IS NULL
  )
  OR
  (
    "calculationType" = 'TIERED'
    AND "tierDefinition" IS NOT NULL
    AND "percentageRate" IS NULL
    AND "fixedAmount" IS NULL
  )
  OR
  (
    "calculationType" = 'NONE'
    AND "percentageRate" IS NULL
    AND "fixedAmount" IS NULL
    AND "tierDefinition" IS NULL
  )
);

ALTER TABLE "commission_entries"
ADD CONSTRAINT "commission_entries_values_valid"
CHECK (
  "baseAmount" >= 0
  AND (
    "percentageRateSnapshot" IS NULL
    OR (
      "percentageRateSnapshot" >= 0
      AND "percentageRateSnapshot" <= 100
    )
  )
  AND (
    "fixedAmountSnapshot" IS NULL
    OR "fixedAmountSnapshot" >= 0
  )
  AND (
    (
      "reversalOfEntryId" IS NULL
      AND "commissionAmount" >= 0
    )
    OR
    (
      "reversalOfEntryId" IS NOT NULL
      AND "commissionAmount" < 0
    )
  )
);

ALTER TABLE "dealer_settlements"
ADD CONSTRAINT "dealer_settlements_amounts_valid"
CHECK (
  "grossCommissionAmount" >= 0
  AND "feeAmount" >= 0
  AND "netSettlementAmount" >= 0
  AND "netSettlementAmount" =
    "grossCommissionAmount"
    + "adjustmentAmount"
    - "feeAmount"
);

ALTER TABLE "dealer_settlements"
ADD CONSTRAINT "dealer_settlements_status_valid"
CHECK (
  (
    "status" = 'COMPLETED'
    AND "completedAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'FAILED'
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" IN (
      'DRAFT',
      'PENDING',
      'PROCESSING',
      'CANCELLED',
      'REVERSED'
    )
  )
);

ALTER TABLE "dealer_settlement_items"
ADD CONSTRAINT "dealer_settlement_items_amount_valid"
CHECK ("amount" > 0);

ALTER TABLE "dealer_ledger_entries"
ADD CONSTRAINT "dealer_ledger_entries_amount_valid"
CHECK ("amount" > 0);

CREATE UNIQUE INDEX
  "subscriptions_one_current_per_vehicle"
ON "subscriptions" ("vehicleId")
WHERE "status" IN (
  'PENDING',
  'TRIALING',
  'ACTIVE',
  'PAST_DUE',
  'SUSPENDED'
);

CREATE UNIQUE INDEX
  "dealer_payout_accounts_one_default_per_dealer"
ON "dealer_payout_accounts" ("dealerOrganizationId")
WHERE "isDefault" = TRUE AND "status" = 'ACTIVE';

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_subscription_vehicle"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vehicle_customer_id UUID;
BEGIN
  SELECT "customerId"
  INTO vehicle_customer_id
  FROM "vehicles"
  WHERE "id" = NEW."vehicleId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Vehicle % does not exist',
      NEW."vehicleId";
  END IF;

  IF vehicle_customer_id <> NEW."customerId" THEN
    RAISE EXCEPTION
      'Subscription customer must own the selected vehicle';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "subscriptions_validate_vehicle"
BEFORE INSERT OR UPDATE OF "customerId", "vehicleId"
ON "subscriptions"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_subscription_vehicle"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_invoice_context"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  subscription_customer_id UUID;
BEGIN
  IF NEW."subscriptionId" IS NOT NULL THEN
    SELECT "customerId"
    INTO subscription_customer_id
    FROM "subscriptions"
    WHERE "id" = NEW."subscriptionId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Subscription % does not exist',
        NEW."subscriptionId";
    END IF;

    IF subscription_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Invoice customer must match subscription customer';
    END IF;
  END IF;

  IF NEW."managingDealerIdAtIssue" IS NOT NULL THEN
    PERFORM "solid_tracker_assert_organization_type"(
      NEW."managingDealerIdAtIssue",
      'DEALER'
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "invoices_validate_context"
BEFORE INSERT OR UPDATE OF
  "customerId",
  "subscriptionId",
  "managingDealerIdAtIssue"
ON "invoices"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_invoice_context"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_payment_allocation"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  payment_customer_id UUID;
  payment_currency VARCHAR(3);
  payment_amount NUMERIC(14, 2);
  payment_status "PaymentStatus";
  invoice_customer_id UUID;
  invoice_currency VARCHAR(3);
  invoice_total NUMERIC(14, 2);
  allocated_from_payment NUMERIC(14, 2);
  allocated_to_invoice NUMERIC(14, 2);
BEGIN
  SELECT
    "customerId",
    "currency",
    "amount",
    "status"
  INTO
    payment_customer_id,
    payment_currency,
    payment_amount,
    payment_status
  FROM "payments"
  WHERE "id" = NEW."paymentId"
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Payment % does not exist',
      NEW."paymentId";
  END IF;

  IF payment_status NOT IN (
    'SUCCEEDED',
    'PARTIALLY_REFUNDED',
    'REFUNDED'
  ) THEN
    RAISE EXCEPTION
      'Only confirmed payments can be allocated';
  END IF;

  SELECT
    "customerId",
    "currency",
    "totalAmount"
  INTO
    invoice_customer_id,
    invoice_currency,
    invoice_total
  FROM "invoices"
  WHERE "id" = NEW."invoiceId"
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Invoice % does not exist',
      NEW."invoiceId";
  END IF;

  IF payment_customer_id <> invoice_customer_id THEN
    RAISE EXCEPTION
      'Payment and invoice customers must match';
  END IF;

  IF payment_currency <> invoice_currency THEN
    RAISE EXCEPTION
      'Payment and invoice currencies must match';
  END IF;

  SELECT COALESCE(SUM("amount"), 0)
  INTO allocated_from_payment
  FROM "payment_allocations"
  WHERE "paymentId" = NEW."paymentId";

  SELECT COALESCE(SUM("amount"), 0)
  INTO allocated_to_invoice
  FROM "payment_allocations"
  WHERE "invoiceId" = NEW."invoiceId";

  IF allocated_from_payment + NEW."amount" > payment_amount THEN
    RAISE EXCEPTION
      'Payment allocation exceeds payment amount';
  END IF;

  IF allocated_to_invoice + NEW."amount" > invoice_total THEN
    RAISE EXCEPTION
      'Payment allocation exceeds invoice total';
  END IF;

  UPDATE "invoices"
  SET
    "paidAmount" = allocated_to_invoice + NEW."amount",
    "outstandingAmount" =
      invoice_total - allocated_to_invoice - NEW."amount",
    "status" = CASE
      WHEN allocated_to_invoice + NEW."amount" = invoice_total
        THEN 'PAID'::"InvoiceStatus"
      ELSE 'PARTIALLY_PAID'::"InvoiceStatus"
    END,
    "updatedAt" = NOW()
  WHERE "id" = NEW."invoiceId";

  RETURN NEW;
END;
$$;

CREATE TRIGGER "payment_allocations_validate"
BEFORE INSERT
ON "payment_allocations"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_payment_allocation"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_block_append_only_mutation"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    '% is append-only and cannot be updated or deleted',
    TG_TABLE_NAME;
END;
$$;

CREATE TRIGGER "payment_allocations_block_update"
BEFORE UPDATE
ON "payment_allocations"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_block_append_only_mutation"();

CREATE TRIGGER "payment_allocations_block_delete"
BEFORE DELETE
ON "payment_allocations"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_block_append_only_mutation"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_refund"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  payment_customer_id UUID;
  payment_currency VARCHAR(3);
  payment_amount NUMERIC(14, 2);
  payment_status "PaymentStatus";
  refunded_amount NUMERIC(14, 2);
BEGIN
  SELECT
    "customerId",
    "currency",
    "amount",
    "status"
  INTO
    payment_customer_id,
    payment_currency,
    payment_amount,
    payment_status
  FROM "payments"
  WHERE "id" = NEW."paymentId"
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Payment % does not exist',
      NEW."paymentId";
  END IF;

  IF payment_status NOT IN (
    'SUCCEEDED',
    'PARTIALLY_REFUNDED',
    'REFUNDED'
  ) THEN
    RAISE EXCEPTION
      'Refund requires a confirmed payment';
  END IF;

  IF payment_customer_id <> NEW."customerId" THEN
    RAISE EXCEPTION
      'Refund customer must match payment customer';
  END IF;

  IF payment_currency <> NEW."currency" THEN
    RAISE EXCEPTION
      'Refund currency must match payment currency';
  END IF;

  SELECT COALESCE(SUM("amount"), 0)
  INTO refunded_amount
  FROM "refunds"
  WHERE "paymentId" = NEW."paymentId"
    AND "id" <> NEW."id"
    AND "status" IN (
      'REQUESTED',
      'PENDING',
      'SUCCEEDED'
    );

  IF refunded_amount + NEW."amount" > payment_amount THEN
    RAISE EXCEPTION
      'Refund total exceeds payment amount';
  END IF;

  IF NEW."invoiceId" IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM "payment_allocations"
    WHERE "paymentId" = NEW."paymentId"
      AND "invoiceId" = NEW."invoiceId"
  ) THEN
    RAISE EXCEPTION
      'Refund invoice must be allocated to the payment';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "refunds_validate"
BEFORE INSERT OR UPDATE OF
  "paymentId",
  "customerId",
  "invoiceId",
  "amount",
  "currency",
  "status"
ON "refunds"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_refund"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_commission_entry"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  source_customer_id UUID;
  source_dealer_id UUID;
  source_currency VARCHAR(3);
  rule_dealer_id UUID;
  reversed_dealer_id UUID;
  reversed_customer_id UUID;
  reversed_currency VARCHAR(3);
BEGIN
  PERFORM "solid_tracker_assert_organization_type"(
    NEW."dealerOrganizationId",
    'DEALER'
  );

  IF NEW."invoiceId" IS NOT NULL THEN
    SELECT
      "customerId",
      "managingDealerIdAtIssue",
      "currency"
    INTO
      source_customer_id,
      source_dealer_id,
      source_currency
    FROM "invoices"
    WHERE "id" = NEW."invoiceId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Invoice % does not exist',
        NEW."invoiceId";
    END IF;

    IF source_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Commission customer must match invoice customer';
    END IF;

    IF source_dealer_id IS NOT NULL
       AND source_dealer_id <> NEW."dealerOrganizationId" THEN
      RAISE EXCEPTION
        'Commission dealer must match invoice dealer snapshot';
    END IF;

    IF source_currency <> NEW."currency" THEN
      RAISE EXCEPTION
        'Commission currency must match invoice currency';
    END IF;
  END IF;

  IF NEW."paymentId" IS NOT NULL THEN
    SELECT "customerId", "currency"
    INTO source_customer_id, source_currency
    FROM "payments"
    WHERE "id" = NEW."paymentId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Payment % does not exist',
        NEW."paymentId";
    END IF;

    IF source_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Commission customer must match payment customer';
    END IF;

    IF source_currency <> NEW."currency" THEN
      RAISE EXCEPTION
        'Commission currency must match payment currency';
    END IF;
  END IF;

  IF NEW."commissionRuleId" IS NOT NULL THEN
    SELECT "dealerOrganizationId"
    INTO rule_dealer_id
    FROM "commission_rules"
    WHERE "id" = NEW."commissionRuleId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Commission rule % does not exist',
        NEW."commissionRuleId";
    END IF;

    IF rule_dealer_id <> NEW."dealerOrganizationId" THEN
      RAISE EXCEPTION
        'Commission rule dealer must match commission dealer';
    END IF;
  END IF;

  IF NEW."reversalOfEntryId" IS NOT NULL THEN
    SELECT
      "dealerOrganizationId",
      "customerId",
      "currency"
    INTO
      reversed_dealer_id,
      reversed_customer_id,
      reversed_currency
    FROM "commission_entries"
    WHERE "id" = NEW."reversalOfEntryId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Reversed commission entry % does not exist',
        NEW."reversalOfEntryId";
    END IF;

    IF reversed_dealer_id <> NEW."dealerOrganizationId"
       OR reversed_customer_id <> NEW."customerId"
       OR reversed_currency <> NEW."currency" THEN
      RAISE EXCEPTION
        'Commission reversal must preserve dealer, customer, and currency';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "commission_entries_validate"
BEFORE INSERT OR UPDATE OF
  "dealerOrganizationId",
  "customerId",
  "invoiceId",
  "paymentId",
  "commissionRuleId",
  "reversalOfEntryId",
  "currency"
ON "commission_entries"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_commission_entry"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_payout_account"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM "solid_tracker_assert_organization_type"(
    NEW."dealerOrganizationId",
    'DEALER'
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER "payout_accounts_validate_dealer"
BEFORE INSERT OR UPDATE OF "dealerOrganizationId"
ON "dealer_payout_accounts"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_payout_account"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_settlement"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  payout_dealer_id UUID;
  payout_status "PayoutAccountStatus";
  payout_verification "PayoutVerificationStatus";
BEGIN
  PERFORM "solid_tracker_assert_organization_type"(
    NEW."dealerOrganizationId",
    'DEALER'
  );

  SELECT
    "dealerOrganizationId",
    "status",
    "verificationStatus"
  INTO
    payout_dealer_id,
    payout_status,
    payout_verification
  FROM "dealer_payout_accounts"
  WHERE "id" = NEW."payoutAccountId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Payout account % does not exist',
      NEW."payoutAccountId";
  END IF;

  IF payout_dealer_id <> NEW."dealerOrganizationId" THEN
    RAISE EXCEPTION
      'Settlement dealer must own the payout account';
  END IF;

  IF NEW."status" IN (
    'PENDING',
    'PROCESSING',
    'COMPLETED'
  ) AND (
    payout_status <> 'ACTIVE'
    OR payout_verification <> 'VERIFIED'
  ) THEN
    RAISE EXCEPTION
      'Settlement processing requires an active verified payout account';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "settlements_validate_context"
BEFORE INSERT OR UPDATE OF
  "dealerOrganizationId",
  "payoutAccountId",
  "status"
ON "dealer_settlements"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_settlement"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_settlement_item"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  settlement_dealer_id UUID;
  settlement_currency VARCHAR(3);
  commission_dealer_id UUID;
  commission_currency VARCHAR(3);
  commission_amount NUMERIC(14, 2);
  commission_status "CommissionEntryStatus";
BEGIN
  SELECT
    "dealerOrganizationId",
    "currency"
  INTO
    settlement_dealer_id,
    settlement_currency
  FROM "dealer_settlements"
  WHERE "id" = NEW."settlementId"
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Settlement % does not exist',
      NEW."settlementId";
  END IF;

  SELECT
    "dealerOrganizationId",
    "currency",
    "commissionAmount",
    "status"
  INTO
    commission_dealer_id,
    commission_currency,
    commission_amount,
    commission_status
  FROM "commission_entries"
  WHERE "id" = NEW."commissionEntryId"
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Commission entry % does not exist',
      NEW."commissionEntryId";
  END IF;

  IF settlement_dealer_id <> commission_dealer_id THEN
    RAISE EXCEPTION
      'Settlement and commission dealers must match';
  END IF;

  IF settlement_currency <> commission_currency THEN
    RAISE EXCEPTION
      'Settlement and commission currencies must match';
  END IF;

  IF commission_status NOT IN (
    'AVAILABLE',
    'SETTLEMENT_PENDING'
  ) THEN
    RAISE EXCEPTION
      'Only available commission can enter a settlement';
  END IF;

  IF commission_amount <= 0 OR NEW."amount" > commission_amount THEN
    RAISE EXCEPTION
      'Settlement item amount exceeds eligible commission';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "settlement_items_validate_context"
BEFORE INSERT
ON "dealer_settlement_items"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_settlement_item"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_ledger_dealer"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM "solid_tracker_assert_organization_type"(
    NEW."dealerOrganizationId",
    'DEALER'
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER "dealer_ledger_entries_validate_dealer"
BEFORE INSERT
ON "dealer_ledger_entries"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_ledger_dealer"();

CREATE TRIGGER "dealer_ledger_entries_block_update"
BEFORE UPDATE
ON "dealer_ledger_entries"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_block_append_only_mutation"();

CREATE TRIGGER "dealer_ledger_entries_block_delete"
BEFORE DELETE
ON "dealer_ledger_entries"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_block_append_only_mutation"();