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

function Remove-UnusedForbiddenExceptionImport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $content = [System.IO.File]::ReadAllText($fullPath)

    if (-not $content.Contains("ForbiddenException")) {
        Write-Host (
            "[PRESERVED] $RelativePath no longer imports ForbiddenException"
        ) -ForegroundColor DarkYellow
        return
    }

    $updated = [regex]::Replace(
        $content,
        "(?m)^\s*ForbiddenException,\r?\n",
        ""
    )

    if ($updated -eq $content) {
        throw "Could not remove the unused ForbiddenException import."
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $updated,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED] $RelativePath" -ForegroundColor Green
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Dealer Customer Lint Recovery" -ForegroundColor Cyan
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

    if ($currentBranch -ne "feat/dealer-customer-api") {
        throw (
            "Expected branch feat/dealer-customer-api, " +
            "but current branch is $currentBranch"
        )
    }

    $customersService =
        "services/backend-api/src/management/customers/customers.service.ts"

    $foundationScript =
        "scripts/solid-tracker-dealer-customer-api.ps1"

    foreach ($requiredPath in @(
        ".env",
        $customersService,
        $foundationScript,
        "services/backend-api/prisma.config.ts",
        "services/backend-api/prisma/schema.prisma",
        "services/backend-api/test/dealer-customer.e2e-spec.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file is missing: $requiredPath"
        }
    }

    Write-Step 1 6 "Confirming database and migration state"

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    Write-Step 2 6 "Removing the unused exception import"

    Remove-UnusedForbiddenExceptionImport $customersService

    Write-Step 3 6 "Patching the reproducible foundation script"

    $foundationFullPath = Join-Path `
        $script:RootPath `
        $foundationScript

    $foundationContent = [System.IO.File]::ReadAllText(
        $foundationFullPath
    )

    $patchedFoundation = [regex]::Replace(
        $foundationContent,
        "(?m)^\s*ForbiddenException,\r?\n",
        ""
    )

    if (
        $patchedFoundation -eq $foundationContent -and
        $foundationContent.Contains("ForbiddenException")
    ) {
        throw (
            "Could not patch the unused import in the " +
            "dealer-customer foundation script."
        )
    }

    [System.IO.File]::WriteAllText(
        $foundationFullPath,
        $patchedFoundation,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED] $foundationScript" -ForegroundColor Green

    Write-Step 4 6 "Running complete backend verification"

    Invoke-CheckedCommand "Prisma generate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma generate `
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

    Write-Step 5 6 "Verifying management prerequisites"

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
    FROM "roles"
    WHERE "code" IN (
      'PLATFORM_SUPER_ADMIN',
      'DEALER_OWNER',
      'DEALER_MANAGER',
      'CUSTOMER_OWNER'
    )
      AND "status" = 'ACTIVE'
  ) AS required_role_count;
'@

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "Dealer-customer database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $verificationParts = $verificationLine.Split(",")

    if ($verificationParts.Count -ne 3) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTableCount = [int]$verificationParts[0]
    $migrationCount = [int]$verificationParts[1]
    $requiredRoleCount = [int]$verificationParts[2]

    if ($publicTableCount -lt 50) {
        throw "Expected at least 50 public tables."
    }

    if ($migrationCount -lt 5) {
        throw "Expected at least 5 applied migrations."
    }

    if ($requiredRoleCount -ne 4) {
        throw "Required management roles are missing."
    }

    Write-Host "Public tables:      $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations: $migrationCount" -ForegroundColor Green
    Write-Host "Required roles:     $requiredRoleCount" -ForegroundColor Green

    Write-Step 6 6 "Writing documentation and committing"

    Write-Utf8File `
        "docs/architecture/dealer-customer-api.md" `
        @'
# Dealer and Customer Management API

## Scope

This stage adds REST APIs and application services for:

- dealer organizations;
- dealer staff and scoped roles;
- customer groups;
- individual and organization customer onboarding;
- customer account members;
- customer group assignment;
- dealer-to-dealer and dealer-to-platform transfer;
- immutable management audit records.

The existing database foundation already contains the required entities, so this stage does not add a new migration.

## Authorization

Each protected operation requires both:

1. a matching permission code;
2. access to the specific dealer or customer resource.

Platform-scoped roles can operate across the platform according to their permissions.

Dealer-scoped roles can operate only on the matching dealer and its managed customers.

Customer-scoped roles can access only linked customer accounts.

## Dealer and dealer manager

A dealer is an organization with type `DEALER`.

A dealer manager is a user connected through an organization membership and a dealer-scoped role assignment.

Devices, customers, commissions, and settlements belong to the dealer organization, not to an individual manager.

## Customer groups

A customer group belongs to exactly one dealer.

A customer may belong to a group only when the group belongs to the customer's current managing dealer.

Archived groups remain available for history but cannot be selected for new assignments.

## Customer transfer

A platform-authorized transfer:

1. ends the current assignment-history record;
2. creates the next assignment record;
3. updates the current dealer pointer;
4. validates or clears the customer group;
5. writes an immutable audit record.

Historical invoices, payments, and commission snapshots remain unchanged.

## Provisioned users

Dealer staff and customer members may attach an existing user by normalized mobile number.

A newly provisioned user requires a strong password. The password is hashed and never returned.

## Endpoints

```text
GET    /api/v1/dealers
POST   /api/v1/dealers
GET    /api/v1/dealers/:dealerId
PATCH  /api/v1/dealers/:dealerId

GET    /api/v1/dealers/:dealerId/staff
POST   /api/v1/dealers/:dealerId/staff
PATCH  /api/v1/dealers/:dealerId/staff/:userId

GET    /api/v1/dealers/:dealerId/customer-groups
POST   /api/v1/dealers/:dealerId/customer-groups
PATCH  /api/v1/dealers/:dealerId/customer-groups/:groupId

GET    /api/v1/customers
POST   /api/v1/customers/individual
POST   /api/v1/customers/organization
GET    /api/v1/customers/:customerId
PATCH  /api/v1/customers/:customerId/group
POST   /api/v1/customers/:customerId/transfer

GET    /api/v1/customers/:customerId/members
POST   /api/v1/customers/:customerId/members
```
'@

    git add --all

    git commit `
        -m "feat(management): establish dealer and customer APIs"

    if ($LASTEXITCODE -ne 0) {
        throw "Dealer and customer API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Dealer and Customer API Ready" -ForegroundColor Cyan
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
    Write-Host "Next implementation stage:" -ForegroundColor Yellow
    Write-Host (
        "Vehicle and device inventory, allocation, installation, " +
        "assignment, replacement, and removal APIs"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "DEALER CUSTOMER LINT RECOVERY FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "No migration reset is required." -ForegroundColor Yellow
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
