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
        "?? scripts/solid-tracker-tracking-integration-foundation.ps1"
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
            "tracking-integration script."
        )
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Tracking Integration Foundation" -ForegroundColor Cyan
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
        ".gitattributes",
        "compose.yaml",
        "services\backend-api\package.json",
        "services\backend-api\prisma.config.ts",
        "services\backend-api\prisma\schema.prisma",
        "services\backend-api\prisma\migrations",
        "services\backend-api\src\database\prisma.service.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file or directory is missing: $requiredPath"
        }
    }

    Write-Step 1 10 `
        "Merging the billing foundation and creating the tracking branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/billing-foundation") {
        Assert-CleanExceptSelf

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        git merge-base --is-ancestor `
            feat/billing-foundation `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge billing foundation into main" {
                git merge `
                    --no-ff `
                    feat/billing-foundation `
                    -m "merge: integrate billing foundation"
            }
        }
        else {
            Write-Host (
                "Billing foundation is already contained in main."
            ) -ForegroundColor Green
        }

        $branchExists = git branch --list `
            "feat/tracking-integration-foundation"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing tracking branch" {
                git checkout feat/tracking-integration-foundation
            }
        }
        else {
            Invoke-CheckedCommand "Create tracking feature branch" {
                git checkout -b feat/tracking-integration-foundation
            }
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-CleanExceptSelf

        git merge-base --is-ancestor `
            feat/billing-foundation `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge billing foundation into main" {
                git merge `
                    --no-ff `
                    feat/billing-foundation `
                    -m "merge: integrate billing foundation"
            }
        }

        $branchExists = git branch --list `
            "feat/tracking-integration-foundation"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing tracking branch" {
                git checkout feat/tracking-integration-foundation
            }
        }
        else {
            Invoke-CheckedCommand "Create tracking feature branch" {
                git checkout -b feat/tracking-integration-foundation
            }
        }
    }
    elseif (
        $currentBranch -eq
        "feat/tracking-integration-foundation"
    ) {
        Assert-CleanExceptSelf

        Write-Host (
            "Already on feat/tracking-integration-foundation."
        ) -ForegroundColor Green
    }
    else {
        throw (
            "Expected feat/billing-foundation, main, or " +
            "feat/tracking-integration-foundation. " +
            "Current branch: $currentBranch"
        )
    }

    Write-Step 2 10 `
        "Validating PostgreSQL and existing Prisma migrations"

    $postgresHealth = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        solid-tracker-postgres 2>$null

    if (
        $LASTEXITCODE -ne 0 -or
        $postgresHealth.Trim() -ne "healthy"
    ) {
        throw "solid-tracker-postgres must be running and healthy."
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $existingMigrationCount = @(
        Get-ChildItem `
            -LiteralPath "services\backend-api\prisma\migrations" `
            -Directory
    ).Count

    if ($existingMigrationCount -lt 3) {
        throw (
            "Expected identity/customer, vehicle/device, and billing " +
            "migrations before starting tracking integration."
        )
    }

    Write-Host "PostgreSQL: healthy" -ForegroundColor Green
    Write-Host (
        "Existing migrations: $existingMigrationCount"
    ) -ForegroundColor Green

    Write-Step 3 10 `
        "Extending Prisma with Traccar, event, geofence, notification, and command entities"

    $schemaPath = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\schema.prisma"

    $schema = [System.IO.File]::ReadAllText($schemaPath)

    if (-not $schema.Contains("model TraccarServer {")) {
        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "Customer" `
            -Marker "trackingEvents" `
            -Fields @'
  trackingEvents    TrackingEvent[]
  geofences         Geofence[]
  notificationRules NotificationRule[]
  notifications     Notification[]
'@

        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "Vehicle" `
            -Marker "trackingEvents" `
            -Fields @'
  trackingEvents       TrackingEvent[]
  geofenceAssignments  VehicleGeofenceAssignment[]
  notificationRules    NotificationRule[]
  commandRequests      DeviceCommandRequest[]
'@

        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "Device" `
            -Marker "traccarMappings" `
            -Fields @'
  traccarMappings TraccarDeviceMapping[]
  trackingEvents  TrackingEvent[]
  commandRequests DeviceCommandRequest[]
'@

        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "User" `
            -Marker "acknowledgedTrackingEvents" `
            -Fields @'
  acknowledgedTrackingEvents TrackingEvent[]        @relation("TrackingEventAcknowledger")
  createdGeofences            Geofence[]             @relation("GeofenceCreator")
  createdNotificationRules    NotificationRule[]     @relation("NotificationRuleCreator")
  notificationRuleRecipients  NotificationRule[]     @relation("NotificationRuleRecipientUser")
  notifications               Notification[]         @relation("NotificationRecipientUser")
  requestedDeviceCommands     DeviceCommandRequest[] @relation("DeviceCommandRequester")
  approvedDeviceCommands      DeviceCommandRequest[] @relation("DeviceCommandApprover")
'@

        $trackingSchema = @'

enum TraccarServerStatus {
  ACTIVE
  INACTIVE
  DEGRADED
  MAINTENANCE
  ARCHIVED
}

enum TraccarHealthStatus {
  UNKNOWN
  UP
  DEGRADED
  DOWN
}

enum TraccarSyncStatus {
  PENDING
  SYNCED
  FAILED
  DISABLED
  DELETED_EXTERNALLY
}

enum TrackingEventSeverity {
  INFO
  WARNING
  CRITICAL
}

enum TrackingEventProcessingStatus {
  RECEIVED
  PROCESSING
  PROCESSED
  FAILED
  IGNORED
}

enum GeofenceGeometryType {
  CIRCLE
  POLYGON
  POLYLINE
}

enum GeofenceStatus {
  DRAFT
  ACTIVE
  INACTIVE
  ARCHIVED
}

enum GeofenceAssignmentStatus {
  ACTIVE
  INACTIVE
  ENDED
}

enum NotificationChannel {
  PUSH
  SMS
  EMAIL
  IN_APP
  WHATSAPP
  VOICE_CALL
}

enum NotificationRecipientType {
  USER
  CUSTOMER_OWNER
  CUSTOMER_ADMIN
  CUSTOM_ADDRESS
}

enum NotificationStatus {
  QUEUED
  PROCESSING
  SENT
  DELIVERED
  FAILED
  CANCELLED
}

enum DeviceCommandType {
  REQUEST_POSITION
  RESTART_DEVICE
  SET_REPORTING_INTERVAL
  ACTIVATE_RELAY
  DEACTIVATE_RELAY
  ENGINE_CUTOFF
  ENGINE_RESTORE
  CHANGE_SERVER
  CUSTOM
}

enum DeviceCommandStatus {
  PENDING_APPROVAL
  QUEUED
  SENT
  ACKNOWLEDGED
  COMPLETED
  FAILED
  CANCELLED
  EXPIRED
}

enum IntegrationJobType {
  CREATE_DEVICE
  UPDATE_DEVICE
  DISABLE_DEVICE
  SYNC_DEVICE
  FETCH_LATEST_POSITION
  PROCESS_EVENT
  SYNC_GEOFENCE
  SEND_COMMAND
  RETRY_FAILED_SYNC
}

enum IntegrationJobStatus {
  PENDING
  PROCESSING
  SUCCEEDED
  FAILED
  CANCELLED
  DEAD_LETTER
}

model TraccarServer {
  id                           String               @id @default(uuid()) @db.Uuid
  serverCode                   String               @unique @db.VarChar(60)
  name                         String               @db.VarChar(160)
  baseUrl                      String               @unique @db.VarChar(500)
  apiUsernameReference         String?              @db.VarChar(160)
  encryptedCredentialReference String
  status                       TraccarServerStatus  @default(ACTIVE)
  isDefault                    Boolean              @default(false)
  lastHealthCheckAt            DateTime?            @db.Timestamptz(3)
  lastHealthStatus             TraccarHealthStatus  @default(UNKNOWN)
  lastHealthError              String?
  createdAt                    DateTime             @default(now()) @db.Timestamptz(3)
  updatedAt                    DateTime             @updatedAt @db.Timestamptz(3)
  archivedAt                   DateTime?            @db.Timestamptz(3)

  deviceMappings TraccarDeviceMapping[]
  trackingEvents TrackingEvent[]
  geofences      Geofence[]
  commandRequests DeviceCommandRequest[]
  integrationJobs IntegrationJob[]

  @@index([status])
  @@map("traccar_servers")
}

model TraccarDeviceMapping {
  id                  String            @id @default(uuid()) @db.Uuid
  deviceId            String            @db.Uuid
  traccarServerId     String            @db.Uuid
  traccarDeviceId     BigInt
  traccarUniqueId     String            @db.VarChar(160)
  syncStatus          TraccarSyncStatus @default(PENDING)
  isPrimary           Boolean           @default(true)
  isActive            Boolean           @default(true)
  lastSyncAttemptAt   DateTime?         @db.Timestamptz(3)
  lastSyncedAt        DateTime?         @db.Timestamptz(3)
  lastSyncError       String?
  disabledAt          DateTime?         @db.Timestamptz(3)
  createdAt           DateTime          @default(now()) @db.Timestamptz(3)
  updatedAt           DateTime          @updatedAt @db.Timestamptz(3)

  device        Device         @relation(fields: [deviceId], references: [id], onDelete: Restrict)
  traccarServer TraccarServer  @relation(fields: [traccarServerId], references: [id], onDelete: Restrict)

  @@unique([deviceId, traccarServerId])
  @@unique([traccarServerId, traccarDeviceId])
  @@unique([traccarServerId, traccarUniqueId])
  @@index([syncStatus, isActive])
  @@map("traccar_device_mappings")
}

model TrackingEvent {
  id               String                        @id @default(uuid()) @db.Uuid
  eventCode        String                        @unique @db.VarChar(70)
  customerId       String                        @db.Uuid
  vehicleId        String                        @db.Uuid
  deviceId         String                        @db.Uuid
  traccarServerId  String?                       @db.Uuid
  traccarEventId   BigInt?
  deduplicationKey String                        @unique @db.VarChar(160)
  eventType        String                        @db.VarChar(100)
  severity         TrackingEventSeverity         @default(INFO)
  latitude         Decimal?                      @db.Decimal(10, 7)
  longitude        Decimal?                      @db.Decimal(10, 7)
  occurredAt       DateTime                      @db.Timestamptz(3)
  receivedAt       DateTime                      @default(now()) @db.Timestamptz(3)
  attributes       Json?
  processingStatus TrackingEventProcessingStatus @default(RECEIVED)
  processingError  String?
  acknowledgedAt   DateTime?                     @db.Timestamptz(3)
  acknowledgedByUserId String?                    @db.Uuid
  createdAt        DateTime                      @default(now()) @db.Timestamptz(3)
  updatedAt        DateTime                      @updatedAt @db.Timestamptz(3)

  customer       Customer       @relation(fields: [customerId], references: [id], onDelete: Restrict)
  vehicle        Vehicle        @relation(fields: [vehicleId], references: [id], onDelete: Restrict)
  device         Device         @relation(fields: [deviceId], references: [id], onDelete: Restrict)
  traccarServer  TraccarServer? @relation(fields: [traccarServerId], references: [id], onDelete: Restrict)
  acknowledgedBy User?          @relation("TrackingEventAcknowledger", fields: [acknowledgedByUserId], references: [id], onDelete: SetNull)
  notifications  Notification[]

  @@unique([traccarServerId, traccarEventId])
  @@index([customerId, occurredAt])
  @@index([vehicleId, occurredAt])
  @@index([deviceId, occurredAt])
  @@index([eventType, severity, occurredAt])
  @@index([processingStatus, receivedAt])
  @@map("tracking_events")
}

model Geofence {
  id                  String             @id @default(uuid()) @db.Uuid
  geofenceCode        String             @unique @db.VarChar(60)
  customerId          String             @db.Uuid
  name                String             @db.VarChar(160)
  normalizedName      String             @db.VarChar(160)
  description         String?
  geometryType        GeofenceGeometryType
  geometryData        Json
  status              GeofenceStatus     @default(DRAFT)
  traccarServerId     String?            @db.Uuid
  traccarGeofenceId   BigInt?
  syncStatus          TraccarSyncStatus  @default(PENDING)
  lastSyncAttemptAt   DateTime?          @db.Timestamptz(3)
  lastSyncedAt        DateTime?          @db.Timestamptz(3)
  lastSyncError       String?
  createdByUserId     String?            @db.Uuid
  createdAt           DateTime           @default(now()) @db.Timestamptz(3)
  updatedAt           DateTime           @updatedAt @db.Timestamptz(3)
  archivedAt          DateTime?          @db.Timestamptz(3)

  customer       Customer       @relation(fields: [customerId], references: [id], onDelete: Restrict)
  traccarServer  TraccarServer? @relation(fields: [traccarServerId], references: [id], onDelete: Restrict)
  createdBy      User?          @relation("GeofenceCreator", fields: [createdByUserId], references: [id], onDelete: SetNull)
  assignments    VehicleGeofenceAssignment[]

  @@unique([customerId, normalizedName])
  @@unique([traccarServerId, traccarGeofenceId])
  @@index([customerId, status])
  @@index([syncStatus])
  @@map("geofences")
}

model VehicleGeofenceAssignment {
  id           String                   @id @default(uuid()) @db.Uuid
  geofenceId   String                   @db.Uuid
  vehicleId    String                   @db.Uuid
  monitorEntry Boolean                  @default(true)
  monitorExit  Boolean                  @default(true)
  activeFrom   DateTime                 @default(now()) @db.Timestamptz(3)
  activeUntil  DateTime?                @db.Timestamptz(3)
  status       GeofenceAssignmentStatus @default(ACTIVE)
  createdAt    DateTime                 @default(now()) @db.Timestamptz(3)
  updatedAt    DateTime                 @updatedAt @db.Timestamptz(3)

  geofence Geofence @relation(fields: [geofenceId], references: [id], onDelete: Restrict)
  vehicle  Vehicle  @relation(fields: [vehicleId], references: [id], onDelete: Restrict)

  @@index([geofenceId, status])
  @@index([vehicleId, status])
  @@map("vehicle_geofence_assignments")
}

model NotificationRule {
  id                    String                    @id @default(uuid()) @db.Uuid
  ruleCode              String                    @unique @db.VarChar(60)
  customerId            String                    @db.Uuid
  vehicleId             String?                   @db.Uuid
  eventType             String                    @db.VarChar(100)
  minimumSeverity       TrackingEventSeverity     @default(INFO)
  channel               NotificationChannel
  recipientType         NotificationRecipientType
  recipientUserId       String?                   @db.Uuid
  recipientAddress      String?                   @db.VarChar(320)
  enabled               Boolean                   @default(true)
  quietHoursStartMinute Int?
  quietHoursEndMinute   Int?
  cooldownSeconds       Int                       @default(0)
  dailyLimit            Int?
  createdByUserId       String?                   @db.Uuid
  createdAt             DateTime                  @default(now()) @db.Timestamptz(3)
  updatedAt             DateTime                  @updatedAt @db.Timestamptz(3)
  archivedAt            DateTime?                 @db.Timestamptz(3)

  customer      Customer      @relation(fields: [customerId], references: [id], onDelete: Restrict)
  vehicle       Vehicle?      @relation(fields: [vehicleId], references: [id], onDelete: Restrict)
  recipientUser User?         @relation("NotificationRuleRecipientUser", fields: [recipientUserId], references: [id], onDelete: Restrict)
  createdBy     User?         @relation("NotificationRuleCreator", fields: [createdByUserId], references: [id], onDelete: SetNull)
  notifications Notification[]

  @@index([customerId, enabled])
  @@index([vehicleId, enabled])
  @@index([eventType, minimumSeverity, enabled])
  @@map("notification_rules")
}

model Notification {
  id                String             @id @default(uuid()) @db.Uuid
  notificationCode  String             @unique @db.VarChar(70)
  customerId        String             @db.Uuid
  userId            String?            @db.Uuid
  trackingEventId   String?            @db.Uuid
  notificationRuleId String?           @db.Uuid
  channel           NotificationChannel
  recipient         String             @db.VarChar(320)
  subject           String?            @db.VarChar(240)
  renderedContent   String
  status            NotificationStatus @default(QUEUED)
  provider          String?            @db.VarChar(120)
  providerMessageId String?            @db.VarChar(200)
  queuedAt          DateTime           @default(now()) @db.Timestamptz(3)
  processingAt      DateTime?          @db.Timestamptz(3)
  sentAt            DateTime?          @db.Timestamptz(3)
  deliveredAt       DateTime?          @db.Timestamptz(3)
  failedAt          DateTime?          @db.Timestamptz(3)
  failureReason     String?
  createdAt         DateTime           @default(now()) @db.Timestamptz(3)
  updatedAt         DateTime           @updatedAt @db.Timestamptz(3)

  customer        Customer          @relation(fields: [customerId], references: [id], onDelete: Restrict)
  user            User?             @relation("NotificationRecipientUser", fields: [userId], references: [id], onDelete: SetNull)
  trackingEvent   TrackingEvent?    @relation(fields: [trackingEventId], references: [id], onDelete: Restrict)
  notificationRule NotificationRule? @relation(fields: [notificationRuleId], references: [id], onDelete: Restrict)

  @@unique([provider, providerMessageId])
  @@index([customerId, status])
  @@index([userId, status])
  @@index([trackingEventId])
  @@index([status, queuedAt])
  @@map("notifications")
}

model DeviceCommandRequest {
  id                    String              @id @default(uuid()) @db.Uuid
  commandCode           String              @unique @db.VarChar(70)
  deviceId              String              @db.Uuid
  vehicleId             String?             @db.Uuid
  traccarServerId       String?             @db.Uuid
  requestedByUserId     String              @db.Uuid
  approvedByUserId      String?             @db.Uuid
  commandType           DeviceCommandType
  parameters            Json?
  reason                String
  status                DeviceCommandStatus @default(QUEUED)
  requiresApproval      Boolean             @default(false)
  approvedAt            DateTime?           @db.Timestamptz(3)
  traccarCommandId      BigInt?
  requestedAt           DateTime            @default(now()) @db.Timestamptz(3)
  sentAt                DateTime?           @db.Timestamptz(3)
  acknowledgedAt        DateTime?           @db.Timestamptz(3)
  completedAt           DateTime?           @db.Timestamptz(3)
  failedAt              DateTime?           @db.Timestamptz(3)
  failureReason         String?
  expiresAt             DateTime?           @db.Timestamptz(3)
  createdAt             DateTime            @default(now()) @db.Timestamptz(3)
  updatedAt             DateTime            @updatedAt @db.Timestamptz(3)

  device         Device         @relation(fields: [deviceId], references: [id], onDelete: Restrict)
  vehicle        Vehicle?       @relation(fields: [vehicleId], references: [id], onDelete: Restrict)
  traccarServer  TraccarServer? @relation(fields: [traccarServerId], references: [id], onDelete: Restrict)
  requestedBy    User           @relation("DeviceCommandRequester", fields: [requestedByUserId], references: [id], onDelete: Restrict)
  approvedBy     User?          @relation("DeviceCommandApprover", fields: [approvedByUserId], references: [id], onDelete: Restrict)

  @@unique([traccarServerId, traccarCommandId])
  @@index([deviceId, status])
  @@index([vehicleId, status])
  @@index([requestedByUserId, requestedAt])
  @@index([status, expiresAt])
  @@map("device_command_requests")
}

model IntegrationJob {
  id               String               @id @default(uuid()) @db.Uuid
  jobCode          String               @unique @db.VarChar(70)
  idempotencyKey   String?              @unique @db.VarChar(180)
  jobType          IntegrationJobType
  traccarServerId  String?              @db.Uuid
  entityType       String               @db.VarChar(100)
  entityId         String               @db.VarChar(100)
  status           IntegrationJobStatus @default(PENDING)
  priority         Int                  @default(100)
  attemptCount     Int                  @default(0)
  maximumAttempts  Int                  @default(5)
  nextAttemptAt    DateTime?            @db.Timestamptz(3)
  lockedAt         DateTime?            @db.Timestamptz(3)
  startedAt        DateTime?            @db.Timestamptz(3)
  completedAt      DateTime?            @db.Timestamptz(3)
  failedAt         DateTime?            @db.Timestamptz(3)
  lastError        String?
  payload          Json?
  result           Json?
  correlationId    String?              @db.VarChar(100)
  createdAt        DateTime             @default(now()) @db.Timestamptz(3)
  updatedAt        DateTime             @updatedAt @db.Timestamptz(3)

  traccarServer TraccarServer? @relation(fields: [traccarServerId], references: [id], onDelete: Restrict)

  @@index([status, priority, nextAttemptAt])
  @@index([traccarServerId, status])
  @@index([entityType, entityId])
  @@index([correlationId])
  @@map("integration_jobs")
}
'@

        $schema = (
            $schema.TrimEnd() +
            [Environment]::NewLine +
            $trackingSchema.TrimStart()
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
        Write-Host (
            "Tracking-integration schema already exists; preserving it."
        ) -ForegroundColor DarkYellow
    }

    Write-Step 4 10 `
        "Formatting and validating the tracking-integration schema"

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

    Write-Step 5 10 `
        "Creating and customizing the tracking-integration migration"

    $migrationRoot = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\migrations"

    $trackingMigration = Get-ChildItem `
        -LiteralPath $migrationRoot `
        -Directory |
        Where-Object {
            $_.Name -like "*_tracking_integration_foundation"
        } |
        Select-Object -First 1

    if (-not $trackingMigration) {
        Invoke-CheckedCommand "Prisma migration create-only" {
            pnpm.cmd `
                --filter "@solid-tracker/backend-api" `
                exec prisma migrate dev `
                --name tracking_integration_foundation `
                --create-only `
                --config prisma.config.ts
        }

        $trackingMigration = Get-ChildItem `
            -LiteralPath $migrationRoot `
            -Directory |
            Where-Object {
                $_.Name -like "*_tracking_integration_foundation"
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if (-not $trackingMigration) {
        throw (
            "The tracking-integration migration directory " +
            "was not created."
        )
    }

    $migrationSqlPath = Join-Path `
        $trackingMigration.FullName `
        "migration.sql"

    if (-not (Test-Path -LiteralPath $migrationSqlPath)) {
        throw "The tracking-integration migration.sql file is missing."
    }

    $migrationSql = [System.IO.File]::ReadAllText(
        $migrationSqlPath
    )

    $customMarker = (
        "-- Solid Tracker Phase 4 tracking-integration invariants."
    )

    if (-not $migrationSql.Contains($customMarker)) {
        $customSql = @'

-- Solid Tracker Phase 4 tracking-integration invariants.

ALTER TABLE "traccar_servers"
ADD CONSTRAINT "traccar_servers_archive_consistency"
CHECK (
  (
    "status" = 'ARCHIVED'
    AND "archivedAt" IS NOT NULL
  )
  OR
  (
    "status" <> 'ARCHIVED'
  )
);

ALTER TABLE "traccar_device_mappings"
ADD CONSTRAINT "traccar_device_mappings_state_consistency"
CHECK (
  (
    "isActive" = TRUE
    AND "disabledAt" IS NULL
    AND "syncStatus" <> 'DISABLED'
  )
  OR
  (
    "isActive" = FALSE
    AND "disabledAt" IS NOT NULL
  )
);

ALTER TABLE "tracking_events"
ADD CONSTRAINT "tracking_events_coordinates_valid"
CHECK (
  (
    "latitude" IS NULL
    AND "longitude" IS NULL
  )
  OR
  (
    "latitude" BETWEEN -90 AND 90
    AND "longitude" BETWEEN -180 AND 180
  )
);

ALTER TABLE "tracking_events"
ADD CONSTRAINT "tracking_events_acknowledgement_valid"
CHECK (
  (
    "acknowledgedAt" IS NULL
    AND "acknowledgedByUserId" IS NULL
  )
  OR
  (
    "acknowledgedAt" IS NOT NULL
    AND "acknowledgedByUserId" IS NOT NULL
  )
);

ALTER TABLE "geofences"
ADD CONSTRAINT "geofences_external_mapping_valid"
CHECK (
  (
    "traccarGeofenceId" IS NULL
    AND (
      "syncStatus" IN ('PENDING', 'FAILED', 'DISABLED')
      OR "traccarServerId" IS NOT NULL
    )
  )
  OR
  (
    "traccarGeofenceId" IS NOT NULL
    AND "traccarServerId" IS NOT NULL
  )
);

ALTER TABLE "vehicle_geofence_assignments"
ADD CONSTRAINT "vehicle_geofence_assignments_period_valid"
CHECK (
  (
    "activeUntil" IS NULL
    OR "activeUntil" > "activeFrom"
  )
  AND (
    "monitorEntry" = TRUE
    OR "monitorExit" = TRUE
  )
);

ALTER TABLE "notification_rules"
ADD CONSTRAINT "notification_rules_limits_valid"
CHECK (
  "cooldownSeconds" >= 0
  AND (
    "dailyLimit" IS NULL
    OR "dailyLimit" > 0
  )
  AND (
    (
      "quietHoursStartMinute" IS NULL
      AND "quietHoursEndMinute" IS NULL
    )
    OR
    (
      "quietHoursStartMinute" BETWEEN 0 AND 1439
      AND "quietHoursEndMinute" BETWEEN 0 AND 1439
    )
  )
);

ALTER TABLE "notification_rules"
ADD CONSTRAINT "notification_rules_recipient_valid"
CHECK (
  (
    "recipientType" = 'USER'
    AND "recipientUserId" IS NOT NULL
    AND "recipientAddress" IS NULL
  )
  OR
  (
    "recipientType" = 'CUSTOM_ADDRESS'
    AND "recipientUserId" IS NULL
    AND "recipientAddress" IS NOT NULL
  )
  OR
  (
    "recipientType" IN ('CUSTOMER_OWNER', 'CUSTOMER_ADMIN')
    AND "recipientUserId" IS NULL
    AND "recipientAddress" IS NULL
  )
);

ALTER TABLE "notifications"
ADD CONSTRAINT "notifications_status_timestamps_valid"
CHECK (
  (
    "status" = 'QUEUED'
    AND "processingAt" IS NULL
    AND "sentAt" IS NULL
    AND "deliveredAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'PROCESSING'
    AND "processingAt" IS NOT NULL
    AND "deliveredAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'SENT'
    AND "sentAt" IS NOT NULL
    AND "deliveredAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'DELIVERED'
    AND "sentAt" IS NOT NULL
    AND "deliveredAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'FAILED'
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" = 'CANCELLED'
  )
);

ALTER TABLE "device_command_requests"
ADD CONSTRAINT "device_command_requests_expiry_valid"
CHECK (
  "expiresAt" IS NULL
  OR "expiresAt" > "requestedAt"
);

ALTER TABLE "device_command_requests"
ADD CONSTRAINT "device_command_requests_approval_valid"
CHECK (
  (
    "requiresApproval" = FALSE
    AND "approvedByUserId" IS NULL
    AND "approvedAt" IS NULL
    AND "status" <> 'PENDING_APPROVAL'
  )
  OR
  (
    "requiresApproval" = TRUE
    AND (
      (
        "status" = 'PENDING_APPROVAL'
        AND "approvedByUserId" IS NULL
        AND "approvedAt" IS NULL
      )
      OR
      (
        "status" <> 'PENDING_APPROVAL'
        AND "approvedByUserId" IS NOT NULL
        AND "approvedAt" IS NOT NULL
        AND "approvedByUserId" <> "requestedByUserId"
      )
    )
  )
);

ALTER TABLE "device_command_requests"
ADD CONSTRAINT "device_command_requests_status_timestamps_valid"
CHECK (
  (
    "status" IN ('PENDING_APPROVAL', 'QUEUED')
    AND "sentAt" IS NULL
    AND "acknowledgedAt" IS NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'SENT'
    AND "sentAt" IS NOT NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'ACKNOWLEDGED'
    AND "sentAt" IS NOT NULL
    AND "acknowledgedAt" IS NOT NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'COMPLETED'
    AND "sentAt" IS NOT NULL
    AND "completedAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'FAILED'
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" IN ('CANCELLED', 'EXPIRED')
  )
);

ALTER TABLE "integration_jobs"
ADD CONSTRAINT "integration_jobs_attempts_valid"
CHECK (
  "priority" >= 0
  AND "attemptCount" >= 0
  AND "maximumAttempts" > 0
  AND "attemptCount" <= "maximumAttempts"
);

ALTER TABLE "integration_jobs"
ADD CONSTRAINT "integration_jobs_status_timestamps_valid"
CHECK (
  (
    "status" = 'PENDING'
    AND "startedAt" IS NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'PROCESSING'
    AND "startedAt" IS NOT NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'SUCCEEDED'
    AND "startedAt" IS NOT NULL
    AND "completedAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" IN ('FAILED', 'DEAD_LETTER')
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" = 'CANCELLED'
  )
);

CREATE UNIQUE INDEX
  "traccar_servers_one_active_default"
ON "traccar_servers" ("isDefault")
WHERE
  "isDefault" = TRUE
  AND "status" = 'ACTIVE';

CREATE UNIQUE INDEX
  "traccar_device_mappings_one_active_primary_per_device"
ON "traccar_device_mappings" ("deviceId")
WHERE
  "isPrimary" = TRUE
  AND "isActive" = TRUE
  AND "syncStatus" <> 'DISABLED';

CREATE UNIQUE INDEX
  "vehicle_geofence_assignments_one_active_pair"
ON "vehicle_geofence_assignments" ("geofenceId", "vehicleId")
WHERE "status" = 'ACTIVE';

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_traccar_mapping"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  server_status "TraccarServerStatus";
BEGIN
  SELECT "status"
  INTO server_status
  FROM "traccar_servers"
  WHERE "id" = NEW."traccarServerId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Traccar server % does not exist',
      NEW."traccarServerId";
  END IF;

  IF NEW."isActive" = TRUE
     AND server_status NOT IN ('ACTIVE', 'DEGRADED') THEN
    RAISE EXCEPTION
      'Active mappings require an active or degraded Traccar server';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "traccar_mappings_validate_server"
BEFORE INSERT OR UPDATE OF
  "traccarServerId",
  "isActive",
  "syncStatus"
ON "traccar_device_mappings"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_traccar_mapping"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_tracking_event"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vehicle_customer_id UUID;
BEGIN
  SELECT "customerId"
  INTO vehicle_customer_id
  FROM "vehicles"
  WHERE "id" = NEW."vehicleId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Vehicle % does not exist',
      NEW."vehicleId";
  END IF;

  IF vehicle_customer_id <> NEW."customerId" THEN
    RAISE EXCEPTION
      'Tracking event customer must own the vehicle';
  END IF;

  IF NEW."traccarServerId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "traccar_device_mappings"
       WHERE "deviceId" = NEW."deviceId"
         AND "traccarServerId" = NEW."traccarServerId"
     ) THEN
    RAISE EXCEPTION
      'Tracking event device is not mapped to the selected Traccar server';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "tracking_events_validate_context"
BEFORE INSERT OR UPDATE OF
  "customerId",
  "vehicleId",
  "deviceId",
  "traccarServerId"
ON "tracking_events"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_tracking_event"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_geofence"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."traccarServerId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "traccar_servers"
       WHERE "id" = NEW."traccarServerId"
         AND "status" IN ('ACTIVE', 'DEGRADED', 'MAINTENANCE')
     ) THEN
    RAISE EXCEPTION
      'Geofence references an unavailable Traccar server';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "geofences_validate_context"
BEFORE INSERT OR UPDATE OF
  "traccarServerId",
  "syncStatus"
ON "geofences"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_geofence"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_geofence_assignment"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  geofence_customer_id UUID;
  vehicle_customer_id UUID;
BEGIN
  SELECT "customerId"
  INTO geofence_customer_id
  FROM "geofences"
  WHERE "id" = NEW."geofenceId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Geofence % does not exist',
      NEW."geofenceId";
  END IF;

  SELECT "customerId"
  INTO vehicle_customer_id
  FROM "vehicles"
  WHERE "id" = NEW."vehicleId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Vehicle % does not exist',
      NEW."vehicleId";
  END IF;

  IF geofence_customer_id <> vehicle_customer_id THEN
    RAISE EXCEPTION
      'Geofence and vehicle must belong to the same customer';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "geofence_assignments_validate_context"
BEFORE INSERT OR UPDATE OF
  "geofenceId",
  "vehicleId"
ON "vehicle_geofence_assignments"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_geofence_assignment"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_notification_rule"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vehicle_customer_id UUID;
BEGIN
  IF NEW."vehicleId" IS NOT NULL THEN
    SELECT "customerId"
    INTO vehicle_customer_id
    FROM "vehicles"
    WHERE "id" = NEW."vehicleId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Vehicle % does not exist',
        NEW."vehicleId";
    END IF;

    IF vehicle_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Notification-rule vehicle must belong to the rule customer';
    END IF;
  END IF;

  IF NEW."recipientUserId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "customer_memberships"
       WHERE "customerId" = NEW."customerId"
         AND "userId" = NEW."recipientUserId"
         AND "status" = 'ACTIVE'
     ) THEN
    RAISE EXCEPTION
      'Notification recipient user must be an active customer member';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "notification_rules_validate_context"
BEFORE INSERT OR UPDATE OF
  "customerId",
  "vehicleId",
  "recipientUserId",
  "recipientType"
ON "notification_rules"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_notification_rule"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_notification"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  event_customer_id UUID;
  rule_customer_id UUID;
BEGIN
  IF NEW."trackingEventId" IS NOT NULL THEN
    SELECT "customerId"
    INTO event_customer_id
    FROM "tracking_events"
    WHERE "id" = NEW."trackingEventId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Tracking event % does not exist',
        NEW."trackingEventId";
    END IF;

    IF event_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Notification customer must match tracking-event customer';
    END IF;
  END IF;

  IF NEW."notificationRuleId" IS NOT NULL THEN
    SELECT "customerId"
    INTO rule_customer_id
    FROM "notification_rules"
    WHERE "id" = NEW."notificationRuleId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Notification rule % does not exist',
        NEW."notificationRuleId";
    END IF;

    IF rule_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Notification customer must match notification-rule customer';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "notifications_validate_context"
BEFORE INSERT OR UPDATE OF
  "customerId",
  "trackingEventId",
  "notificationRuleId"
ON "notifications"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_notification"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_device_command"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."commandType" IN ('ENGINE_CUTOFF', 'ENGINE_RESTORE') THEN
    IF NEW."requiresApproval" <> TRUE THEN
      RAISE EXCEPTION
        'Engine-control commands require approval';
    END IF;

    IF NEW."vehicleId" IS NULL THEN
      RAISE EXCEPTION
        'Engine-control commands require a vehicle';
    END IF;
  END IF;

  IF NEW."vehicleId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "vehicle_device_assignments"
       WHERE "vehicleId" = NEW."vehicleId"
         AND "deviceId" = NEW."deviceId"
         AND "status" = 'ACTIVE'
         AND "endedAt" IS NULL
     ) THEN
    RAISE EXCEPTION
      'Command device must be actively assigned to the selected vehicle';
  END IF;

  IF NEW."traccarServerId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "traccar_device_mappings"
       WHERE "deviceId" = NEW."deviceId"
         AND "traccarServerId" = NEW."traccarServerId"
         AND "isActive" = TRUE
     ) THEN
    RAISE EXCEPTION
      'Command device must have an active mapping on the selected server';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "device_commands_validate_context"
BEFORE INSERT OR UPDATE OF
  "deviceId",
  "vehicleId",
  "traccarServerId",
  "commandType",
  "requiresApproval",
  "approvedByUserId",
  "approvedAt",
  "status"
ON "device_command_requests"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_device_command"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_integration_job"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."traccarServerId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "traccar_servers"
       WHERE "id" = NEW."traccarServerId"
         AND "status" <> 'ARCHIVED'
     ) THEN
    RAISE EXCEPTION
      'Integration job references an unavailable Traccar server';
  END IF;

  IF NEW."status" IN ('FAILED', 'DEAD_LETTER')
     AND NEW."lastError" IS NULL THEN
    RAISE EXCEPTION
      'Failed integration jobs require an error message';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "integration_jobs_validate_context"
BEFORE INSERT OR UPDATE OF
  "traccarServerId",
  "status",
  "lastError"
ON "integration_jobs"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_integration_job"();
'@

        [System.IO.File]::AppendAllText(
            $migrationSqlPath,
            $customSql,
            $script:Utf8NoBom
        )

        Write-Host (
            "[CUSTOMIZED] " +
            $trackingMigration.Name +
            "\migration.sql"
        ) -ForegroundColor Green
    }
    else {
        Write-Host (
            "PostgreSQL-native tracking constraints already exist."
        ) -ForegroundColor DarkYellow
    }

    Write-Step 6 10 `
        "Applying migration and generating Prisma Client"

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

    Write-Step 7 10 "Running backend quality checks and tests"

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

    Write-Step 8 10 `
        "Verifying tracking tables, indexes, and distinct triggers"

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

    $verificationOutput = $verificationSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL tracking-integration verification failed."
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
    $trackingIndexCount = [int]$parts[1]
    $trackingTriggerCount = [int]$parts[2]

    if ($tableCount -lt 49) {
        throw (
            "Expected at least 49 public tables, but found " +
            $tableCount
        )
    }

    if ($trackingIndexCount -ne 3) {
        throw (
            "Expected 3 tracking invariant indexes, but found " +
            $trackingIndexCount
        )
    }

    if ($trackingTriggerCount -ne 8) {
        throw (
            "Expected 8 distinct tracking triggers, but found " +
            $trackingTriggerCount
        )
    }

    Write-Host (
        "Public tables:              $tableCount"
    ) -ForegroundColor Green

    Write-Host (
        "Tracking invariant indexes: $trackingIndexCount"
    ) -ForegroundColor Green

    Write-Host (
        "Distinct tracking triggers: $trackingTriggerCount"
    ) -ForegroundColor Green

    Write-Step 9 10 `
        "Writing tracking-integration architecture documentation"

    $documentation = @'
# Tracking Integration Foundation

## Scope

This migration introduces:

- `TraccarServer`
- `TraccarDeviceMapping`
- `TrackingEvent`
- `Geofence`
- `VehicleGeofenceAssignment`
- `NotificationRule`
- `Notification`
- `DeviceCommandRequest`
- `IntegrationJob`

## System ownership

```text
Traccar
→ raw positions, routes, trips, stops, and native telemetry

Solid Tracker PostgreSQL
→ device mappings, normalized business events, geofences,
  notification history, command requests, and integration jobs

Redis
→ latest telemetry cache, online/offline cache, cooldown state,
  queues, locks, and command timeouts
```

Android and web clients communicate with NestJS. NestJS applies authentication, permissions, scope, customer ownership, subscription entitlement, and safety rules before calling Traccar.

## Traccar servers and mappings

Multiple Traccar servers are represented, while only one active server may be marked as the default.

A device may have one mapping per server. Only one active primary mapping may exist for a device across the platform.

External Traccar IDs remain separate from Solid Tracker business IDs.

## Tracking events

A normalized tracking event records:

- customer;
- vehicle;
- device;
- source Traccar server and event ID;
- deduplication key;
- event type and severity;
- optional coordinates;
- occurrence and receipt times;
- processing and acknowledgement state.

The combination of Traccar server and external event ID is unique. A second deterministic deduplication key protects integrations where no reliable external event ID is available.

## Geofences

Solid Tracker owns geofence business configuration. Traccar performs geographic detection.

A geofence and assigned vehicle must belong to the same customer. Only one active assignment may exist for a given geofence and vehicle pair.

## Notifications

Notification rules specify:

- event type and minimum severity;
- channel;
- recipient strategy;
- optional vehicle boundary;
- quiet hours;
- cooldown;
- optional daily limit.

Notification records preserve rendered content and provider delivery history.

## Device commands

Every command preserves:

- requester;
- device and optional vehicle;
- parameters and business reason;
- Traccar server and command ID;
- approval and execution timestamps;
- final status and failure details.

Engine cutoff and engine restore commands require approval by another user and require the device to be actively assigned to the selected vehicle.

## Integration jobs

Integration jobs provide durable PostgreSQL history for asynchronous work. Redis may execute the live queue, while PostgreSQL retains idempotency, attempt counts, scheduling, status, error, result, entity, and correlation data.

## Database enforcement

PostgreSQL enforces:

- one active default Traccar server;
- one active primary mapping per device;
- event customer/vehicle consistency;
- mapping/server consistency;
- geofence/vehicle ownership;
- notification recipient consistency;
- safe command approval;
- active device/vehicle command assignment;
- integration retry and status invariants.
'@

    Write-Utf8File `
        "docs\architecture\tracking-integration-foundation.md" `
        $documentation

    Write-Step 10 10 `
        "Committing the tracking-integration foundation"

    git add --all

    git commit `
        -m "feat(tracking): establish Traccar integration foundation"

    if ($LASTEXITCODE -ne 0) {
        throw "Tracking-integration foundation commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Tracking Integration Foundation Ready" -ForegroundColor Cyan
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
        "NestJS identity and authorization modules, including users, " +
        "organizations, memberships, roles, permissions, and sessions"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "TRACKING INTEGRATION FOUNDATION FAILED" -ForegroundColor Red
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
