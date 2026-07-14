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

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $hash = $sha256.ComputeHash($Bytes)

        return (
            [System.BitConverter]::ToString($hash)
        ).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
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

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Phase 2 Verification Recovery" -ForegroundColor Cyan
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

    if ($currentBranch -ne "feat/vehicle-device-foundation") {
        throw "Expected branch feat/vehicle-device-foundation, but current branch is $currentBranch"
    }

    $phase2Script = "scripts/solid-tracker-vehicle-device-foundation.ps1"
    $recoveryScript = "scripts/solid-tracker-vehicle-device-verification-recovery.ps1"
    $schemaPath = "services/backend-api/prisma/schema.prisma"
    $migrationRoot = "services/backend-api/prisma/migrations"

    foreach ($requiredPath in @(
        ".env",
        ".gitattributes",
        $phase2Script,
        $schemaPath,
        "services/backend-api/prisma.config.ts",
        $migrationRoot
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file or directory is missing: $requiredPath"
        }
    }

    $phase2Migration = Get-ChildItem `
        -LiteralPath $migrationRoot `
        -Directory |
        Where-Object {
            $_.Name -like "*_vehicle_device_foundation"
        } |
        Select-Object -First 1

    if (-not $phase2Migration) {
        throw "The vehicle/device migration directory was not found."
    }

    $phase2MigrationRelativePath = (
        "services/backend-api/prisma/migrations/" +
        $phase2Migration.Name
    )

    $allowedStatusEntries = @(
        " M $schemaPath",
        "?? $phase2Script",
        "?? $recoveryScript",
        "?? $phase2MigrationRelativePath/"
    )

    $unexpectedChanges = @(
        git status --short |
            Where-Object {
                $_ -and
                $allowedStatusEntries -notcontains $_.TrimEnd()
            }
    )

    if ($unexpectedChanges.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        $unexpectedChanges | ForEach-Object {
            Write-Host $_ -ForegroundColor Yellow
        }

        throw "Recovery stopped because unrelated working-tree changes were found."
    }

    Write-Step 1 7 "Verifying the applied Phase 2 migration checksum"

    $migrationSqlPath = Join-Path `
        $phase2Migration.FullName `
        "migration.sql"

    if (-not (Test-Path -LiteralPath $migrationSqlPath)) {
        throw "The Phase 2 migration.sql file is missing."
    }

    $migrationName = $phase2Migration.Name

    $migrationQuery = @"
SELECT
  checksum,
  CASE
    WHEN finished_at IS NOT NULL AND rolled_back_at IS NULL
    THEN 'APPLIED'
    ELSE 'NOT_APPLIED'
  END
FROM "_prisma_migrations"
WHERE migration_name = '$migrationName';
"@

    $migrationOutput = $migrationQuery |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify the Phase 2 migration in PostgreSQL."
    }

    $migrationLine = ($migrationOutput | Out-String).Trim()
    $migrationParts = $migrationLine.Split(",")

    if ($migrationParts.Count -ne 2) {
        throw "Unexpected Phase 2 migration result: $migrationLine"
    }

    $databaseChecksum = $migrationParts[0].ToLowerInvariant()
    $migrationState = $migrationParts[1]

    if ($migrationState -ne "APPLIED") {
        throw "The Phase 2 migration is not recorded as successfully applied."
    }

    $fileChecksum = Get-Sha256Hex `
        -Bytes ([System.IO.File]::ReadAllBytes($migrationSqlPath))

    if ($fileChecksum -ne $databaseChecksum) {
        throw (
            "The Phase 2 migration file does not match PostgreSQL. " +
            "Database checksum: $databaseChecksum; file checksum: $fileChecksum"
        )
    }

    Write-Host "Migration: $migrationName" -ForegroundColor Green
    Write-Host "State:     APPLIED" -ForegroundColor Green
    Write-Host "Checksum:  MATCHED" -ForegroundColor Green

    Write-Step 2 7 "Correcting the trigger verification logic"

    $phase2ScriptFullPath = Join-Path $script:RootPath $phase2Script
    $phase2ScriptContent = [System.IO.File]::ReadAllText(
        $phase2ScriptFullPath
    )

    $patchedContent = [regex]::Replace(
        $phase2ScriptContent,
        '(?ms)(SELECT\s+)COUNT\(\*\)(\s+FROM\s+information_schema\.triggers)',
        '$1COUNT(DISTINCT trigger_name)$2',
        1
    )

    if ($patchedContent -eq $phase2ScriptContent) {
        if (
            -not $phase2ScriptContent.Contains(
                "COUNT(DISTINCT trigger_name)"
            )
        ) {
            throw "Could not locate the Phase 2 trigger-count query."
        }

        Write-Host "Trigger verification was already corrected." -ForegroundColor DarkYellow
    }
    else {
        [System.IO.File]::WriteAllText(
            $phase2ScriptFullPath,
            $patchedContent,
            $script:Utf8NoBom
        )

        Write-Host "[UPDATED] $phase2Script" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Why the original count was 10:" -ForegroundColor Cyan
    Write-Host (
        "Each of the 5 triggers handles both INSERT and UPDATE. " +
        "information_schema.triggers returns one row per trigger event, " +
        "so it produced 10 rows although only 5 trigger names exist."
    ) -ForegroundColor Gray

    Write-Step 3 7 "Verifying Phase 2 tables, indexes, and distinct triggers"

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
        'device_ownership_history_one_active_per_device',
        'device_custody_history_one_active_per_device',
        'dealer_device_allocations_one_active_per_device',
        'vehicle_device_assignments_one_active_per_device',
        'vehicle_device_assignments_one_active_primary_per_vehicle'
      )
  ) AS invariant_index_count,
  (
    SELECT COUNT(DISTINCT trigger_name)
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'device_ownership_validate_owner',
        'device_custody_validate_custodian',
        'dealer_device_allocations_validate_dealer',
        'device_installations_validate_dealer',
        'vehicle_device_assignments_validate_installation'
      )
  ) AS distinct_trigger_count,
  (
    SELECT COUNT(*)
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'device_ownership_validate_owner',
        'device_custody_validate_custodian',
        'dealer_device_allocations_validate_dealer',
        'device_installations_validate_dealer',
        'vehicle_device_assignments_validate_installation'
      )
  ) AS trigger_event_row_count;
'@

    $verificationOutput = $verificationSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL Phase 2 verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split(",")

    if ($parts.Count -ne 4) {
        throw "Unexpected PostgreSQL verification result: $verificationLine"
    }

    $tableCount = [int]$parts[0]
    $indexCount = [int]$parts[1]
    $distinctTriggerCount = [int]$parts[2]
    $triggerEventRowCount = [int]$parts[3]

    if ($tableCount -lt 26) {
        throw "Expected at least 26 public tables, but found $tableCount."
    }

    if ($indexCount -ne 5) {
        throw "Expected 5 Phase 2 invariant indexes, but found $indexCount."
    }

    if ($distinctTriggerCount -ne 5) {
        throw "Expected 5 distinct Phase 2 triggers, but found $distinctTriggerCount."
    }

    if ($triggerEventRowCount -ne 10) {
        throw "Expected 10 INSERT/UPDATE trigger-event rows, but found $triggerEventRowCount."
    }

    Write-Host "Public tables:              $tableCount" -ForegroundColor Green
    Write-Host "Phase 2 unique indexes:     $indexCount" -ForegroundColor Green
    Write-Host "Distinct Phase 2 triggers:  $distinctTriggerCount" -ForegroundColor Green
    Write-Host "Trigger event rows:         $triggerEventRowCount" -ForegroundColor Green

    Write-Step 4 7 "Verifying Prisma state and generated client"

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

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma generate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma generate `
            --config prisma.config.ts
    }

    Write-Step 5 7 "Running final backend quality checks"

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

    Write-Step 6 7 "Writing the Vehicle and Device architecture record"

    $documentation = @'
# Vehicle and Device Database Foundation

## Scope

This migration introduces:

- `Vehicle`
- `DeviceModel`
- `Device`
- `DeviceOwnershipHistory`
- `DeviceCustodyHistory`
- `DealerDeviceAllocation`
- `DeviceInstallation`
- `VehicleDeviceAssignment`

## Core separation

A vehicle is a customer-owned trackable asset. A device is a physical GPS tracker. They are connected through a historical assignment.

```text
Customer
    ↓
Vehicle
    ↓
VehicleDeviceAssignment
    ↓
Device
    ↓
DeviceModel
```

## Version 1 assignment invariants

- One device may have only one active vehicle assignment.
- One vehicle may have only one active `PRIMARY` assignment.
- `SECONDARY` and `BACKUP` types are represented for future use.
- Historical assignments remain after removal or replacement.
- An assignment linked to an installation must use the same vehicle and device.

## Ownership and custody

Ownership and custody are separate histories.

Only one current ownership entry and one current custody entry may exist for each device.

## Dealer allocation

A device can be allocated to only one dealer at a time while its allocation remains active. Dealer allocations must reference an organization whose type is `DEALER`.

## Installation lifecycle

Installation records preserve the installer, dealer, physical installation time, connection details, verification, removal time, and removal reason.

Completed or removed installations require an installation timestamp. Removed installations require both a removal timestamp and removal reason.

## Device identity

- `deviceCode` is the Solid Tracker business identifier.
- `imei` is stored as text and is unique when present.
- `serialNumber` is unique when present.
- Device lifecycle state is separate from future Traccar online/offline state.

## Database enforcement

Prisma defines the relational structure. PostgreSQL partial unique indexes, check constraints, and triggers enforce cross-row and polymorphic business rules.

Five trigger names are installed. Each trigger handles both `INSERT` and `UPDATE`; therefore, `information_schema.triggers` exposes ten event rows. Verification must count distinct trigger names rather than raw rows.
'@

    Write-Utf8File `
        "docs\architecture\vehicle-device-foundation.md" `
        $documentation

    Write-Step 7 7 "Committing the completed Vehicle and Device foundation"

    git add -- `
        $schemaPath `
        $phase2Script `
        $recoveryScript `
        $phase2MigrationRelativePath `
        "docs/architecture/vehicle-device-foundation.md"

    git commit `
        -m "feat(assets): establish vehicle and device foundation"

    if ($LASTEXITCODE -ne 0) {
        throw "Vehicle and Device foundation commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Vehicle and Device Foundation Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current
    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate
    Write-Host ""
    Write-Host "Recent graph:" -ForegroundColor Yellow
    git log --oneline --decorate --graph -6
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    Write-Host "Next domain stage:" -ForegroundColor Yellow
    Write-Host (
        "Service plans, subscriptions, invoices, payments, " +
        "commissions, and dealer settlements"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "PHASE 2 VERIFICATION RECOVERY FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Do not delete or reset either applied migration." -ForegroundColor Yellow
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    exit 1
}
