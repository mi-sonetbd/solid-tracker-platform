[CmdletBinding()]
param(
    [string]$RepositoryPath = "D:\GitHub\gps-tracker-platform"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param(
        [int]$Number,
        [int]$Total,
        [string]$Message
    )

    Write-Host ("[{0}/{1}] {2}" -f $Number, $Total, $Message) -ForegroundColor Yellow
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $parentPath = Split-Path -Parent $fullPath

    if (-not (Test-Path -LiteralPath $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $Content.TrimStart(),
        $script:Utf8NoBom
    )

    Write-Host "[WRITTEN] $RelativePath" -ForegroundColor Green
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-Host $Description -ForegroundColor DarkCyan
    & $Command

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed."
    }
}

function Add-PrismaFields {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Schema,

        [Parameter(Mandatory = $true)]
        [string]$ModelName,

        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [Parameter(Mandatory = $true)]
        [string]$Fields
    )

    if ($Schema.Contains($Marker)) {
        return $Schema
    }

    $pattern = "(?ms)(model\s+" +
        [regex]::Escape($ModelName) +
        "\s+\{.*?)(\r?\n\})"

    $match = [regex]::Match($Schema, $pattern)

    if (-not $match.Success) {
        throw "Could not locate Prisma model: $ModelName"
    }

    $replacement = (
        $match.Groups[1].Value +
        [Environment]::NewLine +
        $Fields.TrimEnd() +
        $match.Groups[2].Value
    )

    return (
        $Schema.Substring(0, $match.Index) +
        $replacement +
        $Schema.Substring($match.Index + $match.Length)
    )
}

function Assert-CleanExceptSelf {
    $allowedEntries = @(
        "?? scripts/solid-tracker-billing-foundation.ps1"
    )

    $unexpectedChanges = @(
        git status --short |
            Where-Object {
                $_ -and
                $allowedEntries -notcontains $_.TrimEnd()
            }
    )

    if ($unexpectedChanges.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        $unexpectedChanges | ForEach-Object {
            Write-Host $_ -ForegroundColor Yellow
        }

        throw "Working tree contains changes other than this billing script."
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Billing Foundation" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath
    $script:RootPath = (Get-Location).Path
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found."
    }

    foreach ($requiredPath in @(
        ".env",
        ".gitattributes",
        "compose.yaml",
        "services\backend-api\package.json",
        "services\backend-api\prisma.config.ts",
        "services\backend-api\prisma\schema.prisma",
        "services\backend-api\prisma\migrations",
        "services\backend-api\src\database\prisma.service.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file or directory is missing: $requiredPath"
        }
    }

    Write-Step 1 10 "Merging the asset foundation and creating the billing branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/vehicle-device-foundation") {
        Assert-CleanExceptSelf

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        git merge-base --is-ancestor `
            feat/vehicle-device-foundation `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge vehicle/device foundation into main" {
                git merge `
                    --no-ff `
                    feat/vehicle-device-foundation `
                    -m "merge: integrate vehicle and device foundation"
            }
        }
        else {
            Write-Host (
                "Vehicle/device foundation is already contained in main."
            ) -ForegroundColor Green
        }

        $branchExists = git branch --list "feat/billing-foundation"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing billing branch" {
                git checkout feat/billing-foundation
            }
        }
        else {
            Invoke-CheckedCommand "Create billing feature branch" {
                git checkout -b feat/billing-foundation
            }
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-CleanExceptSelf

        git merge-base --is-ancestor `
            feat/vehicle-device-foundation `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge vehicle/device foundation into main" {
                git merge `
                    --no-ff `
                    feat/vehicle-device-foundation `
                    -m "merge: integrate vehicle and device foundation"
            }
        }

        $branchExists = git branch --list "feat/billing-foundation"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing billing branch" {
                git checkout feat/billing-foundation
            }
        }
        else {
            Invoke-CheckedCommand "Create billing feature branch" {
                git checkout -b feat/billing-foundation
            }
        }
    }
    elseif ($currentBranch -eq "feat/billing-foundation") {
        Assert-CleanExceptSelf
        Write-Host "Already on feat/billing-foundation." -ForegroundColor Green
    }
    else {
        throw (
            "Expected feat/vehicle-device-foundation, main, or " +
            "feat/billing-foundation. Current branch: $currentBranch"
        )
    }

    Write-Step 2 10 "Validating PostgreSQL and existing Prisma migrations"

    $postgresHealth = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        solid-tracker-postgres 2>$null

    if (
        $LASTEXITCODE -ne 0 -or
        $postgresHealth.Trim() -ne "healthy"
    ) {
        throw "solid-tracker-postgres must be running and healthy."
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $existingMigrationCount = @(
        Get-ChildItem `
            -LiteralPath "services\backend-api\prisma\migrations" `
            -Directory
    ).Count

    if ($existingMigrationCount -lt 2) {
        throw (
            "Expected the identity/customer and vehicle/device " +
            "migrations before starting billing."
        )
    }

    Write-Host "PostgreSQL: healthy" -ForegroundColor Green
    Write-Host "Existing migrations: $existingMigrationCount" -ForegroundColor Green

    Write-Step 3 10 "Extending the Prisma schema with billing and settlement entities"

    $schemaPath = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\schema.prisma"

    $schema = [System.IO.File]::ReadAllText($schemaPath)

    if (-not $schema.Contains("model ServicePlan {")) {
        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "Organization" `
            -Marker "dealerCommissionRules" `
            -Fields @'
  managedInvoices          Invoice[]             @relation("InvoiceManagingDealer")
  dealerCommissionRules    CommissionRule[]
  dealerCommissionEntries  CommissionEntry[]
  dealerPayoutAccounts     DealerPayoutAccount[]
  dealerSettlements        DealerSettlement[]
  dealerLedgerEntries      DealerLedgerEntry[]
'@

        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "Customer" `
            -Marker "billingSubscriptions" `
            -Fields @'
  billingSubscriptions Subscription[]
  invoices             Invoice[]
  payments             Payment[]
  refunds              Refund[]
  commissionEntries    CommissionEntry[]
'@

        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "Vehicle" `
            -Marker "billingSubscriptions" `
            -Fields @'
  billingSubscriptions Subscription[]
'@

        $billingSchema = @'

enum BillingIntervalUnit {
  DAY
  MONTH
  YEAR
}

enum TaxBehavior {
  NONE
  INCLUSIVE
  EXCLUSIVE
}

enum ServicePlanStatus {
  DRAFT
  ACTIVE
  INACTIVE
  ARCHIVED
}

enum SubscriptionStatus {
  PENDING
  TRIALING
  ACTIVE
  PAST_DUE
  SUSPENDED
  CANCELLED
  EXPIRED
}

enum InvoiceStatus {
  DRAFT
  ISSUED
  PARTIALLY_PAID
  PAID
  OVERDUE
  VOID
  REFUNDED
}

enum InvoiceLineItemType {
  DEVICE_SALE
  INSTALLATION
  SUBSCRIPTION
  SIM_FEE
  REPLACEMENT
  ADD_ON
  DISCOUNT
  OTHER
}

enum PaymentMethod {
  BKASH
  NAGAD
  BANK_TRANSFER
  CARD
  CASH
  MANUAL_ADJUSTMENT
}

enum PaymentGateway {
  NONE
  BKASH
  NAGAD
  SSLCOMMERZ
  BANK
  MANUAL
  OTHER
}

enum PaymentStatus {
  INITIATED
  PENDING
  SUCCEEDED
  FAILED
  CANCELLED
  REFUNDED
  PARTIALLY_REFUNDED
}

enum PaymentGatewayEventStatus {
  RECEIVED
  PROCESSING
  PROCESSED
  FAILED
  IGNORED
}

enum RefundStatus {
  REQUESTED
  PENDING
  SUCCEEDED
  FAILED
  CANCELLED
}

enum CommissionTransactionType {
  DEVICE_SALE
  INSTALLATION
  INITIAL_SUBSCRIPTION
  SUBSCRIPTION_RENEWAL
  UPGRADE
  ADD_ON_SERVICE
}

enum CommissionCalculationType {
  PERCENTAGE
  FIXED_AMOUNT
  TIERED
  NONE
}

enum CommissionRuleStatus {
  DRAFT
  ACTIVE
  INACTIVE
  ARCHIVED
}

enum CommissionEntryStatus {
  PENDING
  EARNED
  ON_HOLD
  AVAILABLE
  SETTLEMENT_PENDING
  SETTLED
  REVERSED
  CANCELLED
}

enum PayoutAccountType {
  BANK_ACCOUNT
  MOBILE_FINANCIAL_SERVICE
  PAYMENT_GATEWAY_ACCOUNT
}

enum PayoutProvider {
  BANK
  BKASH
  NAGAD
  OTHER
}

enum PayoutVerificationStatus {
  UNVERIFIED
  PENDING
  VERIFIED
  REJECTED
  EXPIRED
}

enum PayoutAccountStatus {
  ACTIVE
  INACTIVE
  SUSPENDED
  ARCHIVED
}

enum SettlementStatus {
  DRAFT
  PENDING
  PROCESSING
  COMPLETED
  FAILED
  CANCELLED
  REVERSED
}

enum LedgerEntryType {
  COMMISSION_EARNED
  COMMISSION_REVERSAL
  SETTLEMENT
  SETTLEMENT_REVERSAL
  MANUAL_ADJUSTMENT
  FEE
}

enum LedgerDirection {
  CREDIT
  DEBIT
}

model ServicePlan {
  id                   String              @id @default(uuid()) @db.Uuid
  planCode             String              @unique @db.VarChar(60)
  planFamilyCode       String              @db.VarChar(60)
  version              Int
  name                 String              @db.VarChar(160)
  description          String?
  billingIntervalUnit  BillingIntervalUnit
  billingIntervalCount Int                 @default(1)
  basePrice            Decimal             @db.Decimal(14, 2)
  currency             String              @default("BDT") @db.VarChar(3)
  taxBehavior          TaxBehavior         @default(NONE)
  trialDays            Int                 @default(0)
  features             Json?
  deviceLimit          Int?
  historyRetentionDays Int?
  status               ServicePlanStatus   @default(DRAFT)
  effectiveFrom        DateTime            @db.Timestamptz(3)
  effectiveUntil       DateTime?           @db.Timestamptz(3)
  createdAt            DateTime            @default(now()) @db.Timestamptz(3)
  updatedAt            DateTime            @updatedAt @db.Timestamptz(3)
  archivedAt           DateTime?           @db.Timestamptz(3)

  subscriptions   Subscription[]
  commissionRules CommissionRule[]

  @@unique([planFamilyCode, version])
  @@index([status, effectiveFrom])
  @@map("service_plans")
}

model Subscription {
  id                 String             @id @default(uuid()) @db.Uuid
  subscriptionCode   String             @unique @db.VarChar(60)
  customerId         String             @db.Uuid
  vehicleId          String             @db.Uuid
  servicePlanId      String             @db.Uuid
  status             SubscriptionStatus @default(PENDING)
  startedAt          DateTime?          @db.Timestamptz(3)
  currentPeriodStart DateTime?          @db.Timestamptz(3)
  currentPeriodEnd   DateTime?          @db.Timestamptz(3)
  nextBillingAt      DateTime?          @db.Timestamptz(3)
  trialEndsAt        DateTime?          @db.Timestamptz(3)
  cancelledAt        DateTime?          @db.Timestamptz(3)
  cancellationReason String?
  autoRenew          Boolean            @default(true)
  createdAt          DateTime           @default(now()) @db.Timestamptz(3)
  updatedAt          DateTime           @updatedAt @db.Timestamptz(3)

  customer    Customer    @relation(fields: [customerId], references: [id], onDelete: Restrict)
  vehicle     Vehicle     @relation(fields: [vehicleId], references: [id], onDelete: Restrict)
  servicePlan ServicePlan @relation(fields: [servicePlanId], references: [id], onDelete: Restrict)
  invoices    Invoice[]

  @@index([customerId, status])
  @@index([vehicleId, status])
  @@index([servicePlanId, status])
  @@index([nextBillingAt])
  @@map("subscriptions")
}

model Invoice {
  id                      String        @id @default(uuid()) @db.Uuid
  invoiceNumber           String        @unique @db.VarChar(60)
  customerId              String        @db.Uuid
  subscriptionId          String?       @db.Uuid
  managingDealerIdAtIssue String?       @db.Uuid
  billingPeriodStart      DateTime?     @db.Timestamptz(3)
  billingPeriodEnd        DateTime?     @db.Timestamptz(3)
  issueDate               DateTime      @db.Date
  dueDate                 DateTime      @db.Date
  subtotal                Decimal       @db.Decimal(14, 2)
  discountAmount          Decimal       @default(0) @db.Decimal(14, 2)
  taxAmount               Decimal       @default(0) @db.Decimal(14, 2)
  totalAmount             Decimal       @db.Decimal(14, 2)
  paidAmount              Decimal       @default(0) @db.Decimal(14, 2)
  outstandingAmount       Decimal       @db.Decimal(14, 2)
  currency                String        @default("BDT") @db.VarChar(3)
  status                  InvoiceStatus @default(DRAFT)
  issuedAt                DateTime?     @db.Timestamptz(3)
  voidedAt                DateTime?     @db.Timestamptz(3)
  voidReason              String?
  createdAt               DateTime      @default(now()) @db.Timestamptz(3)
  updatedAt               DateTime      @updatedAt @db.Timestamptz(3)

  customer              Customer       @relation(fields: [customerId], references: [id], onDelete: Restrict)
  subscription          Subscription?  @relation(fields: [subscriptionId], references: [id], onDelete: Restrict)
  managingDealerAtIssue Organization?  @relation("InvoiceManagingDealer", fields: [managingDealerIdAtIssue], references: [id], onDelete: Restrict)
  lines                 InvoiceLine[]
  paymentAllocations    PaymentAllocation[]
  refunds               Refund[]
  commissionEntries     CommissionEntry[]

  @@index([customerId, status])
  @@index([subscriptionId])
  @@index([managingDealerIdAtIssue, status])
  @@index([dueDate, status])
  @@map("invoices")
}

model InvoiceLine {
  id             String              @id @default(uuid()) @db.Uuid
  invoiceId      String              @db.Uuid
  lineNumber     Int
  itemType       InvoiceLineItemType
  description    String
  quantity       Decimal             @default(1) @db.Decimal(12, 3)
  unitPrice      Decimal             @db.Decimal(14, 2)
  discountAmount Decimal             @default(0) @db.Decimal(14, 2)
  taxAmount      Decimal             @default(0) @db.Decimal(14, 2)
  lineTotal      Decimal             @db.Decimal(14, 2)
  referenceType  String?             @db.VarChar(100)
  referenceId    String?             @db.VarChar(100)
  createdAt      DateTime            @default(now()) @db.Timestamptz(3)

  invoice           Invoice           @relation(fields: [invoiceId], references: [id], onDelete: Restrict)
  commissionEntries CommissionEntry[]

  @@unique([invoiceId, lineNumber])
  @@index([referenceType, referenceId])
  @@map("invoice_lines")
}

model Payment {
  id                   String         @id @default(uuid()) @db.Uuid
  paymentNumber        String         @unique @db.VarChar(60)
  customerId           String         @db.Uuid
  amount               Decimal        @db.Decimal(14, 2)
  currency             String         @default("BDT") @db.VarChar(3)
  paymentMethod        PaymentMethod
  paymentGateway       PaymentGateway @default(NONE)
  gatewayTransactionId String?        @db.VarChar(160)
  gatewayReference     String?        @db.VarChar(160)
  status               PaymentStatus  @default(INITIATED)
  initiatedAt          DateTime       @default(now()) @db.Timestamptz(3)
  confirmedAt          DateTime?      @db.Timestamptz(3)
  failedAt             DateTime?      @db.Timestamptz(3)
  failureReason        String?
  metadata             Json?
  createdAt            DateTime       @default(now()) @db.Timestamptz(3)
  updatedAt            DateTime       @updatedAt @db.Timestamptz(3)

  customer          Customer              @relation(fields: [customerId], references: [id], onDelete: Restrict)
  allocations       PaymentAllocation[]
  gatewayEvents     PaymentGatewayEvent[]
  refunds           Refund[]
  commissionEntries CommissionEntry[]

  @@unique([paymentGateway, gatewayTransactionId])
  @@index([customerId, status])
  @@index([status, initiatedAt])
  @@map("payments")
}

model PaymentAllocation {
  id          String   @id @default(uuid()) @db.Uuid
  paymentId   String   @db.Uuid
  invoiceId   String   @db.Uuid
  amount      Decimal  @db.Decimal(14, 2)
  allocatedAt DateTime @default(now()) @db.Timestamptz(3)
  createdAt   DateTime @default(now()) @db.Timestamptz(3)

  payment Payment @relation(fields: [paymentId], references: [id], onDelete: Restrict)
  invoice Invoice @relation(fields: [invoiceId], references: [id], onDelete: Restrict)

  @@unique([paymentId, invoiceId])
  @@index([invoiceId, allocatedAt])
  @@map("payment_allocations")
}

model PaymentGatewayEvent {
  id              String                    @id @default(uuid()) @db.Uuid
  paymentId       String?                   @db.Uuid
  gateway         PaymentGateway
  externalEventId String                    @db.VarChar(200)
  eventType       String                    @db.VarChar(120)
  payload         Json
  payloadHash     String                    @db.VarChar(128)
  status          PaymentGatewayEventStatus @default(RECEIVED)
  receivedAt      DateTime                  @default(now()) @db.Timestamptz(3)
  processedAt     DateTime?                 @db.Timestamptz(3)
  errorMessage    String?
  createdAt       DateTime                  @default(now()) @db.Timestamptz(3)
  updatedAt       DateTime                  @updatedAt @db.Timestamptz(3)

  payment Payment? @relation(fields: [paymentId], references: [id], onDelete: Restrict)

  @@unique([gateway, externalEventId])
  @@index([paymentId, status])
  @@index([status, receivedAt])
  @@map("payment_gateway_events")
}

model Refund {
  id              String       @id @default(uuid()) @db.Uuid
  refundNumber    String       @unique @db.VarChar(60)
  paymentId       String       @db.Uuid
  customerId      String       @db.Uuid
  invoiceId       String?      @db.Uuid
  amount          Decimal      @db.Decimal(14, 2)
  currency        String       @default("BDT") @db.VarChar(3)
  gatewayRefundId String?      @db.VarChar(160)
  reason          String
  status          RefundStatus @default(REQUESTED)
  requestedAt     DateTime     @default(now()) @db.Timestamptz(3)
  completedAt     DateTime?    @db.Timestamptz(3)
  failedAt        DateTime?    @db.Timestamptz(3)
  failureReason   String?
  metadata        Json?
  createdAt       DateTime     @default(now()) @db.Timestamptz(3)
  updatedAt       DateTime     @updatedAt @db.Timestamptz(3)

  payment  Payment  @relation(fields: [paymentId], references: [id], onDelete: Restrict)
  customer Customer @relation(fields: [customerId], references: [id], onDelete: Restrict)
  invoice  Invoice? @relation(fields: [invoiceId], references: [id], onDelete: Restrict)

  @@index([paymentId, status])
  @@index([customerId, status])
  @@map("refunds")
}

model CommissionRule {
  id                   String                    @id @default(uuid()) @db.Uuid
  ruleCode             String                    @unique @db.VarChar(60)
  dealerOrganizationId String                    @db.Uuid
  servicePlanId        String?                   @db.Uuid
  transactionType      CommissionTransactionType
  calculationType      CommissionCalculationType
  percentageRate       Decimal?                  @db.Decimal(7, 4)
  fixedAmount          Decimal?                  @db.Decimal(14, 2)
  tierDefinition       Json?
  minimumAmount        Decimal?                  @db.Decimal(14, 2)
  maximumAmount        Decimal?                  @db.Decimal(14, 2)
  priority             Int                       @default(100)
  effectiveFrom        DateTime                  @db.Timestamptz(3)
  effectiveUntil       DateTime?                 @db.Timestamptz(3)
  status               CommissionRuleStatus      @default(DRAFT)
  createdAt            DateTime                  @default(now()) @db.Timestamptz(3)
  updatedAt            DateTime                  @updatedAt @db.Timestamptz(3)
  archivedAt           DateTime?                 @db.Timestamptz(3)

  dealerOrganization Organization      @relation(fields: [dealerOrganizationId], references: [id], onDelete: Restrict)
  servicePlan        ServicePlan?      @relation(fields: [servicePlanId], references: [id], onDelete: Restrict)
  entries            CommissionEntry[]

  @@index([dealerOrganizationId, status])
  @@index([servicePlanId, transactionType, status])
  @@index([effectiveFrom, effectiveUntil])
  @@map("commission_rules")
}

model CommissionEntry {
  id                     String                    @id @default(uuid()) @db.Uuid
  commissionNumber       String                    @unique @db.VarChar(60)
  dealerOrganizationId   String                    @db.Uuid
  customerId             String                    @db.Uuid
  invoiceId              String?                   @db.Uuid
  invoiceLineId          String?                   @db.Uuid
  paymentId              String?                   @db.Uuid
  commissionRuleId       String?                   @db.Uuid
  reversalOfEntryId      String?                   @db.Uuid
  transactionType        CommissionTransactionType
  calculationType        CommissionCalculationType
  baseAmount             Decimal                   @db.Decimal(14, 2)
  percentageRateSnapshot Decimal?                  @db.Decimal(7, 4)
  fixedAmountSnapshot    Decimal?                  @db.Decimal(14, 2)
  commissionAmount       Decimal                   @db.Decimal(14, 2)
  currency               String                    @default("BDT") @db.VarChar(3)
  status                 CommissionEntryStatus     @default(PENDING)
  earnedAt               DateTime?                 @db.Timestamptz(3)
  availableAt            DateTime?                 @db.Timestamptz(3)
  settledAt              DateTime?                 @db.Timestamptz(3)
  holdReason             String?
  createdAt              DateTime                  @default(now()) @db.Timestamptz(3)
  updatedAt              DateTime                  @updatedAt @db.Timestamptz(3)

  dealerOrganization Organization       @relation(fields: [dealerOrganizationId], references: [id], onDelete: Restrict)
  customer           Customer           @relation(fields: [customerId], references: [id], onDelete: Restrict)
  invoice            Invoice?           @relation(fields: [invoiceId], references: [id], onDelete: Restrict)
  invoiceLine        InvoiceLine?       @relation(fields: [invoiceLineId], references: [id], onDelete: Restrict)
  payment            Payment?           @relation(fields: [paymentId], references: [id], onDelete: Restrict)
  commissionRule     CommissionRule?    @relation(fields: [commissionRuleId], references: [id], onDelete: Restrict)
  reversalOf         CommissionEntry?   @relation("CommissionReversal", fields: [reversalOfEntryId], references: [id], onDelete: Restrict)
  reversalEntries    CommissionEntry[]  @relation("CommissionReversal")
  settlementItem     DealerSettlementItem?

  @@index([dealerOrganizationId, status])
  @@index([customerId, status])
  @@index([invoiceId])
  @@index([paymentId])
  @@index([reversalOfEntryId])
  @@map("commission_entries")
}

model DealerPayoutAccount {
  id                        String                   @id @default(uuid()) @db.Uuid
  accountCode               String                   @unique @db.VarChar(60)
  dealerOrganizationId      String                   @db.Uuid
  accountType               PayoutAccountType
  provider                  PayoutProvider
  accountHolderName         String                   @db.VarChar(160)
  maskedAccountNumber       String                   @db.VarChar(80)
  encryptedAccountReference String
  verificationStatus        PayoutVerificationStatus @default(UNVERIFIED)
  isDefault                 Boolean                  @default(false)
  status                    PayoutAccountStatus      @default(ACTIVE)
  verifiedAt                DateTime?                @db.Timestamptz(3)
  createdAt                 DateTime                 @default(now()) @db.Timestamptz(3)
  updatedAt                 DateTime                 @updatedAt @db.Timestamptz(3)
  archivedAt                DateTime?                @db.Timestamptz(3)

  dealerOrganization Organization      @relation(fields: [dealerOrganizationId], references: [id], onDelete: Restrict)
  settlements        DealerSettlement[]

  @@index([dealerOrganizationId, status])
  @@map("dealer_payout_accounts")
}

model DealerSettlement {
  id                      String           @id @default(uuid()) @db.Uuid
  settlementNumber        String           @unique @db.VarChar(60)
  dealerOrganizationId    String           @db.Uuid
  payoutAccountId         String           @db.Uuid
  grossCommissionAmount   Decimal          @db.Decimal(14, 2)
  adjustmentAmount        Decimal          @default(0) @db.Decimal(14, 2)
  feeAmount               Decimal          @default(0) @db.Decimal(14, 2)
  netSettlementAmount     Decimal          @db.Decimal(14, 2)
  currency                String           @default("BDT") @db.VarChar(3)
  status                  SettlementStatus @default(DRAFT)
  providerReference       String?          @db.VarChar(160)
  initiatedAt             DateTime?        @db.Timestamptz(3)
  completedAt             DateTime?        @db.Timestamptz(3)
  failedAt                DateTime?        @db.Timestamptz(3)
  failureReason           String?
  createdAt               DateTime         @default(now()) @db.Timestamptz(3)
  updatedAt               DateTime         @updatedAt @db.Timestamptz(3)

  dealerOrganization Organization          @relation(fields: [dealerOrganizationId], references: [id], onDelete: Restrict)
  payoutAccount      DealerPayoutAccount    @relation(fields: [payoutAccountId], references: [id], onDelete: Restrict)
  items              DealerSettlementItem[]

  @@index([dealerOrganizationId, status])
  @@index([payoutAccountId, status])
  @@map("dealer_settlements")
}

model DealerSettlementItem {
  id                String   @id @default(uuid()) @db.Uuid
  settlementId      String   @db.Uuid
  commissionEntryId String   @unique @db.Uuid
  amount            Decimal  @db.Decimal(14, 2)
  createdAt         DateTime @default(now()) @db.Timestamptz(3)

  settlement      DealerSettlement @relation(fields: [settlementId], references: [id], onDelete: Restrict)
  commissionEntry CommissionEntry  @relation(fields: [commissionEntryId], references: [id], onDelete: Restrict)

  @@index([settlementId])
  @@map("dealer_settlement_items")
}

model DealerLedgerEntry {
  id                   String          @id @default(uuid()) @db.Uuid
  ledgerNumber         String          @unique @db.VarChar(60)
  dealerOrganizationId String          @db.Uuid
  entryType            LedgerEntryType
  direction            LedgerDirection
  amount               Decimal         @db.Decimal(14, 2)
  currency             String          @default("BDT") @db.VarChar(3)
  referenceType        String          @db.VarChar(100)
  referenceId          String          @db.VarChar(100)
  description          String
  occurredAt           DateTime        @default(now()) @db.Timestamptz(3)
  createdAt            DateTime        @default(now()) @db.Timestamptz(3)

  dealerOrganization Organization @relation(fields: [dealerOrganizationId], references: [id], onDelete: Restrict)

  @@index([dealerOrganizationId, occurredAt])
  @@index([referenceType, referenceId])
  @@map("dealer_ledger_entries")
}
'@

        $schema = (
            $schema.TrimEnd() +
            [Environment]::NewLine +
            $billingSchema.TrimStart()
        )

        [System.IO.File]::WriteAllText(
            $schemaPath,
            $schema,
            $script:Utf8NoBom
        )

        Write-Host (
            "[UPDATED] services\backend-api\prisma\schema.prisma"
        ) -ForegroundColor Green
    }
    else {
        Write-Host (
            "Billing schema already exists; preserving it."
        ) -ForegroundColor DarkYellow
    }

    Write-Step 4 10 "Formatting and validating the billing schema"

    Invoke-CheckedCommand "Prisma format" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma format `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma validate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma validate `
            --config prisma.config.ts
    }

    Write-Step 5 10 "Creating and customizing the billing migration"

    $migrationRoot = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\migrations"

    $billingMigration = Get-ChildItem `
        -LiteralPath $migrationRoot `
        -Directory |
        Where-Object {
            $_.Name -like "*_billing_foundation"
        } |
        Select-Object -First 1

    if (-not $billingMigration) {
        Invoke-CheckedCommand "Prisma migration create-only" {
            pnpm.cmd `
                --filter "@solid-tracker/backend-api" `
                exec prisma migrate dev `
                --name billing_foundation `
                --create-only `
                --config prisma.config.ts
        }

        $billingMigration = Get-ChildItem `
            -LiteralPath $migrationRoot `
            -Directory |
            Where-Object {
                $_.Name -like "*_billing_foundation"
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if (-not $billingMigration) {
        throw "The billing migration directory was not created."
    }

    $migrationSqlPath = Join-Path `
        $billingMigration.FullName `
        "migration.sql"

    if (-not (Test-Path -LiteralPath $migrationSqlPath)) {
        throw "The billing migration.sql file is missing."
    }

    $migrationSql = [System.IO.File]::ReadAllText(
        $migrationSqlPath
    )

    $customMarker = "-- Solid Tracker Phase 3 billing invariants."

    if (-not $migrationSql.Contains($customMarker)) {
        $customSql = @'

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
'@

        [System.IO.File]::AppendAllText(
            $migrationSqlPath,
            $customSql,
            $script:Utf8NoBom
        )

        Write-Host (
            "[CUSTOMIZED] " +
            $billingMigration.Name +
            "\migration.sql"
        ) -ForegroundColor Green
    }
    else {
        Write-Host (
            "PostgreSQL-native billing constraints already exist."
        ) -ForegroundColor DarkYellow
    }

    Write-Step 6 10 "Applying migration and generating Prisma Client"

    Invoke-CheckedCommand "Prisma migrate deploy" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate deploy `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma generate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma generate `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    Write-Step 7 10 "Running backend quality checks and tests"

    Invoke-CheckedCommand "Backend format" {
        pnpm.cmd --filter "@solid-tracker/backend-api" format
    }

    Invoke-CheckedCommand "Backend lint" {
        pnpm.cmd --filter "@solid-tracker/backend-api" lint
    }

    Invoke-CheckedCommand "Backend typecheck" {
        pnpm.cmd --filter "@solid-tracker/backend-api" typecheck
    }

    Invoke-CheckedCommand "Backend unit tests" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test --runInBand
    }

    Invoke-CheckedCommand "Backend E2E tests" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test:e2e --runInBand
    }

    Invoke-CheckedCommand "Backend production build" {
        pnpm.cmd --filter "@solid-tracker/backend-api" build
    }

    Write-Step 8 10 "Verifying billing tables, indexes, and triggers"

    $verificationSql = @'
SELECT
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'public'
  ) AS public_table_count,
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'subscriptions_one_current_per_vehicle',
        'dealer_payout_accounts_one_default_per_dealer'
      )
  ) AS billing_index_count,
  (
    SELECT COUNT(DISTINCT trigger_name)
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'subscriptions_validate_vehicle',
        'invoices_validate_context',
        'payment_allocations_validate',
        'payment_allocations_block_update',
        'payment_allocations_block_delete',
        'refunds_validate',
        'commission_entries_validate',
        'payout_accounts_validate_dealer',
        'settlements_validate_context',
        'settlement_items_validate_context',
        'dealer_ledger_entries_validate_dealer',
        'dealer_ledger_entries_block_update',
        'dealer_ledger_entries_block_delete'
      )
  ) AS billing_trigger_count;
'@

    $verificationOutput = $verificationSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL billing verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split(",")

    if ($parts.Count -ne 3) {
        throw "Unexpected PostgreSQL verification result: $verificationLine"
    }

    $tableCount = [int]$parts[0]
    $billingIndexCount = [int]$parts[1]
    $billingTriggerCount = [int]$parts[2]

    if ($tableCount -lt 40) {
        throw "Expected at least 40 public tables, but found $tableCount."
    }

    if ($billingIndexCount -ne 2) {
        throw "Expected 2 billing invariant indexes, but found $billingIndexCount."
    }

    if ($billingTriggerCount -ne 13) {
        throw "Expected 13 distinct billing triggers, but found $billingTriggerCount."
    }

    Write-Host "Public tables:             $tableCount" -ForegroundColor Green
    Write-Host "Billing invariant indexes: $billingIndexCount" -ForegroundColor Green
    Write-Host "Distinct billing triggers: $billingTriggerCount" -ForegroundColor Green

    Write-Step 9 10 "Writing billing architecture documentation"

    $documentation = @'
# Billing, Commission, and Settlement Foundation

## Scope

This migration introduces:

- service plans and plan versions;
- vehicle subscriptions;
- invoices and invoice lines;
- payments and payment allocations;
- payment gateway event idempotency;
- refunds;
- dealer commission rules and commission entries;
- dealer payout accounts;
- dealer settlements and settlement items;
- append-only dealer ledger entries.

## Core financial flow

```text
Service Plan
    ↓
Vehicle Subscription
    ↓
Invoice
    ↓
Payment
    ↓
Payment Allocation
    ↓
Commission Entry
    ↓
Dealer Settlement
    ↓
Dealer Ledger
```

## Plan versioning

A plan family may have multiple immutable versions. Historical subscriptions and invoices retain the plan version and monetary values that applied at the time.

## Subscription invariant

A vehicle may have only one current subscription across these statuses:

- `PENDING`
- `TRIALING`
- `ACTIVE`
- `PAST_DUE`
- `SUSPENDED`

Cancelled and expired subscriptions remain as history.

## Invoice accounting

Invoice totals obey:

```text
total = subtotal - discount + tax
paid + outstanding = total
```

Payment allocation is append-only. A confirmed payment may be allocated across one or more invoices, while an invoice may receive multiple payments.

The database prevents:

- allocation beyond the payment amount;
- allocation beyond the invoice total;
- customer mismatch;
- currency mismatch;
- allocation from an unconfirmed payment.

## Gateway idempotency

`PaymentGatewayEvent` has a unique pair:

```text
gateway + externalEventId
```

Repeated gateway webhooks therefore cannot produce duplicate payment effects.

## Refunds

A refund must reference a confirmed payment, preserve customer and currency, and may not make total requested/pending/succeeded refunds exceed the original payment.

## Dealer commission

Commission rules support:

- percentage;
- fixed amount;
- tiered calculation;
- no commission.

Commission entries retain calculation snapshots. Reversal entries are negative and reference the original commission entry.

Historical commission belongs to the dealer recorded at transaction time, even if the customer later changes dealer.

## Payout and settlement

A dealer may have only one active default payout account. Processing or completing a settlement requires an active, verified payout account belonging to the same dealer.

Settlement items can include only available commission entries for the same dealer and currency.

## Ledger immutability

Dealer ledger entries are append-only. Corrections use new reversal or adjustment entries rather than update or delete operations.

## Data types

All money fields use PostgreSQL `NUMERIC` through Prisma `Decimal`. Currency is stored separately as a three-character code, initially `BDT`.
'@

    Write-Utf8File `
        "docs\architecture\billing-foundation.md" `
        $documentation

    Write-Step 10 10 "Committing the billing foundation"

    git add --all

    git commit `
        -m "feat(billing): establish payments commissions and settlements"

    if ($LASTEXITCODE -ne 0) {
        throw "Billing foundation commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Billing Foundation Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current
    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate
    Write-Host ""
    Write-Host "Recent graph:" -ForegroundColor Yellow
    git log --oneline --decorate --graph -7
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    Write-Host "Next domain stage:" -ForegroundColor Yellow
    Write-Host (
        "Traccar servers, device mappings, tracking events, " +
        "geofences, notifications, and device commands"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "BILLING FOUNDATION FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Do not delete or reset an applied migration." -ForegroundColor Yellow
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
