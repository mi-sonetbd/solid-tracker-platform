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
        "?? scripts/solid-tracker-identity-access-api.ps1"
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

        throw (
            "Working tree contains changes other than this " +
            "identity-access script."
        )
    }
}

function Add-EnvironmentVariableIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $fullPath = Join-Path $script:RootPath $RelativePath

    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Environment file is missing: $RelativePath"
    }

    $content = [System.IO.File]::ReadAllText($fullPath)
    $pattern = "(?m)^\s*" + [regex]::Escape($Name) + "\s*="

    if ([regex]::IsMatch($content, $pattern)) {
        return
    }

    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
        $content += "`n"
    }

    $content += "$Name=$Value`n"

    [System.IO.File]::WriteAllText(
        $fullPath,
        $content,
        $script:Utf8NoBom
    )

    Write-Host "[ENV] $RelativePath -> $Name" -ForegroundColor Green
}

function New-SecureSecret {
    param(
        [int]$ByteLength = 48
    )

    $bytes = New-Object byte[] $ByteLength
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return (
        [Convert]::ToBase64String($bytes).
            TrimEnd("=").
            Replace("+", "-").
            Replace("/", "_")
    )
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

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Identity and Access API" -ForegroundColor Cyan
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
        ".env.example",
        ".gitattributes",
        "compose.yaml",
        "services\backend-api\package.json",
        "services\backend-api\src\app.module.ts",
        "services\backend-api\src\config\environment.validation.ts",
        "services\backend-api\src\redis\redis.service.ts",
        "services\backend-api\prisma.config.ts",
        "services\backend-api\prisma\schema.prisma",
        "services\backend-api\prisma\migrations",
        "services\backend-api\src\database\prisma.service.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file or directory is missing: $requiredPath"
        }
    }

    Write-Step 1 11 `
        "Merging tracking integration and creating the identity branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/tracking-integration-foundation") {
        Assert-CleanExceptSelf

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        git merge-base --is-ancestor `
            feat/tracking-integration-foundation `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge tracking foundation into main" {
                git merge `
                    --no-ff `
                    feat/tracking-integration-foundation `
                    -m "merge: integrate tracking foundation"
            }
        }
        else {
            Write-Host (
                "Tracking foundation is already contained in main."
            ) -ForegroundColor Green
        }

        $branchExists = git branch --list "feat/identity-access-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing identity branch" {
                git checkout feat/identity-access-api
            }
        }
        else {
            Invoke-CheckedCommand "Create identity feature branch" {
                git checkout -b feat/identity-access-api
            }
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-CleanExceptSelf

        git merge-base --is-ancestor `
            feat/tracking-integration-foundation `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge tracking foundation into main" {
                git merge `
                    --no-ff `
                    feat/tracking-integration-foundation `
                    -m "merge: integrate tracking foundation"
            }
        }

        $branchExists = git branch --list "feat/identity-access-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing identity branch" {
                git checkout feat/identity-access-api
            }
        }
        else {
            Invoke-CheckedCommand "Create identity feature branch" {
                git checkout -b feat/identity-access-api
            }
        }
    }
    elseif ($currentBranch -eq "feat/identity-access-api") {
        Assert-CleanExceptSelf
        Write-Host "Already on feat/identity-access-api." -ForegroundColor Green
    }
    else {
        throw (
            "Expected feat/tracking-integration-foundation, main, or " +
            "feat/identity-access-api. Current branch: $currentBranch"
        )
    }

    Write-Step 2 11 `
        "Validating infrastructure and installing JWT support"

    $postgresHealth = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        solid-tracker-postgres 2>$null

    $redisHealth = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        solid-tracker-redis 2>$null

    if (
        $postgresHealth.Trim() -ne "healthy" -or
        $redisHealth.Trim() -ne "healthy"
    ) {
        throw "PostgreSQL and Redis must both be running and healthy."
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Install @nestjs/jwt 11.0.2" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            add "@nestjs/jwt@11.0.2"
    }

    Write-Host "PostgreSQL: healthy" -ForegroundColor Green
    Write-Host "Redis:      healthy" -ForegroundColor Green

    Write-Step 3 11 `
        "Adding OTP challenges and session-security constraints"

    $schemaPath = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\schema.prisma"

    $schema = [System.IO.File]::ReadAllText($schemaPath)

    if (-not $schema.Contains("model OtpChallenge {")) {
        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "User" `
            -Marker "otpChallenges" `
            -Fields @'
  otpChallenges OtpChallenge[]
'@

        $otpSchema = @'

enum OtpPurpose {
  MOBILE_VERIFICATION
  PASSWORD_RESET
  HIGH_RISK_ACTION
}

enum OtpChallengeStatus {
  PENDING
  VERIFIED
  EXPIRED
  CANCELLED
  LOCKED
}

model OtpChallenge {
  id                     String             @id @default(uuid()) @db.Uuid
  userId                 String?            @db.Uuid
  normalizedMobileNumber String             @db.VarChar(30)
  purpose                OtpPurpose
  codeHash               String
  status                 OtpChallengeStatus @default(PENDING)
  attemptCount           Int                @default(0)
  maxAttempts            Int                @default(5)
  resendCount            Int                @default(0)
  expiresAt              DateTime           @db.Timestamptz(3)
  verifiedAt             DateTime?          @db.Timestamptz(3)
  invalidatedAt          DateTime?          @db.Timestamptz(3)
  requestIp              String?            @db.VarChar(45)
  requestUserAgent       String?
  createdAt              DateTime           @default(now()) @db.Timestamptz(3)
  updatedAt              DateTime           @updatedAt @db.Timestamptz(3)

  user User? @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@index([normalizedMobileNumber, purpose, status])
  @@index([expiresAt, status])
  @@index([userId, purpose, status])
  @@map("otp_challenges")
}
'@

        $schema = (
            $schema.TrimEnd() +
            [Environment]::NewLine +
            $otpSchema.TrimStart()
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
        Write-Host "OTP schema already exists; preserving it." -ForegroundColor DarkYellow
    }

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

    $migrationRoot = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\migrations"

    $identityMigration = Get-ChildItem `
        -LiteralPath $migrationRoot `
        -Directory |
        Where-Object {
            $_.Name -like "*_identity_access_api"
        } |
        Select-Object -First 1

    if (-not $identityMigration) {
        Invoke-CheckedCommand "Prisma migration create-only" {
            pnpm.cmd `
                --filter "@solid-tracker/backend-api" `
                exec prisma migrate dev `
                --name identity_access_api `
                --create-only `
                --config prisma.config.ts
        }

        $identityMigration = Get-ChildItem `
            -LiteralPath $migrationRoot `
            -Directory |
            Where-Object {
                $_.Name -like "*_identity_access_api"
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if (-not $identityMigration) {
        throw "The identity-access migration directory was not created."
    }

    $migrationSqlPath = Join-Path `
        $identityMigration.FullName `
        "migration.sql"

    if (-not (Test-Path -LiteralPath $migrationSqlPath)) {
        throw "The identity-access migration.sql file is missing."
    }

    $migrationSql = [System.IO.File]::ReadAllText($migrationSqlPath)
    $customMarker = "-- Solid Tracker identity and access invariants."

    if (-not $migrationSql.Contains($customMarker)) {
        $customSql = @'

-- Solid Tracker identity and access invariants.

ALTER TABLE "user_sessions"
ADD CONSTRAINT "user_sessions_expiry_valid"
CHECK ("expiresAt" > "createdAt");

ALTER TABLE "user_sessions"
ADD CONSTRAINT "user_sessions_status_consistency"
CHECK (
  (
    "status" = 'ACTIVE'
    AND "revokedAt" IS NULL
    AND "revocationReason" IS NULL
  )
  OR
  (
    "status" = 'REVOKED'
    AND "revokedAt" IS NOT NULL
  )
  OR
  (
    "status" = 'EXPIRED'
  )
);

ALTER TABLE "otp_challenges"
ADD CONSTRAINT "otp_challenges_attempts_valid"
CHECK (
  "attemptCount" >= 0
  AND "maxAttempts" > 0
  AND "attemptCount" <= "maxAttempts"
  AND "resendCount" >= 0
);

ALTER TABLE "otp_challenges"
ADD CONSTRAINT "otp_challenges_expiry_valid"
CHECK ("expiresAt" > "createdAt");

ALTER TABLE "otp_challenges"
ADD CONSTRAINT "otp_challenges_status_consistency"
CHECK (
  (
    "status" = 'PENDING'
    AND "verifiedAt" IS NULL
    AND "invalidatedAt" IS NULL
  )
  OR
  (
    "status" = 'VERIFIED'
    AND "verifiedAt" IS NOT NULL
  )
  OR
  (
    "status" IN ('EXPIRED', 'CANCELLED', 'LOCKED')
    AND "invalidatedAt" IS NOT NULL
  )
);

CREATE UNIQUE INDEX
  "otp_challenges_one_pending_per_identity"
ON "otp_challenges" (
  "normalizedMobileNumber",
  "purpose"
)
WHERE "status" = 'PENDING';

CREATE OR REPLACE FUNCTION
  "solid_tracker_block_audit_log_mutation"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'audit_logs is append-only and cannot be updated or deleted';
END;
$$;

CREATE TRIGGER "audit_logs_block_update"
BEFORE UPDATE
ON "audit_logs"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_block_audit_log_mutation"();

CREATE TRIGGER "audit_logs_block_delete"
BEFORE DELETE
ON "audit_logs"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_block_audit_log_mutation"();
'@

        [System.IO.File]::AppendAllText(
            $migrationSqlPath,
            $customSql,
            $script:Utf8NoBom
        )

        Write-Host (
            "[CUSTOMIZED] " +
            $identityMigration.Name +
            "\migration.sql"
        ) -ForegroundColor Green
    }

    Write-Step 4 11 `
        "Configuring authentication secrets and validation"

    Add-EnvironmentVariableIfMissing `
        ".env" `
        "AUTH_JWT_ACCESS_SECRET" `
        (New-SecureSecret 64)

    Add-EnvironmentVariableIfMissing `
        ".env" `
        "AUTH_REFRESH_TOKEN_PEPPER" `
        (New-SecureSecret 64)

    Add-EnvironmentVariableIfMissing `
        ".env" `
        "AUTH_OTP_PEPPER" `
        (New-SecureSecret 64)

    foreach ($setting in @(
        @("AUTH_ACCESS_TOKEN_TTL_SECONDS", "900"),
        @("AUTH_REFRESH_TOKEN_TTL_SECONDS", "2592000"),
        @("AUTH_MAX_FAILED_ATTEMPTS", "5"),
        @("AUTH_LOCKOUT_SECONDS", "900"),
        @("AUTH_LOGIN_IP_LIMIT", "20"),
        @("AUTH_LOGIN_IP_WINDOW_SECONDS", "60"),
        @("AUTH_LOGIN_MOBILE_LIMIT", "5"),
        @("AUTH_LOGIN_MOBILE_WINDOW_SECONDS", "300"),
        @("AUTH_OTP_TTL_SECONDS", "300"),
        @("AUTH_OTP_MAX_ATTEMPTS", "5")
    )) {
        Add-EnvironmentVariableIfMissing `
            ".env" `
            $setting[0] `
            $setting[1]
    }

    foreach ($setting in @(
        @("AUTH_JWT_ACCESS_SECRET", "replace-with-at-least-32-random-characters"),
        @("AUTH_REFRESH_TOKEN_PEPPER", "replace-with-at-least-32-random-characters"),
        @("AUTH_OTP_PEPPER", "replace-with-at-least-32-random-characters"),
        @("AUTH_ACCESS_TOKEN_TTL_SECONDS", "900"),
        @("AUTH_REFRESH_TOKEN_TTL_SECONDS", "2592000"),
        @("AUTH_MAX_FAILED_ATTEMPTS", "5"),
        @("AUTH_LOCKOUT_SECONDS", "900"),
        @("AUTH_LOGIN_IP_LIMIT", "20"),
        @("AUTH_LOGIN_IP_WINDOW_SECONDS", "60"),
        @("AUTH_LOGIN_MOBILE_LIMIT", "5"),
        @("AUTH_LOGIN_MOBILE_WINDOW_SECONDS", "300"),
        @("AUTH_OTP_TTL_SECONDS", "300"),
        @("AUTH_OTP_MAX_ATTEMPTS", "5")
    )) {
        Add-EnvironmentVariableIfMissing `
            ".env.example" `
            $setting[0] `
            $setting[1]
    }

    $environmentValidationPath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\config\environment.validation.ts"

    $environmentValidation = [System.IO.File]::ReadAllText(
        $environmentValidationPath
    )

    if (-not $environmentValidation.Contains("AUTH_JWT_ACCESS_SECRET")) {
        $validationFields = @'
  AUTH_JWT_ACCESS_SECRET: Joi.string().min(32).required(),
  AUTH_REFRESH_TOKEN_PEPPER: Joi.string().min(32).required(),
  AUTH_OTP_PEPPER: Joi.string().min(32).required(),
  AUTH_ACCESS_TOKEN_TTL_SECONDS: Joi.number().integer().min(60).default(900),
  AUTH_REFRESH_TOKEN_TTL_SECONDS: Joi.number()
    .integer()
    .min(3600)
    .default(2592000),
  AUTH_MAX_FAILED_ATTEMPTS: Joi.number().integer().min(3).max(20).default(5),
  AUTH_LOCKOUT_SECONDS: Joi.number().integer().min(60).default(900),
  AUTH_LOGIN_IP_LIMIT: Joi.number().integer().min(1).default(20),
  AUTH_LOGIN_IP_WINDOW_SECONDS: Joi.number().integer().min(1).default(60),
  AUTH_LOGIN_MOBILE_LIMIT: Joi.number().integer().min(1).default(5),
  AUTH_LOGIN_MOBILE_WINDOW_SECONDS: Joi.number()
    .integer()
    .min(1)
    .default(300),
  AUTH_OTP_TTL_SECONDS: Joi.number().integer().min(60).default(300),
  AUTH_OTP_MAX_ATTEMPTS: Joi.number().integer().min(3).max(20).default(5),
'@

        $closingPattern = "(?ms)(\r?\n\}\);\s*)$"
        $closingMatch = [regex]::Match(
            $environmentValidation,
            $closingPattern
        )

        if (-not $closingMatch.Success) {
            throw (
                "Could not locate the environment-validation closing block."
            )
        }

        $environmentValidation = (
            $environmentValidation.Substring(0, $closingMatch.Index) +
            [Environment]::NewLine +
            $validationFields.TrimEnd() +
            $closingMatch.Groups[1].Value
        )

        [System.IO.File]::WriteAllText(
            $environmentValidationPath,
            $environmentValidation,
            $script:Utf8NoBom
        )

        Write-Host (
            "[UPDATED] services\backend-api\src\config\environment.validation.ts"
        ) -ForegroundColor Green
    }

    Write-Step 5 11 `
        "Writing security, authorization, audit, and OTP services"

    Write-Utf8File `
        "services\backend-api\src\identity\common\auth-context.ts" `
        @'
import type { Request } from 'express';

export interface AuthenticatedRole {
  code: string;
  scopeType: string;
  scopeId: string;
}

export interface AuthContext {
  userId: string;
  sessionId: string;
  userCode: string;
  fullName: string;
  mobileNumber: string;
  roles: AuthenticatedRole[];
  permissions: string[];
  organizationIds: string[];
  customerIds: string[];
}

export interface AuthenticatedRequest extends Request {
  auth?: AuthContext;
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\common\current-auth.decorator.ts" `
        @'
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthContext, AuthenticatedRequest } from './auth-context';

export const CurrentAuth = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthContext => {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();

    if (!request.auth) {
      throw new Error('Authenticated request context is missing.');
    }

    return request.auth;
  },
);
'@

    Write-Utf8File `
        "services\backend-api\src\identity\common\permissions.decorator.ts" `
        @'
import { SetMetadata } from '@nestjs/common';

export const REQUIRED_PERMISSIONS_KEY = 'solid-tracker.required-permissions';

export const RequirePermissions = (...permissions: string[]) =>
  SetMetadata(REQUIRED_PERMISSIONS_KEY, permissions);
'@

    Write-Utf8File `
        "services\backend-api\src\identity\common\mobile-number.util.ts" `
        @'
import { BadRequestException } from '@nestjs/common';

export function normalizeMobileNumber(value: string): string {
  const compact = value.trim().replace(/[\s()-]/g, '');

  let normalized = compact;

  if (normalized.startsWith('00')) {
    normalized = `+${normalized.slice(2)}`;
  } else if (/^01\d{9}$/.test(normalized)) {
    normalized = `+88${normalized}`;
  } else if (/^8801\d{9}$/.test(normalized)) {
    normalized = `+${normalized}`;
  }

  if (!/^\+\d{8,15}$/.test(normalized)) {
    throw new BadRequestException('Mobile number format is invalid.');
  }

  return normalized;
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\common\password.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const KEY_LENGTH = 64;
const COST = 32768;
const BLOCK_SIZE = 8;
const PARALLELIZATION = 1;
const MAX_MEMORY = 64 * 1024 * 1024;

@Injectable()
export class PasswordService {
  async hash(password: string): Promise<string> {
    this.assertPasswordPolicy(password);

    const salt = randomBytes(24);    const derivedKey = await this.deriveKey(
      password,
      salt,
      KEY_LENGTH,
      COST,
      BLOCK_SIZE,
      PARALLELIZATION,
    );

    return [
      'scrypt',
      COST,
      BLOCK_SIZE,
      PARALLELIZATION,
      salt.toString('base64url'),
      derivedKey.toString('base64url'),
    ].join('$');
  }

  async verify(password: string, encodedHash: string): Promise<boolean> {
    const parts = encodedHash.split('$');

    if (parts.length !== 6 || parts[0] !== 'scrypt') {
      return false;
    }

    const cost = Number(parts[1]);
    const blockSize = Number(parts[2]);
    const parallelization = Number(parts[3]);
    const salt = Buffer.from(parts[4], 'base64url');
    const expectedKey = Buffer.from(parts[5], 'base64url');

    if (
      !Number.isInteger(cost) ||
      !Number.isInteger(blockSize) ||
      !Number.isInteger(parallelization) ||
      expectedKey.length !== KEY_LENGTH
    ) {
      return false;
    }    const actualKey = await this.deriveKey(
      password,
      salt,
      expectedKey.length,
      cost,
      blockSize,
      parallelization,
    );

    return timingSafeEqual(expectedKey, actualKey);
  }

  private deriveKey(
    password: string,
    salt: Buffer,
    keyLength: number,
    cost: number,
    blockSize: number,
    parallelization: number,
  ): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      scrypt(
        password,
        salt,
        keyLength,
        {
          N: cost,
          r: blockSize,
          p: parallelization,
          maxmem: MAX_MEMORY,
        },
        (error, derivedKey) => {
          if (error) {
            reject(error);
            return;
          }

          resolve(derivedKey);
        },
      );
    });
  }
  private assertPasswordPolicy(password: string): void {
    if (
      password.length < 12 ||
      !/[a-z]/.test(password) ||
      !/[A-Z]/.test(password) ||
      !/\d/.test(password)
    ) {
      throw new Error(
        'Password must contain at least 12 characters, uppercase, lowercase, and a number.',
      );
    }
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\common\token.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { createHmac, randomBytes } from 'node:crypto';

export interface AccessTokenPayload {
  sub: string;
  sid: string;
  typ: 'access';
}

@Injectable()
export class TokenService {
  private readonly accessSecret: string;
  private readonly refreshPepper: string;
  private readonly accessTtlSeconds: number;
  private readonly refreshTtlSeconds: number;

  constructor(
    private readonly jwtService: JwtService,
    configService: ConfigService,
  ) {
    this.accessSecret =
      configService.getOrThrow<string>('AUTH_JWT_ACCESS_SECRET');
    this.refreshPepper =
      configService.getOrThrow<string>('AUTH_REFRESH_TOKEN_PEPPER');
    this.accessTtlSeconds = configService.get<number>(
      'AUTH_ACCESS_TOKEN_TTL_SECONDS',
      900,
    );
    this.refreshTtlSeconds = configService.get<number>(
      'AUTH_REFRESH_TOKEN_TTL_SECONDS',
      2592000,
    );
  }

  async signAccessToken(userId: string, sessionId: string): Promise<string> {
    return this.jwtService.signAsync(
      {
        sub: userId,
        sid: sessionId,
        typ: 'access',
      } satisfies AccessTokenPayload,
      {
        secret: this.accessSecret,
        expiresIn: this.accessTtlSeconds,
      },
    );
  }

  async verifyAccessToken(token: string): Promise<AccessTokenPayload> {
    return this.jwtService.verifyAsync<AccessTokenPayload>(token, {
      secret: this.accessSecret,
    });
  }

  createRefreshToken(): string {
    return randomBytes(48).toString('base64url');
  }

  hashRefreshToken(token: string): string {
    return createHmac('sha256', this.refreshPepper)
      .update(token)
      .digest('hex');
  }

  getRefreshExpiry(now = new Date()): Date {
    return new Date(now.getTime() + this.refreshTtlSeconds * 1000);
  }

  get accessTokenExpiresInSeconds(): number {
    return this.accessTtlSeconds;
  }
}
'@

    $redisServicePath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\redis\redis.service.ts"

    $redisService = [System.IO.File]::ReadAllText($redisServicePath)

    if (-not $redisService.Contains("incrementWithExpiry")) {
        $redisAnchor = @'
  async ping(): Promise<void> {
'@

        $redisMethods = @'
  async incrementWithExpiry(key: string, ttlSeconds: number): Promise<number> {
    await this.ensureConnected();

    const result = await this.client.eval(
      `
        local count = redis.call('INCR', KEYS[1])
        if count == 1 then
          redis.call('EXPIRE', KEYS[1], ARGV[1])
        end
        return count
      `,
      1,
      key,
      ttlSeconds,
    );

    return Number(result);
  }

  async delete(key: string): Promise<void> {
    await this.ensureConnected();
    await this.client.del(key);
  }

'@

        if (-not $redisService.Contains($redisAnchor.Trim())) {
            throw "Could not locate RedisService insertion point."
        }

        $redisService = $redisService.Replace(
            $redisAnchor,
            $redisMethods + $redisAnchor
        )

        [System.IO.File]::WriteAllText(
            $redisServicePath,
            $redisService,
            $script:Utf8NoBom
        )

        Write-Host (
            "[UPDATED] services\backend-api\src\redis\redis.service.ts"
        ) -ForegroundColor Green
    }

    Write-Utf8File `
        "services\backend-api\src\identity\common\auth-rate-limit.service.ts" `
        @'
import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RedisService } from '../../redis/redis.service';

@Injectable()
export class AuthRateLimitService {
  constructor(
    private readonly redisService: RedisService,
    private readonly configService: ConfigService,
  ) {}

  async consumeLoginAttempt(ipAddress: string, mobileNumber: string): Promise<void> {
    await Promise.all([
      this.consume(
        `auth:login:ip:${ipAddress}`,
        this.configService.get<number>('AUTH_LOGIN_IP_LIMIT', 20),
        this.configService.get<number>('AUTH_LOGIN_IP_WINDOW_SECONDS', 60),
      ),
      this.consume(
        `auth:login:mobile:${mobileNumber}`,
        this.configService.get<number>('AUTH_LOGIN_MOBILE_LIMIT', 5),
        this.configService.get<number>('AUTH_LOGIN_MOBILE_WINDOW_SECONDS', 300),
      ),
    ]);
  }

  async clearMobileLoginAttempts(mobileNumber: string): Promise<void> {
    await this.redisService.delete(`auth:login:mobile:${mobileNumber}`);
  }

  private async consume(
    key: string,
    limit: number,
    windowSeconds: number,
  ): Promise<void> {
    const count = await this.redisService.incrementWithExpiry(
      key,
      windowSeconds,
    );

    if (count > limit) {
      throw new HttpException(
        'Too many authentication attempts. Try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\common\security.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthRateLimitService } from './auth-rate-limit.service';
import { PasswordService } from './password.service';
import { TokenService } from './token.service';

@Module({
  imports: [JwtModule.register({})],
  providers: [PasswordService, TokenService, AuthRateLimitService],
  exports: [JwtModule, PasswordService, TokenService, AuthRateLimitService],
})
export class SecurityModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\access-control\access-control.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuthContext, AuthenticatedRole } from '../common/auth-context';

@Injectable()
export class AccessControlService {
  constructor(private readonly prisma: PrismaService) {}

  async buildContext(userId: string, sessionId: string): Promise<AuthContext> {
    const now = new Date();

    const [user, assignments, organizationMemberships, customerMemberships] =
      await Promise.all([
        this.prisma.user.findUniqueOrThrow({
          where: { id: userId },
          select: {
            id: true,
            userCode: true,
            fullName: true,
            mobileNumber: true,
          },
        }),
        this.prisma.roleAssignment.findMany({
          where: {
            userId,
            status: 'ACTIVE',
            effectiveFrom: { lte: now },
            OR: [{ effectiveUntil: null }, { effectiveUntil: { gt: now } }],
            role: {
              status: 'ACTIVE',
            },
          },
          include: {
            role: {
              include: {
                permissions: {
                  include: {
                    permission: true,
                  },
                },
              },
            },
          },
        }),
        this.prisma.organizationMembership.findMany({
          where: {
            userId,
            status: 'ACTIVE',
          },
          select: {
            organizationId: true,
          },
        }),
        this.prisma.customerMembership.findMany({
          where: {
            userId,
            status: 'ACTIVE',
          },
          select: {
            customerId: true,
          },
        }),
      ]);

    const roles: AuthenticatedRole[] = assignments.map((assignment) => ({
      code: assignment.role.code,
      scopeType: assignment.scopeType,
      scopeId: assignment.scopeId,
    }));

    const permissions = Array.from(
      new Set(
        assignments.flatMap((assignment) =>
          assignment.role.permissions
            .filter((rolePermission) => rolePermission.permission.status === 'ACTIVE')
            .map((rolePermission) => rolePermission.permission.code),
        ),
      ),
    ).sort();

    return {
      userId: user.id,
      sessionId,
      userCode: user.userCode,
      fullName: user.fullName,
      mobileNumber: user.mobileNumber,
      roles,
      permissions,
      organizationIds: organizationMemberships.map(
        (membership) => membership.organizationId,
      ),
      customerIds: customerMemberships.map(
        (membership) => membership.customerId,
      ),
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\access-control\access-token.guard.ts" `
        @'
import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuthenticatedRequest } from '../common/auth-context';
import { TokenService } from '../common/token.service';
import { AccessControlService } from './access-control.service';

@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(
    private readonly tokenService: TokenService,
    private readonly prisma: PrismaService,
    private readonly accessControlService: AccessControlService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const token = this.extractBearerToken(request);

    let payload;

    try {
      payload = await this.tokenService.verifyAccessToken(token);
    } catch {
      throw new UnauthorizedException('Access token is invalid or expired.');
    }

    if (payload.typ !== 'access') {
      throw new UnauthorizedException('Access token type is invalid.');
    }

    const session = await this.prisma.userSession.findUnique({
      where: { id: payload.sid },
      include: {
        user: {
          select: {
            id: true,
            status: true,
          },
        },
      },
    });

    const now = new Date();

    if (
      !session ||
      session.userId !== payload.sub ||
      session.status !== 'ACTIVE' ||
      session.expiresAt <= now ||
      session.user.status !== 'ACTIVE'
    ) {
      throw new UnauthorizedException('Authentication session is not active.');
    }

    request.auth = await this.accessControlService.buildContext(
      session.userId,
      session.id,
    );

    return true;
  }

  private extractBearerToken(request: AuthenticatedRequest): string {
    const authorization = request.headers.authorization;

    if (!authorization) {
      throw new UnauthorizedException('Bearer token is required.');
    }

    const [scheme, token] = authorization.split(' ');

    if (scheme !== 'Bearer' || !token) {
      throw new UnauthorizedException('Bearer token is malformed.');
    }

    return token;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\access-control\permissions.guard.ts" `
        @'
import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthenticatedRequest } from '../common/auth-context';
import {
  REQUIRED_PERMISSIONS_KEY,
} from '../common/permissions.decorator';

@Injectable()
export class PermissionsGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredPermissions =
      this.reflector.getAllAndOverride<string[]>(
        REQUIRED_PERMISSIONS_KEY,
        [context.getHandler(), context.getClass()],
      ) ?? [];

    if (requiredPermissions.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const grantedPermissions = new Set(request.auth?.permissions ?? []);

    const missingPermissions = requiredPermissions.filter(
      (permission) => !grantedPermissions.has(permission),
    );

    if (missingPermissions.length > 0) {
      throw new ForbiddenException({
        message: 'Required permissions are missing.',
        missingPermissions,
      });
    }

    return true;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\access-control\access-control.module.ts" `
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

    Write-Utf8File `
        "services\backend-api\src\identity\audit\audit.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';

export interface AuditRecordInput {
  actorUserId?: string;
  actorOrganizationId?: string;
  action: string;
  resourceType: string;
  resourceId?: string;
  metadata?: Record<string, unknown>;
  ipAddress?: string;
  userAgent?: string;
  correlationId?: string;
}

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async record(input: AuditRecordInput): Promise<void> {
    await this.prisma.auditLog.create({
      data: {
        actorUserId: input.actorUserId,
        actorOrganizationId: input.actorOrganizationId,
        action: input.action,
        resourceType: input.resourceType,
        resourceId: input.resourceId,
        metadata: input.metadata
          ? JSON.parse(JSON.stringify(input.metadata))
          : undefined,
        ipAddress: input.ipAddress,
        userAgent: input.userAgent,
        correlationId: input.correlationId,
      },
    });
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\audit\audit.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AuditService } from './audit.service';

@Module({
  providers: [AuditService],
  exports: [AuditService],
})
export class AuditModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\otp\otp.service.ts" `
        @'
import {
  BadRequestException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  createHmac,
  randomInt,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';
import { PrismaService } from '../../database/prisma.service';
import { normalizeMobileNumber } from '../common/mobile-number.util';

export interface OtpIssueInput {
  userId?: string;
  mobileNumber: string;
  purpose: 'MOBILE_VERIFICATION' | 'PASSWORD_RESET' | 'HIGH_RISK_ACTION';
  requestIp?: string;
  requestUserAgent?: string;
}

export interface OtpIssueResult {
  challengeId: string;
  code: string;
  expiresAt: Date;
}

@Injectable()
export class OtpService {
  private readonly pepper: string;
  private readonly ttlSeconds: number;
  private readonly maxAttempts: number;

  constructor(
    private readonly prisma: PrismaService,
    configService: ConfigService,
  ) {
    this.pepper = configService.getOrThrow<string>('AUTH_OTP_PEPPER');
    this.ttlSeconds = configService.get<number>('AUTH_OTP_TTL_SECONDS', 300);
    this.maxAttempts = configService.get<number>('AUTH_OTP_MAX_ATTEMPTS', 5);
  }

  async issue(input: OtpIssueInput): Promise<OtpIssueResult> {
    const normalizedMobileNumber = normalizeMobileNumber(input.mobileNumber);
    const challengeId = randomUUID();
    const code = randomInt(100000, 1000000).toString();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + this.ttlSeconds * 1000);

    await this.prisma.$transaction(async (transaction) => {
      await transaction.otpChallenge.updateMany({
        where: {
          normalizedMobileNumber,
          purpose: input.purpose,
          status: 'PENDING',
        },
        data: {
          status: 'CANCELLED',
          invalidatedAt: now,
        },
      });

      await transaction.otpChallenge.create({
        data: {
          id: challengeId,
          userId: input.userId,
          normalizedMobileNumber,
          purpose: input.purpose,
          codeHash: this.hashCode(challengeId, code),
          maxAttempts: this.maxAttempts,
          expiresAt,
          requestIp: input.requestIp,
          requestUserAgent: input.requestUserAgent,
        },
      });
    });

    return {
      challengeId,
      code,
      expiresAt,
    };
  }

  async verify(challengeId: string, code: string): Promise<void> {
    if (!/^\d{6}$/.test(code)) {
      throw new BadRequestException('OTP code format is invalid.');
    }

    const challenge = await this.prisma.otpChallenge.findUnique({
      where: { id: challengeId },
    });

    if (!challenge || challenge.status !== 'PENDING') {
      throw new UnauthorizedException('OTP challenge is not active.');
    }

    const now = new Date();

    if (challenge.expiresAt <= now) {
      await this.prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: {
          status: 'EXPIRED',
          invalidatedAt: now,
        },
      });

      throw new UnauthorizedException('OTP challenge has expired.');
    }

    const expected = Buffer.from(challenge.codeHash, 'hex');
    const actual = Buffer.from(this.hashCode(challenge.id, code), 'hex');
    const valid =
      expected.length === actual.length && timingSafeEqual(expected, actual);

    if (!valid) {
      const attemptCount = challenge.attemptCount + 1;
      const locked = attemptCount >= challenge.maxAttempts;

      await this.prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: {
          attemptCount,
          status: locked ? 'LOCKED' : 'PENDING',
          invalidatedAt: locked ? now : null,
        },
      });

      throw new UnauthorizedException('OTP code is invalid.');
    }

    await this.prisma.otpChallenge.update({
      where: { id: challenge.id },
      data: {
        status: 'VERIFIED',
        verifiedAt: now,
      },
    });
  }

  private hashCode(challengeId: string, code: string): string {
    return createHmac('sha256', this.pepper)
      .update(`${challengeId}:${code}`)
      .digest('hex');
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\otp\otp.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { OtpService } from './otp.service';

@Module({
  providers: [OtpService],
  exports: [OtpService],
})
export class OtpModule {}
'@

    Write-Step 6 11 `
        "Writing authentication and session APIs"

    Write-Utf8File `
        "services\backend-api\src\identity\auth\dto\login.dto.ts" `
        @'
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsEnum,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { SessionPlatform } from '../../../generated/prisma/client';

export class LoginDto {
  @ApiProperty({ example: '+8801712345678' })
  @IsString()
  @MaxLength(30)
  mobileNumber!: string;

  @ApiProperty({ minLength: 8 })
  @IsString()
  @MinLength(8)
  @MaxLength(200)
  password!: string;

  @ApiProperty({ enum: SessionPlatform, example: SessionPlatform.WEB })
  @IsEnum(SessionPlatform)
  platform!: SessionPlatform;

  @ApiPropertyOptional({ example: 'Chrome on Windows' })
  @IsOptional()
  @IsString()
  @MaxLength(160)
  deviceName?: string;

  @ApiPropertyOptional({ example: '0.1.0' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  appVersion?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\auth\dto\refresh-token.dto.ts" `
        @'
import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

export class RefreshTokenDto {
  @ApiProperty()
  @IsString()
  @MinLength(40)
  refreshToken!: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\auth\auth.service.ts" `
        @'
import {
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../../database/prisma.service';
import { AccessControlService } from '../access-control/access-control.service';
import { AuditService } from '../audit/audit.service';
import type { AuthContext } from '../common/auth-context';
import { AuthRateLimitService } from '../common/auth-rate-limit.service';
import { normalizeMobileNumber } from '../common/mobile-number.util';
import { PasswordService } from '../common/password.service';
import { TokenService } from '../common/token.service';
import { LoginDto } from './dto/login.dto';

export interface RequestMetadata {
  ipAddress: string;
  userAgent?: string;
}

export interface AuthTokenResponse {
  tokenType: 'Bearer';
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
  sessionId: string;
}

@Injectable()
export class AuthService {
  private readonly maxFailedAttempts: number;
  private readonly lockoutSeconds: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly passwordService: PasswordService,
    private readonly tokenService: TokenService,
    private readonly rateLimitService: AuthRateLimitService,
    private readonly accessControlService: AccessControlService,
    private readonly auditService: AuditService,
    configService: ConfigService,
  ) {
    this.maxFailedAttempts = configService.get<number>(
      'AUTH_MAX_FAILED_ATTEMPTS',
      5,
    );
    this.lockoutSeconds = configService.get<number>(
      'AUTH_LOCKOUT_SECONDS',
      900,
    );
  }

  async login(
    dto: LoginDto,
    metadata: RequestMetadata,
  ): Promise<AuthTokenResponse> {
    const normalizedMobileNumber = normalizeMobileNumber(dto.mobileNumber);

    await this.rateLimitService.consumeLoginAttempt(
      metadata.ipAddress,
      normalizedMobileNumber,
    );

    let user = await this.prisma.user.findUnique({
      where: { normalizedMobileNumber },
    });

    if (!user) {
      throw this.invalidCredentials();
    }

    const now = new Date();

    if (
      user.status === 'LOCKED' &&
      user.lockedUntil &&
      user.lockedUntil <= now
    ) {
      user = await this.prisma.user.update({
        where: { id: user.id },
        data: {
          status: 'ACTIVE',
          failedLoginCount: 0,
          lockedUntil: null,
        },
      });
    }

    if (
      user.status !== 'ACTIVE' ||
      !user.passwordHash ||
      (user.lockedUntil && user.lockedUntil > now)
    ) {
      throw this.invalidCredentials();
    }

    const passwordValid = await this.passwordService.verify(
      dto.password,
      user.passwordHash,
    );

    if (!passwordValid) {
      await this.registerFailedLogin(user.id, user.failedLoginCount);
      throw this.invalidCredentials();
    }

    await this.prisma.user.update({
      where: { id: user.id },
      data: {
        failedLoginCount: 0,
        lockedUntil: null,
        lastLoginAt: now,
      },
    });

    await this.rateLimitService.clearMobileLoginAttempts(
      normalizedMobileNumber,
    );

    const tokenResponse = await this.createSession(
      user.id,
      randomUUID(),
      dto.platform,
      dto.deviceName,
      dto.appVersion,
      metadata,
    );

    await this.auditService.record({
      actorUserId: user.id,
      action: 'auth.login.succeeded',
      resourceType: 'UserSession',
      resourceId: tokenResponse.sessionId,
      ipAddress: metadata.ipAddress,
      userAgent: metadata.userAgent,
    });

    return tokenResponse;
  }

  async refresh(
    refreshToken: string,
    metadata: RequestMetadata,
  ): Promise<AuthTokenResponse> {
    const refreshTokenHash =
      this.tokenService.hashRefreshToken(refreshToken);

    const session = await this.prisma.userSession.findUnique({
      where: { refreshTokenHash },
      include: {
        user: true,
      },
    });

    if (!session) {
      throw new UnauthorizedException('Refresh token is invalid.');
    }

    const now = new Date();

    if (
      session.status !== 'ACTIVE' ||
      session.expiresAt <= now ||
      session.user.status !== 'ACTIVE'
    ) {
      await this.revokeTokenFamily(
        session.tokenFamilyId,
        'REFRESH_TOKEN_REUSE_OR_EXPIRED',
      );

      throw new UnauthorizedException('Refresh token is no longer active.');
    }

    const nextRefreshToken = this.tokenService.createRefreshToken();
    const nextRefreshTokenHash =
      this.tokenService.hashRefreshToken(nextRefreshToken);

    const nextSession = await this.prisma.$transaction(
      async (transaction) => {
        const claimed = await transaction.userSession.updateMany({
          where: {
            id: session.id,
            status: 'ACTIVE',
          },
          data: {
            status: 'REVOKED',
            revokedAt: now,
            revocationReason: 'ROTATED',
            lastUsedAt: now,
          },
        });

        if (claimed.count !== 1) {
          throw new UnauthorizedException(
            'Refresh token has already been used.',
          );
        }

        return transaction.userSession.create({
          data: {
            userId: session.userId,
            tokenFamilyId: session.tokenFamilyId,
            refreshTokenHash: nextRefreshTokenHash,
            deviceName: session.deviceName,
            platform: session.platform,
            appVersion: session.appVersion,
            ipAddress: metadata.ipAddress,
            userAgent: metadata.userAgent,
            expiresAt: this.tokenService.getRefreshExpiry(now),
          },
        });
      },
    );

    const accessToken = await this.tokenService.signAccessToken(
      session.userId,
      nextSession.id,
    );

    await this.auditService.record({
      actorUserId: session.userId,
      action: 'auth.session.refreshed',
      resourceType: 'UserSession',
      resourceId: nextSession.id,
      metadata: {
        previousSessionId: session.id,
        tokenFamilyId: session.tokenFamilyId,
      },
      ipAddress: metadata.ipAddress,
      userAgent: metadata.userAgent,
    });

    return {
      tokenType: 'Bearer',
      accessToken,
      accessTokenExpiresIn:
        this.tokenService.accessTokenExpiresInSeconds,
      refreshToken: nextRefreshToken,
      sessionId: nextSession.id,
    };
  }

  async logout(
    auth: AuthContext,
    metadata: RequestMetadata,
  ): Promise<void> {
    const now = new Date();

    await this.prisma.userSession.updateMany({
      where: {
        id: auth.sessionId,
        userId: auth.userId,
        status: 'ACTIVE',
      },
      data: {
        status: 'REVOKED',
        revokedAt: now,
        revocationReason: 'USER_LOGOUT',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      action: 'auth.logout',
      resourceType: 'UserSession',
      resourceId: auth.sessionId,
      ipAddress: metadata.ipAddress,
      userAgent: metadata.userAgent,
    });
  }

  async logoutAll(
    auth: AuthContext,
    metadata: RequestMetadata,
  ): Promise<number> {
    const now = new Date();

    const result = await this.prisma.userSession.updateMany({
      where: {
        userId: auth.userId,
        status: 'ACTIVE',
      },
      data: {
        status: 'REVOKED',
        revokedAt: now,
        revocationReason: 'USER_LOGOUT_ALL',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      action: 'auth.logout_all',
      resourceType: 'UserSession',
      metadata: {
        revokedSessionCount: result.count,
      },
      ipAddress: metadata.ipAddress,
      userAgent: metadata.userAgent,
    });

    return result.count;
  }

  async getMe(auth: AuthContext): Promise<AuthContext> {
    return this.accessControlService.buildContext(
      auth.userId,
      auth.sessionId,
    );
  }

  private async createSession(
    userId: string,
    tokenFamilyId: string,
    platform: LoginDto['platform'],
    deviceName: string | undefined,
    appVersion: string | undefined,
    metadata: RequestMetadata,
  ): Promise<AuthTokenResponse> {
    const refreshToken = this.tokenService.createRefreshToken();

    const session = await this.prisma.userSession.create({
      data: {
        userId,
        tokenFamilyId,
        refreshTokenHash:
          this.tokenService.hashRefreshToken(refreshToken),
        platform,
        deviceName,
        appVersion,
        ipAddress: metadata.ipAddress,
        userAgent: metadata.userAgent,
        expiresAt: this.tokenService.getRefreshExpiry(),
      },
    });

    const accessToken = await this.tokenService.signAccessToken(
      userId,
      session.id,
    );

    return {
      tokenType: 'Bearer',
      accessToken,
      accessTokenExpiresIn:
        this.tokenService.accessTokenExpiresInSeconds,
      refreshToken,
      sessionId: session.id,
    };
  }

  private async registerFailedLogin(
    userId: string,
    currentFailedCount: number,
  ): Promise<void> {
    const nextFailedCount = currentFailedCount + 1;
    const shouldLock = nextFailedCount >= this.maxFailedAttempts;

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        failedLoginCount: nextFailedCount,
        status: shouldLock ? 'LOCKED' : undefined,
        lockedUntil: shouldLock
          ? new Date(Date.now() + this.lockoutSeconds * 1000)
          : undefined,
      },
    });
  }

  private async revokeTokenFamily(
    tokenFamilyId: string,
    reason: string,
  ): Promise<void> {
    await this.prisma.userSession.updateMany({
      where: {
        tokenFamilyId,
        status: 'ACTIVE',
      },
      data: {
        status: 'REVOKED',
        revokedAt: new Date(),
        revocationReason: reason,
      },
    });
  }

  private invalidCredentials(): UnauthorizedException {
    return new UnauthorizedException(
      'Mobile number or password is invalid.',
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\auth\auth.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  HttpCode,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import type { Request } from 'express';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import {
  AuthService,
  RequestMetadata,
} from './auth.service';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';

@ApiTags('Authentication')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  @HttpCode(200)
  @ApiOperation({ summary: 'Authenticate with mobile number and password' })
  login(@Body() dto: LoginDto, @Req() request: Request) {
    return this.authService.login(dto, this.getMetadata(request));
  }

  @Post('refresh')
  @HttpCode(200)
  @ApiOperation({ summary: 'Rotate a refresh token and issue a new session' })
  refresh(@Body() dto: RefreshTokenDto, @Req() request: Request) {
    return this.authService.refresh(
      dto.refreshToken,
      this.getMetadata(request),
    );
  }

  @Get('me')
  @ApiBearerAuth()
  @UseGuards(AccessTokenGuard)
  @ApiOperation({ summary: 'Return the authenticated access context' })
  me(@CurrentAuth() auth: AuthContext) {
    return this.authService.getMe(auth);
  }

  @Post('logout')
  @HttpCode(204)
  @ApiBearerAuth()
  @UseGuards(AccessTokenGuard)
  @ApiOperation({ summary: 'Revoke the current session' })
  async logout(
    @CurrentAuth() auth: AuthContext,
    @Req() request: Request,
  ): Promise<void> {
    await this.authService.logout(auth, this.getMetadata(request));
  }

  @Post('logout-all')
  @HttpCode(200)
  @ApiBearerAuth()
  @UseGuards(AccessTokenGuard)
  @ApiOperation({ summary: 'Revoke every active session for the user' })
  async logoutAll(
    @CurrentAuth() auth: AuthContext,
    @Req() request: Request,
  ): Promise<{ revokedSessionCount: number }> {
    return {
      revokedSessionCount: await this.authService.logoutAll(
        auth,
        this.getMetadata(request),
      ),
    };
  }

  private getMetadata(request: Request): RequestMetadata {
    const userAgentHeader = request.headers['user-agent'];

    return {
      ipAddress: request.ip || request.socket.remoteAddress || 'unknown',
      userAgent: Array.isArray(userAgentHeader)
        ? userAgentHeader.join(' ')
        : userAgentHeader,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\auth\auth.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { AuditModule } from '../audit/audit.module';
import { SecurityModule } from '../common/security.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

@Module({
  imports: [SecurityModule, AccessControlModule, AuditModule],
  controllers: [AuthController],
  providers: [AuthService],
  exports: [AuthService],
})
export class AuthModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\sessions\sessions.service.ts" `
        @'
import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../audit/audit.service';
import type { AuthContext } from '../common/auth-context';

@Injectable()
export class SessionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditService: AuditService,
  ) {}

  list(auth: AuthContext) {
    return this.prisma.userSession.findMany({
      where: { userId: auth.userId },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        tokenFamilyId: true,
        deviceName: true,
        platform: true,
        appVersion: true,
        ipAddress: true,
        status: true,
        createdAt: true,
        lastUsedAt: true,
        expiresAt: true,
        revokedAt: true,
        revocationReason: true,
      },
    });
  }

  async revoke(auth: AuthContext, sessionId: string): Promise<void> {
    const session = await this.prisma.userSession.findUnique({
      where: { id: sessionId },
      select: {
        id: true,
        userId: true,
        status: true,
      },
    });

    if (!session) {
      throw new NotFoundException('Session was not found.');
    }

    if (session.userId !== auth.userId) {
      throw new ForbiddenException('Session does not belong to this user.');
    }

    if (session.status === 'ACTIVE') {
      await this.prisma.userSession.update({
        where: { id: session.id },
        data: {
          status: 'REVOKED',
          revokedAt: new Date(),
          revocationReason: 'USER_REVOKED_SESSION',
        },
      });
    }

    await this.auditService.record({
      actorUserId: auth.userId,
      action: 'auth.session.revoked',
      resourceType: 'UserSession',
      resourceId: session.id,
    });
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\sessions\sessions.controller.ts" `
        @'
import {
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { SessionsService } from './sessions.service';

@ApiTags('Sessions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('sessions')
export class SessionsController {
  constructor(private readonly sessionsService: SessionsService) {}

  @Get()
  @ApiOperation({ summary: 'List the current user sessions' })
  list(@CurrentAuth() auth: AuthContext) {
    return this.sessionsService.list(auth);
  }

  @Delete(':sessionId')
  @HttpCode(204)
  @ApiOperation({ summary: 'Revoke one session owned by the user' })
  async revoke(
    @CurrentAuth() auth: AuthContext,
    @Param('sessionId', new ParseUUIDPipe()) sessionId: string,
  ): Promise<void> {
    await this.sessionsService.revoke(auth, sessionId);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\sessions\sessions.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { AuditModule } from '../audit/audit.module';
import { SessionsController } from './sessions.controller';
import { SessionsService } from './sessions.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [SessionsController],
  providers: [SessionsService],
})
export class SessionsModule {}
'@

    Write-Step 7 11 `
        "Writing users, organizations, memberships, roles, and permissions APIs"

    Write-Utf8File `
        "services\backend-api\src\identity\users\users.service.ts" `
        @'
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findPublicProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        userCode: true,
        fullName: true,
        mobileNumber: true,
        email: true,
        status: true,
        mobileVerifiedAt: true,
        emailVerifiedAt: true,
        lastLoginAt: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!user) {
      throw new NotFoundException('User was not found.');
    }

    return user;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\users\users.controller.ts" `
        @'
import {
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import { PermissionsGuard } from '../access-control/permissions.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { RequirePermissions } from '../common/permissions.decorator';
import { UsersService } from './users.service';

@ApiTags('Users')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('me')
  @ApiOperation({ summary: 'Return the authenticated user profile' })
  me(@CurrentAuth() auth: AuthContext) {
    return this.usersService.findPublicProfile(auth.userId);
  }

  @Get(':userId')
  @RequirePermissions('user.view')
  @ApiOperation({ summary: 'Return a user profile when permitted' })
  findOne(
    @Param('userId', new ParseUUIDPipe()) userId: string,
  ) {
    return this.usersService.findPublicProfile(userId);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\users\users.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  imports: [AccessControlModule],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\organizations\organizations.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../common/auth-context';

@Injectable()
export class OrganizationsService {
  constructor(private readonly prisma: PrismaService) {}

  listMine(auth: AuthContext) {
    return this.prisma.organizationMembership.findMany({
      where: {
        userId: auth.userId,
      },
      orderBy: [{ status: 'asc' }, { createdAt: 'asc' }],
      select: {
        id: true,
        membershipType: true,
        status: true,
        isPrimary: true,
        joinedAt: true,
        endedAt: true,
        organization: {
          select: {
            id: true,
            code: true,
            type: true,
            name: true,
            legalName: true,
            status: true,
            zoneId: true,
          },
        },
      },
    });
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\organizations\organizations.controller.ts" `
        @'
import { Controller, Get, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { OrganizationsService } from './organizations.service';

@ApiTags('Organizations')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('organizations')
export class OrganizationsController {
  constructor(
    private readonly organizationsService: OrganizationsService,
  ) {}

  @Get('me')
  @ApiOperation({ summary: 'List organizations linked to the user' })
  listMine(@CurrentAuth() auth: AuthContext) {
    return this.organizationsService.listMine(auth);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\organizations\organizations.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { OrganizationsController } from './organizations.controller';
import { OrganizationsService } from './organizations.service';

@Module({
  imports: [AccessControlModule],
  controllers: [OrganizationsController],
  providers: [OrganizationsService],
})
export class OrganizationsModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\memberships\memberships.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../common/auth-context';

@Injectable()
export class MembershipsService {
  constructor(private readonly prisma: PrismaService) {}

  async listMine(auth: AuthContext) {
    const [organizations, customers] = await Promise.all([
      this.prisma.organizationMembership.findMany({
        where: { userId: auth.userId },
        orderBy: { createdAt: 'asc' },
        select: {
          id: true,
          organizationId: true,
          membershipType: true,
          status: true,
          isPrimary: true,
          joinedAt: true,
          endedAt: true,
        },
      }),
      this.prisma.customerMembership.findMany({
        where: { userId: auth.userId },
        orderBy: { createdAt: 'asc' },
        select: {
          id: true,
          customerId: true,
          status: true,
          isPrimary: true,
          joinedAt: true,
          endedAt: true,
        },
      }),
    ]);

    return {
      organizations,
      customers,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\memberships\memberships.controller.ts" `
        @'
import { Controller, Get, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { MembershipsService } from './memberships.service';

@ApiTags('Memberships')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('memberships')
export class MembershipsController {
  constructor(
    private readonly membershipsService: MembershipsService,
  ) {}

  @Get('me')
  @ApiOperation({ summary: 'List the user organization and customer memberships' })
  listMine(@CurrentAuth() auth: AuthContext) {
    return this.membershipsService.listMine(auth);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\memberships\memberships.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { MembershipsController } from './memberships.controller';
import { MembershipsService } from './memberships.service';

@Module({
  imports: [AccessControlModule],
  controllers: [MembershipsController],
  providers: [MembershipsService],
})
export class MembershipsModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\roles\roles.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../common/auth-context';

@Injectable()
export class RolesService {
  constructor(private readonly prisma: PrismaService) {}

  listMine(auth: AuthContext) {
    return this.prisma.roleAssignment.findMany({
      where: {
        userId: auth.userId,
      },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        scopeType: true,
        scopeId: true,
        status: true,
        effectiveFrom: true,
        effectiveUntil: true,
        role: {
          select: {
            id: true,
            code: true,
            name: true,
            description: true,
            status: true,
          },
        },
      },
    });
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\roles\roles.controller.ts" `
        @'
import { Controller, Get, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { RolesService } from './roles.service';

@ApiTags('Roles')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('roles')
export class RolesController {
  constructor(private readonly rolesService: RolesService) {}

  @Get('me')
  @ApiOperation({ summary: 'List role assignments for the user' })
  listMine(@CurrentAuth() auth: AuthContext) {
    return this.rolesService.listMine(auth);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\roles\roles.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { RolesController } from './roles.controller';
import { RolesService } from './roles.service';

@Module({
  imports: [AccessControlModule],
  controllers: [RolesController],
  providers: [RolesService],
})
export class RolesModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\permissions\permissions.controller.ts" `
        @'
import { Controller, Get, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';

@ApiTags('Permissions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('permissions')
export class PermissionsController {
  @Get('me')
  @ApiOperation({ summary: 'List effective permission codes for the user' })
  listMine(@CurrentAuth() auth: AuthContext) {
    return {
      permissions: auth.permissions,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\permissions\permissions.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../access-control/access-control.module';
import { PermissionsController } from './permissions.controller';

@Module({
  imports: [AccessControlModule],
  controllers: [PermissionsController],
})
export class PermissionsModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\identity\identity-access.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from './access-control/access-control.module';
import { AuditModule } from './audit/audit.module';
import { AuthModule } from './auth/auth.module';
import { SecurityModule } from './common/security.module';
import { MembershipsModule } from './memberships/memberships.module';
import { OrganizationsModule } from './organizations/organizations.module';
import { OtpModule } from './otp/otp.module';
import { PermissionsModule } from './permissions/permissions.module';
import { RolesModule } from './roles/roles.module';
import { SessionsModule } from './sessions/sessions.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [
    SecurityModule,
    AccessControlModule,
    AuditModule,
    OtpModule,
    AuthModule,
    SessionsModule,
    UsersModule,
    OrganizationsModule,
    MembershipsModule,
    RolesModule,
    PermissionsModule,
  ],
})
export class IdentityAccessModule {}
'@

    Write-Step 8 11 `
        "Adding secure platform-administrator bootstrap tooling"

    Write-Utf8File `
        "services\backend-api\src\identity\cli\create-platform-admin.ts" `
        @'
import { PrismaPg } from '@prisma/adapter-pg';
import { config } from 'dotenv';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { PrismaClient } from '../../generated/prisma/client';
import { normalizeMobileNumber } from '../common/mobile-number.util';
import { PasswordService } from '../common/password.service';

config({
  path: resolve(process.cwd(), '../../.env'),
});

function readArgument(name: string): string {
  const index = process.argv.indexOf(name);
  const value = index >= 0 ? process.argv[index + 1] : undefined;

  if (!value) {
    throw new Error(`Required argument is missing: ${name}`);
  }

  return value;
}

async function main(): Promise<void> {
  const connectionString = process.env.DATABASE_URL;
  const password = process.env.SOLID_TRACKER_BOOTSTRAP_PASSWORD;

  if (!connectionString) {
    throw new Error('DATABASE_URL is required.');
  }

  if (!password) {
    throw new Error('SOLID_TRACKER_BOOTSTRAP_PASSWORD is required.');
  }

  const mobileNumber = readArgument('--mobile');
  const fullName = readArgument('--name');
  const normalizedMobileNumber = normalizeMobileNumber(mobileNumber);
  const passwordService = new PasswordService();
  const passwordHash = await passwordService.hash(password);

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString }),
  });

  try {
    const platformOrganization =
      await prisma.organization.findUniqueOrThrow({
        where: { code: 'ORG-PLATFORM' },
      });

    const superAdminRole = await prisma.role.findUniqueOrThrow({
      where: { code: 'PLATFORM_SUPER_ADMIN' },
    });

    const user = await prisma.$transaction(async (transaction) => {
      const createdOrUpdatedUser = await transaction.user.upsert({
        where: { normalizedMobileNumber },
        update: {
          fullName,
          mobileNumber,
          passwordHash,
          passwordChangedAt: new Date(),
          mobileVerifiedAt: new Date(),
          status: 'ACTIVE',
          failedLoginCount: 0,
          lockedUntil: null,
        },
        create: {
          userCode: `USR-${randomUUID()
            .replace(/-/g, '')
            .slice(0, 12)
            .toUpperCase()}`,
          fullName,
          mobileNumber,
          normalizedMobileNumber,
          passwordHash,
          passwordChangedAt: new Date(),
          mobileVerifiedAt: new Date(),
          status: 'ACTIVE',
        },
      });

      const membership =
        await transaction.organizationMembership.upsert({
          where: {
            organizationId_userId: {
              organizationId: platformOrganization.id,
              userId: createdOrUpdatedUser.id,
            },
          },
          update: {
            membershipType: 'OWNER',
            status: 'ACTIVE',
            joinedAt: new Date(),
            endedAt: null,
          },
          create: {
            organizationId: platformOrganization.id,
            userId: createdOrUpdatedUser.id,
            membershipType: 'OWNER',
            status: 'ACTIVE',
            joinedAt: new Date(),
            isPrimary: false,
          },
        });

      await transaction.roleAssignment.upsert({
        where: {
          userId_roleId_scopeType_scopeId: {
            userId: createdOrUpdatedUser.id,
            roleId: superAdminRole.id,
            scopeType: 'PLATFORM',
            scopeId: platformOrganization.id,
          },
        },
        update: {
          organizationMembershipId: membership.id,
          status: 'ACTIVE',
          effectiveFrom: new Date(),
          effectiveUntil: null,
          revokedAt: null,
          revokedByUserId: null,
          revocationReason: null,
        },
        create: {
          userId: createdOrUpdatedUser.id,
          roleId: superAdminRole.id,
          organizationMembershipId: membership.id,
          scopeType: 'PLATFORM',
          scopeId: platformOrganization.id,
          status: 'ACTIVE',
        },
      });

      await transaction.auditLog.create({
        data: {
          actorUserId: createdOrUpdatedUser.id,
          actorOrganizationId: platformOrganization.id,
          action: 'identity.platform_admin.bootstrapped',
          resourceType: 'User',
          resourceId: createdOrUpdatedUser.id,
        },
      });

      return createdOrUpdatedUser;
    });

    console.log('Solid Tracker platform administrator is ready.');
    console.log({
      userId: user.id,
      userCode: user.userCode,
      mobileNumber: user.mobileNumber,
    });
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
'@

    Write-Utf8File `
        "scripts\solid-tracker-create-platform-admin.ps1" `
        @'
[CmdletBinding()]
param(
    [string]$RepositoryPath = "D:\GitHub\gps-tracker-platform",
    [string]$MobileNumber,
    [string]$FullName
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath $RepositoryPath

if ([string]::IsNullOrWhiteSpace($MobileNumber)) {
    $MobileNumber = Read-Host "Administrator mobile number"
}

if ([string]::IsNullOrWhiteSpace($FullName)) {
    $FullName = Read-Host "Administrator full name"
}

$password = Read-Host "Administrator password" -AsSecureString
$confirmation = Read-Host "Confirm administrator password" -AsSecureString

$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
    $password
)

$confirmationPointer =
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $confirmation
    )

try {
    $plainPassword =
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            $passwordPointer
        )

    $plainConfirmation =
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            $confirmationPointer
        )

    if ($plainPassword -cne $plainConfirmation) {
        throw "Password confirmation does not match."
    }

    $env:SOLID_TRACKER_BOOTSTRAP_PASSWORD = $plainPassword

    & pnpm.cmd `
        --filter "@solid-tracker/backend-api" `
        identity:create-admin `
        -- `
        --mobile $MobileNumber `
        --name $FullName

    if ($LASTEXITCODE -ne 0) {
        throw "Platform administrator creation failed."
    }
}
finally {
    Remove-Item Env:SOLID_TRACKER_BOOTSTRAP_PASSWORD `
        -ErrorAction SilentlyContinue

    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $passwordPointer
        )
    }

    if ($confirmationPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $confirmationPointer
        )
    }

    $plainPassword = $null
    $plainConfirmation = $null
}
'@

    Write-Step 9 11 `
        "Updating application modules, package scripts, and tests"

    $appModulePath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\app.module.ts"

    $appModule = [System.IO.File]::ReadAllText($appModulePath)

    if (-not $appModule.Contains("IdentityAccessModule")) {
        $importAnchor = @'
import { HealthModule } from './health/health.module';
'@

        $identityImport = @'
import { IdentityAccessModule } from './identity/identity-access.module';
'@

        if (-not $appModule.Contains($importAnchor.Trim())) {
            throw "Could not locate AppModule import insertion point."
        }

        $appModule = $appModule.Replace(
            $importAnchor,
            $importAnchor + $identityImport
        )

        $moduleAnchor = @'
    HealthModule,
'@

        if (-not $appModule.Contains($moduleAnchor.Trim())) {
            throw "Could not locate AppModule module insertion point."
        }

        $appModule = $appModule.Replace(
            $moduleAnchor,
            @'
    IdentityAccessModule,
    HealthModule,
'@
        )

        [System.IO.File]::WriteAllText(
            $appModulePath,
            $appModule,
            $script:Utf8NoBom
        )

        Write-Host (
            "[UPDATED] services\backend-api\src\app.module.ts"
        ) -ForegroundColor Green
    }

    $backendPackage = Get-Content `
        -LiteralPath "services\backend-api\package.json" `
        -Raw |
        ConvertFrom-Json

    Set-JsonScript `
        $backendPackage `
        "identity:create-admin" `
        "tsx src/identity/cli/create-platform-admin.ts"

    Save-JsonFile `
        "services\backend-api\package.json" `
        $backendPackage

    $rootPackage = Get-Content `
        -LiteralPath "package.json" `
        -Raw |
        ConvertFrom-Json

    Set-JsonScript `
        $rootPackage `
        "identity:create-admin" `
        "pnpm --filter @solid-tracker/backend-api identity:create-admin"

    Save-JsonFile "package.json" $rootPackage

    Write-Utf8File `
        "services\backend-api\src\identity\common\password.service.spec.ts" `
        @'
import { PasswordService } from './password.service';

describe('PasswordService', () => {
  const service = new PasswordService();

  it('hashes and verifies a strong password', async () => {
    const hash = await service.hash('SolidTracker123!');

    expect(hash).not.toContain('SolidTracker123!');
    await expect(
      service.verify('SolidTracker123!', hash),
    ).resolves.toBe(true);
    await expect(
      service.verify('WrongPassword123!', hash),
    ).resolves.toBe(false);
  });

  it('rejects weak passwords', async () => {
    await expect(service.hash('password')).rejects.toThrow(
      'Password must contain at least 12 characters',
    );
  });
});
'@

    Write-Utf8File `
        "services\backend-api\src\identity\common\mobile-number.util.spec.ts" `
        @'
import { normalizeMobileNumber } from './mobile-number.util';

describe('normalizeMobileNumber', () => {
  it('normalizes Bangladeshi local and international formats', () => {
    expect(normalizeMobileNumber('01712-345678')).toBe('+8801712345678');
    expect(normalizeMobileNumber('8801712345678')).toBe('+8801712345678');
    expect(normalizeMobileNumber('+8801712345678')).toBe('+8801712345678');
  });

  it('rejects malformed values', () => {
    expect(() => normalizeMobileNumber('123')).toThrow(
      'Mobile number format is invalid',
    );
  });
});
'@

    Write-Utf8File `
        "services\backend-api\test\auth.e2e-spec.ts" `
        @'
import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

describe('Solid Tracker Authentication (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let testUserId: string;
  let testMobile: string;
  const testPassword = 'SolidTracker123!';

  beforeAll(async () => {
    const moduleFixture: TestingModule =
      await Test.createTestingModule({
        imports: [AppModule],
      }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    const passwordService = app.get(PasswordService);
    const suffix = Date.now().toString().slice(-8);
    testMobile = `+88017${suffix}`;

    const user = await prisma.user.create({
      data: {
        userCode: `TEST-${randomUUID()
          .replace(/-/g, '')
          .slice(0, 12)
          .toUpperCase()}`,
        fullName: 'Authentication E2E User',
        mobileNumber: testMobile,
        normalizedMobileNumber: testMobile,
        passwordHash: await passwordService.hash(testPassword),
        passwordChangedAt: new Date(),
        mobileVerifiedAt: new Date(),
        status: 'ACTIVE',
      },
    });

    testUserId = user.id;
  });

  afterAll(async () => {
    if (testUserId) {
      await prisma.userSession.deleteMany({
        where: { userId: testUserId },
      });
      await prisma.otpChallenge.deleteMany({
        where: { userId: testUserId },
      });      await prisma.user.update({
        where: { id: testUserId },
        data: {
          status: 'ARCHIVED',
          passwordHash: null,
          archivedAt: new Date(),
        },
      });
    }

    if (app) {
      await app.close();
    }
  });

  it('logs in, rotates refresh token, and revokes the session', async () => {
    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        mobileNumber: testMobile,
        password: testPassword,
        platform: 'WEB',
        deviceName: 'E2E Test',
        appVersion: 'test',
      })
      .expect(200);

    expect(login.body.tokenType).toBe('Bearer');
    expect(login.body.accessToken).toEqual(expect.any(String));
    expect(login.body.refreshToken).toEqual(expect.any(String));

    const me = await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${login.body.accessToken}`)
      .expect(200);

    expect(me.body.userId).toBe(testUserId);
    expect(me.body.permissions).toEqual([]);

    const refreshed = await request(app.getHttpServer())
      .post('/api/v1/auth/refresh')
      .send({
        refreshToken: login.body.refreshToken,
      })
      .expect(200);

    expect(refreshed.body.refreshToken).not.toBe(
      login.body.refreshToken,
    );

    await request(app.getHttpServer())
      .post('/api/v1/auth/logout')
      .set('Authorization', `Bearer ${refreshed.body.accessToken}`)
      .expect(204);

    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${refreshed.body.accessToken}`)
      .expect(401);
  });
});
'@

    Write-Step 10 11 `
        "Applying migration and running complete verification"

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
        throw "Expected at least 50 public tables, but found $tableCount."
    }

    if ($otpIndexCount -ne 1) {
        throw "Expected the active OTP uniqueness index."
    }

    if ($auditTriggerCount -ne 2) {
        throw "Expected 2 append-only audit triggers."
    }

    Write-Host "Public tables:             $tableCount" -ForegroundColor Green
    Write-Host "OTP invariant indexes:     $otpIndexCount" -ForegroundColor Green
    Write-Host "Append-only audit triggers: $auditTriggerCount" -ForegroundColor Green

    Write-Step 11 11 `
        "Writing architecture records and committing the identity API"

    $documentation = @'
# Identity and Access API Foundation

## Delivered modules

- `AuthModule`
- `UsersModule`
- `OrganizationsModule`
- `MembershipsModule`
- `RolesModule`
- `PermissionsModule`
- `SessionsModule`
- `AuditModule`
- `OtpModule`
- `AccessControlModule`

## Authentication

Users authenticate with normalized mobile number and password.

Passwords are hashed with Node.js `scrypt` using a unique random salt. Password hashes are never returned through API responses.

Access tokens are short-lived JWT bearer tokens. The token contains only the user ID, session ID, and token type.

Refresh tokens are opaque random values. Only an HMAC hash is stored in PostgreSQL.

## Refresh-token rotation

Every successful refresh:

1. revokes the previous session record;
2. creates a new session in the same token family;
3. stores a new refresh-token hash;
4. issues a new access token.

Reusing a revoked or expired refresh token revokes every active session in that token family.

## Authorization

The access-token guard validates:

- JWT signature and expiry;
- token type;
- session status and expiry;
- user status.

The access-control service loads current database role assignments, permissions, organization memberships, and customer memberships.

`@RequirePermissions()` and `PermissionsGuard` provide reusable permission enforcement.

## Lockout and rate limiting

Redis limits login attempts by IP address and normalized mobile number.

PostgreSQL stores failed-login count and lock expiry. A user reaches `LOCKED` after the configured number of failed attempts and is automatically unlocked after the lock period expires.

## OTP foundation

`OtpChallenge` stores only a keyed hash of each six-digit code.

The service supports:

- mobile verification;
- password reset;
- high-risk action verification;
- challenge replacement;
- expiry;
- attempt limits;
- lockout;
- one pending challenge per mobile and purpose.

No OTP value is exposed by a public controller. A future SMS provider adapter will receive the internally generated code.

## Audit history

Authentication events are written to `audit_logs`.

PostgreSQL blocks UPDATE and DELETE operations on audit records. Corrections must be represented by new audit records.

## Initial administrator

No default administrator or password is created.

Run:

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\scripts\solid-tracker-create-platform-admin.ps1"
```

The script securely prompts for the password and does not place it in command history.

## API endpoints

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

## Next stage

The next stage implements customer and dealer-management application services and REST endpoints using the identity guards and scope context established here.
'@

    Write-Utf8File `
        "docs\architecture\identity-access-api.md" `
        $documentation

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
    Write-Host ""
    Write-Host "Next implementation stage:" -ForegroundColor Yellow
    Write-Host (
        "Dealer and customer management APIs with scoped authorization"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "IDENTITY AND ACCESS API FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "Do not delete or reset an applied migration."
    ) -ForegroundColor Yellow
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
