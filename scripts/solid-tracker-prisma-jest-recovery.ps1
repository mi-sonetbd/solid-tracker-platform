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
    $parent = Split-Path -Parent $fullPath

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $Content.TrimStart(),
        $script:Utf8NoBom
    )

    Write-Host "[WRITTEN] $RelativePath" -ForegroundColor Green
}

function Set-JsonScript {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Package,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if (-not $Package.scripts) {
        $Package | Add-Member `
            -NotePropertyName scripts `
            -NotePropertyValue ([pscustomobject]@{})
    }

    if ($Package.scripts.PSObject.Properties.Name -contains $Name) {
        $Package.scripts.$Name = $Value
    }
    else {
        $Package.scripts | Add-Member `
            -NotePropertyName $Name `
            -NotePropertyValue $Value
    }
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 100
    Write-Utf8File `
        -RelativePath $RelativePath `
        -Content ($json + [Environment]::NewLine)
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

function Patch-FoundationScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path $script:RootPath $RelativePath

    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Foundation script is missing: $RelativePath"
    }

    $content = [System.IO.File]::ReadAllText($fullPath)
    $updated = $content

    $testScriptLine = @'
    Set-JsonScript $backendPackage "test:e2e" "node --experimental-vm-modules ./node_modules/jest/bin/jest.js --config ./test/jest-e2e.json"
'@.TrimEnd()

    if (-not $updated.Contains($testScriptLine.Trim())) {
        $anchor = @'
    Set-JsonScript $backendPackage "prisma:format" "prisma format --config prisma.config.ts"
'@.TrimEnd()

        if (-not $updated.Contains($anchor.Trim())) {
            throw "Could not find the backend package-script insertion point."
        }

        $replacement = $testScriptLine + [Environment]::NewLine + [Environment]::NewLine + $anchor
        $updated = $updated.Replace($anchor, $replacement)
    }

    $approvalBlock = @'
    Invoke-CheckedCommand "Approve reviewed Prisma build scripts" {
        pnpm.cmd approve-builds "@prisma/engines" "esbuild" "prisma"
    }

    Invoke-CheckedCommand "Rebuild reviewed Prisma dependencies" {
        pnpm.cmd rebuild "@prisma/engines" "esbuild" "prisma"
    }

'@

    if (-not $updated.Contains('Approve reviewed Prisma build scripts')) {
        $approvalAnchor = '    Write-Step 3 10 "Writing Prisma configuration and Phase 1 schema"'

        if (-not $updated.Contains($approvalAnchor)) {
            throw "Could not find the Prisma build-approval insertion point."
        }

        $updated = $updated.Replace(
            $approvalAnchor,
            $approvalBlock + $approvalAnchor
        )
    }

    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText(
            $fullPath,
            $updated,
            $script:Utf8NoBom
        )

        Write-Host "[UPDATED] $RelativePath" -ForegroundColor Green
    }
    else {
        Write-Host "[PRESERVED] $RelativePath already contains the fixes" -ForegroundColor DarkYellow
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Prisma Jest Recovery" -ForegroundColor Cyan
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

    $branch = (git branch --show-current).Trim()

    if ($branch -ne "feat/domain-model-foundation") {
        throw "Expected branch feat/domain-model-foundation, but current branch is $branch"
    }

    foreach ($requiredFile in @(
        ".env",
        "pnpm-workspace.yaml",
        "services\backend-api\package.json",
        "services\backend-api\prisma.config.ts",
        "services\backend-api\prisma\schema.prisma",
        "services\backend-api\prisma\seed.ts",
        "services\backend-api\src\database\prisma.service.ts",
        "scripts\solid-tracker-prisma-phase1-foundation.ps1"
    )) {
        if (-not (Test-Path -LiteralPath $requiredFile)) {
            throw "Required Phase 1 file is missing: $requiredFile"
        }
    }

    Write-Step 1 8 "Validating the applied Prisma migration"

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    Write-Host "The applied database migration will be preserved." -ForegroundColor Green

    Write-Step 2 8 "Approving reviewed Prisma dependency build scripts"

    & pnpm.cmd approve-builds "@prisma/engines" "esbuild" "prisma"

    if ($LASTEXITCODE -ne 0) {
        throw "Could not record the reviewed Prisma build approvals."
    }

    & pnpm.cmd rebuild "@prisma/engines" "esbuild" "prisma"

    if ($LASTEXITCODE -ne 0) {
        throw "Could not rebuild the approved Prisma dependencies."
    }

    Write-Host "@prisma/engines, esbuild, and prisma: explicitly approved" -ForegroundColor Green
    Write-Host "@scarf/scarf: remains denied" -ForegroundColor Green

    Write-Step 3 8 "Enabling Jest VM modules for Prisma 7 integration tests"

    $backendPackagePath = "services\backend-api\package.json"
    $backendPackage = Get-Content `
        -LiteralPath $backendPackagePath `
        -Raw |
        ConvertFrom-Json

    $e2eCommand = "node --experimental-vm-modules ./node_modules/jest/bin/jest.js --config ./test/jest-e2e.json"

    Set-JsonScript `
        -Package $backendPackage `
        -Name "test:e2e" `
        -Value $e2eCommand

    Save-JsonFile `
        -RelativePath $backendPackagePath `
        -Value $backendPackage

    Patch-FoundationScript `
        "scripts\solid-tracker-prisma-phase1-foundation.ps1"

    Write-Host "Permanent E2E command:" -ForegroundColor Green
    Write-Host $e2eCommand -ForegroundColor DarkGreen

    Write-Step 4 8 "Regenerating the Prisma Client"

    Invoke-CheckedCommand "Prisma generate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma generate `
            --config prisma.config.ts
    }

    Write-Step 5 8 "Running complete backend verification"

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

    Invoke-CheckedCommand "Backend E2E tests with VM modules" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test:e2e --runInBand
    }

    Invoke-CheckedCommand "Backend production build" {
        pnpm.cmd --filter "@solid-tracker/backend-api" build
    }

    Write-Step 6 8 "Verifying seeded database records and table count"

    $verificationSql = @'
SELECT
  (SELECT COUNT(*) FROM "organizations") AS organization_count,
  (SELECT COUNT(*) FROM "roles") AS role_count,
  (SELECT COUNT(*) FROM "permissions") AS permission_count,
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'public'
  ) AS public_table_count;
'@

    $verificationOutput = $verificationSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL Phase 1 verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split(",")

    if ($parts.Count -ne 4) {
        throw "Unexpected PostgreSQL verification result: $verificationLine"
    }

    $organizationCount = [int]$parts[0]
    $roleCount = [int]$parts[1]
    $permissionCount = [int]$parts[2]
    $tableCount = [int]$parts[3]

    if ($organizationCount -lt 1) {
        throw "The platform organization seed is missing."
    }

    if ($roleCount -ne 11) {
        throw "Expected 11 system roles, but found $roleCount."
    }

    if ($permissionCount -ne 29) {
        throw "Expected 29 permissions, but found $permissionCount."
    }

    if ($tableCount -lt 18) {
        throw "Expected at least 18 public tables, but found $tableCount."
    }

    Write-Host "Organizations: $organizationCount" -ForegroundColor Green
    Write-Host "Roles:         $roleCount" -ForegroundColor Green
    Write-Host "Permissions:   $permissionCount" -ForegroundColor Green
    Write-Host "Public tables: $tableCount" -ForegroundColor Green

    Write-Step 7 8 "Writing Prisma Phase 1 architecture documentation"

    $documentation = @'
# Prisma Phase 1 Database Foundation

## Scope

The first migration establishes:

- users and sessions;
- organizations and zones;
- dealer profiles;
- organization memberships;
- roles, permissions, and scoped role assignments;
- customers and type-specific profiles;
- dealer customer groups;
- customer memberships;
- customer dealer-assignment history;
- audit logs.

Vehicles, devices, subscriptions, payments, commissions, Traccar mappings, and notifications remain outside this migration.

## Runtime architecture

```text
NestJS service
    ↓
PrismaService
    ↓
Prisma Client 7
    ↓
@prisma/adapter-pg
    ↓
node-postgres
    ↓
PostgreSQL
```

## Jest integration

Prisma Client 7 loads parts of its query compiler through dynamic imports.

The E2E test command starts Jest through Node with:

```text
--experimental-vm-modules
```

This enables dynamic imports inside Jest's VM-based test environment. It does not change the production NestJS runtime.

## Dependency build approvals

The repository explicitly allows reviewed build scripts for:

- `@prisma/engines`
- `esbuild`
- `prisma`

Unrelated analytics scripts remain denied. The repository does not enable all dependency build scripts globally.

## Commands

From the repository root:

```powershell
pnpm.cmd db:format
pnpm.cmd db:validate
pnpm.cmd db:generate
pnpm.cmd db:migrate:status
pnpm.cmd db:seed
pnpm.cmd db:studio
```

To create a future development migration after changing the schema:

```powershell
pnpm.cmd db:migrate:dev -- --name descriptive_migration_name
```

## Important rules

- Prisma Client is generated into `src/generated/prisma`.
- Generated code is not committed.
- The PostgreSQL migration contains native constraints and triggers.
- Seed execution is explicit and idempotent.
- The seed creates the platform organization, system roles, permissions, and role-permission mappings.
- No default administrator password or insecure account is created.
'@

    Write-Utf8File `
        "docs\architecture\prisma-phase-1.md" `
        $documentation

    Write-Step 8 8 "Committing the completed Prisma Phase 1 foundation"

    git add --all

    git commit `
        -m "feat(database): establish Prisma identity and customer foundation"

    if ($LASTEXITCODE -ne 0) {
        throw "Git commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Prisma Phase 1 Foundation Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current
    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    Write-Host "Useful commands:" -ForegroundColor Yellow
    Write-Host "pnpm.cmd db:migrate:status" -ForegroundColor Green
    Write-Host "pnpm.cmd db:seed" -ForegroundColor Green
    Write-Host "pnpm.cmd db:studio" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "PRISMA JEST RECOVERY FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "The database migration must not be deleted or recreated." -ForegroundColor Yellow
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    exit 1
}
