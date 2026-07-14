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

function Add-DefensiveAppClose {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $content = [System.IO.File]::ReadAllText($fullPath)

    if ($content.Contains("if (app) {")) {
        Write-Host "[PRESERVED] $RelativePath teardown is already defensive" -ForegroundColor DarkYellow
        return
    }

    $updated = $content.Replace(
        "    await app.close();",
        @'
    if (app) {
      await app.close();
    }
'@
    )

    if ($updated -eq $content) {
        throw "Could not locate app.close() in $RelativePath"
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
    Write-Host " Solid Tracker - Identity Recovery v3" -ForegroundColor Cyan
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

    if ($currentBranch -ne "feat/identity-access-api") {
        throw (
            "Expected branch feat/identity-access-api, " +
            "but current branch is $currentBranch"
        )
    }

    $foundationScript =
        "scripts/solid-tracker-identity-access-api.ps1"

    $recoveryScript =
        "scripts/solid-tracker-identity-access-typecheck-recovery.ps1"

    $accessControlModule =
        "services/backend-api/src/identity/access-control/access-control.module.ts"

    foreach ($requiredPath in @(
        ".env",
        ".env.example",
        $foundationScript,
        $recoveryScript,
        $accessControlModule,
        "services/backend-api/prisma.config.ts",
        "services/backend-api/prisma/schema.prisma",
        "services/backend-api/test/app.e2e-spec.ts",
        "services/backend-api/test/auth.e2e-spec.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file is missing: $requiredPath"
        }
    }

    Write-Step 1 7 "Verifying the applied identity-access migration"

    $identityMigration = Get-ChildItem `
        -LiteralPath "services/backend-api/prisma/migrations" `
        -Directory |
        Where-Object {
            $_.Name -like "*_identity_access_api"
        } |
        Select-Object -First 1

    if (-not $identityMigration) {
        throw "The identity-access migration directory was not found."
    }

    $migrationName = $identityMigration.Name
    $migrationSqlPath = Join-Path `
        $identityMigration.FullName `
        "migration.sql"

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
        throw "Could not verify the identity-access migration."
    }

    $migrationLine = ($migrationOutput | Out-String).Trim()
    $migrationParts = $migrationLine.Split(",")

    if ($migrationParts.Count -ne 2) {
        throw "Unexpected identity migration result: $migrationLine"
    }

    $databaseChecksum = $migrationParts[0].ToLowerInvariant()
    $migrationState = $migrationParts[1]

    $fileChecksum = Get-Sha256Hex `
        -Bytes ([System.IO.File]::ReadAllBytes($migrationSqlPath))

    if ($migrationState -ne "APPLIED") {
        throw "The identity-access migration is not recorded as applied."
    }

    if ($databaseChecksum -ne $fileChecksum) {
        throw (
            "The identity-access migration file does not match " +
            "the checksum stored by PostgreSQL."
        )
    }

    Write-Host "Migration: $migrationName" -ForegroundColor Green
    Write-Host "State:     APPLIED" -ForegroundColor Green
    Write-Host "Checksum:  MATCHED" -ForegroundColor Green

    Write-Step 2 7 "Re-exporting the security dependency module"

    Write-Utf8File `
        $accessControlModule `
        @'
import { Module } from '@nestjs/common';
import { SecurityModule } from '../common/security.module';
import { AccessControlService } from './access-control.service';
import { AccessTokenGuard } from './access-token.guard';
import { PermissionsGuard } from './permissions.guard';

@Module({
  imports: [SecurityModule],
  providers: [AccessControlService, AccessTokenGuard, PermissionsGuard],
  exports: [
    SecurityModule,
    AccessControlService,
    AccessTokenGuard,
    PermissionsGuard,
  ],
})
export class AccessControlModule {}
'@

    Write-Host ""
    Write-Host "Dependency path:" -ForegroundColor Cyan
    Write-Host (
        "Feature module -> AccessControlModule -> " +
        "SecurityModule -> TokenService"
    ) -ForegroundColor Gray

    Write-Step 3 7 "Making E2E teardown resilient to bootstrap failures"

    Add-DefensiveAppClose `
        "services/backend-api/test/app.e2e-spec.ts"

    Add-DefensiveAppClose `
        "services/backend-api/test/auth.e2e-spec.ts"

    Write-Step 4 7 "Patching the reproducible identity foundation script"

    $foundationFullPath = Join-Path `
        $script:RootPath `
        $foundationScript

    $foundationContent = [System.IO.File]::ReadAllText(
        $foundationFullPath
    )

    $oldExportLine = @'
  exports: [AccessControlService, AccessTokenGuard, PermissionsGuard],
'@

    $newExportBlock = @'
  exports: [
    SecurityModule,
    AccessControlService,
    AccessTokenGuard,
    PermissionsGuard,
  ],
'@

    if ($foundationContent.Contains($oldExportLine)) {
        $foundationContent = $foundationContent.Replace(
            $oldExportLine,
            $newExportBlock
        )
    }
    elseif (-not $foundationContent.Contains("    SecurityModule,`r`n    AccessControlService")) {
        throw (
            "Could not patch AccessControlModule exports in " +
            "the reproducible foundation script."
        )
    }

    $foundationContent = $foundationContent.Replace(
        "    await app.close();",
        @'
    if (app) {
      await app.close();
    }
'@
    )

    [System.IO.File]::WriteAllText(
        $foundationFullPath,
        $foundationContent,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED] $foundationScript" -ForegroundColor Green

    Write-Step 5 7 "Running complete identity API verification"

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

    Write-Step 6 7 "Verifying identity database invariants"

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
      AND indexname =
        'otp_challenges_one_pending_per_identity'
  ) AS otp_index_count,
  (
    SELECT COUNT(DISTINCT trigger_name)
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'audit_logs_block_update',
        'audit_logs_block_delete'
      )
  ) AS audit_trigger_count;
'@

    $verificationOutput = $verificationSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL identity-access verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split(",")

    if ($parts.Count -ne 3) {
        throw (
            "Unexpected PostgreSQL verification result: " +
            $verificationLine
        )
    }

    $tableCount = [int]$parts[0]
    $otpIndexCount = [int]$parts[1]
    $auditTriggerCount = [int]$parts[2]

    if ($tableCount -lt 50) {
        throw (
            "Expected at least 50 public tables, but found " +
            $tableCount
        )
    }

    if ($otpIndexCount -ne 1) {
        throw "Expected 1 active OTP uniqueness index."
    }

    if ($auditTriggerCount -ne 2) {
        throw "Expected 2 append-only audit triggers."
    }

    Write-Host "Public tables:              $tableCount" -ForegroundColor Green
    Write-Host "OTP invariant indexes:      $otpIndexCount" -ForegroundColor Green
    Write-Host "Append-only audit triggers: $auditTriggerCount" -ForegroundColor Green

    Write-Step 7 7 "Writing documentation and committing the identity API"

    Write-Utf8File `
        "docs/architecture/identity-access-api.md" `
        @'
# Identity and Access API Foundation

## Delivered modules

- `AuthModule`
- `AccessControlModule`
- `UsersModule`
- `OrganizationsModule`
- `MembershipsModule`
- `RolesModule`
- `PermissionsModule`
- `SessionsModule`
- `AuditModule`
- `OtpModule`

## Authentication

Users authenticate with a normalized mobile number and password.

Passwords are hashed using Node.js `scrypt`, a unique random salt, and explicit cost, block-size, parallelization, and memory parameters.

Access tokens are short-lived JWT bearer tokens containing only the user ID, session ID, and token type.

Refresh tokens are opaque random values. PostgreSQL stores only keyed hashes.

## Session security

Refresh-token rotation atomically revokes the old session and creates a replacement in the same token family.

A reused, revoked, or expired refresh token revokes active sessions in that token family.

## Authorization

The access-token guard validates JWT signature, token expiry, token type, active database session, session expiry, and active user status.

`AccessControlModule` imports and re-exports `SecurityModule`. This makes `TokenService` available when Nest resolves the exported access guard in feature-module controller contexts.

The access-control service loads effective roles, permissions, organization memberships, and customer memberships from PostgreSQL.

## Login protection

Redis limits login attempts by IP address and normalized mobile number.

PostgreSQL records failed-login counts and temporary account locking.

## OTP

OTP values are stored only as keyed hashes. Challenges support mobile verification, password reset, high-risk action verification, expiry, attempt limits, replacement, and lockout.

## Audit immutability

PostgreSQL prevents updates and deletes on `audit_logs`.

Automated tests archive test identities instead of deleting immutable audit history.

## Initial administrator

No default administrator or password is committed.

Create the first administrator with:

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\scripts\solid-tracker-create-platform-admin.ps1"
```

## Endpoints

```text
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
GET    /api/v1/auth/me
POST   /api/v1/auth/logout
POST   /api/v1/auth/logout-all

GET    /api/v1/sessions
DELETE /api/v1/sessions/:sessionId

GET    /api/v1/users/me
GET    /api/v1/users/:userId

GET    /api/v1/organizations/me
GET    /api/v1/memberships/me
GET    /api/v1/roles/me
GET    /api/v1/permissions/me
```
'@

    git add --all

    git commit `
        -m "feat(identity): establish authentication and authorization API"

    if ($LASTEXITCODE -ne 0) {
        throw "Identity and access API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Identity and Access API Ready" -ForegroundColor Cyan
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
    Write-Host "Create the first platform administrator:" -ForegroundColor Yellow
    Write-Host (
        "powershell.exe -NoProfile -ExecutionPolicy Bypass " +
        "-File .\scripts\solid-tracker-create-platform-admin.ps1"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "IDENTITY RECOVERY V3 FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "Do not delete or reset the applied migration."
    ) -ForegroundColor Yellow
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    exit 1
}
