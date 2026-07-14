[CmdletBinding()]
param(
    [string]$RepositoryPath = "D:\GitHub\gps-tracker-platform"
)

$ErrorActionPreference = "Stop"

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

function Get-AppliedMigrationCount {
    $sql = @'
SELECT COUNT(*)
FROM "_prisma_migrations"
WHERE finished_at IS NOT NULL
  AND rolled_back_at IS NULL;
'@

    $output = $sql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Could not query the applied migration count."
    }

    return [int](($output | Out-String).Trim())
}

function Get-LfContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.File]::ReadAllText($Path).Replace(
        "`r`n",
        "`n"
    )
}

function Set-LfContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $Path,
        $Content.Replace("`r`n", "`n"),
        $utf8NoBom
    )
}

function Assert-ExpectedWorkingTree {
    $allowed = @(
        ".env.example",
        "docs/architecture/notification-delivery.md",
        "scripts/solid-tracker-notification-delivery.ps1",
        "scripts/solid-tracker-notification-delivery-recovery.ps1",
        "services/backend-api/prisma/schema.prisma",
        "services/backend-api/prisma/seed.ts",
        "services/backend-api/prisma/migrations/20260714230000_notification_delivery_foundation/",
        "services/backend-api/src/app.module.ts",
        "services/backend-api/src/config/environment.validation.ts",
        "services/backend-api/src/notification-delivery/",
        "services/backend-api/test/notification-delivery.e2e-spec.ts"
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
        $isAllowed = $false

        foreach ($allowedPath in $allowed) {
            if (
                $path -eq $allowedPath -or
                $path.StartsWith($allowedPath)
            ) {
                $isAllowed = $true
                break
            }
        }

        if (-not $isAllowed) {
            $unexpected.Add($line)
        }
    }

    if ($unexpected.Count -gt 0) {
        Write-Host "Unexpected working-tree changes:" -ForegroundColor Yellow

        foreach ($line in $unexpected) {
            Write-Host $line -ForegroundColor Yellow
        }

        throw "Working tree contains changes outside the notification stage."
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Notification Commit Recovery v2" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found."
    }

    $currentBranch = (
        (git branch --show-current) |
            Out-String
    ).Trim()

    if ($currentBranch -ne "feat/notification-delivery") {
        throw (
            "Expected branch feat/notification-delivery, " +
            "but current branch is $currentBranch."
        )
    }

    Assert-ExpectedWorkingTree

    $foundationRelative =
        "scripts/solid-tracker-notification-delivery.ps1"
    $recoveryRelative =
        "scripts/solid-tracker-notification-delivery-recovery.ps1"
    $legacyRecoveryRelative =
        "scripts/solid-tracker-notification-delivery-branch-recovery.ps1"

    foreach ($requiredPath in @(
        $foundationRelative,
        $recoveryRelative,
        "docs/architecture/notification-delivery.md",
        "services/backend-api/prisma/schema.prisma",
        "services/backend-api/prisma/seed.ts",
        "services/backend-api/prisma/migrations/20260714230000_notification_delivery_foundation/migration.sql",
        "services/backend-api/src/notification-delivery",
        "services/backend-api/test/notification-delivery.e2e-spec.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required path was not found: $requiredPath"
        }
    }

    Write-Host "[1/5] Confirming migration and repository state" -ForegroundColor Yellow

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $migrationCount = Get-AppliedMigrationCount

    if ($migrationCount -ne 6) {
        throw (
            "Expected exactly 6 applied migrations, " +
            "but found $migrationCount."
        )
    }

    Write-Host "Applied migrations: 6" -ForegroundColor Green
    Write-Host "Pending migrations:  0" -ForegroundColor Green

    Write-Host "[2/5] Confirming the reproducible recovery filename" -ForegroundColor Yellow

    $foundationPath = Join-Path $RepositoryPath $foundationRelative
    $foundationContent = Get-LfContent $foundationPath

    $legacyCount = (
        [regex]::Matches(
            $foundationContent,
            [regex]::Escape($legacyRecoveryRelative)
        )
    ).Count

    $correctCount = (
        [regex]::Matches(
            $foundationContent,
            [regex]::Escape($recoveryRelative)
        )
    ).Count

    if ($legacyCount -gt 0) {
        $foundationContent = $foundationContent.Replace(
            $legacyRecoveryRelative,
            $recoveryRelative
        )

        Set-LfContent `
            -Path $foundationPath `
            -Content $foundationContent

        Write-Host (
            "[UPDATED] $foundationRelative " +
            "($legacyCount filename reference(s))"
        ) -ForegroundColor Green
    }
    elseif ($correctCount -gt 0) {
        Write-Host (
            "[UNCHANGED] Reproducible recovery filename is correct."
        ) -ForegroundColor DarkGreen
    }
    else {
        throw (
            "The foundation script contains neither the legacy nor " +
            "the current recovery filename."
        )
    }

    Write-Host "[3/5] Reconfirming notification delivery invariants" -ForegroundColor Yellow

    $verificationSql = @'
SELECT
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'public'
  ),
  (
    SELECT COUNT(*)
    FROM "_prisma_migrations"
    WHERE finished_at IS NOT NULL
      AND rolled_back_at IS NULL
  ),
  (
    SELECT COUNT(*)
    FROM "permissions"
    WHERE "code" IN (
      'notification.template.manage',
      'notification.delivery.manage',
      'notification.delivery.view'
    )
      AND "status" = 'ACTIVE'
  ),
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN (
        'notification_templates',
        'notification_delivery_attempts',
        'notification_provider_events'
      )
  ),
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'notification_templates_templateKey_channel_locale_version_key',
        'notification_templates_one_active_variant',
        'notification_delivery_attempts_notificationId_attemptNumber_key',
        'notification_provider_events_provider_externalEventId_key'
      )
  ),
  (
    SELECT COUNT(*)
    FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND constraint_type = 'FOREIGN KEY'
      AND constraint_name IN (
        'notification_templates_createdByUserId_fkey',
        'notification_delivery_attempts_notificationId_fkey',
        'notification_provider_events_notificationId_fkey'
      )
  );
'@

    $verificationOutput = $verificationSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Notification database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split("|")

    if ($parts.Count -ne 6) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTables = [int]$parts[0]
    $appliedMigrations = [int]$parts[1]
    $permissions = [int]$parts[2]
    $deliveryTables = [int]$parts[3]
    $deliveryIndexes = [int]$parts[4]
    $deliveryForeignKeys = [int]$parts[5]

    if (
        $publicTables -ne 53 -or
        $appliedMigrations -ne 6 -or
        $permissions -ne 3 -or
        $deliveryTables -ne 3 -or
        $deliveryIndexes -ne 4 -or
        $deliveryForeignKeys -ne 3
    ) {
        throw (
            "Notification invariant verification failed: " +
            "tables=$publicTables migrations=$appliedMigrations " +
            "permissions=$permissions deliveryTables=$deliveryTables " +
            "indexes=$deliveryIndexes foreignKeys=$deliveryForeignKeys."
        )
    }

    Write-Host "Public tables:              53" -ForegroundColor Green
    Write-Host "Applied migrations:         6" -ForegroundColor Green
    Write-Host "Delivery permissions:       3" -ForegroundColor Green
    Write-Host "Delivery tables:            3" -ForegroundColor Green
    Write-Host "Delivery invariant indexes: 4" -ForegroundColor Green
    Write-Host "Delivery foreign keys:      3" -ForegroundColor Green

    Write-Host "[4/5] Checking staged content quality" -ForegroundColor Yellow

    Invoke-CheckedCommand "Git whitespace check" {
        git diff --check
    }

    Write-Host "[5/5] Staging and committing notification delivery" -ForegroundColor Yellow

    git add -- `
        ".env.example" `
        "docs/architecture/notification-delivery.md" `
        "scripts/solid-tracker-notification-delivery.ps1" `
        "scripts/solid-tracker-notification-delivery-recovery.ps1" `
        "services/backend-api/prisma/schema.prisma" `
        "services/backend-api/prisma/seed.ts" `
        "services/backend-api/prisma/migrations/20260714230000_notification_delivery_foundation" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/notification-delivery" `
        "services/backend-api/test/notification-delivery.e2e-spec.ts"

    if ($LASTEXITCODE -ne 0) {
        throw "Git staging failed."
    }

    git commit `
        -m "feat(notifications): establish delivery workers templates and observability"

    if ($LASTEXITCODE -ne 0) {
        throw "Notification delivery commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Notification Delivery Platform Ready" -ForegroundColor Cyan
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
        "Customer-facing mobile API, device dashboard, live tracking " +
        "sessions, and app-ready response contracts"
    ) -ForegroundColor Green

    exit 0
}
catch {
    Write-Host ""
    Write-Host "NOTIFICATION COMMIT RECOVERY V2 FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "Do not reset, delete, rename, or edit any of the six applied migrations."
    ) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    exit 1
}
