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

    $pattern = "(?ms)(model\s+" + [regex]::Escape($ModelName) + "\s+\{.*?)(\r?\n\})"
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

function Get-AllowedSelfStatus {
    return "?? scripts/solid-tracker-vehicle-device-foundation.ps1"
}

function Assert-CleanExceptSelf {
    $allowedSelfEntry = Get-AllowedSelfStatus
    $unexpectedChanges = @(
        git status --short |
            Where-Object {
                $_ -and $_.TrimEnd() -ne $allowedSelfEntry
            }
    )

    if ($unexpectedChanges.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow
        $unexpectedChanges | ForEach-Object {
            Write-Host $_ -ForegroundColor Yellow
        }

        throw "Working tree contains changes other than this Phase 2 script."
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Vehicle and Device Foundation" -ForegroundColor Cyan
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

    foreach ($requiredFile in @(
        ".env",
        "compose.yaml",
        "services\backend-api\package.json",
        "services\backend-api\prisma.config.ts",
        "services\backend-api\prisma\schema.prisma",
        "services\backend-api\src\database\prisma.service.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredFile)) {
            throw "Required file is missing: $requiredFile"
        }
    }

    Write-Step 1 10 "Merging the completed domain foundation and creating the asset branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/domain-model-foundation") {
        Assert-CleanExceptSelf

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        $alreadyMerged = $false
        git merge-base --is-ancestor feat/domain-model-foundation main

        if ($LASTEXITCODE -eq 0) {
            $alreadyMerged = $true
        }

        if (-not $alreadyMerged) {
            Invoke-CheckedCommand "Merge domain-model foundation into main" {
                git merge `
                    --no-ff `
                    feat/domain-model-foundation `
                    -m "merge: integrate domain and database foundation"
            }
        }
        else {
            Write-Host "Domain foundation is already contained in main." -ForegroundColor Green
        }

        $branchExists = git branch --list "feat/vehicle-device-foundation"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing vehicle-device branch" {
                git checkout feat/vehicle-device-foundation
            }
        }
        else {
            Invoke-CheckedCommand "Create vehicle-device feature branch" {
                git checkout -b feat/vehicle-device-foundation
            }
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-CleanExceptSelf

        $alreadyMerged = $false
        git merge-base --is-ancestor feat/domain-model-foundation main

        if ($LASTEXITCODE -eq 0) {
            $alreadyMerged = $true
        }

        if (-not $alreadyMerged) {
            Invoke-CheckedCommand "Merge domain-model foundation into main" {
                git merge `
                    --no-ff `
                    feat/domain-model-foundation `
                    -m "merge: integrate domain and database foundation"
            }
        }

        $branchExists = git branch --list "feat/vehicle-device-foundation"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing vehicle-device branch" {
                git checkout feat/vehicle-device-foundation
            }
        }
        else {
            Invoke-CheckedCommand "Create vehicle-device feature branch" {
                git checkout -b feat/vehicle-device-foundation
            }
        }
    }
    elseif ($currentBranch -eq "feat/vehicle-device-foundation") {
        Assert-CleanExceptSelf
        Write-Host "Already on feat/vehicle-device-foundation." -ForegroundColor Green
    }
    else {
        throw "Expected feat/domain-model-foundation, main, or feat/vehicle-device-foundation. Current branch: $currentBranch"
    }

    Write-Step 2 10 "Validating PostgreSQL and Prisma Phase 1"

    $postgresHealth = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        solid-tracker-postgres 2>$null

    if ($LASTEXITCODE -ne 0 -or $postgresHealth.Trim() -ne "healthy") {
        throw "solid-tracker-postgres must be running and healthy."
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $phase1Migration = Get-ChildItem `
        -LiteralPath "services\backend-api\prisma\migrations" `
        -Directory |
        Where-Object {
            $_.Name -like "*_identity_customer_foundation"
        } |
        Select-Object -First 1

    if (-not $phase1Migration) {
        throw "The Phase 1 identity/customer migration was not found."
    }

    Write-Host "PostgreSQL: healthy" -ForegroundColor Green
    Write-Host "Prisma Phase 1: applied" -ForegroundColor Green

    Write-Step 3 10 "Extending the Prisma schema with vehicle and device entities"

    $schemaPath = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\schema.prisma"

    $schema = [System.IO.File]::ReadAllText($schemaPath)

    if (-not $schema.Contains("model Vehicle {")) {
        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "Organization" `
            -Marker "ownedDeviceHistory" `
            -Fields @'
  ownedDeviceHistory       DeviceOwnershipHistory[] @relation("DeviceOwnerOrganization")
  custodiedDeviceHistory   DeviceCustodyHistory[]   @relation("DeviceCustodianOrganization")
  dealerDeviceAllocations  DealerDeviceAllocation[] @relation("DealerDeviceAllocationDealer")
  deviceInstallations      DeviceInstallation[]     @relation("InstallationDealer")
'@

        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "User" `
            -Marker "createdVehicles" `
            -Fields @'
  createdVehicles          Vehicle[]                @relation("VehicleCreator")
  changedDeviceOwnerships  DeviceOwnershipHistory[] @relation("DeviceOwnershipChanger")
  custodiedDeviceHistory   DeviceCustodyHistory[]   @relation("DeviceCustodianUser")
  changedDeviceCustodies   DeviceCustodyHistory[]   @relation("DeviceCustodyChanger")
  allocatedDevices         DealerDeviceAllocation[] @relation("DeviceAllocationAllocator")
  returnedDeviceAllocations DealerDeviceAllocation[] @relation("DeviceAllocationReturner")
  installedDevices         DeviceInstallation[]     @relation("InstallationInstaller")
  verifiedInstallations    DeviceInstallation[]     @relation("InstallationVerifier")
  assignedDeviceRelations  VehicleDeviceAssignment[] @relation("DeviceAssignmentAssigner")
  endedDeviceRelations     VehicleDeviceAssignment[] @relation("DeviceAssignmentEnder")
'@

        $schema = Add-PrismaFields `
            -Schema $schema `
            -ModelName "Customer" `
            -Marker "vehicles" `
            -Fields @'
  vehicles               Vehicle[]
  ownedDeviceHistory     DeviceOwnershipHistory[] @relation("DeviceOwnerCustomer")
  custodiedDeviceHistory DeviceCustodyHistory[]   @relation("DeviceCustodianCustomer")
'@

        $assetSchema = @'

enum VehicleType {
  CAR
  MOTORCYCLE
  BUS
  TRUCK
  CNG
  PICKUP
  MICROBUS
  AMBULANCE
  CONSTRUCTION_EQUIPMENT
  OTHER
}

enum VehicleStatus {
  PENDING
  ACTIVE
  INACTIVE
  SUSPENDED
  ARCHIVED
}

enum DeviceNetworkType {
  GSM_2G
  UMTS_3G
  LTE_4G
  LTE_5G
  LORA
  SATELLITE
  OTHER
}

enum DeviceModelStatus {
  ACTIVE
  INACTIVE
  ARCHIVED
}

enum DeviceLifecycleStatus {
  RECEIVED
  IN_STOCK
  RESERVED
  ALLOCATED
  INSTALLED
  UNDER_REPAIR
  LOST
  DAMAGED
  RETIRED
}

enum DeviceOwnerType {
  PLATFORM
  DEALER
  CUSTOMER
}

enum DeviceCustodianType {
  PLATFORM
  DEALER
  CUSTOMER
  USER
}

enum DeviceOwnershipReason {
  INITIAL_STOCK
  PURCHASE
  SALE
  TRANSFER
  RETURN
  ADJUSTMENT
  OTHER
}

enum DeviceCustodyReason {
  RECEIVED
  ALLOCATION
  INSTALLATION
  REMOVAL
  REPAIR
  RETURN
  TRANSFER
  ADJUSTMENT
  OTHER
}

enum DeviceAllocationStatus {
  ALLOCATED
  AVAILABLE
  INSTALLED
  RETURNED
  CANCELLED
}

enum InstallationStatus {
  SCHEDULED
  IN_PROGRESS
  COMPLETED
  FAILED
  CANCELLED
  REMOVED
}

enum AssignmentType {
  PRIMARY
  SECONDARY
  BACKUP
}

enum AssignmentStatus {
  ACTIVE
  ENDED
  CANCELLED
}

enum AssignmentEndReason {
  DEVICE_FAILURE
  DEVICE_REPLACEMENT
  VEHICLE_TRANSFER
  VEHICLE_SOLD
  CUSTOMER_REQUEST
  SUBSCRIPTION_CANCELLED
  TRANSFER_TO_ANOTHER_VEHICLE
  LOST
  OTHER
}

enum InstallationRemovalReason {
  CUSTOMER_REQUEST
  VEHICLE_SOLD
  DEVICE_FAILURE
  WARRANTY_REPLACEMENT
  SUBSCRIPTION_CANCELLED
  TRANSFER_TO_ANOTHER_VEHICLE
  LOST
  OTHER
}

model Vehicle {
  id                           String        @id @default(uuid()) @db.Uuid
  vehicleCode                  String        @unique @db.VarChar(40)
  customerId                   String        @db.Uuid
  registrationNumber           String?       @db.VarChar(100)
  normalizedRegistrationNumber String?       @unique @db.VarChar(100)
  vehicleType                  VehicleType
  manufacturer                 String?       @db.VarChar(120)
  modelName                    String?       @db.VarChar(120)
  manufacturingYear            Int?
  color                        String?       @db.VarChar(60)
  chassisNumber                String?       @unique @db.VarChar(120)
  engineNumber                 String?       @unique @db.VarChar(120)
  status                       VehicleStatus @default(PENDING)
  createdByUserId              String?       @db.Uuid
  createdAt                    DateTime      @default(now()) @db.Timestamptz(3)
  updatedAt                    DateTime      @updatedAt @db.Timestamptz(3)
  archivedAt                   DateTime?     @db.Timestamptz(3)

  customer          Customer                  @relation(fields: [customerId], references: [id], onDelete: Restrict)
  createdBy         User?                     @relation("VehicleCreator", fields: [createdByUserId], references: [id], onDelete: SetNull)
  installations     DeviceInstallation[]
  deviceAssignments VehicleDeviceAssignment[]

  @@index([customerId, status])
  @@index([vehicleType, status])
  @@map("vehicles")
}

model DeviceModel {
  id                String            @id @default(uuid()) @db.Uuid
  modelCode         String            @unique @db.VarChar(60)
  manufacturer      String            @db.VarChar(120)
  modelName         String            @db.VarChar(160)
  protocol          String            @db.VarChar(100)
  networkType       DeviceNetworkType
  capabilities      Json?
  status            DeviceModelStatus @default(ACTIVE)
  createdAt         DateTime          @default(now()) @db.Timestamptz(3)
  updatedAt         DateTime          @updatedAt @db.Timestamptz(3)
  archivedAt        DateTime?         @db.Timestamptz(3)

  devices Device[]

  @@index([status])
  @@map("device_models")
}

model Device {
  id              String                @id @default(uuid()) @db.Uuid
  deviceCode      String                @unique @db.VarChar(40)
  deviceModelId   String                @db.Uuid
  imei            String?               @unique @db.VarChar(32)
  serialNumber    String?               @unique @db.VarChar(100)
  hardwareVersion String?               @db.VarChar(60)
  firmwareVersion String?               @db.VarChar(60)
  lifecycleStatus DeviceLifecycleStatus @default(RECEIVED)
  receivedAt      DateTime?             @db.Timestamptz(3)
  retiredAt       DateTime?             @db.Timestamptz(3)
  createdAt       DateTime              @default(now()) @db.Timestamptz(3)
  updatedAt       DateTime              @updatedAt @db.Timestamptz(3)

  deviceModel       DeviceModel               @relation(fields: [deviceModelId], references: [id], onDelete: Restrict)
  ownershipHistory  DeviceOwnershipHistory[]
  custodyHistory    DeviceCustodyHistory[]
  dealerAllocations DealerDeviceAllocation[]
  installations     DeviceInstallation[]
  vehicleAssignments VehicleDeviceAssignment[]

  @@index([deviceModelId, lifecycleStatus])
  @@index([lifecycleStatus])
  @@map("devices")
}

model DeviceOwnershipHistory {
  id                  String                @id @default(uuid()) @db.Uuid
  deviceId            String                @db.Uuid
  ownerType           DeviceOwnerType
  ownerOrganizationId String?               @db.Uuid
  ownerCustomerId     String?               @db.Uuid
  startedAt           DateTime              @default(now()) @db.Timestamptz(3)
  endedAt             DateTime?             @db.Timestamptz(3)
  reason              DeviceOwnershipReason
  changedByUserId     String?               @db.Uuid
  notes               String?
  createdAt           DateTime              @default(now()) @db.Timestamptz(3)

  device            Device        @relation(fields: [deviceId], references: [id], onDelete: Restrict)
  ownerOrganization Organization? @relation("DeviceOwnerOrganization", fields: [ownerOrganizationId], references: [id], onDelete: Restrict)
  ownerCustomer     Customer?     @relation("DeviceOwnerCustomer", fields: [ownerCustomerId], references: [id], onDelete: Restrict)
  changedBy         User?         @relation("DeviceOwnershipChanger", fields: [changedByUserId], references: [id], onDelete: SetNull)

  @@index([deviceId, startedAt])
  @@index([ownerOrganizationId, endedAt])
  @@index([ownerCustomerId, endedAt])
  @@map("device_ownership_history")
}

model DeviceCustodyHistory {
  id                      String                @id @default(uuid()) @db.Uuid
  deviceId                String                @db.Uuid
  custodianType           DeviceCustodianType
  custodianOrganizationId String?               @db.Uuid
  custodianCustomerId     String?               @db.Uuid
  custodianUserId         String?               @db.Uuid
  startedAt               DateTime              @default(now()) @db.Timestamptz(3)
  endedAt                 DateTime?             @db.Timestamptz(3)
  reason                  DeviceCustodyReason
  changedByUserId         String?               @db.Uuid
  notes                   String?
  createdAt               DateTime              @default(now()) @db.Timestamptz(3)

  device                Device        @relation(fields: [deviceId], references: [id], onDelete: Restrict)
  custodianOrganization Organization? @relation("DeviceCustodianOrganization", fields: [custodianOrganizationId], references: [id], onDelete: Restrict)
  custodianCustomer     Customer?     @relation("DeviceCustodianCustomer", fields: [custodianCustomerId], references: [id], onDelete: Restrict)
  custodianUser         User?         @relation("DeviceCustodianUser", fields: [custodianUserId], references: [id], onDelete: Restrict)
  changedBy             User?         @relation("DeviceCustodyChanger", fields: [changedByUserId], references: [id], onDelete: SetNull)

  @@index([deviceId, startedAt])
  @@index([custodianOrganizationId, endedAt])
  @@index([custodianCustomerId, endedAt])
  @@index([custodianUserId, endedAt])
  @@map("device_custody_history")
}

model DealerDeviceAllocation {
  id                   String                 @id @default(uuid()) @db.Uuid
  allocationCode       String                 @unique @db.VarChar(40)
  dealerOrganizationId String                 @db.Uuid
  deviceId             String                 @db.Uuid
  status               DeviceAllocationStatus @default(ALLOCATED)
  allocatedAt          DateTime               @default(now()) @db.Timestamptz(3)
  availableAt          DateTime?              @db.Timestamptz(3)
  installedAt          DateTime?              @db.Timestamptz(3)
  returnedAt           DateTime?              @db.Timestamptz(3)
  allocatedByUserId    String?                @db.Uuid
  returnedByUserId     String?                @db.Uuid
  notes                String?
  createdAt            DateTime               @default(now()) @db.Timestamptz(3)
  updatedAt            DateTime               @updatedAt @db.Timestamptz(3)

  dealerOrganization Organization @relation("DealerDeviceAllocationDealer", fields: [dealerOrganizationId], references: [id], onDelete: Restrict)
  device             Device       @relation(fields: [deviceId], references: [id], onDelete: Restrict)
  allocatedBy        User?        @relation("DeviceAllocationAllocator", fields: [allocatedByUserId], references: [id], onDelete: SetNull)
  returnedBy         User?        @relation("DeviceAllocationReturner", fields: [returnedByUserId], references: [id], onDelete: SetNull)

  @@index([dealerOrganizationId, status])
  @@index([deviceId, status])
  @@map("dealer_device_allocations")
}

model DeviceInstallation {
  id                   String                    @id @default(uuid()) @db.Uuid
  installationCode     String                    @unique @db.VarChar(40)
  deviceId             String                    @db.Uuid
  vehicleId            String                    @db.Uuid
  dealerOrganizationId String?                   @db.Uuid
  installedByUserId    String?                   @db.Uuid
  installedAt          DateTime?                 @db.Timestamptz(3)
  installationLocation Json?
  odometerReading      Decimal?                  @db.Decimal(12, 2)
  powerConnectionType  String?                   @db.VarChar(80)
  ignitionConnected    Boolean                   @default(false)
  relayConnected       Boolean                   @default(false)
  sosConnected         Boolean                   @default(false)
  installationNotes    String?
  status               InstallationStatus        @default(SCHEDULED)
  verifiedByUserId     String?                   @db.Uuid
  verifiedAt           DateTime?                 @db.Timestamptz(3)
  removedAt            DateTime?                 @db.Timestamptz(3)
  removalReason        InstallationRemovalReason?
  createdAt            DateTime                  @default(now()) @db.Timestamptz(3)
  updatedAt            DateTime                  @updatedAt @db.Timestamptz(3)

  device             Device                    @relation(fields: [deviceId], references: [id], onDelete: Restrict)
  vehicle            Vehicle                   @relation(fields: [vehicleId], references: [id], onDelete: Restrict)
  dealerOrganization Organization?             @relation("InstallationDealer", fields: [dealerOrganizationId], references: [id], onDelete: Restrict)
  installedBy        User?                     @relation("InstallationInstaller", fields: [installedByUserId], references: [id], onDelete: SetNull)
  verifiedBy         User?                     @relation("InstallationVerifier", fields: [verifiedByUserId], references: [id], onDelete: SetNull)
  assignment         VehicleDeviceAssignment?

  @@index([deviceId, status])
  @@index([vehicleId, status])
  @@index([dealerOrganizationId, status])
  @@map("device_installations")
}

model VehicleDeviceAssignment {
  id               String              @id @default(uuid()) @db.Uuid
  vehicleId        String              @db.Uuid
  deviceId         String              @db.Uuid
  installationId   String?             @unique @db.Uuid
  assignmentType   AssignmentType      @default(PRIMARY)
  startedAt        DateTime            @default(now()) @db.Timestamptz(3)
  endedAt          DateTime?           @db.Timestamptz(3)
  status           AssignmentStatus    @default(ACTIVE)
  assignedByUserId String?             @db.Uuid
  endedByUserId    String?             @db.Uuid
  endReason        AssignmentEndReason?
  endNotes         String?
  createdAt        DateTime            @default(now()) @db.Timestamptz(3)
  updatedAt        DateTime            @updatedAt @db.Timestamptz(3)

  vehicle      Vehicle             @relation(fields: [vehicleId], references: [id], onDelete: Restrict)
  device       Device              @relation(fields: [deviceId], references: [id], onDelete: Restrict)
  installation DeviceInstallation? @relation(fields: [installationId], references: [id], onDelete: Restrict)
  assignedBy   User?               @relation("DeviceAssignmentAssigner", fields: [assignedByUserId], references: [id], onDelete: SetNull)
  endedBy      User?               @relation("DeviceAssignmentEnder", fields: [endedByUserId], references: [id], onDelete: SetNull)

  @@index([vehicleId, status])
  @@index([deviceId, status])
  @@index([assignmentType, status])
  @@map("vehicle_device_assignments")
}
'@

        $schema = $schema.TrimEnd() + [Environment]::NewLine + $assetSchema.TrimStart()
        [System.IO.File]::WriteAllText(
            $schemaPath,
            $schema,
            $script:Utf8NoBom
        )

        Write-Host "[UPDATED] services\backend-api\prisma\schema.prisma" -ForegroundColor Green
    }
    else {
        Write-Host "Vehicle/device schema already exists; preserving it." -ForegroundColor DarkYellow
    }

    Write-Step 4 10 "Formatting and validating the extended Prisma schema"

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

    Write-Step 5 10 "Creating and customizing the vehicle/device migration"

    $migrationRoot = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\migrations"

    $phase2Migration = Get-ChildItem `
        -LiteralPath $migrationRoot `
        -Directory |
        Where-Object {
            $_.Name -like "*_vehicle_device_foundation"
        } |
        Select-Object -First 1

    if (-not $phase2Migration) {
        Invoke-CheckedCommand "Prisma migration create-only" {
            pnpm.cmd `
                --filter "@solid-tracker/backend-api" `
                exec prisma migrate dev `
                --name vehicle_device_foundation `
                --create-only `
                --config prisma.config.ts
        }

        $phase2Migration = Get-ChildItem `
            -LiteralPath $migrationRoot `
            -Directory |
            Where-Object {
                $_.Name -like "*_vehicle_device_foundation"
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if (-not $phase2Migration) {
        throw "The vehicle/device migration directory was not created."
    }

    $migrationSqlPath = Join-Path $phase2Migration.FullName "migration.sql"

    if (-not (Test-Path -LiteralPath $migrationSqlPath)) {
        throw "Vehicle/device migration.sql was not found."
    }

    $migrationSql = [System.IO.File]::ReadAllText($migrationSqlPath)
    $customMarker = "-- Solid Tracker Phase 2 vehicle/device invariants."

    if (-not $migrationSql.Contains($customMarker)) {
        $customSql = @'

-- Solid Tracker Phase 2 vehicle/device invariants.

ALTER TABLE "vehicles"
ADD CONSTRAINT "vehicles_manufacturing_year_range"
CHECK (
  "manufacturingYear" IS NULL
  OR "manufacturingYear" BETWEEN 1886 AND 2100
);

ALTER TABLE "devices"
ADD CONSTRAINT "devices_retirement_consistency"
CHECK (
  ("lifecycleStatus" = 'RETIRED' AND "retiredAt" IS NOT NULL)
  OR
  ("lifecycleStatus" <> 'RETIRED' AND "retiredAt" IS NULL)
);

ALTER TABLE "device_installations"
ADD CONSTRAINT "device_installations_status_consistency"
CHECK (
  (
    "status" IN ('COMPLETED', 'REMOVED')
    AND "installedAt" IS NOT NULL
  )
  OR
  "status" IN ('SCHEDULED', 'IN_PROGRESS', 'FAILED', 'CANCELLED')
);

ALTER TABLE "device_installations"
ADD CONSTRAINT "device_installations_removal_consistency"
CHECK (
  (
    "status" = 'REMOVED'
    AND "removedAt" IS NOT NULL
    AND "removalReason" IS NOT NULL
  )
  OR
  (
    "status" <> 'REMOVED'
    AND "removedAt" IS NULL
    AND "removalReason" IS NULL
  )
);

ALTER TABLE "vehicle_device_assignments"
ADD CONSTRAINT "vehicle_device_assignments_status_consistency"
CHECK (
  (
    "status" = 'ACTIVE'
    AND "endedAt" IS NULL
    AND "endReason" IS NULL
  )
  OR
  (
    "status" IN ('ENDED', 'CANCELLED')
    AND "endedAt" IS NOT NULL
  )
);

CREATE UNIQUE INDEX
  "device_ownership_history_one_active_per_device"
ON "device_ownership_history" ("deviceId")
WHERE "endedAt" IS NULL;

CREATE UNIQUE INDEX
  "device_custody_history_one_active_per_device"
ON "device_custody_history" ("deviceId")
WHERE "endedAt" IS NULL;

CREATE UNIQUE INDEX
  "dealer_device_allocations_one_active_per_device"
ON "dealer_device_allocations" ("deviceId")
WHERE "status" IN ('ALLOCATED', 'AVAILABLE', 'INSTALLED');

CREATE UNIQUE INDEX
  "vehicle_device_assignments_one_active_per_device"
ON "vehicle_device_assignments" ("deviceId")
WHERE "status" = 'ACTIVE' AND "endedAt" IS NULL;

CREATE UNIQUE INDEX
  "vehicle_device_assignments_one_active_primary_per_vehicle"
ON "vehicle_device_assignments" ("vehicleId")
WHERE
  "assignmentType" = 'PRIMARY'
  AND "status" = 'ACTIVE'
  AND "endedAt" IS NULL;

CREATE OR REPLACE FUNCTION "solid_tracker_assert_organization_type"(
  organization_id UUID,
  expected_type "OrganizationType"
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  actual_type "OrganizationType";
BEGIN
  SELECT "type"
  INTO actual_type
  FROM "organizations"
  WHERE "id" = organization_id;

  IF NOT FOUND OR actual_type <> expected_type THEN
    RAISE EXCEPTION
      'Organization % must exist and have type %',
      organization_id,
      expected_type;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION "solid_tracker_validate_device_owner"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."ownerType" = 'CUSTOMER' THEN
    IF NEW."ownerCustomerId" IS NULL
       OR NEW."ownerOrganizationId" IS NOT NULL THEN
      RAISE EXCEPTION
        'CUSTOMER ownership requires only ownerCustomerId';
    END IF;

  ELSIF NEW."ownerType" = 'PLATFORM' THEN
    IF NEW."ownerOrganizationId" IS NULL
       OR NEW."ownerCustomerId" IS NOT NULL THEN
      RAISE EXCEPTION
        'PLATFORM ownership requires only ownerOrganizationId';
    END IF;

    PERFORM "solid_tracker_assert_organization_type"(
      NEW."ownerOrganizationId",
      'PLATFORM'
    );

  ELSIF NEW."ownerType" = 'DEALER' THEN
    IF NEW."ownerOrganizationId" IS NULL
       OR NEW."ownerCustomerId" IS NOT NULL THEN
      RAISE EXCEPTION
        'DEALER ownership requires only ownerOrganizationId';
    END IF;

    PERFORM "solid_tracker_assert_organization_type"(
      NEW."ownerOrganizationId",
      'DEALER'
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "device_ownership_validate_owner"
BEFORE INSERT OR UPDATE OF
  "ownerType",
  "ownerOrganizationId",
  "ownerCustomerId"
ON "device_ownership_history"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_device_owner"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_device_custodian"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."custodianType" = 'CUSTOMER' THEN
    IF NEW."custodianCustomerId" IS NULL
       OR NEW."custodianOrganizationId" IS NOT NULL
       OR NEW."custodianUserId" IS NOT NULL THEN
      RAISE EXCEPTION
        'CUSTOMER custody requires only custodianCustomerId';
    END IF;

  ELSIF NEW."custodianType" = 'USER' THEN
    IF NEW."custodianUserId" IS NULL
       OR NEW."custodianOrganizationId" IS NOT NULL
       OR NEW."custodianCustomerId" IS NOT NULL THEN
      RAISE EXCEPTION
        'USER custody requires only custodianUserId';
    END IF;

  ELSIF NEW."custodianType" = 'PLATFORM' THEN
    IF NEW."custodianOrganizationId" IS NULL
       OR NEW."custodianCustomerId" IS NOT NULL
       OR NEW."custodianUserId" IS NOT NULL THEN
      RAISE EXCEPTION
        'PLATFORM custody requires only custodianOrganizationId';
    END IF;

    PERFORM "solid_tracker_assert_organization_type"(
      NEW."custodianOrganizationId",
      'PLATFORM'
    );

  ELSIF NEW."custodianType" = 'DEALER' THEN
    IF NEW."custodianOrganizationId" IS NULL
       OR NEW."custodianCustomerId" IS NOT NULL
       OR NEW."custodianUserId" IS NOT NULL THEN
      RAISE EXCEPTION
        'DEALER custody requires only custodianOrganizationId';
    END IF;

    PERFORM "solid_tracker_assert_organization_type"(
      NEW."custodianOrganizationId",
      'DEALER'
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "device_custody_validate_custodian"
BEFORE INSERT OR UPDATE OF
  "custodianType",
  "custodianOrganizationId",
  "custodianCustomerId",
  "custodianUserId"
ON "device_custody_history"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_device_custodian"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_device_allocation"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM "solid_tracker_assert_organization_type"(
    NEW."dealerOrganizationId",
    'DEALER'
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER "dealer_device_allocations_validate_dealer"
BEFORE INSERT OR UPDATE OF "dealerOrganizationId"
ON "dealer_device_allocations"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_device_allocation"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_installation_dealer"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."dealerOrganizationId" IS NOT NULL THEN
    PERFORM "solid_tracker_assert_organization_type"(
      NEW."dealerOrganizationId",
      'DEALER'
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "device_installations_validate_dealer"
BEFORE INSERT OR UPDATE OF "dealerOrganizationId"
ON "device_installations"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_installation_dealer"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_assignment_installation"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  installation_device_id UUID;
  installation_vehicle_id UUID;
BEGIN
  IF NEW."installationId" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT "deviceId", "vehicleId"
  INTO installation_device_id, installation_vehicle_id
  FROM "device_installations"
  WHERE "id" = NEW."installationId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Installation % does not exist',
      NEW."installationId";
  END IF;

  IF installation_device_id <> NEW."deviceId"
     OR installation_vehicle_id <> NEW."vehicleId" THEN
    RAISE EXCEPTION
      'Assignment device and vehicle must match the linked installation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "vehicle_device_assignments_validate_installation"
BEFORE INSERT OR UPDATE OF
  "installationId",
  "deviceId",
  "vehicleId"
ON "vehicle_device_assignments"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_assignment_installation"();
'@

        [System.IO.File]::AppendAllText(
            $migrationSqlPath,
            $customSql,
            $script:Utf8NoBom
        )

        Write-Host "[CUSTOMIZED] $($phase2Migration.Name)\migration.sql" -ForegroundColor Green
    }
    else {
        Write-Host "PostgreSQL-native Phase 2 constraints already exist." -ForegroundColor DarkYellow
    }

    Write-Step 6 10 "Applying migration and generating Prisma Client"

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

    Write-Step 8 10 "Verifying vehicle/device tables and database invariants"

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
  ) AS invariant_trigger_count;
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

    if ($parts.Count -ne 3) {
        throw "Unexpected PostgreSQL verification result: $verificationLine"
    }

    $tableCount = [int]$parts[0]
    $invariantIndexCount = [int]$parts[1]
    $invariantTriggerCount = [int]$parts[2]

    if ($tableCount -lt 26) {
        throw "Expected at least 26 public tables, but found $tableCount."
    }

    if ($invariantIndexCount -ne 5) {
        throw "Expected 5 Phase 2 invariant indexes, but found $invariantIndexCount."
    }

    if ($invariantTriggerCount -ne 5) {
        throw "Expected 5 Phase 2 invariant triggers, but found $invariantTriggerCount."
    }

    Write-Host "Public tables:           $tableCount" -ForegroundColor Green
    Write-Host "Phase 2 unique indexes:  $invariantIndexCount" -ForegroundColor Green
    Write-Host "Phase 2 domain triggers: $invariantTriggerCount" -ForegroundColor Green

    Write-Step 9 10 "Writing vehicle/device architecture documentation"

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
- `SECONDARY` and `BACKUP` types are represented but not used as primary replacements.
- Historical assignments remain after removal or replacement.
- An assignment linked to an installation must use the same vehicle and device.

## Ownership and custody

Ownership and custody are separate histories.

Examples:

```text
Owner: Solid Tracker Platform
Custodian: Dealer ABC

Owner: Customer
Custodian: Service installer user during removal
```

Only one current ownership entry and one current custody entry may exist for each device.

## Dealer allocation

A device can be allocated to only one dealer at a time while its allocation is active. Dealer allocations must reference an organization whose type is `DEALER`.

## Installation lifecycle

Installation records preserve:

- installer;
- dealer;
- physical installation time;
- connection details;
- verification;
- removal time and reason.

Completed or removed installations require an installation timestamp. Removed installations require both removal time and removal reason.

## Device identity

- `deviceCode` is the Solid Tracker business identifier.
- `imei` is stored as text and is unique when present.
- `serialNumber` is unique when present.
- Device lifecycle state is separate from future Traccar online/offline state.

## Migration-level enforcement

Prisma defines the relational model. PostgreSQL-native partial indexes, check constraints, and triggers enforce cross-row and polymorphic business rules that cannot be represented safely by Prisma schema syntax alone.
'@

    Write-Utf8File `
        "docs\architecture\vehicle-device-foundation.md" `
        $documentation

    Write-Step 10 10 "Committing the vehicle/device foundation"

    git add --all

    git commit `
        -m "feat(assets): establish vehicle and device foundation"

    if ($LASTEXITCODE -ne 0) {
        throw "Git commit failed."
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
    git log --oneline --decorate --graph -5
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    Write-Host "Next domain stage:" -ForegroundColor Yellow
    Write-Host "Service plans, subscriptions, invoices, and payment records" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "VEHICLE AND DEVICE FOUNDATION FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Do not delete an applied migration manually." -ForegroundColor Yellow
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
