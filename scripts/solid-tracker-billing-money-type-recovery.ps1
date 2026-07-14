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

function Get-LfContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path $script:RootPath $RelativePath

    return [System.IO.File]::ReadAllText($fullPath).Replace(
        "`r`n",
        "`n"
    )
}

function Set-LfContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $fullPath = Join-Path $script:RootPath $RelativePath

    [System.IO.File]::WriteAllText(
        $fullPath,
        $Content.Replace("`r`n", "`n"),
        $script:Utf8NoBom
    )
}

function Sync-FoundationEmbeddedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FoundationContent,

        [Parameter(Mandatory = $true)]
        [string]$EmbeddedPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$SourceContent
    )

    $pathMarker = "`"$EmbeddedPath`""
    $pathIndex = $FoundationContent.IndexOf(
        $pathMarker,
        [System.StringComparison]::Ordinal
    )

    if ($pathIndex -lt 0) {
        throw "Embedded file path was not found: $EmbeddedPath"
    }

    $payloadMarker = "@'"
    $payloadMarkerIndex = $FoundationContent.IndexOf(
        $payloadMarker,
        $pathIndex + $pathMarker.Length,
        [System.StringComparison]::Ordinal
    )

    if ($payloadMarkerIndex -lt 0) {
        throw "Embedded file opening marker was not found: $EmbeddedPath"
    }

    $payloadStart = $payloadMarkerIndex + $payloadMarker.Length

    if (
        $payloadStart -lt $FoundationContent.Length -and
        $FoundationContent[$payloadStart] -eq "`n"
    ) {
        $payloadStart++
    }

    $endMarker = "`n'@"
    $endIndex = $FoundationContent.IndexOf(
        $endMarker,
        $payloadStart,
        [System.StringComparison]::Ordinal
    )

    if ($endIndex -lt 0) {
        throw "Embedded file closing marker was not found: $EmbeddedPath"
    }

    $replacement = $SourceContent.TrimEnd("`n")

    return (
        $FoundationContent.Substring(0, $payloadStart) +
        $replacement +
        $FoundationContent.Substring($endIndex)
    )
}

function Assert-ExpectedRepositoryState {
    $allowedPrefixes = @(
        ".env.example",
        "services/backend-api/src/app.module.ts",
        "services/backend-api/src/config/environment.validation.ts",
        "scripts/solid-tracker-billing-api.ps1",
        "scripts/solid-tracker-billing-money-type-recovery.ps1",
        "services/backend-api/src/billing/",
        "services/backend-api/test/billing.e2e-spec.ts"
    )

    $unexpected = New-Object System.Collections.Generic.List[string]

    foreach ($line in @(git status --short)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line.Length -lt 4) {
            $unexpected.Add($line)
            continue
        }

        $path = $line.Substring(3).Trim()
        $allowed = $false

        foreach ($prefix in $allowedPrefixes) {
            if (
                $path -eq $prefix -or
                $path.StartsWith($prefix)
            ) {
                $allowed = $true
                break
            }
        }

        if (-not $allowed) {
            $unexpected.Add($line)
        }
    }

    if ($unexpected.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        foreach ($line in $unexpected) {
            Write-Host $line -ForegroundColor Yellow
        }

        throw "Working tree contains changes outside the billing API stage."
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Billing Decimal Recovery v3" -ForegroundColor Cyan
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

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -ne "feat/billing-api") {
        throw (
            "Expected branch feat/billing-api, " +
            "but current branch is $currentBranch"
        )
    }

    Assert-ExpectedRepositoryState

    $moneyService =
        "services/backend-api/src/billing/common/billing-money.service.ts"

    $foundationScript =
        "scripts/solid-tracker-billing-api.ps1"

    foreach ($requiredPath in @(
        ".env",
        ".env.example",
        $moneyService,
        $foundationScript,
        "services/backend-api/prisma.config.ts",
        "services/backend-api/prisma/schema.prisma",
        "services/backend-api/test/billing.e2e-spec.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file is missing: $requiredPath"
        }
    }

    Write-Step 1 7 "Confirming database and migration state"

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $migrationSql = @'
SELECT COUNT(*)
FROM "_prisma_migrations"
WHERE finished_at IS NOT NULL
  AND rolled_back_at IS NULL;
'@

    $migrationOutput = $migrationSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify the applied migration count."
    }

    $migrationCount = [int](($migrationOutput | Out-String).Trim())

    if ($migrationCount -ne 5) {
        throw "Expected exactly 5 applied migrations."
    }

    Write-Host "Applied migrations: 5" -ForegroundColor Green
    Write-Host "New migration required: no" -ForegroundColor Green

    Write-Step 2 7 "Rewriting the Decimal service deterministically"

    $correctMoneyService = @'
import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';

type DecimalInput = Prisma.Decimal | string | number;

@Injectable()
export class BillingMoneyService {
  decimal(value: DecimalInput): Prisma.Decimal {
    return new Prisma.Decimal(value);
  }

  money(value: DecimalInput): Prisma.Decimal {
    return this.decimal(value).toDecimalPlaces(2);
  }

  quantity(value: DecimalInput): Prisma.Decimal {
    return this.decimal(value).toDecimalPlaces(3);
  }

  requireNonNegative(
    value: DecimalInput,
    field: string,
  ): Prisma.Decimal {
    const decimal = this.money(value);

    if (decimal.isNegative()) {
      throw new BadRequestException(`${field} cannot be negative.`);
    }

    return decimal;
  }

  requirePositive(
    value: DecimalInput,
    field: string,
  ): Prisma.Decimal {
    const decimal = this.money(value);

    if (!decimal.isPositive()) {
      throw new BadRequestException(
        `${field} must be greater than zero.`,
      );
    }

    return decimal;
  }

  sum(values: DecimalInput[]): Prisma.Decimal {
    return values.reduce<Prisma.Decimal>(
      (total, value) => total.plus(this.decimal(value)),
      new Prisma.Decimal(0),
    );
  }

  invoiceLine(input: {
    quantity: DecimalInput;
    unitPrice: DecimalInput;
    discountAmount?: DecimalInput;
    taxAmount?: DecimalInput;
  }): {
    quantity: Prisma.Decimal;
    unitPrice: Prisma.Decimal;
    grossAmount: Prisma.Decimal;
    discountAmount: Prisma.Decimal;
    taxAmount: Prisma.Decimal;
    lineTotal: Prisma.Decimal;
  } {
    const quantity = this.quantity(input.quantity);
    const unitPrice = this.requireNonNegative(
      input.unitPrice,
      'unitPrice',
    );
    const discountAmount = this.requireNonNegative(
      input.discountAmount ?? 0,
      'discountAmount',
    );
    const taxAmount = this.requireNonNegative(
      input.taxAmount ?? 0,
      'taxAmount',
    );
    const grossAmount = quantity
      .mul(unitPrice)
      .toDecimalPlaces(2);
    const lineTotal = grossAmount
      .minus(discountAmount)
      .plus(taxAmount)
      .toDecimalPlaces(2);

    if (quantity.lte(0)) {
      throw new BadRequestException(
        'Invoice line quantity must be greater than zero.',
      );
    }

    if (discountAmount.gt(grossAmount)) {
      throw new BadRequestException(
        'Invoice line discount cannot exceed its gross amount.',
      );
    }

    if (lineTotal.isNegative()) {
      throw new BadRequestException(
        'Invoice line total cannot be negative.',
      );
    }

    return {
      quantity,
      unitPrice,
      grossAmount,
      discountAmount,
      taxAmount,
      lineTotal,
    };
  }
}
'@

    Write-Utf8File $moneyService $correctMoneyService

    $foundationContent = Get-LfContent $foundationScript
    $foundationContent = Sync-FoundationEmbeddedFile `
        -FoundationContent $foundationContent `
        -EmbeddedPath "services\backend-api\src\billing\common\billing-money.service.ts" `
        -SourceContent (Get-LfContent $moneyService)

    Set-LfContent $foundationScript $foundationContent
    Write-Host "[UPDATED] $foundationScript" -ForegroundColor Green

    Write-Step 3 7 "Running Prisma and static verification"

    Invoke-CheckedCommand "Prisma validate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma validate `
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

    Invoke-CheckedCommand "Backend format" {
        pnpm.cmd --filter "@solid-tracker/backend-api" format
    }

    Invoke-CheckedCommand "Backend lint" {
        pnpm.cmd --filter "@solid-tracker/backend-api" lint
    }

    Invoke-CheckedCommand "Backend typecheck" {
        pnpm.cmd --filter "@solid-tracker/backend-api" typecheck
    }

    Write-Step 4 7 "Running accounting tests and production build"

    Invoke-CheckedCommand "Backend unit tests" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test --runInBand
    }

    Invoke-CheckedCommand "Backend E2E tests" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test:e2e --runInBand
    }

    Invoke-CheckedCommand "Backend production build" {
        pnpm.cmd --filter "@solid-tracker/backend-api" build
    }

    Write-Step 5 7 "Verifying billing database invariants"

    $databaseVerification = @'
SELECT
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'public'
  ) AS public_table_count,
  (
    SELECT COUNT(*)
    FROM "_prisma_migrations"
    WHERE finished_at IS NOT NULL
      AND rolled_back_at IS NULL
  ) AS applied_migration_count,
  (
    SELECT COUNT(*)
    FROM "permissions"
    WHERE "code" IN (
      'subscription.view',
      'subscription.create',
      'subscription.suspend',
      'invoice.view',
      'payment.view',
      'commission.view',
      'settlement.create'
    )
      AND "status" = 'ACTIVE'
  ) AS billing_permission_count,
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'subscriptions_one_current_per_vehicle',
        'dealer_payout_accounts_one_default_per_dealer'
      )
  ) AS billing_invariant_index_count,
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

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "Billing database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split(",")

    if ($parts.Count -ne 5) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTableCount = [int]$parts[0]
    $appliedMigrationCount = [int]$parts[1]
    $permissionCount = [int]$parts[2]
    $indexCount = [int]$parts[3]
    $triggerCount = [int]$parts[4]

    if ($publicTableCount -lt 50) {
        throw "Expected at least 50 public tables."
    }

    if ($appliedMigrationCount -ne 5) {
        throw "Expected exactly 5 applied migrations."
    }

    if ($permissionCount -ne 7) {
        throw "Expected 7 active billing permissions."
    }

    if ($indexCount -ne 2) {
        throw "Expected 2 billing invariant indexes."
    }

    if ($triggerCount -ne 13) {
        throw "Expected 13 distinct billing triggers."
    }

    Write-Host "Public tables:       $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:  $appliedMigrationCount" -ForegroundColor Green
    Write-Host "Billing permissions: $permissionCount" -ForegroundColor Green
    Write-Host "Billing indexes:     $indexCount" -ForegroundColor Green
    Write-Host "Billing triggers:    $triggerCount" -ForegroundColor Green

    Write-Step 6 7 "Writing billing architecture documentation"

    Write-Utf8File `
        "docs/architecture/billing-api.md" `
        @'
# Billing, Commission, and Settlement API

## Scope

This stage exposes the existing billing foundation through authenticated REST APIs and transactional application services.

It implements service-plan versioning, vehicle subscriptions, invoices, payment allocations, refunds, dealer commission, encrypted payout accounts, settlements, and immutable dealer-ledger movements.

No Prisma migration is introduced. The existing billing migration already contains the required tables, constraints, indexes, and validation triggers.

## Decimal accounting

Financial arithmetic uses Prisma Decimal rather than JavaScript floating-point arithmetic.

Accepted inputs are Prisma Decimal instances, strings, or numbers. The sum operation uses an explicitly typed `Prisma.Decimal` accumulator and converts each input before addition.

## Accounting invariants

Payment allocations and dealer-ledger entries are append-only. Refunds and corrections produce reversal records rather than deleting financial history.

Only one current subscription may exist for a vehicle. Only one default payout account may exist for a dealer.

Payout account references are encrypted using AES-256-GCM and only masked identifiers are exposed by the API.

## Payment-gateway boundary

The API stores provider-neutral payment state and idempotent gateway events. Provider-specific bKash, Nagad, SSLCommerz, and bank adapters remain isolated for the payment-gateway integration stage.
'@

    Write-Step 7 7 "Committing the billing API"

    git add -- `
        ".env.example" `
        "docs/architecture/billing-api.md" `
        "scripts/solid-tracker-billing-api.ps1" `
        "scripts/solid-tracker-billing-money-type-recovery.ps1" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/billing" `
        "services/backend-api/test/billing.e2e-spec.ts"

    git commit `
        -m "feat(billing): establish billing commission and settlement APIs"

    if ($LASTEXITCODE -ne 0) {
        throw "Billing API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Billing API Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current
    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate
    Write-Host ""
    Write-Host "Recent graph:" -ForegroundColor Yellow
    git log --oneline --decorate --graph -8
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    Write-Host "Next implementation stage:" -ForegroundColor Yellow
    Write-Host (
        "Traccar synchronization, live positions, events, geofences, " +
        "commands, and notification APIs"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "BILLING DECIMAL RECOVERY V3 FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "No migration reset is required. This stage adds no migration."
    ) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
