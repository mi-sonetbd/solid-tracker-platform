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

function Count-ExactText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    return (
        [regex]::Matches(
            $Content,
            [regex]::Escape($Text)
        )
    ).Count
}

function Assert-ExpectedRepositoryState {
    $allowedPrefixes = @(
        ".env.example",
        "services/backend-api/src/app.module.ts",
        "services/backend-api/src/billing/billing-api.module.ts",
        "services/backend-api/src/config/environment.validation.ts",
        "scripts/solid-tracker-payment-gateway-automation.ps1",
        "scripts/solid-tracker-payment-gateway-invariant-recovery.ps1",
        "services/backend-api/src/payment-automation/",
        "services/backend-api/test/payment-gateway-automation.e2e-spec.ts"
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

        throw (
            "Working tree contains changes outside the payment gateway " +
            "automation stage."
        )
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Gateway Invariant Recovery v3" -ForegroundColor Cyan
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

    if ($currentBranch -ne "feat/payment-gateway-automation") {
        throw (
            "Expected branch feat/payment-gateway-automation, " +
            "but current branch is $currentBranch"
        )
    }

    Assert-ExpectedRepositoryState

    $foundationScript =
        "scripts/solid-tracker-payment-gateway-automation.ps1"

    foreach ($requiredPath in @(
        ".env",
        ".env.example",
        $foundationScript,
        "services/backend-api/prisma.config.ts",
        "services/backend-api/prisma/schema.prisma",
        "services/backend-api/src/payment-automation",
        "services/backend-api/test/payment-gateway-automation.e2e-spec.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file is missing: $requiredPath"
        }
    }

    Write-Step 1 7 "Confirming migration and infrastructure state"

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

    Write-Step 2 7 "Inspecting the actual gateway idempotency index"

    $indexInspectionSql = @'
SELECT
  index_record.relname
  || ' :: '
  || pg_get_indexdef(index_record.oid)
FROM pg_index AS index_metadata
INNER JOIN pg_class AS table_record
  ON table_record.oid = index_metadata.indrelid
INNER JOIN pg_class AS index_record
  ON index_record.oid = index_metadata.indexrelid
INNER JOIN pg_namespace AS namespace_record
  ON namespace_record.oid = table_record.relnamespace
WHERE namespace_record.nspname = 'public'
  AND table_record.relname = 'payment_gateway_events'
  AND index_metadata.indisunique
  AND (
    SELECT string_agg(
      attribute_record.attname,
      ',' ORDER BY key_record.ordinality
    )
    FROM unnest(index_metadata.indkey)
      WITH ORDINALITY AS key_record(attnum, ordinality)
    INNER JOIN pg_attribute AS attribute_record
      ON attribute_record.attrelid = table_record.oid
     AND attribute_record.attnum = key_record.attnum
  ) = 'gateway,externalEventId';
'@

    $indexInspectionOutput = $indexInspectionSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Gateway index catalog inspection failed."
    }

    $indexInspectionLine =
        ($indexInspectionOutput | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($indexInspectionLine)) {
        throw (
            "The unique gateway/externalEventId index is genuinely missing. " +
            "No migration was changed."
        )
    }

    Write-Host (
        "Gateway idempotency index: $indexInspectionLine"
    ) -ForegroundColor Green

    Write-Step 3 7 "Correcting the reproducible invariant verification"

    $foundationContent = Get-LfContent $foundationScript

    $legacyGatewayIndexQuery = @'
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'payment_gateway_events'
      AND indexdef LIKE '%"gateway"%'
      AND indexdef LIKE '%"externalEventId"%'
  ) AS gateway_event_idempotency_index_count,
'@

    $catalogGatewayIndexQuery = @'
  (
    SELECT COUNT(*)
    FROM pg_index AS index_metadata
    INNER JOIN pg_class AS table_record
      ON table_record.oid = index_metadata.indrelid
    INNER JOIN pg_namespace AS namespace_record
      ON namespace_record.oid = table_record.relnamespace
    WHERE namespace_record.nspname = 'public'
      AND table_record.relname = 'payment_gateway_events'
      AND index_metadata.indisunique
      AND (
        SELECT string_agg(
          attribute_record.attname,
          ',' ORDER BY key_record.ordinality
        )
        FROM unnest(index_metadata.indkey)
          WITH ORDINALITY AS key_record(attnum, ordinality)
        INNER JOIN pg_attribute AS attribute_record
          ON attribute_record.attrelid = table_record.oid
         AND attribute_record.attnum = key_record.attnum
      ) = 'gateway,externalEventId'
  ) AS gateway_event_idempotency_index_count,
'@

    $legacyGatewayIndexQuery =
        $legacyGatewayIndexQuery.Replace("`r`n", "`n")

    $catalogGatewayIndexQuery =
        $catalogGatewayIndexQuery.Replace("`r`n", "`n")

    $legacyCount = Count-ExactText `
        -Content $foundationContent `
        -Text $legacyGatewayIndexQuery

    $correctedCount = Count-ExactText `
        -Content $foundationContent `
        -Text $catalogGatewayIndexQuery

    if ($legacyCount -eq 1 -and $correctedCount -eq 0) {
        $foundationContent = $foundationContent.Replace(
            $legacyGatewayIndexQuery,
            $catalogGatewayIndexQuery
        )
    }
    elseif ($legacyCount -eq 0 -and $correctedCount -eq 1) {
        Write-Host (
            "[UNCHANGED] Gateway catalog verification is already corrected."
        ) -ForegroundColor DarkGreen
    }
    else {
        throw (
            "Unexpected gateway-query state: " +
            "legacy=$legacyCount corrected=$correctedCount."
        )
    }

    $legacyPsqlOption = '-AtF ","'
    $correctPsqlOption = '-At'

    $legacyPsqlCount = Count-ExactText `
        -Content $foundationContent `
        -Text $legacyPsqlOption

    if ($legacyPsqlCount -eq 1) {
        $foundationContent = $foundationContent.Replace(
            $legacyPsqlOption,
            $correctPsqlOption
        )
    }
    elseif (
        $legacyPsqlCount -eq 0 -and
        (Count-ExactText $foundationContent $correctPsqlOption) -ge 2
    ) {
        Write-Host (
            "[UNCHANGED] Foundation psql output mode is already corrected."
        ) -ForegroundColor DarkGreen
    }
    else {
        throw (
            "Unexpected foundation psql state: legacy option count=" +
            "$legacyPsqlCount."
        )
    }

    $legacySplit = '$parts = $verificationLine.Split(",")'
    $correctSplit = '$parts = $verificationLine.Split("|")'

    $legacySplitCount = Count-ExactText `
        -Content $foundationContent `
        -Text $legacySplit

    $correctSplitCount = Count-ExactText `
        -Content $foundationContent `
        -Text $correctSplit

    if ($legacySplitCount -eq 1 -and $correctSplitCount -eq 0) {
        $foundationContent = $foundationContent.Replace(
            $legacySplit,
            $correctSplit
        )
    }
    elseif ($legacySplitCount -eq 0 -and $correctSplitCount -eq 1) {
        Write-Host (
            "[UNCHANGED] Foundation verification parsing is already corrected."
        ) -ForegroundColor DarkGreen
    }
    else {
        throw (
            "Unexpected foundation split state: " +
            "legacy=$legacySplitCount corrected=$correctSplitCount."
        )
    }

    Set-LfContent $foundationScript $foundationContent
    Write-Host "[UPDATED] $foundationScript" -ForegroundColor Green

    Write-Step 4 7 "Rerunning complete backend verification"

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

    Invoke-CheckedCommand "Backend unit tests" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test --runInBand
    }

    Invoke-CheckedCommand "Backend E2E tests" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test:e2e --runInBand
    }

    Invoke-CheckedCommand "Backend production build" {
        pnpm.cmd --filter "@solid-tracker/backend-api" build
    }

    Write-Step 5 7 "Verifying billing and gateway invariants"

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
    FROM pg_index AS index_metadata
    INNER JOIN pg_class AS table_record
      ON table_record.oid = index_metadata.indrelid
    INNER JOIN pg_namespace AS namespace_record
      ON namespace_record.oid = table_record.relnamespace
    WHERE namespace_record.nspname = 'public'
      AND table_record.relname = 'payment_gateway_events'
      AND index_metadata.indisunique
      AND (
        SELECT string_agg(
          attribute_record.attname,
          ',' ORDER BY key_record.ordinality
        )
        FROM unnest(index_metadata.indkey)
          WITH ORDINALITY AS key_record(attnum, ordinality)
        INNER JOIN pg_attribute AS attribute_record
          ON attribute_record.attrelid = table_record.oid
         AND attribute_record.attnum = key_record.attnum
      ) = 'gateway,externalEventId'
  ) AS gateway_event_idempotency_index_count,
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'subscriptions_one_current_per_vehicle',
        'dealer_payout_accounts_one_default_per_dealer'
      )
  ) AS billing_invariant_index_count;
'@

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Gateway database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split("|")

    if ($parts.Count -ne 5) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTableCount = [int]$parts[0]
    $appliedMigrationCount = [int]$parts[1]
    $permissionCount = [int]$parts[2]
    $gatewayIndexCount = [int]$parts[3]
    $billingIndexCount = [int]$parts[4]

    if ($publicTableCount -lt 50) {
        throw "Expected at least 50 public tables."
    }

    if ($appliedMigrationCount -ne 5) {
        throw "Expected exactly 5 applied migrations."
    }

    if ($permissionCount -ne 7) {
        throw "Expected 7 active billing permissions."
    }

    if ($gatewayIndexCount -ne 1) {
        throw (
            "Expected exactly one gateway-event idempotency index, " +
            "but found $gatewayIndexCount."
        )
    }

    if ($billingIndexCount -ne 2) {
        throw "Expected 2 billing invariant indexes."
    }

    Write-Host "Public tables:          $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:     $appliedMigrationCount" -ForegroundColor Green
    Write-Host "Billing permissions:    $permissionCount" -ForegroundColor Green
    Write-Host "Gateway idempotency:    1 unique index" -ForegroundColor Green
    Write-Host "Billing invariants:     $billingIndexCount indexes" -ForegroundColor Green

    Write-Step 6 7 "Writing payment automation architecture documentation"

    Write-Utf8File `
        "docs/architecture/payment-gateway-automation.md" `
        @'
# Payment Gateway and Recurring Billing Automation

## Scope

This stage adds a provider-neutral payment gateway boundary and recurring billing operations without introducing a Prisma migration.

It implements:

- gateway checkout initialization;
- signed and idempotent callback processing;
- payment amount and currency validation;
- automatic invoice allocation and dealer commission;
- callback retry and reconciliation operations;
- recurring invoice generation;
- billing-period advancement;
- overdue invoice and past-due subscription transitions;
- durable automation-run claims;
- bounded manual and scheduled processing;
- sandbox gateway E2E coverage.

## Gateway adapters

The deterministic `OTHER` gateway supports local development and automated tests.

The SSLCOMMERZ adapter initializes hosted checkout and validates provider callback data before financial state changes.

The bKash and Nagad boundaries use signed merchant-proxy adapters so provider credentials remain isolated from the core billing domain.

## Idempotency

`payment_gateway_events` has a database-enforced unique key over:

```text
gateway
externalEventId
```

The verification uses PostgreSQL catalog metadata rather than matching rendered index SQL. This avoids false negatives caused by PostgreSQL omitting quotation marks around identifiers that do not require quoting.

## Recurring automation

The worker is disabled by default in local development. The same bounded operation can be triggered through the authenticated billing-automation endpoint.

Durable run claims prevent concurrent workers from processing the same automation interval.

## Accounting safety

Callbacks do not confirm payments until gateway identity, amount, currency, customer, payment, and invoice context are validated.

Successful allocations use the existing append-only payment allocation and dealer commission services.
'@

    Write-Step 7 7 "Committing payment gateway automation"

    git add -- `
        ".env.example" `
        "docs/architecture/payment-gateway-automation.md" `
        "scripts/solid-tracker-payment-gateway-automation.ps1" `
        "scripts/solid-tracker-payment-gateway-invariant-recovery.ps1" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/billing/billing-api.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/payment-automation" `
        "services/backend-api/test/payment-gateway-automation.e2e-spec.ts"

    git commit `
        -m "feat(payments): establish gateway adapters and billing automation"

    if ($LASTEXITCODE -ne 0) {
        throw "Payment gateway automation commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Payment Gateway and Billing Automation Ready" -ForegroundColor Cyan
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
        "Notification delivery providers, templates, outbox workers, " +
        "retries, and delivery observability"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "GATEWAY INVARIANT RECOVERY V3 FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "No migration reset is required. This recovery adds no migration."
    ) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
