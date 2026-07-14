[CmdletBinding()]
param(
    [string]$RepositoryPath = "D:\GitHub\gps-tracker-platform",
    [int]$MaximumNetworkAttempts = 5
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

function Invoke-PnpmWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    for ($attempt = 1; $attempt -le $MaximumNetworkAttempts; $attempt++) {
        Write-Host ""
        Write-Host ("pnpm attempt {0}/{1}" -f $attempt, $MaximumNetworkAttempts) -ForegroundColor Cyan
        Write-Host ("pnpm {0}" -f ($Arguments -join " ")) -ForegroundColor DarkCyan

        & pnpm.cmd @Arguments

        if ($LASTEXITCODE -eq 0) {
            return
        }

        if ($attempt -eq $MaximumNetworkAttempts) {
            throw "pnpm failed after $MaximumNetworkAttempts attempts."
        }

        $waitSeconds = [Math]::Min(20 * $attempt, 90)
        Write-Host ("Waiting {0} seconds before retrying..." -f $waitSeconds) -ForegroundColor Yellow
        Start-Sleep -Seconds $waitSeconds
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
        $Package | Add-Member -NotePropertyName scripts -NotePropertyValue ([pscustomobject]@{})
    }

    if ($Package.scripts.PSObject.Properties.Name -contains $Name) {
        $Package.scripts.$Name = $Value
    }
    else {
        $Package.scripts | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
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
    Write-Utf8File -RelativePath $RelativePath -Content ($json + [Environment]::NewLine)
}

function Add-LineIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    $fullPath = Join-Path $script:RootPath $RelativePath

    if (Test-Path -LiteralPath $fullPath) {
        $content = [System.IO.File]::ReadAllText($fullPath)

        if ($content -split "\r?\n" | Where-Object { $_ -eq $Line }) {
            return
        }

        if ($content.Length -gt 0 -and -not $content.EndsWith([Environment]::NewLine)) {
            $content += [Environment]::NewLine
        }

        $content += $Line + [Environment]::NewLine
        [System.IO.File]::WriteAllText($fullPath, $content, $script:Utf8NoBom)
    }
    else {
        Write-Utf8File -RelativePath $RelativePath -Content ($Line + [Environment]::NewLine)
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Prisma Phase 1 Foundation" -ForegroundColor Cyan
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

    $selfStatusEntry = "?? scripts/solid-tracker-prisma-phase1-foundation.ps1"
    $unexpectedChanges = @(
        git status --short |
            Where-Object {
                $_ -and $_.TrimEnd() -ne $selfStatusEntry
            }
    )

    if ($unexpectedChanges.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow
        $unexpectedChanges | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
        throw "Working tree contains changes other than this Prisma setup script."
    }

    foreach ($requiredFile in @(
        ".env",
        "package.json",
        "pnpm-workspace.yaml",
        "compose.yaml",
        "services\backend-api\package.json",
        "services\backend-api\src\app.module.ts",
        "services\backend-api\src\database\database.module.ts",
        "services\backend-api\src\health\database.health.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredFile)) {
            throw "Required file is missing: $requiredFile"
        }
    }

    Write-Step 1 10 "Validating PostgreSQL and repository prerequisites"

    $postgresHealth = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        solid-tracker-postgres 2>$null

    if ($LASTEXITCODE -ne 0 -or $postgresHealth.Trim() -ne "healthy") {
        throw "solid-tracker-postgres must be running and healthy."
    }

    $databaseUrlLine = Get-Content -LiteralPath ".env" |
        Where-Object { $_ -match "^\s*DATABASE_URL\s*=" } |
        Select-Object -First 1

    if (-not $databaseUrlLine) {
        throw "DATABASE_URL is missing from the repository .env file."
    }

    Write-Host "PostgreSQL: healthy" -ForegroundColor Green
    Write-Host "DATABASE_URL: configured" -ForegroundColor Green

    Write-Step 2 10 "Installing Prisma ORM 7 and PostgreSQL adapter dependencies"

    $env:npm_config_fetch_retries = "6"
    $env:npm_config_fetch_retry_factor = "2"
    $env:npm_config_fetch_retry_mintimeout = "10000"
    $env:npm_config_fetch_retry_maxtimeout = "120000"
    $env:npm_config_fetch_timeout = "300000"
    $env:npm_config_network_concurrency = "4"

    Invoke-PnpmWithRetry @(
        "--filter",
        "@solid-tracker/backend-api",
        "add",
        "@prisma/client@7.8.0",
        "@prisma/adapter-pg@7.8.0",
        "dotenv@17.4.2"
    )

    Invoke-PnpmWithRetry @(
        "--filter",
        "@solid-tracker/backend-api",
        "add",
        "--save-dev",
        "prisma@7.8.0",
        "tsx@4.23.1"
    )

    Invoke-CheckedCommand "Approve reviewed Prisma build scripts" {
        pnpm.cmd approve-builds "@prisma/engines" "esbuild" "prisma"
    }

    Invoke-CheckedCommand "Rebuild reviewed Prisma dependencies" {
        pnpm.cmd rebuild "@prisma/engines" "esbuild" "prisma"
    }
    Write-Step 3 10 "Writing Prisma configuration and Phase 1 schema"

    $prismaConfig = @'
import { config } from "dotenv";
import { defineConfig } from "prisma/config";
import { resolve } from "node:path";

config({
  path: resolve(process.cwd(), "../../.env"),
});

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
    seed: "tsx prisma/seed.ts",
  },
  datasource: {
    url: process.env.DATABASE_URL ?? "",
  },
});
'@

    Write-Utf8File "services\backend-api\prisma.config.ts" $prismaConfig

    $schema = @'
generator client {
  provider               = "prisma-client"
  output                 = "../src/generated/prisma"
  moduleFormat           = "cjs"
  generatedFileExtension = "ts"
  importFileExtension    = ""
}

datasource db {
  provider = "postgresql"
}

enum RecordStatus {
  ACTIVE
  INACTIVE
  ARCHIVED
}

enum UserStatus {
  PENDING_VERIFICATION
  ACTIVE
  LOCKED
  DISABLED
  SUSPENDED
  ARCHIVED
}

enum OrganizationType {
  PLATFORM
  DEALER
  CUSTOMER_ORGANIZATION
}

enum OrganizationStatus {
  PENDING
  ACTIVE
  SUSPENDED
  INACTIVE
  ARCHIVED
}

enum MembershipType {
  OWNER
  EMPLOYEE
  CONTRACTOR
  MEMBER
}

enum MembershipStatus {
  INVITED
  ACTIVE
  SUSPENDED
  ENDED
}

enum ScopeType {
  PLATFORM
  ZONE
  DEALER
  CUSTOMER_GROUP
  CUSTOMER
  VEHICLE
  SELF
}

enum RoleAssignmentStatus {
  ACTIVE
  SUSPENDED
  REVOKED
  EXPIRED
}

enum SessionPlatform {
  ANDROID
  WEB
  IOS
  API_CLIENT
}

enum SessionStatus {
  ACTIVE
  REVOKED
  EXPIRED
}

enum CustomerType {
  INDIVIDUAL
  ORGANIZATION
}

enum CustomerStatus {
  PENDING
  ACTIVE
  SUSPENDED
  INACTIVE
  ARCHIVED
}

enum AcquisitionSource {
  DIRECT
  DEALER
  MIGRATION
  PARTNER
}

enum CustomerGroupStatus {
  ACTIVE
  INACTIVE
  ARCHIVED
}

enum CustomerManagementType {
  PLATFORM
  DEALER
}

enum AssignmentReason {
  INITIAL_ASSIGNMENT
  PLATFORM_ASSIGNMENT
  DEALER_TRANSFER
  MANUAL_CORRECTION
  OTHER
}

model Zone {
  id          String       @id @default(uuid()) @db.Uuid
  code        String       @unique @db.VarChar(40)
  name        String       @db.VarChar(120)
  description String?
  status      RecordStatus @default(ACTIVE)
  createdAt   DateTime     @default(now()) @db.Timestamptz(3)
  updatedAt   DateTime     @updatedAt @db.Timestamptz(3)
  archivedAt  DateTime?    @db.Timestamptz(3)

  organizations Organization[]

  @@index([status])
  @@map("zones")
}

model Organization {
  id         String             @id @default(uuid()) @db.Uuid
  code       String             @unique @db.VarChar(40)
  type       OrganizationType
  name       String             @db.VarChar(160)
  legalName  String?            @db.VarChar(200)
  zoneId     String?            @db.Uuid
  status     OrganizationStatus @default(PENDING)
  createdAt  DateTime           @default(now()) @db.Timestamptz(3)
  updatedAt  DateTime           @updatedAt @db.Timestamptz(3)
  archivedAt DateTime?          @db.Timestamptz(3)

  zone              Zone?                      @relation(fields: [zoneId], references: [id], onDelete: Restrict)
  dealerProfile     DealerProfile?
  memberships       OrganizationMembership[]
  customerGroups    CustomerGroup[]
  managedCustomers  Customer[]                 @relation("ManagingDealer")
  dealerAssignments CustomerDealerAssignment[]
  actorAuditLogs    AuditLog[]                  @relation("AuditActorOrganization")

  @@index([type, status])
  @@index([zoneId])
  @@map("organizations")
}

model DealerProfile {
  organizationId          String   @id @db.Uuid
  dealerCode              String   @unique @db.VarChar(40)
  tradeLicenseNumber      String?  @db.VarChar(100)
  taxIdentificationNumber String?  @db.VarChar(100)
  contactMobile           String?  @db.VarChar(30)
  contactEmail            String?  @db.VarChar(254)
  commissionEnabled       Boolean  @default(true)
  createdAt               DateTime @default(now()) @db.Timestamptz(3)
  updatedAt               DateTime @updatedAt @db.Timestamptz(3)

  organization Organization @relation(fields: [organizationId], references: [id], onDelete: Restrict)

  @@map("dealer_profiles")
}

model User {
  id                     String     @id @default(uuid()) @db.Uuid
  userCode               String     @unique @db.VarChar(40)
  fullName               String     @db.VarChar(160)
  mobileNumber           String     @db.VarChar(30)
  normalizedMobileNumber String     @unique @db.VarChar(30)
  email                  String?    @db.VarChar(254)
  normalizedEmail        String?    @unique @db.VarChar(254)
  passwordHash           String?
  status                 UserStatus @default(PENDING_VERIFICATION)
  mobileVerifiedAt       DateTime?  @db.Timestamptz(3)
  emailVerifiedAt        DateTime?  @db.Timestamptz(3)
  passwordChangedAt      DateTime?  @db.Timestamptz(3)
  lastLoginAt            DateTime?  @db.Timestamptz(3)
  failedLoginCount       Int        @default(0)
  lockedUntil            DateTime?  @db.Timestamptz(3)
  createdAt              DateTime   @default(now()) @db.Timestamptz(3)
  updatedAt              DateTime   @updatedAt @db.Timestamptz(3)
  archivedAt             DateTime?  @db.Timestamptz(3)

  organizationMemberships OrganizationMembership[]   @relation("OrganizationMember")
  invitedMemberships      OrganizationMembership[]   @relation("OrganizationMembershipInviter")
  roleAssignments         RoleAssignment[]           @relation("RoleAssignmentUser")
  assignedRoles           RoleAssignment[]           @relation("RoleAssignmentAssigner")
  revokedRoles            RoleAssignment[]           @relation("RoleAssignmentRevoker")
  sessions                UserSession[]
  customerMemberships     CustomerMembership[]       @relation("CustomerMember")
  invitedCustomerMembers  CustomerMembership[]       @relation("CustomerMembershipInviter")
  createdCustomerGroups   CustomerGroup[]            @relation("CustomerGroupCreator")
  createdCustomers        Customer[]                 @relation("CustomerCreator")
  assignedCustomers       CustomerDealerAssignment[] @relation("CustomerDealerAssigner")
  actorAuditLogs          AuditLog[]                  @relation("AuditActorUser")

  @@index([status])
  @@map("users")
}

model OrganizationMembership {
  id                       String           @id @default(uuid()) @db.Uuid
  organizationId           String           @db.Uuid
  userId                   String           @db.Uuid
  membershipType           MembershipType
  status                   MembershipStatus @default(INVITED)
  isPrimary                Boolean          @default(false)
  invitedByUserId          String?          @db.Uuid
  joinedAt                 DateTime?        @db.Timestamptz(3)
  endedAt                  DateTime?        @db.Timestamptz(3)
  createdAt                DateTime         @default(now()) @db.Timestamptz(3)
  updatedAt                DateTime         @updatedAt @db.Timestamptz(3)

  organization   Organization     @relation(fields: [organizationId], references: [id], onDelete: Restrict)
  user           User             @relation("OrganizationMember", fields: [userId], references: [id], onDelete: Restrict)
  invitedBy      User?            @relation("OrganizationMembershipInviter", fields: [invitedByUserId], references: [id], onDelete: SetNull)
  roleAssignments RoleAssignment[]

  @@unique([organizationId, userId])
  @@index([userId, status])
  @@index([organizationId, status])
  @@map("organization_memberships")
}

model Role {
  id          String       @id @default(uuid()) @db.Uuid
  code        String       @unique @db.VarChar(80)
  name        String       @db.VarChar(120)
  description String?
  status      RecordStatus @default(ACTIVE)
  isSystem    Boolean      @default(true)
  createdAt   DateTime     @default(now()) @db.Timestamptz(3)
  updatedAt   DateTime     @updatedAt @db.Timestamptz(3)

  permissions RolePermission[]
  assignments RoleAssignment[]

  @@index([status])
  @@map("roles")
}

model Permission {
  id          String       @id @default(uuid()) @db.Uuid
  code        String       @unique @db.VarChar(120)
  name        String       @db.VarChar(160)
  description String?
  status      RecordStatus @default(ACTIVE)
  createdAt   DateTime     @default(now()) @db.Timestamptz(3)
  updatedAt   DateTime     @updatedAt @db.Timestamptz(3)

  roles RolePermission[]

  @@index([status])
  @@map("permissions")
}

model RolePermission {
  roleId       String   @db.Uuid
  permissionId String   @db.Uuid
  createdAt    DateTime @default(now()) @db.Timestamptz(3)

  role       Role       @relation(fields: [roleId], references: [id], onDelete: Cascade)
  permission Permission @relation(fields: [permissionId], references: [id], onDelete: Cascade)

  @@id([roleId, permissionId])
  @@index([permissionId])
  @@map("role_permissions")
}

model RoleAssignment {
  id                       String               @id @default(uuid()) @db.Uuid
  userId                   String               @db.Uuid
  roleId                   String               @db.Uuid
  organizationMembershipId String?              @db.Uuid
  scopeType                ScopeType
  scopeId                  String               @db.Uuid
  status                   RoleAssignmentStatus @default(ACTIVE)
  effectiveFrom            DateTime             @default(now()) @db.Timestamptz(3)
  effectiveUntil           DateTime?            @db.Timestamptz(3)
  assignedByUserId         String?              @db.Uuid
  revokedByUserId          String?              @db.Uuid
  revokedAt                DateTime?            @db.Timestamptz(3)
  revocationReason         String?
  createdAt                DateTime             @default(now()) @db.Timestamptz(3)
  updatedAt                DateTime             @updatedAt @db.Timestamptz(3)

  user                   User                    @relation("RoleAssignmentUser", fields: [userId], references: [id], onDelete: Restrict)
  role                   Role                    @relation(fields: [roleId], references: [id], onDelete: Restrict)
  organizationMembership OrganizationMembership? @relation(fields: [organizationMembershipId], references: [id], onDelete: Restrict)
  assignedBy             User?                   @relation("RoleAssignmentAssigner", fields: [assignedByUserId], references: [id], onDelete: SetNull)
  revokedBy              User?                   @relation("RoleAssignmentRevoker", fields: [revokedByUserId], references: [id], onDelete: SetNull)

  @@unique([userId, roleId, scopeType, scopeId])
  @@index([userId, status])
  @@index([scopeType, scopeId, status])
  @@map("role_assignments")
}

model UserSession {
  id               String          @id @default(uuid()) @db.Uuid
  userId           String          @db.Uuid
  tokenFamilyId    String          @db.Uuid
  refreshTokenHash String          @unique
  deviceName       String?         @db.VarChar(160)
  platform         SessionPlatform
  appVersion       String?         @db.VarChar(50)
  ipAddress        String?         @db.VarChar(45)
  userAgent        String?
  status           SessionStatus   @default(ACTIVE)
  createdAt        DateTime        @default(now()) @db.Timestamptz(3)
  lastUsedAt       DateTime        @default(now()) @db.Timestamptz(3)
  expiresAt        DateTime        @db.Timestamptz(3)
  revokedAt        DateTime?       @db.Timestamptz(3)
  revocationReason String?

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@index([userId, status])
  @@index([expiresAt])
  @@map("user_sessions")
}

model CustomerGroup {
  id                   String              @id @default(uuid()) @db.Uuid
  code                 String              @unique @db.VarChar(40)
  dealerOrganizationId String              @db.Uuid
  name                 String              @db.VarChar(120)
  normalizedName       String              @db.VarChar(120)
  description          String?
  status               CustomerGroupStatus @default(ACTIVE)
  createdByUserId      String?             @db.Uuid
  createdAt            DateTime            @default(now()) @db.Timestamptz(3)
  updatedAt            DateTime            @updatedAt @db.Timestamptz(3)
  archivedAt           DateTime?           @db.Timestamptz(3)

  dealerOrganization Organization @relation(fields: [dealerOrganizationId], references: [id], onDelete: Restrict)
  createdBy          User?        @relation("CustomerGroupCreator", fields: [createdByUserId], references: [id], onDelete: SetNull)
  customers          Customer[]

  @@unique([dealerOrganizationId, normalizedName])
  @@index([dealerOrganizationId, status])
  @@map("customer_groups")
}

model Customer {
  id                  String            @id @default(uuid()) @db.Uuid
  customerCode        String            @unique @db.VarChar(40)
  customerType        CustomerType
  status              CustomerStatus    @default(PENDING)
  managingDealerId    String?           @db.Uuid
  customerGroupId     String?           @db.Uuid
  acquisitionSource   AcquisitionSource
  primaryMobile       String?           @db.VarChar(30)
  primaryEmail        String?           @db.VarChar(254)
  billingAddress      Json?
  createdByUserId     String?           @db.Uuid
  createdAt           DateTime          @default(now()) @db.Timestamptz(3)
  updatedAt           DateTime          @updatedAt @db.Timestamptz(3)
  archivedAt          DateTime?         @db.Timestamptz(3)

  managingDealer      Organization?                @relation("ManagingDealer", fields: [managingDealerId], references: [id], onDelete: Restrict)
  customerGroup       CustomerGroup?               @relation(fields: [customerGroupId], references: [id], onDelete: Restrict)
  createdBy           User?                        @relation("CustomerCreator", fields: [createdByUserId], references: [id], onDelete: SetNull)
  individualProfile   IndividualCustomerProfile?
  organizationProfile OrganizationCustomerProfile?
  memberships         CustomerMembership[]
  dealerAssignments   CustomerDealerAssignment[]

  @@index([managingDealerId, status])
  @@index([customerGroupId])
  @@index([customerType, status])
  @@index([primaryMobile])
  @@map("customers")
}

model IndividualCustomerProfile {
  customerId             String    @id @db.Uuid
  fullName               String    @db.VarChar(160)
  dateOfBirth            DateTime? @db.Date
  emergencyContactName   String?   @db.VarChar(160)
  emergencyContactMobile String?   @db.VarChar(30)
  createdAt              DateTime  @default(now()) @db.Timestamptz(3)
  updatedAt              DateTime  @updatedAt @db.Timestamptz(3)

  customer Customer @relation(fields: [customerId], references: [id], onDelete: Cascade)

  @@map("individual_customer_profiles")
}

model OrganizationCustomerProfile {
  customerId         String   @id @db.Uuid
  legalName          String   @db.VarChar(200)
  displayName        String   @db.VarChar(160)
  registrationNumber String?  @unique @db.VarChar(100)
  taxReference       String?  @db.VarChar(100)
  contactPersonName  String?  @db.VarChar(160)
  contactMobile      String?  @db.VarChar(30)
  contactEmail       String?  @db.VarChar(254)
  operationalAddress Json?
  createdAt          DateTime @default(now()) @db.Timestamptz(3)
  updatedAt          DateTime @updatedAt @db.Timestamptz(3)

  customer Customer @relation(fields: [customerId], references: [id], onDelete: Cascade)

  @@map("organization_customer_profiles")
}

model CustomerMembership {
  id              String           @id @default(uuid()) @db.Uuid
  customerId      String           @db.Uuid
  userId          String           @db.Uuid
  status          MembershipStatus @default(INVITED)
  isPrimary       Boolean          @default(false)
  invitedByUserId String?          @db.Uuid
  joinedAt        DateTime?        @db.Timestamptz(3)
  endedAt         DateTime?        @db.Timestamptz(3)
  createdAt       DateTime         @default(now()) @db.Timestamptz(3)
  updatedAt       DateTime         @updatedAt @db.Timestamptz(3)

  customer  Customer @relation(fields: [customerId], references: [id], onDelete: Restrict)
  user      User     @relation("CustomerMember", fields: [userId], references: [id], onDelete: Restrict)
  invitedBy User?    @relation("CustomerMembershipInviter", fields: [invitedByUserId], references: [id], onDelete: SetNull)

  @@unique([customerId, userId])
  @@index([userId, status])
  @@index([customerId, status])
  @@map("customer_memberships")
}

model CustomerDealerAssignment {
  id                   String                 @id @default(uuid()) @db.Uuid
  customerId           String                 @db.Uuid
  managementType       CustomerManagementType
  dealerOrganizationId String?                @db.Uuid
  assignedAt           DateTime               @default(now()) @db.Timestamptz(3)
  endedAt              DateTime?              @db.Timestamptz(3)
  assignmentReason     AssignmentReason
  assignedByUserId     String?                @db.Uuid
  notes                String?
  createdAt            DateTime               @default(now()) @db.Timestamptz(3)

  customer           Customer      @relation(fields: [customerId], references: [id], onDelete: Restrict)
  dealerOrganization Organization? @relation(fields: [dealerOrganizationId], references: [id], onDelete: Restrict)
  assignedBy         User?         @relation("CustomerDealerAssigner", fields: [assignedByUserId], references: [id], onDelete: SetNull)

  @@index([customerId, assignedAt])
  @@index([dealerOrganizationId, endedAt])
  @@map("customer_dealer_assignments")
}

model AuditLog {
  id                  String     @id @default(uuid()) @db.Uuid
  actorUserId         String?    @db.Uuid
  actorOrganizationId String?    @db.Uuid
  action              String     @db.VarChar(160)
  resourceType        String     @db.VarChar(100)
  resourceId          String?    @db.VarChar(100)
  scopeType           ScopeType?
  scopeId             String?    @db.Uuid
  beforeData          Json?
  afterData           Json?
  metadata            Json?
  ipAddress           String?    @db.VarChar(45)
  userAgent           String?
  correlationId       String?    @db.VarChar(100)
  occurredAt          DateTime   @default(now()) @db.Timestamptz(3)
  createdAt           DateTime   @default(now()) @db.Timestamptz(3)

  actorUser         User?         @relation("AuditActorUser", fields: [actorUserId], references: [id], onDelete: SetNull)
  actorOrganization Organization? @relation("AuditActorOrganization", fields: [actorOrganizationId], references: [id], onDelete: SetNull)

  @@index([actorUserId, occurredAt])
  @@index([resourceType, resourceId])
  @@index([correlationId])
  @@index([occurredAt])
  @@map("audit_logs")
}
'@

    Write-Utf8File "services\backend-api\prisma\schema.prisma" $schema

    Write-Step 4 10 "Writing Prisma service, database adapter, and seed data"

    $prismaService = @'
import { PrismaPg } from '@prisma/adapter-pg';
import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaClient } from '../generated/prisma/client';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor(configService: ConfigService) {
    const connectionString = configService.getOrThrow<string>('DATABASE_URL');
    const adapter = new PrismaPg({ connectionString });

    super({ adapter });
  }

  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
'@

    Write-Utf8File "services\backend-api\src\database\prisma.service.ts" $prismaService

    $databaseService = @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Injectable()
export class DatabaseService {
  constructor(private readonly prisma: PrismaService) {}

  get client(): PrismaService {
    return this.prisma;
  }

  async ping(): Promise<void> {
    await this.prisma.$queryRaw`SELECT 1`;
  }
}
'@

    Write-Utf8File "services\backend-api\src\database\database.service.ts" $databaseService

    $databaseModule = @'
import { Global, Module } from '@nestjs/common';
import { DatabaseService } from './database.service';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService, DatabaseService],
  exports: [PrismaService, DatabaseService],
})
export class DatabaseModule {}
'@

    Write-Utf8File "services\backend-api\src\database\database.module.ts" $databaseModule

    $databaseHealth = @'
import { Injectable } from '@nestjs/common';
import {
  HealthIndicatorResult,
  HealthIndicatorService,
} from '@nestjs/terminus';
import { DatabaseService } from '../database/database.service';

@Injectable()
export class DatabaseHealthIndicator {
  constructor(
    private readonly healthIndicatorService: HealthIndicatorService,
    private readonly databaseService: DatabaseService,
  ) {}

  async isHealthy(key: string): Promise<HealthIndicatorResult> {
    const indicator = this.healthIndicatorService.check(key);

    try {
      await this.databaseService.ping();
      return indicator.up();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Unknown PostgreSQL error';

      return indicator.down({ message });
    }
  }
}
'@

    Write-Utf8File "services\backend-api\src\health\database.health.ts" $databaseHealth

    $seed = @'
import { PrismaPg } from '@prisma/adapter-pg';
import { config } from 'dotenv';
import { resolve } from 'node:path';
import { PrismaClient } from '../src/generated/prisma/client';

config({
  path: resolve(process.cwd(), '../../.env'),
});

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error('DATABASE_URL is required to seed Solid Tracker.');
}

const adapter = new PrismaPg({ connectionString });
const prisma = new PrismaClient({ adapter });

const permissionDefinitions = [
  ['user.view', 'View users'],
  ['user.create', 'Create users'],
  ['user.disable', 'Disable users'],
  ['dealer.view', 'View dealers'],
  ['dealer.manage', 'Manage dealers'],
  ['dealer.staff.manage', 'Manage dealer staff'],
  ['customer.view', 'View customers'],
  ['customer.create', 'Create customers'],
  ['customer.update', 'Update customers'],
  ['customer.transfer', 'Transfer customers'],
  ['vehicle.view', 'View vehicles'],
  ['vehicle.create', 'Create vehicles'],
  ['vehicle.update', 'Update vehicles'],
  ['vehicle.location.view', 'View live vehicle location'],
  ['vehicle.history.view', 'View vehicle history'],
  ['device.view', 'View devices'],
  ['device.register', 'Register devices'],
  ['device.install', 'Install devices'],
  ['device.replace', 'Replace devices'],
  ['device.remove', 'Remove devices'],
  ['subscription.view', 'View subscriptions'],
  ['subscription.create', 'Create subscriptions'],
  ['subscription.suspend', 'Suspend subscriptions'],
  ['invoice.view', 'View invoices'],
  ['payment.view', 'View payments'],
  ['commission.view', 'View commissions'],
  ['settlement.create', 'Create settlements'],
  ['command.send', 'Send device commands'],
  ['command.engine_cutoff', 'Send engine-cutoff commands'],
] as const;

const roleDefinitions = [
  ['PLATFORM_SUPER_ADMIN', 'Platform Super Administrator'],
  ['PLATFORM_ADMIN', 'Platform Administrator'],
  ['PLATFORM_SUPPORT', 'Platform Support'],
  ['PLATFORM_FINANCE', 'Platform Finance'],
  ['DEALER_OWNER', 'Dealer Owner'],
  ['DEALER_MANAGER', 'Dealer Manager'],
  ['DEALER_INSTALLER', 'Dealer Installer'],
  ['DEALER_ACCOUNTS', 'Dealer Accounts'],
  ['CUSTOMER_OWNER', 'Customer Owner'],
  ['CUSTOMER_ADMIN', 'Customer Administrator'],
  ['CUSTOMER_VIEWER', 'Customer Viewer'],
] as const;

const rolePermissionCodes: Record<string, readonly string[]> = {
  PLATFORM_SUPER_ADMIN: permissionDefinitions.map(([code]) => code),
  PLATFORM_ADMIN: permissionDefinitions
    .map(([code]) => code)
    .filter((code) => code !== 'command.engine_cutoff'),
  PLATFORM_SUPPORT: [
    'user.view',
    'dealer.view',
    'customer.view',
    'vehicle.view',
    'vehicle.location.view',
    'vehicle.history.view',
    'device.view',
    'device.replace',
    'device.remove',
    'subscription.view',
    'invoice.view',
    'command.send',
  ],
  PLATFORM_FINANCE: [
    'dealer.view',
    'customer.view',
    'subscription.view',
    'invoice.view',
    'payment.view',
    'commission.view',
    'settlement.create',
  ],
  DEALER_OWNER: [
    'dealer.view',
    'dealer.staff.manage',
    'customer.view',
    'customer.create',
    'customer.update',
    'vehicle.view',
    'vehicle.create',
    'vehicle.update',
    'vehicle.location.view',
    'vehicle.history.view',
    'device.view',
    'device.install',
    'device.replace',
    'device.remove',
    'subscription.view',
    'subscription.create',
    'invoice.view',
    'payment.view',
    'commission.view',
  ],
  DEALER_MANAGER: [
    'customer.view',
    'customer.create',
    'customer.update',
    'vehicle.view',
    'vehicle.create',
    'vehicle.update',
    'vehicle.location.view',
    'vehicle.history.view',
    'device.view',
    'device.install',
    'device.replace',
    'device.remove',
    'subscription.view',
    'subscription.create',
    'invoice.view',
  ],
  DEALER_INSTALLER: [
    'customer.view',
    'vehicle.view',
    'device.view',
    'device.install',
    'device.replace',
    'device.remove',
  ],
  DEALER_ACCOUNTS: [
    'customer.view',
    'subscription.view',
    'invoice.view',
    'payment.view',
    'commission.view',
  ],
  CUSTOMER_OWNER: [
    'customer.view',
    'customer.update',
    'vehicle.view',
    'vehicle.location.view',
    'vehicle.history.view',
    'subscription.view',
    'invoice.view',
    'payment.view',
  ],
  CUSTOMER_ADMIN: [
    'customer.view',
    'vehicle.view',
    'vehicle.location.view',
    'vehicle.history.view',
    'subscription.view',
    'invoice.view',
  ],
  CUSTOMER_VIEWER: [
    'customer.view',
    'vehicle.view',
    'vehicle.location.view',
    'vehicle.history.view',
  ],
};

async function main(): Promise<void> {
  await prisma.organization.upsert({
    where: { code: 'ORG-PLATFORM' },
    update: {
      name: 'Solid Tracker Platform',
      legalName: 'Solid Tracker',
      type: 'PLATFORM',
      status: 'ACTIVE',
    },
    create: {
      code: 'ORG-PLATFORM',
      name: 'Solid Tracker Platform',
      legalName: 'Solid Tracker',
      type: 'PLATFORM',
      status: 'ACTIVE',
    },
  });

  for (const [code, name] of permissionDefinitions) {
    await prisma.permission.upsert({
      where: { code },
      update: {
        name,
        status: 'ACTIVE',
      },
      create: {
        code,
        name,
        status: 'ACTIVE',
        isSystem: undefined,
      },
    });
  }

  for (const [code, name] of roleDefinitions) {
    await prisma.role.upsert({
      where: { code },
      update: {
        name,
        status: 'ACTIVE',
        isSystem: true,
      },
      create: {
        code,
        name,
        status: 'ACTIVE',
        isSystem: true,
      },
    });
  }

  const permissions = await prisma.permission.findMany({
    select: {
      id: true,
      code: true,
    },
  });

  const permissionIdByCode = new Map(
    permissions.map((permission) => [permission.code, permission.id]),
  );

  for (const [roleCode] of roleDefinitions) {
    const role = await prisma.role.findUniqueOrThrow({
      where: { code: roleCode },
      select: { id: true },
    });

    const permissionCodes = rolePermissionCodes[roleCode] ?? [];

    for (const permissionCode of permissionCodes) {
      const permissionId = permissionIdByCode.get(permissionCode);

      if (!permissionId) {
        throw new Error(`Missing seeded permission: ${permissionCode}`);
      }

      await prisma.rolePermission.upsert({
        where: {
          roleId_permissionId: {
            roleId: role.id,
            permissionId,
          },
        },
        update: {},
        create: {
          roleId: role.id,
          permissionId,
        },
      });
    }
  }

  const [organizationCount, roleCount, permissionCount] = await Promise.all([
    prisma.organization.count(),
    prisma.role.count(),
    prisma.permission.count(),
  ]);

  console.log('Solid Tracker seed completed.');
  console.log({
    organizationCount,
    roleCount,
    permissionCount,
  });
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
'@

    # Remove one invalid field from the seed at write time; Permission has no isSystem.
    $seed = $seed.Replace(
        "        isSystem: undefined,`n",
        ""
    ).Replace(
        "        isSystem: undefined,`r`n",
        ""
    )

    Write-Utf8File "services\backend-api\prisma\seed.ts" $seed

    Write-Step 5 10 "Updating package scripts and generated-code exclusions"

    $backendPackage = Get-Content `
        -LiteralPath "services\backend-api\package.json" `
        -Raw |
        ConvertFrom-Json

    Set-JsonScript $backendPackage "test:e2e" "node --experimental-vm-modules ./node_modules/jest/bin/jest.js --config ./test/jest-e2e.json"

    Set-JsonScript $backendPackage "prisma:format" "prisma format --config prisma.config.ts"
    Set-JsonScript $backendPackage "prisma:validate" "prisma validate --config prisma.config.ts"
    Set-JsonScript $backendPackage "prisma:generate" "prisma generate --config prisma.config.ts"
    Set-JsonScript $backendPackage "prisma:migrate:dev" "prisma migrate dev --config prisma.config.ts"
    Set-JsonScript $backendPackage "prisma:migrate:status" "prisma migrate status --config prisma.config.ts"
    Set-JsonScript $backendPackage "prisma:seed" "prisma db seed --config prisma.config.ts"
    Set-JsonScript $backendPackage "prisma:studio" "prisma studio --config prisma.config.ts"
    Set-JsonScript $backendPackage "prebuild" "prisma generate --config prisma.config.ts"

    Save-JsonFile "services\backend-api\package.json" $backendPackage

    $rootPackage = Get-Content -LiteralPath "package.json" -Raw | ConvertFrom-Json

    Set-JsonScript $rootPackage "db:format" "pnpm --filter @solid-tracker/backend-api prisma:format"
    Set-JsonScript $rootPackage "db:validate" "pnpm --filter @solid-tracker/backend-api prisma:validate"
    Set-JsonScript $rootPackage "db:generate" "pnpm --filter @solid-tracker/backend-api prisma:generate"
    Set-JsonScript $rootPackage "db:migrate:dev" "pnpm --filter @solid-tracker/backend-api prisma:migrate:dev"
    Set-JsonScript $rootPackage "db:migrate:status" "pnpm --filter @solid-tracker/backend-api prisma:migrate:status"
    Set-JsonScript $rootPackage "db:seed" "pnpm --filter @solid-tracker/backend-api prisma:seed"
    Set-JsonScript $rootPackage "db:studio" "pnpm --filter @solid-tracker/backend-api prisma:studio"

    Save-JsonFile "package.json" $rootPackage

    Write-Utf8File "services\backend-api\.prettierignore" @'
src/generated/prisma/
prisma/migrations/
'@

    $eslintPath = "services\backend-api\eslint.config.mjs"
    $eslintContent = [System.IO.File]::ReadAllText(
        (Join-Path $script:RootPath $eslintPath)
    )

    if (-not $eslintContent.Contains("src/generated/prisma/**")) {
        $anchor = "export default tseslint.config("

        if (-not $eslintContent.Contains($anchor)) {
            throw "Could not find the ESLint flat-config insertion point."
        }

        $replacement = @'
export default tseslint.config(
  {
    ignores: ['src/generated/prisma/**'],
  },
'@

        $eslintContent = $eslintContent.Replace($anchor, $replacement.TrimEnd())
        [System.IO.File]::WriteAllText(
            (Join-Path $script:RootPath $eslintPath),
            $eslintContent,
            $script:Utf8NoBom
        )
    }

    Add-LineIfMissing ".gitignore" "services/backend-api/src/generated/prisma/"

    Write-Step 6 10 "Formatting and validating the Prisma schema"

    Invoke-CheckedCommand "Prisma format" {
        pnpm.cmd --filter "@solid-tracker/backend-api" exec prisma format --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma validate" {
        pnpm.cmd --filter "@solid-tracker/backend-api" exec prisma validate --config prisma.config.ts
    }

    Write-Step 7 10 "Creating the first PostgreSQL migration"

    $migrationRoot = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\migrations"

    if (Test-Path -LiteralPath $migrationRoot) {
        $existingMigrations = @(
            Get-ChildItem -LiteralPath $migrationRoot -Directory -ErrorAction SilentlyContinue
        )

        if ($existingMigrations.Count -gt 0) {
            throw "Prisma migrations already exist. This Phase 1 script expects an empty migrations directory."
        }
    }

    Invoke-CheckedCommand "Prisma migration create-only" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate dev `
            --name identity_customer_foundation `
            --create-only `
            --config prisma.config.ts
    }

    $migrationDirectory = Get-ChildItem `
        -LiteralPath $migrationRoot `
        -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $migrationDirectory) {
        throw "Prisma did not create a migration directory."
    }

    $migrationSqlPath = Join-Path $migrationDirectory.FullName "migration.sql"

    if (-not (Test-Path -LiteralPath $migrationSqlPath)) {
        throw "Prisma migration.sql was not created."
    }

    $customSql = @'

-- Solid Tracker Phase 1 invariants that require PostgreSQL-native constraints.

ALTER TABLE "customers"
ADD CONSTRAINT "customers_direct_group_consistency"
CHECK (
  "managingDealerId" IS NOT NULL
  OR "customerGroupId" IS NULL
);

ALTER TABLE "customer_dealer_assignments"
ADD CONSTRAINT "customer_dealer_assignment_management_consistency"
CHECK (
  (
    "managementType" = 'PLATFORM'
    AND "dealerOrganizationId" IS NULL
  )
  OR
  (
    "managementType" = 'DEALER'
    AND "dealerOrganizationId" IS NOT NULL
  )
);

CREATE UNIQUE INDEX
  "customer_dealer_assignments_one_active_per_customer"
ON "customer_dealer_assignments" ("customerId")
WHERE "endedAt" IS NULL;

CREATE UNIQUE INDEX
  "customer_memberships_one_active_primary_per_customer"
ON "customer_memberships" ("customerId")
WHERE "isPrimary" = TRUE AND "status" = 'ACTIVE';

CREATE UNIQUE INDEX
  "organization_memberships_one_active_primary_per_organization"
ON "organization_memberships" ("organizationId")
WHERE "isPrimary" = TRUE AND "status" = 'ACTIVE';

CREATE OR REPLACE FUNCTION "solid_tracker_assert_dealer_organization"(
  organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  organization_type "OrganizationType";
BEGIN
  SELECT "type"
  INTO organization_type
  FROM "organizations"
  WHERE "id" = organization_id;

  IF NOT FOUND OR organization_type <> 'DEALER' THEN
    RAISE EXCEPTION
      'Organization % must exist and have type DEALER',
      organization_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION "solid_tracker_validate_dealer_profile"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM "solid_tracker_assert_dealer_organization"(NEW."organizationId");
  RETURN NEW;
END;
$$;

CREATE TRIGGER "dealer_profiles_validate_organization"
BEFORE INSERT OR UPDATE OF "organizationId"
ON "dealer_profiles"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_dealer_profile"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_customer_group"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM "solid_tracker_assert_dealer_organization"(
    NEW."dealerOrganizationId"
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER "customer_groups_validate_dealer"
BEFORE INSERT OR UPDATE OF "dealerOrganizationId"
ON "customer_groups"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_customer_group"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_customer"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  group_dealer_id UUID;
BEGIN
  IF NEW."managingDealerId" IS NOT NULL THEN
    PERFORM "solid_tracker_assert_dealer_organization"(
      NEW."managingDealerId"
    );
  END IF;

  IF NEW."customerGroupId" IS NOT NULL THEN
    IF NEW."managingDealerId" IS NULL THEN
      RAISE EXCEPTION
        'A direct customer cannot belong to a dealer customer group';
    END IF;

    SELECT "dealerOrganizationId"
    INTO group_dealer_id
    FROM "customer_groups"
    WHERE "id" = NEW."customerGroupId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Customer group % does not exist',
        NEW."customerGroupId";
    END IF;

    IF group_dealer_id <> NEW."managingDealerId" THEN
      RAISE EXCEPTION
        'Customer group dealer must match the customer managing dealer';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "customers_validate_management"
BEFORE INSERT OR UPDATE OF "managingDealerId", "customerGroupId"
ON "customers"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_customer"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_customer_assignment"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."managementType" = 'DEALER' THEN
    PERFORM "solid_tracker_assert_dealer_organization"(
      NEW."dealerOrganizationId"
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "customer_assignments_validate_dealer"
BEFORE INSERT OR UPDATE OF "managementType", "dealerOrganizationId"
ON "customer_dealer_assignments"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_customer_assignment"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_individual_profile"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM "customers"
    WHERE "id" = NEW."customerId"
      AND "customerType" = 'INDIVIDUAL'
  ) THEN
    RAISE EXCEPTION
      'Individual profile requires an INDIVIDUAL customer';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "individual_profiles_validate_customer_type"
BEFORE INSERT OR UPDATE OF "customerId"
ON "individual_customer_profiles"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_individual_profile"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_organization_profile"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM "customers"
    WHERE "id" = NEW."customerId"
      AND "customerType" = 'ORGANIZATION'
  ) THEN
    RAISE EXCEPTION
      'Organization profile requires an ORGANIZATION customer';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "organization_profiles_validate_customer_type"
BEFORE INSERT OR UPDATE OF "customerId"
ON "organization_customer_profiles"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_organization_profile"();
'@

    Add-Content `
        -LiteralPath $migrationSqlPath `
        -Value $customSql `
        -Encoding UTF8

    Write-Host ("Customized migration: {0}" -f $migrationDirectory.Name) -ForegroundColor Green

    Write-Step 8 10 "Applying migration, generating Prisma Client, and seeding"

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

    Invoke-CheckedCommand "Prisma seed" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma db seed `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    Write-Step 9 10 "Running quality checks, tests, build, and database verification"

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

    $tableCountOutput = docker compose `
        --env-file .env `
        exec -T postgres `
        sh -lc `
        'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ''public'';"'

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL table verification failed."
    }

    $tableCountText = ($tableCountOutput | Out-String).Trim()
    $tableCount = 0

    if (-not [int]::TryParse($tableCountText, [ref]$tableCount)) {
        throw "Could not parse PostgreSQL table count: $tableCountText"
    }

    if ($tableCount -lt 18) {
        throw "Expected at least 18 public tables, but found $tableCount."
    }

    Write-Host ("PostgreSQL public tables: {0}" -f $tableCount) -ForegroundColor Green

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
- The PostgreSQL migration contains additional native constraints and triggers.
- Seed execution is explicit and idempotent.
- The seed creates the platform organization, system roles, permissions, and role-permission mappings.
- No default administrator password or insecure account is created.
'@

    Write-Utf8File "docs\architecture\prisma-phase-1.md" $documentation

    Write-Step 10 10 "Committing Prisma Phase 1 foundation"

    git add -- `
        ".gitignore" `
        "package.json" `
        "pnpm-lock.yaml" `
        "pnpm-workspace.yaml" `
        "docs/architecture/prisma-phase-1.md" `
        "scripts/solid-tracker-prisma-phase1-foundation.ps1" `
        "services/backend-api/.prettierignore" `
        "services/backend-api/eslint.config.mjs" `
        "services/backend-api/package.json" `
        "services/backend-api/prisma.config.ts" `
        "services/backend-api/prisma" `
        "services/backend-api/src/database" `
        "services/backend-api/src/health/database.health.ts"

    git commit -m "feat(database): establish Prisma identity and customer foundation"

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
    Write-Host "Database commands:" -ForegroundColor Yellow
    Write-Host "pnpm.cmd db:migrate:status" -ForegroundColor Green
    Write-Host "pnpm.cmd db:seed" -ForegroundColor Green
    Write-Host "pnpm.cmd db:studio" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "PRISMA PHASE 1 FOUNDATION FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Do not delete the migration or database manually." -ForegroundColor Yellow
    Write-Host "The failure can be diagnosed and resumed from this state." -ForegroundColor Yellow
    exit 1
}
