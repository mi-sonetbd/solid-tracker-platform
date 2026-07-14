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
        $Content.Replace("`r`n", "`n"),
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

function Ensure-EnvEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $content = [System.IO.File]::ReadAllText($fullPath)
    $pattern = "(?m)^" + [regex]::Escape($Name) + "=.*$"

    if ([regex]::IsMatch($content, $pattern)) {
        return
    }

    if (
        $content.Length -gt 0 -and
        -not $content.EndsWith([Environment]::NewLine)
    ) {
        $content += [Environment]::NewLine
    }

    $content += "$Name=$Value" + [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        $fullPath,
        $content,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED] $RelativePath with $Name" -ForegroundColor Green
}

function New-SecureBase64 {
    $bytes = New-Object byte[] 48
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    return [Convert]::ToBase64String($bytes)
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

function Assert-AllowedWorkingTree {
    $allowed = @(
        "scripts/solid-tracker-notification-delivery.ps1",
        "scripts/solid-tracker-notification-delivery-recovery.ps1"
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

        if (-not $allowed.Contains($path)) {
            $unexpected.Add($line)
        }
    }

    if ($unexpected.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        foreach ($line in $unexpected) {
            Write-Host $line -ForegroundColor Yellow
        }

        throw "Commit or revert unrelated changes before continuing."
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Notification Delivery Platform v5" -ForegroundColor Cyan
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

    Write-Step 1 10 "Integrating payment automation and preparing the branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/payment-gateway-automation") {
        Assert-AllowedWorkingTree

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        Invoke-CheckedCommand "Merge payment gateway automation into main" {
            git merge `
                --no-ff `
                feat/payment-gateway-automation `
                -m "merge: integrate payment gateway automation"
        }

        if (
            ((git branch --list "feat/notification-delivery") | Out-String).Trim()
        ) {
            throw "Branch feat/notification-delivery already exists."
        }

        Invoke-CheckedCommand "Create notification delivery branch" {
            git checkout -b feat/notification-delivery
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-AllowedWorkingTree

        if (
            -not ((git branch --list "feat/payment-gateway-automation") | Out-String).Trim()
        ) {
            throw "Source branch feat/payment-gateway-automation was not found."
        }

        Invoke-CheckedCommand "Merge payment gateway automation into main" {
            git merge `
                --no-ff `
                feat/payment-gateway-automation `
                -m "merge: integrate payment gateway automation"
        }

        if (
            ((git branch --list "feat/notification-delivery") | Out-String).Trim()
        ) {
            throw "Branch feat/notification-delivery already exists."
        }

        Invoke-CheckedCommand "Create notification delivery branch" {
            git checkout -b feat/notification-delivery
        }
    }
    elseif ($currentBranch -eq "feat/notification-delivery") {
        Write-Host "Resuming existing notification delivery branch." -ForegroundColor Green
    }
    else {
        throw (
            "Expected feat/payment-gateway-automation, main, or " +
            "feat/notification-delivery; current branch is $currentBranch."
        )
    }

    Write-Step 2 10 "Validating infrastructure and the existing tracking outbox"

    Invoke-CheckedCommand "Start PostgreSQL and Redis" {
        docker compose --env-file .env up -d postgres redis
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $initialMigrationCount = Get-AppliedMigrationCount

    if ($initialMigrationCount -notin @(5, 6)) {
        throw (
            "Expected 5 migrations before this stage or 6 while resuming, " +
            "but found $initialMigrationCount."
        )
    }

    $schemaPath = "services/backend-api/prisma/schema.prisma"
    $schemaContent = Get-LfContent $schemaPath

    foreach ($requiredModel in @(
        "model NotificationRule {",
        "model Notification {"
    )) {
        if (-not $schemaContent.Contains($requiredModel)) {
            throw "Required notification model is missing: $requiredModel"
        }
    }

    Write-Host "PostgreSQL:         healthy" -ForegroundColor Green
    Write-Host "Redis:              healthy" -ForegroundColor Green
    Write-Host "Existing outbox:    notifications table" -ForegroundColor Green
    Write-Host "Applied migrations: $initialMigrationCount" -ForegroundColor Green

    Write-Step 3 10 "Adding durable notification delivery schema and migration"

    $schemaExtension = @'
enum NotificationTemplateStatus {
  DRAFT
  ACTIVE
  INACTIVE
  ARCHIVED
}

enum NotificationDeliveryAttemptStatus {
  PROCESSING
  SENT
  DELIVERED
  FAILED
  DEAD_LETTER
  CANCELLED
}

enum NotificationProviderEventStatus {
  RECEIVED
  PROCESSED
  IGNORED
  FAILED
}

model NotificationTemplate {
  id                String                     @id @default(uuid()) @db.Uuid
  templateCode      String                     @unique @db.VarChar(80)
  templateKey       String                     @db.VarChar(120)
  channel           NotificationChannel
  locale            String                     @default("en") @db.VarChar(20)
  version           Int                        @default(1)
  name              String                     @db.VarChar(160)
  subjectTemplate   String?                    @db.VarChar(240)
  bodyTemplate      String
  variableSchema    Json?
  status            NotificationTemplateStatus @default(DRAFT)
  createdByUserId   String?                    @db.Uuid
  activatedAt       DateTime?                  @db.Timestamptz(3)
  archivedAt        DateTime?                  @db.Timestamptz(3)
  createdAt         DateTime                   @default(now()) @db.Timestamptz(3)
  updatedAt         DateTime                   @updatedAt @db.Timestamptz(3)

  @@unique([templateKey, channel, locale, version])
  @@index([templateKey, channel, locale, status])
  @@index([status, createdAt])
  @@map("notification_templates")
}

model NotificationDeliveryAttempt {
  id                String                            @id @default(uuid()) @db.Uuid
  notificationId    String                            @db.Uuid
  attemptNumber     Int
  provider          String                            @db.VarChar(120)
  idempotencyKey    String                            @unique @db.VarChar(180)
  status            NotificationDeliveryAttemptStatus @default(PROCESSING)
  requestPayload    Json?
  responsePayload   Json?
  providerMessageId String?                           @db.VarChar(200)
  errorCode         String?                           @db.VarChar(100)
  errorMessage      String?
  nextRetryAt       DateTime?                         @db.Timestamptz(3)
  startedAt         DateTime                          @default(now()) @db.Timestamptz(3)
  completedAt       DateTime?                         @db.Timestamptz(3)
  createdAt         DateTime                          @default(now()) @db.Timestamptz(3)

  @@unique([notificationId, attemptNumber])
  @@index([notificationId, createdAt])
  @@index([status, nextRetryAt])
  @@index([provider, providerMessageId])
  @@map("notification_delivery_attempts")
}

model NotificationProviderEvent {
  id                String                          @id @default(uuid()) @db.Uuid
  provider          String                          @db.VarChar(120)
  externalEventId   String                          @db.VarChar(180)
  notificationId    String?                         @db.Uuid
  providerMessageId String?                         @db.VarChar(200)
  eventType         String                          @db.VarChar(100)
  status            NotificationProviderEventStatus @default(RECEIVED)
  signatureValid    Boolean                         @default(false)
  payload           Json
  receivedAt        DateTime                        @default(now()) @db.Timestamptz(3)
  processedAt       DateTime?                       @db.Timestamptz(3)
  error             String?

  @@unique([provider, externalEventId])
  @@index([notificationId, receivedAt])
  @@index([providerMessageId])
  @@index([status, receivedAt])
  @@map("notification_provider_events")
}
'@

    $schemaContent = Get-LfContent $schemaPath

    if (-not $schemaContent.Contains("model NotificationTemplate {")) {
        $schemaContent = $schemaContent.TrimEnd() + "`n`n" + $schemaExtension.Trim() + "`n"
        Set-LfContent $schemaPath $schemaContent
        Write-Host "[UPDATED] $schemaPath" -ForegroundColor Green
    }
    else {
        Write-Host "[UNCHANGED] Notification delivery schema already present." -ForegroundColor DarkGreen
    }

    $migrationRelativePath = (
        "services/backend-api/prisma/migrations/" +
        "20260714230000_notification_delivery_foundation/" +
        "migration.sql"
    )
    $migrationSql = @'
CREATE TYPE "NotificationTemplateStatus" AS ENUM (
  'DRAFT',
  'ACTIVE',
  'INACTIVE',
  'ARCHIVED'
);

CREATE TYPE "NotificationDeliveryAttemptStatus" AS ENUM (
  'PROCESSING',
  'SENT',
  'DELIVERED',
  'FAILED',
  'DEAD_LETTER',
  'CANCELLED'
);

CREATE TYPE "NotificationProviderEventStatus" AS ENUM (
  'RECEIVED',
  'PROCESSED',
  'IGNORED',
  'FAILED'
);

CREATE TABLE "notification_templates" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "templateCode" VARCHAR(80) NOT NULL,
  "templateKey" VARCHAR(120) NOT NULL,
  "channel" "NotificationChannel" NOT NULL,
  "locale" VARCHAR(20) NOT NULL DEFAULT 'en',
  "version" INTEGER NOT NULL DEFAULT 1,
  "name" VARCHAR(160) NOT NULL,
  "subjectTemplate" VARCHAR(240),
  "bodyTemplate" TEXT NOT NULL,
  "variableSchema" JSONB,
  "status" "NotificationTemplateStatus" NOT NULL DEFAULT 'DRAFT',
  "createdByUserId" UUID,
  "activatedAt" TIMESTAMPTZ(3),
  "archivedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notification_templates_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "notification_templates_version_positive"
    CHECK ("version" > 0)
);

CREATE TABLE "notification_delivery_attempts" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "notificationId" UUID NOT NULL,
  "attemptNumber" INTEGER NOT NULL,
  "provider" VARCHAR(120) NOT NULL,
  "idempotencyKey" VARCHAR(180) NOT NULL,
  "status" "NotificationDeliveryAttemptStatus" NOT NULL DEFAULT 'PROCESSING',
  "requestPayload" JSONB,
  "responsePayload" JSONB,
  "providerMessageId" VARCHAR(200),
  "errorCode" VARCHAR(100),
  "errorMessage" TEXT,
  "nextRetryAt" TIMESTAMPTZ(3),
  "startedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notification_delivery_attempts_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "notification_delivery_attempts_number_positive"
    CHECK ("attemptNumber" > 0)
);

CREATE TABLE "notification_provider_events" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "provider" VARCHAR(120) NOT NULL,
  "externalEventId" VARCHAR(180) NOT NULL,
  "notificationId" UUID,
  "providerMessageId" VARCHAR(200),
  "eventType" VARCHAR(100) NOT NULL,
  "status" "NotificationProviderEventStatus" NOT NULL DEFAULT 'RECEIVED',
  "signatureValid" BOOLEAN NOT NULL DEFAULT false,
  "payload" JSONB NOT NULL,
  "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "processedAt" TIMESTAMPTZ(3),
  "error" TEXT,
  CONSTRAINT "notification_provider_events_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "notification_templates_templateCode_key"
ON "notification_templates" ("templateCode");

CREATE UNIQUE INDEX "notification_templates_templateKey_channel_locale_version_key"
ON "notification_templates" (
  "templateKey",
  "channel",
  "locale",
  "version"
);

CREATE INDEX "notification_templates_templateKey_channel_locale_status_idx"
ON "notification_templates" (
  "templateKey",
  "channel",
  "locale",
  "status"
);

CREATE INDEX "notification_templates_status_createdAt_idx"
ON "notification_templates" ("status", "createdAt");

CREATE UNIQUE INDEX "notification_templates_one_active_variant"
ON "notification_templates" (
  "templateKey",
  "channel",
  "locale"
)
WHERE "status" = 'ACTIVE';

CREATE UNIQUE INDEX "notification_delivery_attempts_idempotencyKey_key"
ON "notification_delivery_attempts" ("idempotencyKey");

CREATE UNIQUE INDEX "notification_delivery_attempts_notificationId_attemptNumber_key"
ON "notification_delivery_attempts" (
  "notificationId",
  "attemptNumber"
);

CREATE INDEX "notification_delivery_attempts_notificationId_createdAt_idx"
ON "notification_delivery_attempts" (
  "notificationId",
  "createdAt"
);

CREATE INDEX "notification_delivery_attempts_status_nextRetryAt_idx"
ON "notification_delivery_attempts" (
  "status",
  "nextRetryAt"
);

CREATE INDEX "notification_delivery_attempts_provider_providerMessageId_idx"
ON "notification_delivery_attempts" (
  "provider",
  "providerMessageId"
);

CREATE UNIQUE INDEX "notification_provider_events_provider_externalEventId_key"
ON "notification_provider_events" (
  "provider",
  "externalEventId"
);

CREATE INDEX "notification_provider_events_notificationId_receivedAt_idx"
ON "notification_provider_events" (
  "notificationId",
  "receivedAt"
);

CREATE INDEX "notification_provider_events_providerMessageId_idx"
ON "notification_provider_events" ("providerMessageId");

CREATE INDEX "notification_provider_events_status_receivedAt_idx"
ON "notification_provider_events" (
  "status",
  "receivedAt"
);

ALTER TABLE "notification_templates"
ADD CONSTRAINT "notification_templates_createdByUserId_fkey"
FOREIGN KEY ("createdByUserId")
REFERENCES "users" ("id")
ON DELETE SET NULL
ON UPDATE CASCADE;

ALTER TABLE "notification_delivery_attempts"
ADD CONSTRAINT "notification_delivery_attempts_notificationId_fkey"
FOREIGN KEY ("notificationId")
REFERENCES "notifications" ("id")
ON DELETE RESTRICT
ON UPDATE CASCADE;

ALTER TABLE "notification_provider_events"
ADD CONSTRAINT "notification_provider_events_notificationId_fkey"
FOREIGN KEY ("notificationId")
REFERENCES "notifications" ("id")
ON DELETE SET NULL
ON UPDATE CASCADE;

INSERT INTO "permissions" (
  "id",
  "code",
  "name",
  "description",
  "status",
  "createdAt",
  "updatedAt"
)
VALUES
  (
    gen_random_uuid(),
    'notification.template.manage',
    'Manage notification templates',
    'Create, activate, and archive notification template versions.',
    'ACTIVE',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    gen_random_uuid(),
    'notification.delivery.manage',
    'Manage notification delivery',
    'Enqueue, retry, and run notification delivery operations.',
    'ACTIVE',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    gen_random_uuid(),
    'notification.delivery.view',
    'View notification delivery',
    'View notification outbox, attempts, dead letters, and metrics.',
    'ACTIVE',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  )
ON CONFLICT ("code") DO NOTHING;

INSERT INTO "role_permissions" (
  "roleId",
  "permissionId",
  "createdAt"
)
SELECT
  role_record."id",
  permission_record."id",
  CURRENT_TIMESTAMP
FROM "roles" AS role_record
INNER JOIN "permissions" AS permission_record
  ON permission_record."code" IN (
    'notification.template.manage',
    'notification.delivery.manage',
    'notification.delivery.view'
  )
WHERE role_record."code" IN (
  'PLATFORM_SUPER_ADMIN',
  'PLATFORM_ADMIN'
)
ON CONFLICT DO NOTHING;

INSERT INTO "role_permissions" (
  "roleId",
  "permissionId",
  "createdAt"
)
SELECT
  role_record."id",
  permission_record."id",
  CURRENT_TIMESTAMP
FROM "roles" AS role_record
INNER JOIN "permissions" AS permission_record
  ON permission_record."code" =
     'notification.delivery.view'
WHERE role_record."code" = 'PLATFORM_SUPPORT'
ON CONFLICT DO NOTHING;
'@

    if (-not (Test-Path -LiteralPath $migrationRelativePath)) {
        Write-Utf8File $migrationRelativePath $migrationSql
    }
    else {
        $existingMigration = Get-LfContent $migrationRelativePath

        if ($existingMigration.Trim() -ne $migrationSql.Trim()) {
            throw (
                "Existing notification-delivery migration content differs " +
                "from the expected immutable migration."
            )
        }

        Write-Host "[UNCHANGED] $migrationRelativePath" -ForegroundColor DarkGreen
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

    Invoke-CheckedCommand "Deploy notification delivery migration" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate deploy `
            --config prisma.config.ts
    }

    $deployedMigrationCount = Get-AppliedMigrationCount

    if ($deployedMigrationCount -ne 6) {
        throw "Expected exactly 6 applied migrations after deployment."
    }

    Write-Host "Applied migrations: 6" -ForegroundColor Green

    Write-Step 4 10 "Configuring delivery workers, providers, and callback security"

    Ensure-EnvEntry ".env" "NOTIFICATION_DELIVERY_ENABLED" "false"
    Ensure-EnvEntry ".env" "NOTIFICATION_DELIVERY_INTERVAL_MS" "5000"
    Ensure-EnvEntry ".env" "NOTIFICATION_DELIVERY_BATCH_SIZE" "25"
    Ensure-EnvEntry ".env" "NOTIFICATION_DELIVERY_MAX_ATTEMPTS" "5"
    Ensure-EnvEntry ".env" "NOTIFICATION_DELIVERY_RETRY_BASE_MS" "30000"
    Ensure-EnvEntry ".env" "NOTIFICATION_PROVIDER_HTTP_TIMEOUT_MS" "10000"
    Ensure-EnvEntry `
        ".env" `
        "NOTIFICATION_CALLBACK_BASE_URL" `
        "http://localhost:3000/api/v1/notification-delivery/callbacks"
    Ensure-EnvEntry `
        ".env" `
        "NOTIFICATION_SANDBOX_WEBHOOK_SECRET" `
        (New-SecureBase64)
    Ensure-EnvEntry ".env" "NOTIFICATION_SMS_PROXY_URL" ""
    Ensure-EnvEntry ".env" "NOTIFICATION_SMS_PROXY_SECRET" ""
    Ensure-EnvEntry ".env" "NOTIFICATION_EMAIL_PROXY_URL" ""
    Ensure-EnvEntry ".env" "NOTIFICATION_EMAIL_PROXY_SECRET" ""
    Ensure-EnvEntry ".env" "NOTIFICATION_PUSH_PROXY_URL" ""
    Ensure-EnvEntry ".env" "NOTIFICATION_PUSH_PROXY_SECRET" ""

    Ensure-EnvEntry ".env.example" "NOTIFICATION_DELIVERY_ENABLED" "false"
    Ensure-EnvEntry ".env.example" "NOTIFICATION_DELIVERY_INTERVAL_MS" "5000"
    Ensure-EnvEntry ".env.example" "NOTIFICATION_DELIVERY_BATCH_SIZE" "25"
    Ensure-EnvEntry ".env.example" "NOTIFICATION_DELIVERY_MAX_ATTEMPTS" "5"
    Ensure-EnvEntry ".env.example" "NOTIFICATION_DELIVERY_RETRY_BASE_MS" "30000"
    Ensure-EnvEntry ".env.example" "NOTIFICATION_PROVIDER_HTTP_TIMEOUT_MS" "10000"
    Ensure-EnvEntry `
        ".env.example" `
        "NOTIFICATION_CALLBACK_BASE_URL" `
        "https://api.example.com/api/v1/notification-delivery/callbacks"
    Ensure-EnvEntry `
        ".env.example" `
        "NOTIFICATION_SANDBOX_WEBHOOK_SECRET" `
        "replace-with-a-dedicated-random-secret-at-least-32-characters"
    Ensure-EnvEntry ".env.example" "NOTIFICATION_SMS_PROXY_URL" ""
    Ensure-EnvEntry ".env.example" "NOTIFICATION_SMS_PROXY_SECRET" ""
    Ensure-EnvEntry ".env.example" "NOTIFICATION_EMAIL_PROXY_URL" ""
    Ensure-EnvEntry ".env.example" "NOTIFICATION_EMAIL_PROXY_SECRET" ""
    Ensure-EnvEntry ".env.example" "NOTIFICATION_PUSH_PROXY_URL" ""
    Ensure-EnvEntry ".env.example" "NOTIFICATION_PUSH_PROXY_SECRET" ""

    $validationPath = "services/backend-api/src/config/environment.validation.ts"
    $validationContent = Get-LfContent $validationPath

    if (-not $validationContent.Contains("NOTIFICATION_DELIVERY_ENABLED")) {
        $validationBlock = @'
  NOTIFICATION_DELIVERY_ENABLED: Joi.boolean()
    .truthy('true')
    .falsy('false')
    .default(false),
  NOTIFICATION_DELIVERY_INTERVAL_MS: Joi.number()
    .integer()
    .min(1000)
    .max(3600000)
    .default(5000),
  NOTIFICATION_DELIVERY_BATCH_SIZE: Joi.number()
    .integer()
    .min(1)
    .max(200)
    .default(25),
  NOTIFICATION_DELIVERY_MAX_ATTEMPTS: Joi.number()
    .integer()
    .min(1)
    .max(20)
    .default(5),
  NOTIFICATION_DELIVERY_RETRY_BASE_MS: Joi.number()
    .integer()
    .min(1000)
    .max(86400000)
    .default(30000),
  NOTIFICATION_PROVIDER_HTTP_TIMEOUT_MS: Joi.number()
    .integer()
    .min(1000)
    .max(120000)
    .default(10000),
  NOTIFICATION_CALLBACK_BASE_URL: Joi.string().uri().required(),
  NOTIFICATION_SANDBOX_WEBHOOK_SECRET: Joi.string().min(32).required(),
  NOTIFICATION_SMS_PROXY_URL: Joi.string().allow('').default(''),
  NOTIFICATION_SMS_PROXY_SECRET: Joi.string().allow('').default(''),
  NOTIFICATION_EMAIL_PROXY_URL: Joi.string().allow('').default(''),
  NOTIFICATION_EMAIL_PROXY_SECRET: Joi.string().allow('').default(''),
  NOTIFICATION_PUSH_PROXY_URL: Joi.string().allow('').default(''),
  NOTIFICATION_PUSH_PROXY_SECRET: Joi.string().allow('').default(''),
'@

        $closingIndex = $validationContent.LastIndexOf("});")

        if ($closingIndex -lt 0) {
            throw "Could not locate the environment validation object."
        }

        $validationContent = (
            $validationContent.Substring(0, $closingIndex) +
            $validationBlock +
            "`n" +
            $validationContent.Substring($closingIndex)
        )

        Set-LfContent $validationPath $validationContent
        Write-Host "[UPDATED] $validationPath" -ForegroundColor Green
    }

    Write-Step 5 10 "Writing templates, providers, outbox workers, callbacks, and observability"

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\common\notification-delivery.types.ts" `
        @'
import type { NotificationChannel, Prisma } from '../../generated/prisma/client';

export interface NotificationSendInput {
  notificationId: string;
  idempotencyKey: string;
  channel: NotificationChannel;
  recipient: string;
  subject?: string | null;
  content: string;
  callbackUrl: string;
}

export interface NotificationSendResult {
  provider: string;
  providerMessageId: string;
  status: 'SENT' | 'DELIVERED';
  responsePayload?: Prisma.InputJsonValue;
}

export interface NotificationProviderAdapter {
  provider: string;
  supports(channel: NotificationChannel): boolean;
  send(input: NotificationSendInput): Promise<NotificationSendResult>;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\common\notification-code.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { randomBytes } from 'node:crypto';

@Injectable()
export class NotificationCodeService {
  template(): string {
    return `NTPL-${this.token(12)}`;
  }

  notification(): string {
    return `NTF-${this.token(16)}`;
  }

  private token(length: number): string {
    return randomBytes(Math.ceil(length / 2))
      .toString('hex')
      .slice(0, length)
      .toUpperCase();
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\common\notification-signature.service.ts" `
        @'
import {
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import {
  createHmac,
  timingSafeEqual,
} from 'node:crypto';

@Injectable()
export class NotificationSignatureService {
  sign(
    secret: string,
    timestamp: string,
    eventId: string,
    payload: unknown,
  ): string {
    return createHmac('sha256', secret)
      .update(this.message(timestamp, eventId, payload))
      .digest('hex');
  }

  verify(input: {
    secret: string;
    timestamp?: string;
    eventId?: string;
    signature?: string;
    payload: unknown;
    toleranceSeconds?: number;
  }): void {
    const {
      secret,
      timestamp,
      eventId,
      signature,
      payload,
      toleranceSeconds = 300,
    } = input;

    if (!timestamp || !eventId || !signature) {
      throw new UnauthorizedException(
        'Notification callback signature headers are required.',
      );
    }

    const timestampValue = Number(timestamp);

    if (!Number.isFinite(timestampValue)) {
      throw new UnauthorizedException(
        'Notification callback timestamp is invalid.',
      );
    }

    const timestampMilliseconds =
      timestampValue < 10_000_000_000
        ? timestampValue * 1000
        : timestampValue;
    const age = Math.abs(Date.now() - timestampMilliseconds);

    if (age > toleranceSeconds * 1000) {
      throw new UnauthorizedException(
        'Notification callback timestamp is outside the accepted window.',
      );
    }

    const expected = this.sign(
      secret,
      timestamp,
      eventId,
      payload,
    );
    const expectedBuffer = Buffer.from(expected, 'hex');
    const actualBuffer = Buffer.from(signature, 'hex');

    if (
      expectedBuffer.length !== actualBuffer.length ||
      !timingSafeEqual(expectedBuffer, actualBuffer)
    ) {
      throw new UnauthorizedException(
        'Notification callback signature is invalid.',
      );
    }
  }

  canonicalize(value: unknown): string {
    const serialized = JSON.stringify(value);

    if (serialized === undefined) {
      return 'null';
    }

    return this.canonicalizeJson(
      JSON.parse(serialized) as unknown,
    );
  }

  private canonicalizeJson(value: unknown): string {
    if (value === null || typeof value !== 'object') {
      return JSON.stringify(value);
    }

    if (Array.isArray(value)) {
      return `[${value
        .map((item) => this.canonicalizeJson(item))
        .join(',')}]`;
    }

    const record = value as Record<string, unknown>;
    const entries = Object.keys(record)
      .sort()
      .map(
        (key) =>
          `${JSON.stringify(key)}:${this.canonicalizeJson(record[key])}`,
      );

    return `{${entries.join(',')}}`;
  }
  private message(
    timestamp: string,
    eventId: string,
    payload: unknown,
  ): string {
    return `${timestamp}.${eventId}.${this.canonicalize(payload)}`;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\common\notification-signature.service.spec.ts" `
        @'
import { UnauthorizedException } from '@nestjs/common';
import { NotificationSignatureService } from './notification-signature.service';

describe('NotificationSignatureService', () => {
  const service = new NotificationSignatureService();
  const secret =
    'notification-secret-that-is-long-enough-for-tests';

  it('signs canonical payloads deterministically', () => {
    const timestamp = Date.now().toString();
    const first = service.sign(
      secret,
      timestamp,
      'evt-1',
      { b: 2, a: 1 },
    );
    const second = service.sign(
      secret,
      timestamp,
      'evt-1',
      { a: 1, b: 2 },
    );

    expect(first).toBe(second);
  });

  it('matches JSON transport when optional DTO fields are undefined', () => {
    const timestamp = Date.now().toString();
    const dtoLikePayload = {
      externalEventId: 'evt-transport',
      providerMessageId: 'msg-transport',
      status: 'DELIVERED',
      occurredAt: new Date().toISOString(),
      errorCode: undefined,
      errorMessage: undefined,
      metadata: { source: 'e2e' },
    };
    const transportedPayload = JSON.parse(
      JSON.stringify(dtoLikePayload),
    ) as unknown;

    expect(
      service.sign(
        secret,
        timestamp,
        'evt-transport',
        dtoLikePayload,
      ),
    ).toBe(
      service.sign(
        secret,
        timestamp,
        'evt-transport',
        transportedPayload,
      ),
    );
  });
  it('rejects an invalid signature', () => {
    expect(() =>
      service.verify({
        secret,
        timestamp: Date.now().toString(),
        eventId: 'evt-2',
        signature: '00'.repeat(32),
        payload: { status: 'DELIVERED' },
      }),
    ).toThrow(UnauthorizedException);
  });
});
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\common\notification-template-renderer.service.ts" `
        @'
import {
  BadRequestException,
  Injectable,
} from '@nestjs/common';

@Injectable()
export class NotificationTemplateRendererService {
  render(
    template: string,
    variables: Record<string, unknown>,
  ): string {
    return template.replace(
      /\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g,
      (_match, path: string) => {
        const value = this.resolvePath(variables, path);

        if (value === undefined || value === null) {
          throw new BadRequestException(
            `Template variable "${path}" is required.`,
          );
        }

        return typeof value === 'object'
          ? JSON.stringify(value)
          : String(value);
      },
    );
  }

  referencedVariables(template: string): string[] {
    const values = new Set<string>();

    for (const match of template.matchAll(
      /\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g,
    )) {
      values.add(match[1]);
    }

    return Array.from(values).sort();
  }

  private resolvePath(
    variables: Record<string, unknown>,
    path: string,
  ): unknown {
    return path.split('.').reduce<unknown>(
      (current, segment) => {
        if (
          current === null ||
          typeof current !== 'object' ||
          Array.isArray(current)
        ) {
          return undefined;
        }

        return (current as Record<string, unknown>)[segment];
      },
      variables,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\common\notification-template-renderer.service.spec.ts" `
        @'
import { BadRequestException } from '@nestjs/common';
import { NotificationTemplateRendererService } from './notification-template-renderer.service';

describe('NotificationTemplateRendererService', () => {
  const service =
    new NotificationTemplateRendererService();

  it('renders nested variables', () => {
    expect(
      service.render(
        'Vehicle {{vehicle.name}} entered {{geofence}}.',
        {
          vehicle: { name: 'Dhaka-01' },
          geofence: 'Warehouse',
        },
      ),
    ).toBe(
      'Vehicle Dhaka-01 entered Warehouse.',
    );
  });

  it('rejects missing variables', () => {
    expect(() =>
      service.render('Hello {{name}}', {}),
    ).toThrow(BadRequestException);
  });
});
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\common\notification-access.service.ts" `
        @'
import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class NotificationDeliveryAccessService {
  constructor(private readonly prisma: PrismaService) {}

  isPlatformScoped(auth: AuthContext): boolean {
    return auth.roles.some(
      (role) => role.scopeType === 'PLATFORM',
    );
  }

  assertPlatform(auth: AuthContext): void {
    if (!this.isPlatformScoped(auth)) {
      throw new ForbiddenException(
        'This notification operation requires platform scope.',
      );
    }
  }

  actorOrganizationId(
    auth: AuthContext,
  ): string | undefined {
    return (
      auth.roles.find(
        (role) => role.scopeType === 'DEALER',
      )?.scopeId ?? auth.organizationIds[0]
    );
  }

  customerWhere(
    auth: AuthContext,
  ): Prisma.CustomerWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = auth.roles
      .filter((role) => role.scopeType === 'DEALER')
      .map((role) => role.scopeId);
    const customerIds = Array.from(
      new Set([
        ...auth.customerIds,
        ...auth.roles
          .filter(
            (role) => role.scopeType === 'CUSTOMER',
          )
          .map((role) => role.scopeId),
      ]),
    );
    const scopes: Prisma.CustomerWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push({
        managingDealerId: { in: dealerIds },
      });
    }

    if (customerIds.length > 0) {
      scopes.push({ id: { in: customerIds } });
    }

    return scopes.length > 0
      ? { OR: scopes }
      : { id: { in: [] } };
  }

  notificationWhere(
    auth: AuthContext,
  ): Prisma.NotificationWhereInput {
    return this.isPlatformScoped(auth)
      ? {}
      : { customer: this.customerWhere(auth) };
  }

  async assertCustomer(
    auth: AuthContext,
    customerId: string,
  ): Promise<void> {
    const customer =
      await this.prisma.customer.findFirst({
        where: {
          AND: [
            { id: customerId },
            this.customerWhere(auth),
          ],
        },
        select: { id: true },
      });

    if (!customer) {
      throw new ForbiddenException(
        'The customer is outside the authenticated scope.',
      );
    }
  }

  async assertNotification(
    auth: AuthContext,
    notificationId: string,
  ): Promise<{
    id: string;
    customerId: string;
    status: string;
  }> {
    const notification =
      await this.prisma.notification.findFirst({
        where: {
          AND: [
            { id: notificationId },
            this.notificationWhere(auth),
          ],
        },
        select: {
          id: true,
          customerId: true,
          status: true,
        },
      });

    if (!notification) {
      throw new NotFoundException(
        'Notification was not found within the authenticated scope.',
      );
    }

    return notification;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\common\notification-rate-limiter.service.ts" `
        @'
import {
  Injectable,
  OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import { randomUUID } from 'node:crypto';

@Injectable()
export class NotificationRateLimiterService
  implements OnModuleDestroy
{
  private readonly client: Redis;

  constructor(config: ConfigService) {
    this.client = new Redis(
      config.getOrThrow<string>('REDIS_URL'),
      {
        lazyConnect: true,
        maxRetriesPerRequest: 2,
        enableReadyCheck: true,
      },
    );
  }

  async acquireLock(
    key: string,
    ttlMilliseconds: number,
  ): Promise<string | null> {
    await this.ensureConnected();
    const token = randomUUID();
    const result = await this.client.set(
      key,
      token,
      'PX',
      ttlMilliseconds,
      'NX',
    );

    return result === 'OK' ? token : null;
  }

  async releaseLock(
    key: string,
    token: string,
  ): Promise<void> {
    await this.ensureConnected();
    await this.client.eval(
      `
      if redis.call('get', KEYS[1]) == ARGV[1] then
        return redis.call('del', KEYS[1])
      end
      return 0
      `,
      1,
      key,
      token,
    );
  }

  async consume(input: {
    key: string;
    limit: number;
    windowSeconds: number;
  }): Promise<boolean> {
    await this.ensureConnected();
    const count = await this.client.incr(input.key);

    if (count === 1) {
      await this.client.expire(
        input.key,
        input.windowSeconds,
      );
    }

    return count <= input.limit;
  }

  async onModuleDestroy(): Promise<void> {
    if (this.client.status !== 'end') {
      await this.client.quit();
    }
  }

  private async ensureConnected(): Promise<void> {
    if (this.client.status === 'wait') {
      await this.client.connect();
    }
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\adapters\sandbox-notification.adapter.ts" `
        @'
import { Injectable } from '@nestjs/common';
import type { NotificationChannel } from '../../generated/prisma/client';
import type {
  NotificationProviderAdapter,
  NotificationSendInput,
  NotificationSendResult,
} from '../common/notification-delivery.types';

@Injectable()
export class SandboxNotificationAdapter
  implements NotificationProviderAdapter
{
  readonly provider = 'SANDBOX';

  supports(channel: NotificationChannel): boolean {
    void channel;
    return true;
  }

  async send(
    input: NotificationSendInput,
  ): Promise<NotificationSendResult> {
    if (
      input.recipient
        .toLowerCase()
        .includes('force-fail')
    ) {
      throw new Error(
        'Sandbox provider was instructed to fail.',
      );
    }

    return {
      provider: this.provider,
      providerMessageId:
        `sandbox-${input.idempotencyKey}`,
      status:
        input.channel === 'IN_APP'
          ? 'DELIVERED'
          : 'SENT',
      responsePayload: {
        accepted: true,
        channel: input.channel,
      },
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\adapters\signed-notification-proxy.adapter.ts" `
        @'
import {
  BadGatewayException,
  Injectable,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type {
  NotificationChannel,
  Prisma,
} from '../../generated/prisma/client';
import { NotificationSignatureService } from '../common/notification-signature.service';
import type {
  NotificationSendInput,
  NotificationSendResult,
} from '../common/notification-delivery.types';

interface ProxyConfiguration {
  provider: string;
  url: string;
  secret: string;
}

@Injectable()
export class SignedNotificationProxyAdapter {
  private readonly timeoutMilliseconds: number;

  constructor(
    private readonly config: ConfigService,
    private readonly signatures: NotificationSignatureService,
  ) {
    this.timeoutMilliseconds = Number(
      this.config.get(
        'NOTIFICATION_PROVIDER_HTTP_TIMEOUT_MS',
        10000,
      ),
    );
  }

  isConfigured(channel: NotificationChannel): boolean {
    const configuration = this.configuration(channel);

    return (
      configuration.url.length > 0 &&
      configuration.secret.length >= 32
    );
  }

  providerFor(channel: NotificationChannel): string {
    return this.configuration(channel).provider;
  }

  async send(
    input: NotificationSendInput,
  ): Promise<NotificationSendResult> {
    const configuration = this.configuration(
      input.channel,
    );

    if (
      !configuration.url ||
      configuration.secret.length < 32
    ) {
      throw new BadGatewayException(
        `Notification provider ${configuration.provider} is not configured.`,
      );
    }

    const timestamp = Date.now().toString();
    const eventId = input.idempotencyKey;
    const payload = {
      notificationId: input.notificationId,
      idempotencyKey: input.idempotencyKey,
      channel: input.channel,
      recipient: input.recipient,
      subject: input.subject,
      content: input.content,
      callbackUrl: input.callbackUrl,
    };
    const signature = this.signatures.sign(
      configuration.secret,
      timestamp,
      eventId,
      payload,
    );
    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      this.timeoutMilliseconds,
    );

    try {
      const response = await fetch(configuration.url, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-solid-timestamp': timestamp,
          'x-solid-event-id': eventId,
          'x-solid-signature': signature,
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      const responseText = await response.text();
      let responseBody: Record<string, unknown> = {};

      if (responseText) {
        try {
          responseBody = JSON.parse(
            responseText,
          ) as Record<string, unknown>;
        } catch {
          responseBody = { raw: responseText };
        }
      }

      if (!response.ok) {
        throw new BadGatewayException(
          `${configuration.provider} returned HTTP ${response.status}.`,
        );
      }

      const providerMessageId =
        typeof responseBody.providerMessageId ===
        'string'
          ? responseBody.providerMessageId
          : typeof responseBody.messageId === 'string'
            ? responseBody.messageId
            : undefined;

      if (!providerMessageId) {
        throw new BadGatewayException(
          `${configuration.provider} did not return a provider message ID.`,
        );
      }

      return {
        provider: configuration.provider,
        providerMessageId,
        status:
          responseBody.status === 'DELIVERED'
            ? 'DELIVERED'
            : 'SENT',
        responsePayload: JSON.parse(
          JSON.stringify(responseBody),
        ) as Prisma.InputJsonValue,
      };
    } finally {
      clearTimeout(timer);
    }
  }

  secretForProvider(provider: string): string {
    const normalized = provider.toUpperCase();

    if (normalized === 'SANDBOX') {
      return this.config.getOrThrow<string>(
        'NOTIFICATION_SANDBOX_WEBHOOK_SECRET',
      );
    }

    if (normalized === 'SMS_PROXY') {
      return this.config.get<string>(
        'NOTIFICATION_SMS_PROXY_SECRET',
        '',
      );
    }

    if (normalized === 'EMAIL_PROXY') {
      return this.config.get<string>(
        'NOTIFICATION_EMAIL_PROXY_SECRET',
        '',
      );
    }

    if (normalized === 'PUSH_PROXY') {
      return this.config.get<string>(
        'NOTIFICATION_PUSH_PROXY_SECRET',
        '',
      );
    }

    throw new BadGatewayException(
      `Unsupported notification provider: ${provider}.`,
    );
  }

  private configuration(
    channel: NotificationChannel,
  ): ProxyConfiguration {
    if (
      channel === 'SMS' ||
      channel === 'WHATSAPP' ||
      channel === 'VOICE_CALL'
    ) {
      return {
        provider: 'SMS_PROXY',
        url: this.config.get<string>(
          'NOTIFICATION_SMS_PROXY_URL',
          '',
        ),
        secret: this.config.get<string>(
          'NOTIFICATION_SMS_PROXY_SECRET',
          '',
        ),
      };
    }

    if (channel === 'EMAIL') {
      return {
        provider: 'EMAIL_PROXY',
        url: this.config.get<string>(
          'NOTIFICATION_EMAIL_PROXY_URL',
          '',
        ),
        secret: this.config.get<string>(
          'NOTIFICATION_EMAIL_PROXY_SECRET',
          '',
        ),
      };
    }

    return {
      provider: 'PUSH_PROXY',
      url: this.config.get<string>(
        'NOTIFICATION_PUSH_PROXY_URL',
        '',
      ),
      secret: this.config.get<string>(
        'NOTIFICATION_PUSH_PROXY_SECRET',
        '',
      ),
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\adapters\notification-provider-registry.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import type { NotificationChannel } from '../../generated/prisma/client';
import { SandboxNotificationAdapter } from './sandbox-notification.adapter';
import { SignedNotificationProxyAdapter } from './signed-notification-proxy.adapter';
import type {
  NotificationSendInput,
  NotificationSendResult,
} from '../common/notification-delivery.types';

@Injectable()
export class NotificationProviderRegistryService {
  constructor(
    private readonly sandbox: SandboxNotificationAdapter,
    private readonly proxy: SignedNotificationProxyAdapter,
  ) {}

  providerFor(channel: NotificationChannel): string {
    return this.proxy.isConfigured(channel)
      ? this.proxy.providerFor(channel)
      : this.sandbox.provider;
  }

  async send(
    input: NotificationSendInput,
  ): Promise<NotificationSendResult> {
    return this.proxy.isConfigured(input.channel)
      ? this.proxy.send(input)
      : this.sandbox.send(input);
  }

  callbackSecret(provider: string): string {
    return this.proxy.secretForProvider(provider);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\dto\create-notification-template.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  Length,
  Matches,
  MaxLength,
} from 'class-validator';

const channels = [
  'PUSH',
  'SMS',
  'EMAIL',
  'IN_APP',
  'WHATSAPP',
  'VOICE_CALL',
] as const;

export class CreateNotificationTemplateDto {
  @ApiProperty({ example: 'tracking.critical-alert' })
  @IsString()
  @Length(3, 120)
  @Matches(/^[a-z0-9][a-z0-9._-]+$/)
  templateKey!: string;

  @ApiProperty({ enum: channels })
  @IsIn(channels)
  channel!: (typeof channels)[number];

  @ApiPropertyOptional({ default: 'en' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  locale?: string;

  @ApiProperty()
  @IsString()
  @Length(3, 160)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(240)
  subjectTemplate?: string;

  @ApiProperty()
  @IsString()
  @Length(1, 20000)
  bodyTemplate!: string;

  @ApiPropertyOptional({
    type: 'object',
    additionalProperties: true,
  })
  @IsOptional()
  @IsObject()
  variableSchema?: Record<string, unknown>;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  activate?: boolean;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\dto\notification-template-query.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class NotificationTemplateQueryDto {
  @ApiPropertyOptional({ default: 1 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @ApiPropertyOptional({ default: 25 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize = 25;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({
    enum: [
      'PUSH',
      'SMS',
      'EMAIL',
      'IN_APP',
      'WHATSAPP',
      'VOICE_CALL',
    ],
  })
  @IsOptional()
  @IsIn([
    'PUSH',
    'SMS',
    'EMAIL',
    'IN_APP',
    'WHATSAPP',
    'VOICE_CALL',
  ])
  channel?: string;

  @ApiPropertyOptional({
    enum: ['DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED'],
  })
  @IsOptional()
  @IsIn(['DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED'])
  status?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\dto\preview-notification-template.dto.ts" `
        @'
import { ApiProperty } from '@nestjs/swagger';
import { IsObject } from 'class-validator';

export class PreviewNotificationTemplateDto {
  @ApiProperty({
    type: 'object',
    additionalProperties: true,
  })
  @IsObject()
  variables!: Record<string, unknown>;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\dto\enqueue-template-notification.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  MaxLength,
} from 'class-validator';

export class EnqueueTemplateNotificationDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  userId?: string;

  @ApiProperty({
    enum: [
      'PUSH',
      'SMS',
      'EMAIL',
      'IN_APP',
      'WHATSAPP',
      'VOICE_CALL',
    ],
  })
  @IsIn([
    'PUSH',
    'SMS',
    'EMAIL',
    'IN_APP',
    'WHATSAPP',
    'VOICE_CALL',
  ])
  channel!:
    | 'PUSH'
    | 'SMS'
    | 'EMAIL'
    | 'IN_APP'
    | 'WHATSAPP'
    | 'VOICE_CALL';

  @ApiProperty()
  @IsString()
  @Length(1, 320)
  recipient!: string;

  @ApiProperty()
  @IsString()
  @Length(3, 120)
  templateKey!: string;

  @ApiPropertyOptional({ default: 'en' })
  @IsOptional()
  @IsString()
  @MaxLength(20)
  locale?: string;

  @ApiProperty({
    type: 'object',
    additionalProperties: true,
  })
  @IsObject()
  variables!: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  trackingEventId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  notificationRuleId?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\dto\run-notification-delivery.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  Max,
  Min,
} from 'class-validator';

export class RunNotificationDeliveryDto {
  @ApiPropertyOptional({ default: 25 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  batchSize?: number;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\dto\retry-notification.dto.ts" `
        @'
import { ApiProperty } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';

export class RetryNotificationDto {
  @ApiProperty()
  @IsString()
  @Length(3, 500)
  reason!: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\dto\notification-provider-callback.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  Length,
} from 'class-validator';

export class NotificationProviderCallbackDto {
  @ApiProperty()
  @IsString()
  @Length(1, 160)
  externalEventId!: string;

  @ApiProperty()
  @IsString()
  @Length(1, 200)
  providerMessageId!: string;

  @ApiProperty({
    enum: ['SENT', 'DELIVERED', 'FAILED'],
  })
  @IsIn(['SENT', 'DELIVERED', 'FAILED'])
  status!: 'SENT' | 'DELIVERED' | 'FAILED';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  occurredAt?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  errorCode?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  errorMessage?: string;

  @ApiPropertyOptional({
    type: 'object',
    additionalProperties: true,
  })
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\dto\notification-delivery-query.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class NotificationDeliveryQueryDto {
  @ApiPropertyOptional({ default: 1 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @ApiPropertyOptional({ default: 25 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize = 25;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({
    enum: [
      'QUEUED',
      'PROCESSING',
      'SENT',
      'DELIVERED',
      'FAILED',
      'CANCELLED',
    ],
  })
  @IsOptional()
  @IsIn([
    'QUEUED',
    'PROCESSING',
    'SENT',
    'DELIVERED',
    'FAILED',
    'CANCELLED',
  ])
  status?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\templates\notification-templates.service.ts" `
        @'
import {
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type {
  NotificationChannel,
  Prisma,
} from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { NotificationDeliveryAccessService } from '../common/notification-access.service';
import { NotificationCodeService } from '../common/notification-code.service';
import { NotificationTemplateRendererService } from '../common/notification-template-renderer.service';
import type { CreateNotificationTemplateDto } from '../dto/create-notification-template.dto';
import type { NotificationTemplateQueryDto } from '../dto/notification-template-query.dto';

@Injectable()
export class NotificationTemplatesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: NotificationDeliveryAccessService,
    private readonly codes: NotificationCodeService,
    private readonly renderer: NotificationTemplateRendererService,
    private readonly audit: AuditService,
  ) {}

  async list(
    auth: AuthContext,
    query: NotificationTemplateQueryDto,
  ) {
    this.access.assertPlatform(auth);
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.NotificationTemplateWhereInput = {
      channel: query.channel as NotificationChannel | undefined,
      status: query.status as
        | 'DRAFT'
        | 'ACTIVE'
        | 'INACTIVE'
        | 'ARCHIVED'
        | undefined,
      OR: query.search
        ? [
            {
              templateKey: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              name: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
          ]
        : undefined,
    };
    const [items, total] = await Promise.all([
      this.prisma.notificationTemplate.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: [
          { templateKey: 'asc' },
          { channel: 'asc' },
          { locale: 'asc' },
          { version: 'desc' },
        ],
      }),
      this.prisma.notificationTemplate.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async createVersion(
    auth: AuthContext,
    dto: CreateNotificationTemplateDto,
  ) {
    this.access.assertPlatform(auth);
    const templateKey = dto.templateKey.trim().toLowerCase();
    const locale = (dto.locale ?? 'en')
      .trim()
      .toLowerCase();
    const versionAggregate =
      await this.prisma.notificationTemplate.aggregate({
        where: {
          templateKey,
          channel: dto.channel,
          locale,
        },
        _max: { version: true },
      });
    const version =
      (versionAggregate._max.version ?? 0) + 1;

    const template = await this.prisma.$transaction(
      async (transaction) => {
        if (dto.activate) {
          await transaction.notificationTemplate.updateMany({
            where: {
              templateKey,
              channel: dto.channel,
              locale,
              status: 'ACTIVE',
            },
            data: { status: 'INACTIVE' },
          });
        }

        return transaction.notificationTemplate.create({
          data: {
            templateCode: this.codes.template(),
            templateKey,
            channel: dto.channel,
            locale,
            version,
            name: dto.name.trim(),
            subjectTemplate:
              dto.subjectTemplate?.trim() || null,
            bodyTemplate: dto.bodyTemplate,
            variableSchema: dto.variableSchema
              ? (JSON.parse(
                  JSON.stringify(dto.variableSchema),
                ) as Prisma.InputJsonValue)
              : undefined,
            status: dto.activate ? 'ACTIVE' : 'DRAFT',
            createdByUserId: auth.userId,
            activatedAt: dto.activate ? new Date() : null,
          },
        });
      },
    );

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'notification.template.version-created',
      resourceType: 'NotificationTemplate',
      resourceId: template.id,
      metadata: {
        templateKey,
        channel: dto.channel,
        locale,
        version,
        status: template.status,
      },
    });

    return template;
  }

  async activate(
    auth: AuthContext,
    templateId: string,
  ) {
    this.access.assertPlatform(auth);
    const template =
      await this.prisma.notificationTemplate.findUnique({
        where: { id: templateId },
      });

    if (!template) {
      throw new NotFoundException(
        'Notification template was not found.',
      );
    }

    const activated = await this.prisma.$transaction(
      async (transaction) => {
        await transaction.notificationTemplate.updateMany({
          where: {
            templateKey: template.templateKey,
            channel: template.channel,
            locale: template.locale,
            status: 'ACTIVE',
            id: { not: template.id },
          },
          data: { status: 'INACTIVE' },
        });

        return transaction.notificationTemplate.update({
          where: { id: template.id },
          data: {
            status: 'ACTIVE',
            activatedAt: new Date(),
            archivedAt: null,
          },
        });
      },
    );

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'notification.template.activated',
      resourceType: 'NotificationTemplate',
      resourceId: activated.id,
      metadata: {
        templateKey: activated.templateKey,
        version: activated.version,
      },
    });

    return activated;
  }

  async archive(
    auth: AuthContext,
    templateId: string,
  ) {
    this.access.assertPlatform(auth);
    const existing =
      await this.prisma.notificationTemplate.findUnique({
        where: { id: templateId },
      });

    if (!existing) {
      throw new NotFoundException(
        'Notification template was not found.',
      );
    }

    const archived =
      await this.prisma.notificationTemplate.update({
        where: { id: templateId },
        data: {
          status: 'ARCHIVED',
          archivedAt: new Date(),
        },
      });

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'notification.template.archived',
      resourceType: 'NotificationTemplate',
      resourceId: archived.id,
    });

    return archived;
  }

  async preview(
    auth: AuthContext,
    templateId: string,
    variables: Record<string, unknown>,
  ) {
    this.access.assertPlatform(auth);
    const template =
      await this.prisma.notificationTemplate.findUnique({
        where: { id: templateId },
      });

    if (!template) {
      throw new NotFoundException(
        'Notification template was not found.',
      );
    }

    return {
      templateId: template.id,
      subject: template.subjectTemplate
        ? this.renderer.render(
            template.subjectTemplate,
            variables,
          )
        : null,
      content: this.renderer.render(
        template.bodyTemplate,
        variables,
      ),
      referencedVariables:
        this.renderer.referencedVariables(
          `${template.subjectTemplate ?? ''}\n${template.bodyTemplate}`,
        ),
    };
  }

  async renderActive(input: {
    templateKey: string;
    channel: NotificationChannel;
    locale: string;
    variables: Record<string, unknown>;
  }): Promise<{
    templateId: string;
    subject: string | null;
    content: string;
  }> {
    const template =
      await this.prisma.notificationTemplate.findFirst({
        where: {
          templateKey: input.templateKey
            .trim()
            .toLowerCase(),
          channel: input.channel,
          locale: input.locale.trim().toLowerCase(),
          status: 'ACTIVE',
        },
        orderBy: { version: 'desc' },
      });

    if (!template) {
      throw new NotFoundException(
        'An active notification template was not found.',
      );
    }

    return {
      templateId: template.id,
      subject: template.subjectTemplate
        ? this.renderer.render(
            template.subjectTemplate,
            input.variables,
          )
        : null,
      content: this.renderer.render(
        template.bodyTemplate,
        input.variables,
      ),
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\templates\notification-templates.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { CreateNotificationTemplateDto } from '../dto/create-notification-template.dto';
import { NotificationTemplateQueryDto } from '../dto/notification-template-query.dto';
import { PreviewNotificationTemplateDto } from '../dto/preview-notification-template.dto';
import { NotificationTemplatesService } from './notification-templates.service';

@ApiTags('Notification templates')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('notification-templates')
export class NotificationTemplatesController {
  constructor(
    private readonly templates: NotificationTemplatesService,
  ) {}

  @Get()
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'List versioned notification templates',
  })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: NotificationTemplateQueryDto,
  ) {
    return this.templates.list(auth, query);
  }

  @Post()
  @RequirePermissions('notification.template.manage')
  @ApiOperation({
    summary: 'Create a new immutable template version',
  })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateNotificationTemplateDto,
  ) {
    return this.templates.createVersion(auth, dto);
  }

  @Post(':templateId/activate')
  @RequirePermissions('notification.template.manage')
  @ApiOperation({
    summary: 'Activate one template version',
  })
  activate(
    @CurrentAuth() auth: AuthContext,
    @Param('templateId', new ParseUUIDPipe())
    templateId: string,
  ) {
    return this.templates.activate(auth, templateId);
  }

  @Post(':templateId/archive')
  @RequirePermissions('notification.template.manage')
  @ApiOperation({
    summary: 'Archive a template version',
  })
  archive(
    @CurrentAuth() auth: AuthContext,
    @Param('templateId', new ParseUUIDPipe())
    templateId: string,
  ) {
    return this.templates.archive(auth, templateId);
  }

  @Post(':templateId/preview')
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'Preview rendered template content',
  })
  preview(
    @CurrentAuth() auth: AuthContext,
    @Param('templateId', new ParseUUIDPipe())
    templateId: string,
    @Body() dto: PreviewNotificationTemplateDto,
  ) {
    return this.templates.preview(
      auth,
      templateId,
      dto.variables,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\delivery\notification-delivery-worker.service.ts" `
        @'
import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type {
  NotificationDeliveryAttempt,
  Prisma,
} from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import { NotificationProviderRegistryService } from '../adapters/notification-provider-registry.service';
import { NotificationRateLimiterService } from '../common/notification-rate-limiter.service';

@Injectable()
export class NotificationDeliveryWorkerService
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(
    NotificationDeliveryWorkerService.name,
  );
  private readonly enabled: boolean;
  private readonly intervalMilliseconds: number;
  private readonly defaultBatchSize: number;
  private readonly maxAttempts: number;
  private readonly retryBaseMilliseconds: number;
  private readonly callbackBaseUrl: string;
  private interval?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly registry: NotificationProviderRegistryService,
    private readonly rateLimiter: NotificationRateLimiterService,
    private readonly audit: AuditService,
  ) {
    this.enabled =
      String(
        this.config.get(
          'NOTIFICATION_DELIVERY_ENABLED',
          'false',
        ),
      ).toLowerCase() === 'true';
    this.intervalMilliseconds = Number(
      this.config.get(
        'NOTIFICATION_DELIVERY_INTERVAL_MS',
        5000,
      ),
    );
    this.defaultBatchSize = Number(
      this.config.get(
        'NOTIFICATION_DELIVERY_BATCH_SIZE',
        25,
      ),
    );
    this.maxAttempts = Number(
      this.config.get(
        'NOTIFICATION_DELIVERY_MAX_ATTEMPTS',
        5,
      ),
    );
    this.retryBaseMilliseconds = Number(
      this.config.get(
        'NOTIFICATION_DELIVERY_RETRY_BASE_MS',
        30000,
      ),
    );
    this.callbackBaseUrl =
      this.config.getOrThrow<string>(
        'NOTIFICATION_CALLBACK_BASE_URL',
      );
  }

  onModuleInit(): void {
    if (!this.enabled) {
      return;
    }

    this.interval = setInterval(() => {
      void this.runBatch().catch((error: unknown) => {
        this.logger.error(
          'Notification delivery interval failed.',
          error instanceof Error
            ? error.stack
            : String(error),
        );
      });
    }, this.intervalMilliseconds);
    this.interval.unref();
  }

  onModuleDestroy(): void {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }

  async runBatch(
    requestedBatchSize?: number,
  ): Promise<{
    claimed: number;
    succeeded: number;
    failed: number;
    deadLettered: number;
    skipped: number;
  }> {
    const batchSize = Math.min(
      Math.max(
        requestedBatchSize ?? this.defaultBatchSize,
        1,
      ),
      200,
    );
    const lockKey =
      'solid-tracker:notification-delivery:worker';
    const lockToken =
      await this.rateLimiter.acquireLock(
        lockKey,
        Math.max(
          this.intervalMilliseconds * 2,
          30000,
        ),
      );

    if (!lockToken) {
      return {
        claimed: 0,
        succeeded: 0,
        failed: 0,
        deadLettered: 0,
        skipped: 1,
      };
    }

    try {
      await this.recoverStaleProcessing();

      const queued =
        await this.prisma.notification.findMany({
          where: { status: 'QUEUED' },
          select: { id: true },
          orderBy: { queuedAt: 'asc' },
          take: batchSize,
        });
      const remaining = Math.max(
        batchSize - queued.length,
        0,
      );
      const dueAttempts =
        remaining > 0
          ? await this.prisma.notificationDeliveryAttempt.findMany(
              {
                where: {
                  status: 'FAILED',
                  nextRetryAt: { lte: new Date() },
                  notificationId: {
                    notIn: queued.map((item) => item.id),
                  },
                },
                select: { notificationId: true },
                orderBy: { nextRetryAt: 'asc' },
                take: remaining * 3,
              },
            )
          : [];
      const ids = Array.from(
        new Set([
          ...queued.map((item) => item.id),
          ...dueAttempts.map(
            (item) => item.notificationId,
          ),
        ]),
      ).slice(0, batchSize);
      const summary = {
        claimed: 0,
        succeeded: 0,
        failed: 0,
        deadLettered: 0,
        skipped: 0,
      };

      for (const notificationId of ids) {
        const result =
          await this.processNotification(
            notificationId,
          );

        if (result === 'SKIPPED') {
          summary.skipped += 1;
          continue;
        }

        summary.claimed += 1;

        if (result === 'SUCCEEDED') {
          summary.succeeded += 1;
        } else if (result === 'DEAD_LETTER') {
          summary.deadLettered += 1;
        } else {
          summary.failed += 1;
        }
      }

      return summary;
    } finally {
      await this.rateLimiter.releaseLock(
        lockKey,
        lockToken,
      );
    }
  }

  private async processNotification(
    notificationId: string,
  ): Promise<
    'SUCCEEDED' | 'FAILED' | 'DEAD_LETTER' | 'SKIPPED'
  > {
    const notification =
      await this.prisma.notification.findUnique({
        where: { id: notificationId },
      });

    if (
      !notification ||
      !['QUEUED', 'FAILED'].includes(
        notification.status,
      )
    ) {
      return 'SKIPPED';
    }

    const manualRetry =
      notification.failureReason ===
      'MANUAL_RETRY';
    const previousAttemptCount =
      await this.prisma.notificationDeliveryAttempt.count(
        {
          where: { notificationId },
        },
      );

    if (
      previousAttemptCount >= this.maxAttempts &&
      !manualRetry
    ) {
      await this.prisma.notification.update({
        where: { id: notificationId },
        data: {
          status: 'FAILED',
          failedAt: new Date(),
          failureReason:
            'DEAD_LETTER: maximum delivery attempts reached.',
        },
      });

      return 'DEAD_LETTER';
    }

    const claimed =
      await this.prisma.notification.updateMany({
        where: {
          id: notificationId,
          status: notification.status,
        },
        data: {
          status: 'PROCESSING',
          processingAt: new Date(),
          failureReason: null,
        },
      });

    if (claimed.count !== 1) {
      return 'SKIPPED';
    }

    const attemptNumber =
      previousAttemptCount + 1;
    const provider = this.registry.providerFor(
      notification.channel,
    );
    const idempotencyKey =
      `${notification.id}:${attemptNumber}`;
    let attempt:
      | NotificationDeliveryAttempt
      | undefined;

    try {
      const allowed =
        await this.rateLimiter.consume({
          key:
            `solid-tracker:notification-rate:${provider}:` +
            notification.channel,
          limit: 120,
          windowSeconds: 60,
        });

      if (!allowed) {
        throw new Error(
          'Notification provider rate limit was exceeded.',
        );
      }

      attempt =
        await this.prisma.notificationDeliveryAttempt.create(
          {
            data: {
              notificationId: notification.id,
              attemptNumber,
              provider,
              idempotencyKey,
              status: 'PROCESSING',
              requestPayload: this.json({
                channel: notification.channel,
                recipient: notification.recipient,
                subject: notification.subject,
              }),
            },
          },
        );

      const result = await this.registry.send({
        notificationId: notification.id,
        idempotencyKey,
        channel: notification.channel,
        recipient: notification.recipient,
        subject: notification.subject,
        content: notification.renderedContent,
        callbackUrl:
          `${this.callbackBaseUrl}/` +
          encodeURIComponent(
            provider.toLowerCase(),
          ),
      });
      const now = new Date();

      await this.prisma.$transaction([
        this.prisma.notificationDeliveryAttempt.update({
          where: { id: attempt.id },
          data: {
            provider: result.provider,
            providerMessageId:
              result.providerMessageId,
            status:
              result.status === 'DELIVERED'
                ? 'DELIVERED'
                : 'SENT',
            responsePayload:
              result.responsePayload,
            completedAt: now,
          },
        }),
        this.prisma.notification.update({
          where: { id: notification.id },
          data: {
            provider: result.provider,
            providerMessageId:
              result.providerMessageId,
            status: result.status,
            sentAt: now,
            deliveredAt:
              result.status === 'DELIVERED'
                ? now
                : null,
            failedAt: null,
            failureReason: null,
          },
        }),
      ]);

      await this.audit.record({
        action: 'notification.delivery.sent',
        resourceType: 'Notification',
        resourceId: notification.id,
        correlationId: idempotencyKey,
        metadata: {
          attemptNumber,
          provider: result.provider,
          providerMessageId:
            result.providerMessageId,
          status: result.status,
        },
      });

      return 'SUCCEEDED';
    } catch (error: unknown) {
      const message =
        error instanceof Error
          ? error.message
          : String(error);
      const deadLetter =
        attemptNumber >= this.maxAttempts;
      const nextRetryAt = deadLetter
        ? null
        : new Date(
            Date.now() +
              this.retryDelay(attemptNumber),
          );

      if (!attempt) {
        await this.prisma.notificationDeliveryAttempt.create(
            {
              data: {
                notificationId: notification.id,
                attemptNumber,
                provider,
                idempotencyKey,
                status: deadLetter
                  ? 'DEAD_LETTER'
                  : 'FAILED',
                errorMessage: message,
                nextRetryAt,
                completedAt: new Date(),
              },
            },
          );
      } else {
        await this.prisma.notificationDeliveryAttempt.update(
          {
            where: { id: attempt.id },
            data: {
              status: deadLetter
                ? 'DEAD_LETTER'
                : 'FAILED',
              errorMessage: message,
              nextRetryAt,
              completedAt: new Date(),
            },
          },
        );
      }

      await this.prisma.notification.update({
        where: { id: notification.id },
        data: {
          status: 'FAILED',
          failedAt: new Date(),
          failureReason: deadLetter
            ? `DEAD_LETTER: ${message}`
            : message,
        },
      });

      await this.audit.record({
        action: deadLetter
          ? 'notification.delivery.dead-lettered'
          : 'notification.delivery.failed',
        resourceType: 'Notification',
        resourceId: notification.id,
        correlationId: idempotencyKey,
        metadata: {
          attemptNumber,
          provider,
          error: message,
          nextRetryAt:
            nextRetryAt?.toISOString() ?? null,
        },
      });

      return deadLetter
        ? 'DEAD_LETTER'
        : 'FAILED';
    }
  }

  private async recoverStaleProcessing(): Promise<void> {
    const staleBefore = new Date(
      Date.now() -
        Math.max(
          this.intervalMilliseconds * 4,
          5 * 60 * 1000,
        ),
    );
    const stale =
      await this.prisma.notification.findMany({
        where: {
          status: 'PROCESSING',
          processingAt: { lt: staleBefore },
        },
        select: { id: true },
        take: 100,
      });

    if (stale.length === 0) {
      return;
    }

    const ids = stale.map((item) => item.id);
    const now = new Date();

    await this.prisma.$transaction([
      this.prisma.notification.updateMany({
        where: { id: { in: ids } },
        data: {
          status: 'FAILED',
          failedAt: now,
          failureReason:
            'Delivery processing lease expired.',
        },
      }),
      this.prisma.notificationDeliveryAttempt.updateMany(
        {
          where: {
            notificationId: { in: ids },
            status: 'PROCESSING',
          },
          data: {
            status: 'FAILED',
            errorMessage:
              'Delivery processing lease expired.',
            nextRetryAt: now,
            completedAt: now,
          },
        },
      ),
    ]);
  }

  private retryDelay(
    attemptNumber: number,
  ): number {
    const exponent = Math.max(
      attemptNumber - 1,
      0,
    );
    const base =
      this.retryBaseMilliseconds *
      2 ** exponent;
    const capped = Math.min(
      base,
      24 * 60 * 60 * 1000,
    );
    const jitter = Math.floor(capped * 0.1);

    return (
      capped +
      Math.floor(Math.random() * Math.max(jitter, 1))
    );
  }

  private json(
    value: unknown,
  ): Prisma.InputJsonValue {
    return JSON.parse(
      JSON.stringify(value),
    ) as Prisma.InputJsonValue;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\delivery\notification-delivery.service.ts" `
        @'
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { NotificationStatus } from '../../generated/prisma/client';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { NotificationProviderRegistryService } from '../adapters/notification-provider-registry.service';
import { NotificationDeliveryAccessService } from '../common/notification-access.service';
import { NotificationCodeService } from '../common/notification-code.service';
import { NotificationSignatureService } from '../common/notification-signature.service';
import type { EnqueueTemplateNotificationDto } from '../dto/enqueue-template-notification.dto';
import type { NotificationDeliveryQueryDto } from '../dto/notification-delivery-query.dto';
import type { NotificationProviderCallbackDto } from '../dto/notification-provider-callback.dto';
import type { RetryNotificationDto } from '../dto/retry-notification.dto';
import { NotificationTemplatesService } from '../templates/notification-templates.service';
import { NotificationDeliveryWorkerService } from './notification-delivery-worker.service';

@Injectable()
export class NotificationDeliveryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: NotificationDeliveryAccessService,
    private readonly codes: NotificationCodeService,
    private readonly templates: NotificationTemplatesService,
    private readonly worker: NotificationDeliveryWorkerService,
    private readonly registry: NotificationProviderRegistryService,
    private readonly signatures: NotificationSignatureService,
    private readonly audit: AuditService,
  ) {}

  async list(
    auth: AuthContext,
    query: NotificationDeliveryQueryDto,
  ) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.NotificationWhereInput = {
      AND: [
        this.access.notificationWhere(auth),
        query.status
          ? {
              status: query.status as NotificationStatus,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  notificationCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  recipient: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  providerMessageId: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };
    const [items, total] = await Promise.all([
      this.prisma.notification.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: { queuedAt: 'desc' },
        include: {
          customer: {
            select: {
              id: true,
              customerCode: true,
              primaryMobile: true,
              individualProfile: {
                select: { fullName: true },
              },
              organizationProfile: {
                select: { displayName: true },
              },
            },
          },
          user: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
        },
      }),
      this.prisma.notification.count({ where }),
    ]);

    const latestAttempts =
      await this.prisma.notificationDeliveryAttempt.findMany(
        {
          where: {
            notificationId: {
              in: items.map((item) => item.id),
            },
          },
          orderBy: [
            { notificationId: 'asc' },
            { attemptNumber: 'desc' },
          ],
        },
      );
    const latestByNotification = new Map<
      string,
      (typeof latestAttempts)[number]
    >();

    for (const attempt of latestAttempts) {
      if (
        !latestByNotification.has(
          attempt.notificationId,
        )
      ) {
        latestByNotification.set(
          attempt.notificationId,
          attempt,
        );
      }
    }

    return {
      items: items.map((item) => ({
        ...item,
        latestAttempt:
          latestByNotification.get(item.id) ?? null,
      })),
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async enqueue(
    auth: AuthContext,
    dto: EnqueueTemplateNotificationDto,
  ) {
    await this.access.assertCustomer(
      auth,
      dto.customerId,
    );

    if (dto.userId) {
      const membership =
        await this.prisma.customerMembership.findFirst({
          where: {
            customerId: dto.customerId,
            userId: dto.userId,
            status: 'ACTIVE',
          },
          select: { id: true },
        });

      if (!membership) {
        throw new BadRequestException(
          'Notification user must be an active customer member.',
        );
      }
    }

    const rendered = await this.templates.renderActive({
      templateKey: dto.templateKey,
      channel: dto.channel,
      locale: dto.locale ?? 'en',
      variables: dto.variables,
    });
    const notification =
      await this.prisma.notification.create({
        data: {
          notificationCode:
            this.codes.notification(),
          customerId: dto.customerId,
          userId: dto.userId,
          trackingEventId: dto.trackingEventId,
          notificationRuleId:
            dto.notificationRuleId,
          channel: dto.channel,
          recipient: dto.recipient.trim(),
          subject: rendered.subject,
          renderedContent: rendered.content,
          status: 'QUEUED',
        },
      });

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'notification.delivery.enqueued',
      resourceType: 'Notification',
      resourceId: notification.id,
      metadata: {
        templateId: rendered.templateId,
        channel: notification.channel,
        recipient: notification.recipient,
      },
    });

    return notification;
  }

  async attempts(
    auth: AuthContext,
    notificationId: string,
  ) {
    await this.access.assertNotification(
      auth,
      notificationId,
    );

    return this.prisma.notificationDeliveryAttempt.findMany(
      {
        where: { notificationId },
        orderBy: { attemptNumber: 'desc' },
      },
    );
  }

  async retry(
    auth: AuthContext,
    notificationId: string,
    dto: RetryNotificationDto,
  ) {
    this.access.assertPlatform(auth);
    const notification =
      await this.prisma.notification.findUnique({
        where: { id: notificationId },
      });

    if (!notification) {
      throw new NotFoundException(
        'Notification was not found.',
      );
    }

    if (
      !['FAILED', 'CANCELLED'].includes(
        notification.status,
      )
    ) {
      throw new BadRequestException(
        'Only failed or cancelled notifications can be retried.',
      );
    }

    const updated =
      await this.prisma.notification.update({
        where: { id: notificationId },
        data: {
          status: 'QUEUED',
          queuedAt: new Date(),
          processingAt: null,
          failedAt: null,
          failureReason: 'MANUAL_RETRY',
        },
      });

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'notification.delivery.retry-requested',
      resourceType: 'Notification',
      resourceId: notificationId,
      metadata: { reason: dto.reason },
    });

    return updated;
  }

  async run(
    auth: AuthContext,
    batchSize?: number,
  ) {
    this.access.assertPlatform(auth);
    const result =
      await this.worker.runBatch(batchSize);

    await this.audit.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'notification.delivery.batch-run',
      resourceType: 'NotificationDeliveryWorker',
      metadata: result,
    });

    return result;
  }

  async metrics(auth: AuthContext) {
    this.access.assertPlatform(auth);
    const [
      notificationCounts,
      attemptCounts,
      oldestQueued,
      providerEventFailures,
    ] = await Promise.all([
      this.prisma.notification.groupBy({
        by: ['status'],
        _count: { _all: true },
      }),
      this.prisma.notificationDeliveryAttempt.groupBy({
        by: ['status'],
        _count: { _all: true },
      }),
      this.prisma.notification.findFirst({
        where: { status: 'QUEUED' },
        orderBy: { queuedAt: 'asc' },
        select: { queuedAt: true },
      }),
      this.prisma.notificationProviderEvent.count({
        where: { status: 'FAILED' },
      }),
    ]);

    return {
      notifications: Object.fromEntries(
        notificationCounts.map((item) => [
          item.status,
          item._count._all,
        ]),
      ),
      attempts: Object.fromEntries(
        attemptCounts.map((item) => [
          item.status,
          item._count._all,
        ]),
      ),
      oldestQueuedAt:
        oldestQueued?.queuedAt ?? null,
      oldestQueuedAgeSeconds: oldestQueued
        ? Math.floor(
            (Date.now() -
              oldestQueued.queuedAt.getTime()) /
              1000,
          )
        : 0,
      providerEventFailures,
      generatedAt: new Date(),
    };
  }

  async deadLetters(
    auth: AuthContext,
    query: NotificationDeliveryQueryDto,
  ) {
    this.access.assertPlatform(auth);
    const skip = (query.page - 1) * query.pageSize;
    const [attempts, total] = await Promise.all([
      this.prisma.notificationDeliveryAttempt.findMany(
        {
          where: { status: 'DEAD_LETTER' },
          skip,
          take: query.pageSize,
          orderBy: { completedAt: 'desc' },
        },
      ),
      this.prisma.notificationDeliveryAttempt.count({
        where: { status: 'DEAD_LETTER' },
      }),
    ]);
    const notifications =
      await this.prisma.notification.findMany({
        where: {
          id: {
            in: attempts.map(
              (attempt) => attempt.notificationId,
            ),
          },
        },
      });
    const byId = new Map(
      notifications.map((item) => [
        item.id,
        item,
      ]),
    );

    return {
      items: attempts.map((attempt) => ({
        attempt,
        notification:
          byId.get(attempt.notificationId) ?? null,
      })),
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async callback(input: {
    provider: string;
    timestamp?: string;
    eventId?: string;
    signature?: string;
    dto: NotificationProviderCallbackDto;
  }) {
    const provider = input.provider.toUpperCase();
    const secret =
      this.registry.callbackSecret(provider);

    if (input.eventId !== input.dto.externalEventId) {
      throw new BadRequestException(
        'Callback event ID header does not match the payload.',
      );
    }

    this.signatures.verify({
      secret,
      timestamp: input.timestamp,
      eventId: input.eventId,
      signature: input.signature,
      payload: input.dto,
    });

    try {
      await this.prisma.notificationProviderEvent.create({
        data: {
          provider,
          externalEventId:
            input.dto.externalEventId,
          providerMessageId:
            input.dto.providerMessageId,
          eventType: input.dto.status,
          status: 'RECEIVED',
          signatureValid: true,
          payload: JSON.parse(
            JSON.stringify(input.dto),
          ) as Prisma.InputJsonValue,
        },
      });
    } catch (error: unknown) {
      if (
        error instanceof
          Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        return {
          accepted: true,
          idempotent: true,
          externalEventId:
            input.dto.externalEventId,
        };
      }

      throw error;
    }

    const attempt =
      await this.prisma.notificationDeliveryAttempt.findFirst(
        {
          where: {
            provider,
            providerMessageId:
              input.dto.providerMessageId,
          },
          orderBy: { attemptNumber: 'desc' },
        },
      );

    if (!attempt) {
      await this.prisma.notificationProviderEvent.update({
        where: {
          provider_externalEventId: {
            provider,
            externalEventId:
              input.dto.externalEventId,
          },
        },
        data: {
          status: 'FAILED',
          processedAt: new Date(),
          error:
            'Delivery attempt was not found for provider message ID.',
        },
      });

      throw new NotFoundException(
        'Delivery attempt was not found for the provider callback.',
      );
    }

    const now = input.dto.occurredAt
      ? new Date(input.dto.occurredAt)
      : new Date();
    const notificationUpdate:
      Prisma.NotificationUpdateInput = {};

    if (input.dto.status === 'SENT') {
      notificationUpdate.status = 'SENT';
      notificationUpdate.sentAt = now;
      notificationUpdate.failureReason = null;
    } else if (
      input.dto.status === 'DELIVERED'
    ) {
      notificationUpdate.status = 'DELIVERED';
      notificationUpdate.sentAt = now;
      notificationUpdate.deliveredAt = now;
      notificationUpdate.failureReason = null;
    } else {
      notificationUpdate.status = 'FAILED';
      notificationUpdate.failedAt = now;
      notificationUpdate.failureReason =
        input.dto.errorMessage ??
        'Notification provider reported failure.';
    }

    await this.prisma.$transaction([
      this.prisma.notification.update({
        where: { id: attempt.notificationId },
        data: notificationUpdate,
      }),
      this.prisma.notificationDeliveryAttempt.update({
        where: { id: attempt.id },
        data: {
          status: input.dto.status,
          errorCode: input.dto.errorCode,
          errorMessage: input.dto.errorMessage,
          responsePayload: JSON.parse(
            JSON.stringify(input.dto),
          ) as Prisma.InputJsonValue,
          completedAt: now,
        },
      }),
      this.prisma.notificationProviderEvent.update({
        where: {
          provider_externalEventId: {
            provider,
            externalEventId:
              input.dto.externalEventId,
          },
        },
        data: {
          notificationId:
            attempt.notificationId,
          status: 'PROCESSED',
          processedAt: new Date(),
        },
      }),
    ]);

    await this.audit.record({
      action: 'notification.delivery.callback-processed',
      resourceType: 'Notification',
      resourceId: attempt.notificationId,
      correlationId:
        input.dto.externalEventId,
      metadata: {
        provider,
        providerMessageId:
          input.dto.providerMessageId,
        status: input.dto.status,
      },
    });

    return {
      accepted: true,
      idempotent: false,
      notificationId:
        attempt.notificationId,
      status: input.dto.status,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\delivery\notification-delivery.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { EnqueueTemplateNotificationDto } from '../dto/enqueue-template-notification.dto';
import { NotificationDeliveryQueryDto } from '../dto/notification-delivery-query.dto';
import { RetryNotificationDto } from '../dto/retry-notification.dto';
import { RunNotificationDeliveryDto } from '../dto/run-notification-delivery.dto';
import { NotificationDeliveryService } from './notification-delivery.service';

@ApiTags('Notification delivery')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('notification-delivery')
export class NotificationDeliveryController {
  constructor(
    private readonly delivery: NotificationDeliveryService,
  ) {}

  @Get()
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'List scoped notification outbox records',
  })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: NotificationDeliveryQueryDto,
  ) {
    return this.delivery.list(auth, query);
  }

  @Post('enqueue')
  @RequirePermissions('notification.delivery.manage')
  @ApiOperation({
    summary: 'Enqueue a rendered template notification',
  })
  enqueue(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: EnqueueTemplateNotificationDto,
  ) {
    return this.delivery.enqueue(auth, dto);
  }

  @Post('run')
  @RequirePermissions('notification.delivery.manage')
  @ApiOperation({
    summary: 'Run one bounded notification delivery batch',
  })
  run(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: RunNotificationDeliveryDto,
  ) {
    return this.delivery.run(auth, dto.batchSize);
  }

  @Get('metrics')
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'Read notification delivery operational metrics',
  })
  metrics(@CurrentAuth() auth: AuthContext) {
    return this.delivery.metrics(auth);
  }

  @Get('dead-letters')
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'List dead-lettered delivery attempts',
  })
  deadLetters(
    @CurrentAuth() auth: AuthContext,
    @Query() query: NotificationDeliveryQueryDto,
  ) {
    return this.delivery.deadLetters(auth, query);
  }

  @Get(':notificationId/attempts')
  @RequirePermissions('notification.delivery.view')
  @ApiOperation({
    summary: 'List immutable delivery attempts',
  })
  attempts(
    @CurrentAuth() auth: AuthContext,
    @Param('notificationId', new ParseUUIDPipe())
    notificationId: string,
  ) {
    return this.delivery.attempts(
      auth,
      notificationId,
    );
  }

  @Post(':notificationId/retry')
  @RequirePermissions('notification.delivery.manage')
  @ApiOperation({
    summary: 'Manually retry a failed notification',
  })
  retry(
    @CurrentAuth() auth: AuthContext,
    @Param('notificationId', new ParseUUIDPipe())
    notificationId: string,
    @Body() dto: RetryNotificationDto,
  ) {
    return this.delivery.retry(
      auth,
      notificationId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\delivery\notification-provider-callback.controller.ts" `
        @'
import {
  Body,
  Controller,
  Headers,
  Param,
  Post,
} from '@nestjs/common';
import {
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { NotificationProviderCallbackDto } from '../dto/notification-provider-callback.dto';
import { NotificationDeliveryService } from './notification-delivery.service';

@ApiTags('Notification provider callbacks')
@Controller('notification-delivery/callbacks')
export class NotificationProviderCallbackController {
  constructor(
    private readonly delivery: NotificationDeliveryService,
  ) {}

  @Post(':provider')
  @ApiOperation({
    summary: 'Process a signed provider delivery callback',
  })
  callback(
    @Param('provider') provider: string,
    @Headers('x-solid-timestamp')
    timestamp: string | undefined,
    @Headers('x-solid-event-id')
    eventId: string | undefined,
    @Headers('x-solid-signature')
    signature: string | undefined,
    @Body() dto: NotificationProviderCallbackDto,
  ) {
    return this.delivery.callback({
      provider,
      timestamp,
      eventId,
      signature,
      dto,
    });
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\notification-delivery\notification-delivery.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { AuditModule } from '../identity/audit/audit.module';
import { NotificationProviderRegistryService } from './adapters/notification-provider-registry.service';
import { SandboxNotificationAdapter } from './adapters/sandbox-notification.adapter';
import { SignedNotificationProxyAdapter } from './adapters/signed-notification-proxy.adapter';
import { NotificationDeliveryAccessService } from './common/notification-access.service';
import { NotificationCodeService } from './common/notification-code.service';
import { NotificationRateLimiterService } from './common/notification-rate-limiter.service';
import { NotificationSignatureService } from './common/notification-signature.service';
import { NotificationTemplateRendererService } from './common/notification-template-renderer.service';
import { NotificationDeliveryController } from './delivery/notification-delivery.controller';
import { NotificationDeliveryService } from './delivery/notification-delivery.service';
import { NotificationDeliveryWorkerService } from './delivery/notification-delivery-worker.service';
import { NotificationProviderCallbackController } from './delivery/notification-provider-callback.controller';
import { NotificationTemplatesController } from './templates/notification-templates.controller';
import { NotificationTemplatesService } from './templates/notification-templates.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [
    NotificationTemplatesController,
    NotificationDeliveryController,
    NotificationProviderCallbackController,
  ],
  providers: [
    NotificationDeliveryAccessService,
    NotificationCodeService,
    NotificationSignatureService,
    NotificationTemplateRendererService,
    NotificationRateLimiterService,
    SandboxNotificationAdapter,
    SignedNotificationProxyAdapter,
    NotificationProviderRegistryService,
    NotificationTemplatesService,
    NotificationDeliveryWorkerService,
    NotificationDeliveryService,
  ],
  exports: [
    NotificationSignatureService,
    NotificationTemplatesService,
    NotificationDeliveryWorkerService,
  ],
})
export class NotificationDeliveryModule {}
'@

    Write-Utf8File `
        "services\backend-api\test\notification-delivery.e2e-spec.ts" `
        @'
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import {
  randomInt,
  randomUUID,
} from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';
import { NotificationSignatureService } from '../src/notification-delivery/common/notification-signature.service';

describe('Notification delivery (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let signatures: NotificationSignatureService;
  let accessToken: string;
  let platformUserId: string;
  let platformMembershipId: string;
  let platformRoleAssignmentId: string;
  let customerId: string;
  let templateId: string;
  let notificationId: string;

  const numericSuffix = randomInt(
    10_000_000,
    100_000_000,
  ).toString();
  const codeSuffix = randomUUID()
    .replace(/-/g, '')
    .slice(0, 10)
    .toUpperCase();
  const mobileNumber = `+88015${numericSuffix}`;
  const password = 'SolidTrackerTest123';

  beforeAll(async () => {
    const moduleFixture: TestingModule =
      await Test.createTestingModule({
        imports: [AppModule],
      }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    signatures = app.get(
      NotificationSignatureService,
    );
    const passwordService = app.get(PasswordService);
    const passwordHash =
      await passwordService.hash(password);
    const platformOrganization =
      await prisma.organization.findUniqueOrThrow({
        where: { code: 'ORG-PLATFORM' },
      });
    const superAdminRole =
      await prisma.role.findUniqueOrThrow({
        where: { code: 'PLATFORM_SUPER_ADMIN' },
      });
    const user = await prisma.user.create({
      data: {
        userCode: `USR-NTF-${codeSuffix}`,
        fullName:
          'Notification Delivery E2E Administrator',
        mobileNumber,
        normalizedMobileNumber: mobileNumber,
        passwordHash,
        passwordChangedAt: new Date(),
        status: 'ACTIVE',
        mobileVerifiedAt: new Date(),
      },
    });

    platformUserId = user.id;

    const membership =
      await prisma.organizationMembership.create({
        data: {
          organizationId: platformOrganization.id,
          userId: user.id,
          membershipType: 'EMPLOYEE',
          status: 'ACTIVE',
          isPrimary: true,
          joinedAt: new Date(),
        },
      });

    platformMembershipId = membership.id;

    const assignment =
      await prisma.roleAssignment.create({
        data: {
          userId: user.id,
          roleId: superAdminRole.id,
          organizationMembershipId: membership.id,
          scopeType: 'PLATFORM',
          scopeId: platformOrganization.id,
          status: 'ACTIVE',
          assignedByUserId: user.id,
        },
      });

    platformRoleAssignmentId = assignment.id;

    const loginResponse =
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({
          mobileNumber,
          password,
          platform: 'WEB',
          deviceName:
            'Notification Delivery E2E',
          appVersion: 'test',
        })
        .expect(200);

    accessToken =
      loginResponse.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

    if (prisma) {
      if (templateId) {
        await prisma.notificationTemplate.update({
          where: { id: templateId },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (customerId) {
        await prisma.customer.update({
          where: { id: customerId },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (platformUserId) {
        await prisma.userSession.deleteMany({
          where: { userId: platformUserId },
        });
        await prisma.roleAssignment.deleteMany({
          where: {
            id: platformRoleAssignmentId,
          },
        });
        await prisma.organizationMembership.deleteMany({
          where: {
            id: platformMembershipId,
          },
        });
        await prisma.user.update({
          where: { id: platformUserId },
          data: {
            status: 'ARCHIVED',
            passwordHash: null,
            archivedAt: now,
          },
        });
      }
    }

    if (app) {
      await app.close();
    }
  });

  it('renders, dispatches, and idempotently confirms a notification', async () => {
    const customerResponse =
      await request(app.getHttpServer())
        .post('/api/v1/customers/individual')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          fullName:
            `Notification Customer ${codeSuffix}`,
          primaryMobile: `016${numericSuffix}`,
        })
        .expect(201);

    customerId = customerResponse.body.id as string;

    const templateResponse =
      await request(app.getHttpServer())
        .post('/api/v1/notification-templates')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          templateKey:
            `e2e.notification.${codeSuffix.toLowerCase()}`,
          channel: 'EMAIL',
          locale: 'en',
          name:
            `E2E Email Template ${codeSuffix}`,
          subjectTemplate:
            'Alert for {{customer.name}}',
          bodyTemplate:
            'Vehicle {{vehicle}} generated {{event}}.',
          variableSchema: {
            required: [
              'customer.name',
              'vehicle',
              'event',
            ],
          },
          activate: true,
        })
        .expect(201);

    templateId = templateResponse.body.id as string;

    const previewResponse =
      await request(app.getHttpServer())
        .post(
          `/api/v1/notification-templates/${templateId}/preview`,
        )
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          variables: {
            customer: { name: 'Test Customer' },
            vehicle: 'DHAKA-01',
            event: 'overspeed',
          },
        })
        .expect(201);

    expect(previewResponse.body.subject).toBe(
      'Alert for Test Customer',
    );

    const enqueueResponse =
      await request(app.getHttpServer())
        .post('/api/v1/notification-delivery/enqueue')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          customerId,
          channel: 'EMAIL',
          recipient: `notify-${codeSuffix}@example.com`,
          templateKey:
            `e2e.notification.${codeSuffix.toLowerCase()}`,
          locale: 'en',
          variables: {
            customer: { name: 'Test Customer' },
            vehicle: 'DHAKA-01',
            event: 'overspeed',
          },
        })
        .expect(201);

    notificationId =
      enqueueResponse.body.id as string;

    const runResponse =
      await request(app.getHttpServer())
        .post('/api/v1/notification-delivery/run')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({ batchSize: 200 })
        .expect(201);

    expect(runResponse.body.succeeded).toBeGreaterThanOrEqual(
      1,
    );

    const notification =
      await prisma.notification.findUniqueOrThrow({
        where: { id: notificationId },
      });

    expect(notification.status).toBe('SENT');
    expect(notification.provider).toBe('SANDBOX');
    expect(notification.providerMessageId).toBeTruthy();

    const attemptsResponse =
      await request(app.getHttpServer())
        .get(
          `/api/v1/notification-delivery/${notificationId}/attempts`,
        )
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .expect(200);

    expect(attemptsResponse.body).toHaveLength(1);
    expect(attemptsResponse.body[0].status).toBe(
      'SENT',
    );

    const callbackBody = {
      externalEventId:
        `NTF-E2E-${codeSuffix}-${randomUUID()}`,
      providerMessageId:
        notification.providerMessageId as string,
      status: 'DELIVERED',
      occurredAt: new Date().toISOString(),
      metadata: {
        source: 'e2e',
      },
    };
    const timestamp = Date.now().toString();
    const secret =
      process.env.NOTIFICATION_SANDBOX_WEBHOOK_SECRET;

    expect(secret).toBeDefined();

    const signature = signatures.sign(
      secret as string,
      timestamp,
      callbackBody.externalEventId,
      callbackBody,
    );

    const firstCallback =
      await request(app.getHttpServer())
        .post(
          '/api/v1/notification-delivery/callbacks/SANDBOX',
        )
        .set('x-solid-timestamp', timestamp)
        .set(
          'x-solid-event-id',
          callbackBody.externalEventId,
        )
        .set('x-solid-signature', signature)
        .send(callbackBody)
        .expect(201);

    expect(firstCallback.body.idempotent).toBe(
      false,
    );

    const duplicateCallback =
      await request(app.getHttpServer())
        .post(
          '/api/v1/notification-delivery/callbacks/SANDBOX',
        )
        .set('x-solid-timestamp', timestamp)
        .set(
          'x-solid-event-id',
          callbackBody.externalEventId,
        )
        .set('x-solid-signature', signature)
        .send(callbackBody)
        .expect(201);

    expect(
      duplicateCallback.body.idempotent,
    ).toBe(true);

    const delivered =
      await prisma.notification.findUniqueOrThrow({
        where: { id: notificationId },
      });

    expect(delivered.status).toBe('DELIVERED');
    expect(delivered.deliveredAt).not.toBeNull();

    const metricsResponse =
      await request(app.getHttpServer())
        .get('/api/v1/notification-delivery/metrics')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .expect(200);

    expect(
      metricsResponse.body.notifications.DELIVERED,
    ).toBeGreaterThanOrEqual(1);
  });
});
'@

    Write-Step 6 10 "Updating seed permissions and registering the module"

    $seedPath = "services/backend-api/prisma/seed.ts"
    $seedContent = Get-LfContent $seedPath

    if (-not $seedContent.Contains("'notification.template.manage'")) {
        $permissionMarker = @'
  ['command.engine_cutoff', 'Send engine-cutoff commands'],
] as const;
'@
        $permissionReplacement = @'
  ['command.engine_cutoff', 'Send engine-cutoff commands'],
  ['notification.template.manage', 'Manage notification templates'],
  ['notification.delivery.manage', 'Manage notification delivery'],
  ['notification.delivery.view', 'View notification delivery'],
] as const;
'@

        if (-not $seedContent.Contains($permissionMarker)) {
            throw "Could not locate the seed permission definition marker."
        }

        $seedContent = $seedContent.Replace(
            $permissionMarker,
            $permissionReplacement
        )

        $supportStart = $seedContent.IndexOf(
            "  PLATFORM_SUPPORT: [",
            [System.StringComparison]::Ordinal
        )
        $supportEnd = $seedContent.IndexOf(
            "`n  ],",
            $supportStart,
            [System.StringComparison]::Ordinal
        )

        if ($supportStart -lt 0 -or $supportEnd -lt 0) {
            throw "Could not locate the PLATFORM_SUPPORT permission block."
        }

        $supportBlock = $seedContent.Substring(
            $supportStart,
            $supportEnd - $supportStart
        )

        if (-not $supportBlock.Contains("'notification.delivery.view'")) {
            $supportBlock += "`n    'notification.delivery.view',"
            $seedContent = (
                $seedContent.Substring(0, $supportStart) +
                $supportBlock +
                $seedContent.Substring($supportEnd)
            )
        }

        Set-LfContent $seedPath $seedContent
        Write-Host "[UPDATED] $seedPath" -ForegroundColor Green
    }

    $appModulePath = "services/backend-api/src/app.module.ts"
    $appModuleContent = Get-LfContent $appModulePath
    $moduleImport =
        "import { NotificationDeliveryModule } from './notification-delivery/notification-delivery.module';"

    if (-not $appModuleContent.Contains($moduleImport)) {
        $moduleImportMarker =
            "import { Module } from '@nestjs/common';"

        if (-not $appModuleContent.Contains($moduleImportMarker)) {
            throw "Could not locate the NestJS Module import."
        }

        $appModuleContent = $appModuleContent.Replace(
            $moduleImportMarker,
            $moduleImportMarker + "`n" + $moduleImport
        )
    }

    if (
        -not $appModuleContent.Contains(
            "NotificationDeliveryModule,"
        )
    ) {
        $importsPattern = "(?ms)(imports:\s*\[\s*)"
        $importsMatch = [regex]::Match(
            $appModuleContent,
            $importsPattern
        )

        if (-not $importsMatch.Success) {
            throw "Could not locate AppModule imports."
        }

        $appModuleContent = (
            $appModuleContent.Substring(
                0,
                $importsMatch.Index + $importsMatch.Length
            ) +
            "NotificationDeliveryModule,`n    " +
            $appModuleContent.Substring(
                $importsMatch.Index + $importsMatch.Length
            )
        )
    }

    Set-LfContent $appModulePath $appModuleContent
    Write-Host "[UPDATED] $appModulePath" -ForegroundColor Green

    Write-Step 7 10 "Running complete Prisma and backend verification"

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

    Write-Step 8 10 "Verifying notification delivery invariants"

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
        throw "Notification delivery database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split("|")

    if ($parts.Count -ne 6) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTableCount = [int]$parts[0]
    $migrationCount = [int]$parts[1]
    $permissionCount = [int]$parts[2]
    $newTableCount = [int]$parts[3]
    $invariantIndexCount = [int]$parts[4]
    $foreignKeyCount = [int]$parts[5]

    if ($publicTableCount -lt 53) {
        throw "Expected at least 53 public tables."
    }

    if ($migrationCount -ne 6) {
        throw "Expected exactly 6 applied migrations."
    }

    if ($permissionCount -ne 3) {
        throw "Expected 3 active notification delivery permissions."
    }

    if ($newTableCount -ne 3) {
        throw "Expected 3 notification delivery tables."
    }

    if ($invariantIndexCount -ne 4) {
        throw "Expected 4 notification delivery invariant indexes."
    }

    if ($foreignKeyCount -ne 3) {
        throw "Expected 3 notification delivery foreign keys."
    }

    Write-Host "Public tables:              $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:         $migrationCount" -ForegroundColor Green
    Write-Host "Delivery permissions:       $permissionCount" -ForegroundColor Green
    Write-Host "Delivery tables:            $newTableCount" -ForegroundColor Green
    Write-Host "Delivery invariant indexes: $invariantIndexCount" -ForegroundColor Green
    Write-Host "Delivery foreign keys:      $foreignKeyCount" -ForegroundColor Green

    Write-Step 9 10 "Writing notification delivery architecture documentation"

    Write-Utf8File `
        "docs/architecture/notification-delivery.md" `
        @'
# Notification Delivery Platform

## Scope

This stage turns the existing `notifications` table into a production-oriented transactional outbox and adds durable delivery metadata.

It implements:

- immutable, versioned notification templates;
- active-template selection by key, channel, and locale;
- deterministic template rendering;
- SMS, email, push, WhatsApp, voice-call, and in-app provider boundaries;
- signed provider-proxy requests;
- HMAC-authenticated provider callbacks;
- durable, numbered delivery attempts;
- exponential retry with jitter;
- dead-letter handling and manual replay;
- Redis-backed worker locking and provider rate limiting;
- callback idempotency;
- delivery metrics and attempt history;
- sandbox provider E2E coverage.

## Data ownership

PostgreSQL owns templates, outbox records, attempts, provider events, callback idempotency, retry schedules, and dead-letter history.

Redis is used only for temporary distributed locks and rate-limit counters.

## Outbox lifecycle

```text
QUEUED
  → PROCESSING
  → SENT
  → DELIVERED
```

Failures create a numbered attempt record and schedule the next retry. After the configured attempt limit, the final attempt is marked `DEAD_LETTER`. Manual retry is explicit and audited.

## Provider isolation

Provider credentials and vendor-specific API shapes remain outside the notification domain.

The core API communicates with signed SMS, email, and push proxy boundaries. When proxies are not configured, the deterministic sandbox adapter supports local development and automated testing.

## Callback security

Callbacks require:

```text
x-solid-timestamp
x-solid-event-id
x-solid-signature
```

The signature covers the timestamp, event ID, and canonical JSON body. Provider events are deduplicated by the database unique key over provider and external event ID.

## Template versioning

Template versions are immutable. Activating one version automatically deactivates the previous active version for the same template key, channel, and locale.

A partial unique index enforces one active version per variant.

## Operations

The worker is disabled by default in local development:

```text
NOTIFICATION_DELIVERY_ENABLED=false
```

A bounded batch can be run through:

```text
POST /api/v1/notification-delivery/run
```
'@

    Write-Step 10 10 "Committing notification delivery platform"

    git add -- `
        ".env.example" `
        "docs/architecture/notification-delivery.md" `
        "scripts/solid-tracker-notification-delivery.ps1" `
        "scripts/solid-tracker-notification-delivery-recovery.ps1" `
        "services/backend-api/prisma/schema.prisma" `
        "services/backend-api/prisma/seed.ts" `
        "services/backend-api/prisma/migrations/20260714230000_notification_delivery_foundation/migration.sql" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/notification-delivery" `
        "services/backend-api/test/notification-delivery.e2e-spec.ts"

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
    git log --oneline --decorate --graph -10
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    Write-Host "Next implementation stage:" -ForegroundColor Yellow
    Write-Host (
        "Customer mobile API composition, dashboard read models, " +
        "real-time updates, and frontend-ready endpoints"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "NOTIFICATION DELIVERY PLATFORM FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "Do not run prisma migrate reset. Preserve all applied migrations."
    ) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
