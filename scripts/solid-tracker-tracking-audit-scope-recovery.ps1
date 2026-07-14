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

function Count-Text {
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

    $openingMarker = "@'"
    $openingIndex = $FoundationContent.IndexOf(
        $openingMarker,
        $pathIndex + $pathMarker.Length,
        [System.StringComparison]::Ordinal
    )

    if ($openingIndex -lt 0) {
        throw "Embedded file opening marker was not found: $EmbeddedPath"
    }

    $payloadStart = $openingIndex + $openingMarker.Length

    if (
        $payloadStart -lt $FoundationContent.Length -and
        $FoundationContent[$payloadStart] -eq "`n"
    ) {
        $payloadStart++
    }

    $closingMarker = "`n'@"
    $closingIndex = $FoundationContent.IndexOf(
        $closingMarker,
        $payloadStart,
        [System.StringComparison]::Ordinal
    )

    if ($closingIndex -lt 0) {
        throw "Embedded file closing marker was not found: $EmbeddedPath"
    }

    return (
        $FoundationContent.Substring(0, $payloadStart) +
        $SourceContent.TrimEnd("`n") +
        $FoundationContent.Substring($closingIndex)
    )
}

function Assert-ExpectedRepositoryState {
    $allowedPrefixes = @(
        ".env.example",
        "services/backend-api/src/app.module.ts",
        "services/backend-api/src/config/environment.validation.ts",
        "scripts/solid-tracker-tracking-api.ps1",
        "scripts/solid-tracker-tracking-audit-scope-recovery.ps1",
        "services/backend-api/src/tracking/",
        "services/backend-api/test/tracking.e2e-spec.ts"
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

        throw "Working tree contains changes outside the tracking API stage."
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Tracking Audit Scope Recovery v2" -ForegroundColor Cyan
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

    if ($currentBranch -ne "feat/tracking-api") {
        throw (
            "Expected branch feat/tracking-api, " +
            "but current branch is $currentBranch"
        )
    }

    Assert-ExpectedRepositoryState

    $commandsService =
        "services/backend-api/src/tracking/commands/device-commands.service.ts"

    $deviceTrackingService =
        "services/backend-api/src/tracking/devices/device-tracking.service.ts"

    $foundationScript =
        "scripts/solid-tracker-tracking-api.ps1"

    foreach ($requiredPath in @(
        ".env",
        ".env.example",
        $commandsService,
        $deviceTrackingService,
        $foundationScript,
        "services/backend-api/prisma.config.ts",
        "services/backend-api/prisma/schema.prisma",
        "services/backend-api/test/tracking.e2e-spec.ts"
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

    Write-Step 2 7 "Correcting tracking audit scopes"

    $commandsContent = Get-LfContent $commandsService

    $legacyCommandScope =
        "scopeType: 'DEVICE',"

    $legacyCommandScopeId =
        "scopeId: command.deviceId,"

    $correctCommandScope = (
        "scopeType: command.vehicleId ? 'VEHICLE' : " +
        "this.access.isPlatformScoped(auth) ? 'PLATFORM' : undefined,"
    )

    $correctCommandScopeId =
        "scopeId: command.vehicleId ?? undefined,"

    $legacyCommandScopeCount =
        Count-Text $commandsContent $legacyCommandScope

    $legacyCommandScopeIdCount =
        Count-Text $commandsContent $legacyCommandScopeId

    $correctCommandScopeCount =
        Count-Text $commandsContent $correctCommandScope

    $correctCommandScopeIdCount =
        Count-Text $commandsContent $correctCommandScopeId

    if (
        $legacyCommandScopeCount -eq 3 -and
        $legacyCommandScopeIdCount -eq 3
    ) {
        $commandsContent = $commandsContent.Replace(
            $legacyCommandScope,
            $correctCommandScope
        )

        $commandsContent = $commandsContent.Replace(
            $legacyCommandScopeId,
            $correctCommandScopeId
        )
    }
    elseif (
        $legacyCommandScopeCount -eq 0 -and
        $legacyCommandScopeIdCount -eq 0 -and
        $correctCommandScopeCount -eq 3 -and
        $correctCommandScopeIdCount -eq 3
    ) {
        Write-Host (
            "[UNCHANGED] Command audit scopes were already corrected."
        ) -ForegroundColor DarkGreen
    }
    else {
        throw (
            "Unexpected command audit-scope state: " +
            "legacyType=$legacyCommandScopeCount, " +
            "legacyId=$legacyCommandScopeIdCount, " +
            "correctType=$correctCommandScopeCount, " +
            "correctId=$correctCommandScopeIdCount."
        )
    }

    Set-LfContent $commandsService $commandsContent
    Write-Host "[UPDATED] $commandsService" -ForegroundColor Green

    $deviceTrackingContent =
        Get-LfContent $deviceTrackingService

    $legacyDeviceScope =
        "scopeType: 'DEVICE',"

    $legacyDeviceScopeId =
        "scopeId: deviceId,"

    $correctDeviceScope =
        "scopeType: 'PLATFORM',"

    $legacyDeviceScopeCount =
        Count-Text $deviceTrackingContent $legacyDeviceScope

    $legacyDeviceScopeIdCount =
        Count-Text $deviceTrackingContent $legacyDeviceScopeId

    $correctDeviceScopeCount =
        Count-Text $deviceTrackingContent $correctDeviceScope

    if (
        $legacyDeviceScopeCount -eq 2 -and
        $legacyDeviceScopeIdCount -eq 2
    ) {
        $deviceTrackingContent =
            $deviceTrackingContent.Replace(
                $legacyDeviceScope,
                $correctDeviceScope
            )

        $scopeIdLinePattern =
            "(?m)^[ \t]*scopeId:\s*deviceId,\s*\n"

        $scopeIdLineMatches =
            [regex]::Matches(
                $deviceTrackingContent,
                $scopeIdLinePattern
            ).Count

        if ($scopeIdLineMatches -ne 2) {
            throw (
                "Expected 2 device scopeId lines, but found " +
                "$scopeIdLineMatches."
            )
        }

        $deviceTrackingContent =
            [regex]::Replace(
                $deviceTrackingContent,
                $scopeIdLinePattern,
                ""
            )
    }
    elseif (
        $legacyDeviceScopeCount -eq 0 -and
        $legacyDeviceScopeIdCount -eq 0 -and
        $correctDeviceScopeCount -ge 2
    ) {
        Write-Host (
            "[UNCHANGED] Device synchronization audit scopes were already corrected."
        ) -ForegroundColor DarkGreen
    }
    else {
        throw (
            "Unexpected device audit-scope state: " +
            "legacyType=$legacyDeviceScopeCount, " +
            "legacyId=$legacyDeviceScopeIdCount, " +
            "platformType=$correctDeviceScopeCount."
        )
    }

    Set-LfContent $deviceTrackingService $deviceTrackingContent
    Write-Host "[UPDATED] $deviceTrackingService" -ForegroundColor Green

    $remainingLegacyScopes = (
        Count-Text (Get-LfContent $commandsService) $legacyCommandScope
    ) + (
        Count-Text (Get-LfContent $deviceTrackingService) $legacyDeviceScope
    )

    if ($remainingLegacyScopes -ne 0) {
        throw (
            "Legacy DEVICE audit scopes remain: " +
            "$remainingLegacyScopes"
        )
    }

    Write-Step 3 7 "Synchronizing the reproducible tracking script"

    $foundationContent = Get-LfContent $foundationScript

    $foundationContent = Sync-FoundationEmbeddedFile `
        -FoundationContent $foundationContent `
        -EmbeddedPath "services\backend-api\src\tracking\commands\device-commands.service.ts" `
        -SourceContent (Get-LfContent $commandsService)

    $foundationContent = Sync-FoundationEmbeddedFile `
        -FoundationContent $foundationContent `
        -EmbeddedPath "services\backend-api\src\tracking\devices\device-tracking.service.ts" `
        -SourceContent (Get-LfContent $deviceTrackingService)

    Set-LfContent $foundationScript $foundationContent
    Write-Host "[UPDATED] $foundationScript" -ForegroundColor Green

    Write-Step 4 7 "Running complete backend verification"

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

    Write-Step 5 7 "Verifying tracking database invariants"

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
      'vehicle.location.view',
      'vehicle.history.view',
      'command.send',
      'command.engine_cutoff'
    )
      AND "status" = 'ACTIVE'
  ) AS tracking_permission_count,
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'traccar_servers_one_active_default',
        'traccar_device_mappings_one_active_primary_per_device',
        'vehicle_geofence_assignments_one_active_pair'
      )
  ) AS tracking_index_count,
  (
    SELECT COUNT(DISTINCT trigger_name)
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'traccar_mappings_validate_server',
        'tracking_events_validate_context',
        'geofences_validate_context',
        'geofence_assignments_validate_context',
        'notification_rules_validate_context',
        'notifications_validate_context',
        'device_commands_validate_context',
        'integration_jobs_validate_context'
      )
  ) AS tracking_trigger_count;
'@

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "Tracking database verification failed."
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

    if ($permissionCount -ne 4) {
        throw "Expected 4 active tracking permissions."
    }

    if ($indexCount -ne 3) {
        throw "Expected 3 tracking invariant indexes."
    }

    if ($triggerCount -ne 8) {
        throw "Expected 8 distinct tracking triggers."
    }

    Write-Host "Public tables:        $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:   $appliedMigrationCount" -ForegroundColor Green
    Write-Host "Tracking permissions: $permissionCount" -ForegroundColor Green
    Write-Host "Tracking indexes:     $indexCount" -ForegroundColor Green
    Write-Host "Tracking triggers:    $triggerCount" -ForegroundColor Green

    Write-Step 6 7 "Writing tracking architecture documentation"

    Write-Utf8File `
        "docs/architecture/tracking-api.md" `
        @'
# Tracking and Traccar Operations API

## Scope

This stage exposes the existing Traccar integration foundation through authenticated REST APIs and secure webhook processing.

It implements encrypted Traccar credentials, server health checks, physical-device synchronization, live positions, bounded history, normalized events, secure webhook ingestion, geofences, notification rules, device commands, integration jobs, authorization scope, audit records, and full E2E coverage.

No Prisma migration is introduced. The existing tracking foundation already contains the required tables, constraints, indexes, and validation triggers.

## System boundary

```text
GPS device
    ↓ protocol
Traccar
    ↓ REST and webhook integration
Solid Tracker NestJS API
    ↓ authenticated business API
Android, web, dealer, customer, and operations clients
```

Clients do not connect directly to Traccar.

## Audit scope

The shared identity audit model supports platform, zone, dealer, customer-group, customer, vehicle, and self scopes.

Tracking command audits use the assigned vehicle when present. Platform-only commands without a vehicle use platform scope. A non-platform device command without a vehicle remains identifiable through its resource type and resource ID without inventing an unsupported device scope.

Platform-only Traccar device synchronization and disable operations use platform audit scope.

## Command safety

Engine cutoff and restore require command permission, engine-control permission, an active vehicle-device assignment, approval by a different authorized user, and an unexpired approval window.

## Credential security

Traccar credentials are encrypted with AES-256-GCM. The runtime environment stores the encryption key and webhook secret. API responses never expose encrypted credential material.
'@

    Write-Step 7 7 "Committing the tracking API"

    git add -- `
        ".env.example" `
        "docs/architecture/tracking-api.md" `
        "scripts/solid-tracker-tracking-api.ps1" `
        "scripts/solid-tracker-tracking-audit-scope-recovery.ps1" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/tracking" `
        "services/backend-api/test/tracking.e2e-spec.ts"

    git commit `
        -m "feat(tracking): establish Traccar synchronization and operations APIs"

    if ($LASTEXITCODE -ne 0) {
        throw "Tracking API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Tracking and Traccar API Ready" -ForegroundColor Cyan
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
        "Payment-gateway adapters, recurring billing automation, " +
        "webhook signatures, and reconciliation"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "TRACKING AUDIT SCOPE RECOVERY V2 FAILED" -ForegroundColor Red
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
