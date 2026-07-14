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

    Write-Host "[CREATED] $RelativePath" -ForegroundColor Green
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Domain Model Documentation" -ForegroundColor Cyan
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

    # The script itself is expected to be untracked on its first run.
    # Any other modification still blocks generation.
    $statusBefore = @(git status --short)
    $allowedSelfEntry = "?? scripts/solid-tracker-domain-model-documentation.ps1"
    $unexpectedChanges = @(
        $statusBefore | Where-Object {
            $_ -and $_.TrimEnd() -ne $allowedSelfEntry
        }
    )

    if ($unexpectedChanges.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow
        $unexpectedChanges | ForEach-Object {
            Write-Host $_ -ForegroundColor Yellow
        }

        throw "Working tree contains changes other than this documentation script."
    }

    Write-Step 1 6 "Creating domain documentation structure"

    foreach ($directory in @(
        "docs\requirements",
        "docs\architecture",
        "docs\diagrams",
        "docs\decisions"
    )) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Write-Step 2 6 "Writing actors, roles, and permission boundaries"

    $actorsAndRoles = @'
# Solid Tracker Actors and Roles

## Purpose

This document defines the people, organizations, roles, and authorization scopes used by the Solid Tracker platform.

## Core identity model

Solid Tracker separates five concepts:

1. **Person** — the real human being.
2. **User account** — the login identity.
3. **Organization** — the business or operating entity.
4. **Role** — the category of work performed.
5. **Scope** — the boundary within which permissions apply.

Authorization is evaluated as:

```text
authenticated user
+ active account
+ active membership
+ role permissions
+ scope
+ resource ownership
+ business status
```

## Organization types

- `PLATFORM`
- `DEALER`
- `CUSTOMER_ORGANIZATION`

A dealer is an organization, not a user account. Dealer owners, managers, installers, and accounts staff are users who act through memberships and role assignments.

## Platform roles

- `PLATFORM_SUPER_ADMIN`
- `PLATFORM_ADMIN`
- `PLATFORM_SUPPORT`
- `PLATFORM_FINANCE`

## Dealer roles

- `DEALER_OWNER`
- `DEALER_MANAGER`
- `DEALER_INSTALLER`
- `DEALER_ACCOUNTS`

## Customer roles

- `CUSTOMER_OWNER`
- `CUSTOMER_ADMIN`
- `CUSTOMER_VIEWER`

Additional customer roles such as fleet manager or driver are intentionally deferred until their permissions are formally required.

## Authorization scopes

- `PLATFORM`
- `ZONE`
- `DEALER`
- `CUSTOMER_GROUP`
- `CUSTOMER`
- `VEHICLE`
- `SELF`

## Permission examples

- `customer.view`
- `customer.create`
- `customer.update`
- `customer.transfer`
- `vehicle.view`
- `vehicle.location.view`
- `vehicle.history.view`
- `device.register`
- `device.install`
- `device.replace`
- `subscription.create`
- `invoice.view`
- `payment.view`
- `commission.view`
- `settlement.create`
- `command.send`
- `command.engine_cutoff`

## Dealer versus dealer manager

| Subject | Dealer | Dealer Manager |
|---|---|---|
| Type | Organization | User role |
| Own business identity | Yes | No |
| Holds commission account | Yes | No by default |
| Holds payout account | Yes | No by default |
| Owns customer relationship | Yes | Acts on dealer behalf |
| Can remain active after employee departure | Yes | No |
| Historical settlement owner | Yes | No |

## Customer access principle

A customer may be either:

- platform-managed, with no managing dealer; or
- dealer-managed, with one current managing dealer.

A customer group belongs to one dealer and may contain only customers managed by that dealer.
'@

    Write-Utf8File "docs\requirements\actors-and-roles.md" $actorsAndRoles

    $permissionBoundaries = @'
# Solid Tracker Permission Boundaries

## Least-privilege principle

Users receive only the permissions required for their responsibilities.

## Platform boundaries

### Platform super administrator

May manage platform-wide configuration, privileged administrators, global integrations, and emergency security operations.

### Platform administrator

May manage platform users, dealers, customers, plans, and operational settings according to assigned permissions.

### Platform support

May investigate devices, installations, Traccar synchronization, and customer issues. Support access does not automatically include finance operations or high-risk remote commands.

### Platform finance

May manage invoices, payments, commissions, payout accounts, settlements, and financial reports. Finance access does not automatically include live tracking or device-control commands.

## Dealer boundaries

### Dealer owner

May manage the dealer organization, dealer staff, dealer customers, inventory, and permitted financial records.

### Dealer manager

May manage dealer customers and operational resources within the assigned dealer or customer-group scope.

### Dealer installer

May view relevant customers and vehicles and perform installations, replacements, and removals for devices allocated to the dealer.

### Dealer accounts

May view invoices, payments, commissions, and settlements for the dealer. This role does not automatically permit device reassignment or installation.

## Customer boundaries

### Customer owner

May manage the customer profile, customer users, vehicles, subscriptions, invoices, and notification preferences.

### Customer admin

May manage operational data and customer users within assigned permissions.

### Customer viewer

May view permitted vehicles, live location, route history, and selected reports.

## Scope enforcement examples

- A dealer manager with `customer.create` may create customers only under the assigned dealer.
- A manager scoped to one customer group may not view customers in another group.
- A customer user may view only vehicles belonging to the customer membership scope.
- A dealer installer may install only devices allocated to the installer’s dealer.
- A platform finance user may view settlements but may not send engine-control commands.

## High-risk actions

The following actions require dedicated permission, reason capture, audit logging, and step-up authentication where implemented:

- changing dealer payout accounts;
- issuing manual refunds;
- transferring customers between dealers;
- modifying device IMEI;
- changing commission rules;
- creating privileged administrators;
- sending engine-cutoff commands.
'@

    Write-Utf8File "docs\requirements\permission-boundaries.md" $permissionBoundaries

    Write-Step 3 6 "Writing business rules and domain architecture"

    $businessRules = @'
# Solid Tracker Core Business Rules

## Customer management

1. Customers are either `INDIVIDUAL` or `ORGANIZATION`.
2. A customer may exist without a user account.
3. A customer may be platform-managed or dealer-managed.
4. `managingDealerId = NULL` means the customer is platform-managed.
5. A customer group belongs to exactly one dealer.
6. Customer-group membership is optional.
7. A direct customer cannot belong to a dealer customer group.
8. Customer acquisition source is historical attribution and is separate from current dealer management.
9. Dealer-transfer history must be preserved.
10. Historical commissions remain with the dealer responsible at transaction time.

## Vehicle and device rules

1. A vehicle and a GPS device are separate entities.
2. One vehicle may have at most one active `PRIMARY` GPS assignment in Version 1.
3. One GPS device may have at most one active vehicle assignment.
4. Device assignment history must never be overwritten.
5. Device ownership and device custody are separate.
6. Device lifecycle state is separate from telemetry state.
7. Vehicle business status is separate from online/offline tracking status.
8. IMEI is stored as text and must be globally unique when present.
9. Traccar IDs are external-system identifiers and must not replace Solid Tracker IDs.
10. Device replacement must end the old assignment and create a new installation and assignment transactionally.

## Subscription and billing rules

1. One active vehicle may have at most one active tracking subscription in Version 1.
2. Automatic invoice generation is supported.
3. Automatic payment is enabled only when the payment provider supports secure recurring authorization.
4. Plan prices are versioned; historical invoices retain the price effective at issue time.
5. One invoice may receive multiple payments.
6. Payments and invoices are linked through payment allocations.
7. Payment success requires verified gateway confirmation.
8. Gateway events must be idempotent.
9. Financial records are append-only; corrections use reversal or adjustment entries.
10. Customer suspension, user-account status, device lifecycle, and telemetry state remain separate.

## Commission and settlement rules

1. Commission belongs to the dealer organization, not the dealer manager.
2. Commission is calculated from the applicable rule at transaction time.
3. Commission entries store calculation snapshots.
4. Commission may move through pending, earned, available, settlement-pending, settled, or reversed states.
5. Payout accounts are verified and sensitive references are encrypted or tokenized.
6. Dealer settlements group eligible commission entries.
7. Refunds create reversals instead of deleting financial history.
8. Already-settled reversals may create a negative dealer balance to be recovered from future settlements.

## Authentication and security rules

1. Mobile number is the primary unique login identity in Version 1.
2. Normal login uses mobile number and password.
3. OTP is used for verification, activation, password recovery, and high-risk actions.
4. OTP-only login is not enabled initially.
5. Passwords and refresh tokens are stored only as hashes.
6. Access tokens are short-lived.
7. Refresh tokens are rotated and session-bound.
8. User, membership, and role-assignment statuses are evaluated separately.
9. Permissions are action-based and combined with scope.
10. Sensitive actions require audit logging.
'@

    Write-Utf8File "docs\requirements\business-rules.md" $businessRules

    $domainModel = @'
# Solid Tracker Domain Model

## Bounded contexts

### Identity and Access

Owns users, organizations, memberships, roles, permissions, sessions, invitations, OTP challenges, and security events.

### Dealer and Customer Management

Owns dealers, dealer profiles, zones, customers, customer profiles, customer groups, memberships, and dealer-assignment history.

### Asset and Installation Management

Owns vehicles, device models, physical devices, ownership history, custody history, dealer allocations, installations, and vehicle-device assignments.

### Subscription and Billing

Owns service plans, subscriptions, invoices, invoice lines, payments, allocations, gateway events, and refunds.

### Commission and Settlement

Owns commission rules, commission entries, dealer payout accounts, dealer ledger entries, settlements, and settlement items.

### Tracking Integration

Owns Traccar servers, mappings, synchronization state, normalized tracking events, geofences, and command requests.

### Notification and Audit

Owns notification rules, notification deliveries, audit logs, and correlation identifiers.

## Primary aggregate boundaries

- **Organization aggregate** — organization, dealer profile, memberships.
- **Customer aggregate** — customer, type-specific profile, group relationship, customer memberships.
- **Vehicle aggregate** — vehicle and current business state.
- **Device aggregate** — device, model reference, ownership, custody, and lifecycle.
- **Installation aggregate** — installation and vehicle-device assignment transaction.
- **Subscription aggregate** — subscription and service period.
- **Invoice aggregate** — invoice and invoice lines.
- **Payment aggregate** — payment, allocations, and gateway events.
- **Commission aggregate** — commission rule snapshot and commission entry.
- **Settlement aggregate** — settlement and settlement items.
- **Identity aggregate** — user, session, membership, and role assignments.

## Important invariants

- Only one active primary device assignment per vehicle.
- Only one active vehicle assignment per device.
- Only one active tracking subscription per vehicle in Version 1.
- A customer group and customer managing dealer must match.
- A direct customer cannot have a dealer customer group.
- Payment gateway events are idempotent.
- Historical assignment, commission, settlement, and audit records are never hard-deleted.
'@

    Write-Utf8File "docs\architecture\domain-model.md" $domainModel

    $dataOwnership = @'
# Solid Tracker Data Ownership

## System-of-record boundaries

### Solid Tracker PostgreSQL

Authoritative for:

- users, organizations, roles, permissions, and memberships;
- dealers, customers, customer groups, and assignment history;
- vehicles, devices, installations, ownership, custody, and allocations;
- subscriptions, invoices, payments, commissions, and settlements;
- audit logs, security events, notification history, and integration mappings.

### Traccar

Authoritative for:

- raw GPS positions;
- route history;
- trips and stops;
- device communication timestamps;
- speed, course, altitude, and telemetry attributes;
- native tracking events and current external device status.

### Redis

Used for temporary or high-speed operational state:

- latest telemetry cache;
- online/offline cache;
- rate limits;
- OTP cooldowns and attempt counters;
- background queues;
- notification cooldown state;
- session and authorization cache;
- command timeout state.

Redis is not the authoritative source for users, payments, commissions, ownership, or subscription records.

## Integration rule

Android and web clients communicate with the NestJS API. NestJS enforces authentication, authorization, scope, subscription entitlement, and business rules before communicating with Traccar.

Clients do not receive Traccar credentials and do not depend directly on Traccar database identifiers.
'@

    Write-Utf8File "docs\architecture\data-ownership.md" $dataOwnership

    $securityModel = @'
# Solid Tracker Security Model

## Authentication

- Primary login identity: normalized mobile number.
- Secondary identity: optional verified email.
- Normal login: mobile number and password.
- OTP purposes: verification, activation, password reset, and sensitive actions.
- Password hashing: Argon2id preferred.
- Access tokens: short-lived JWTs.
- Refresh tokens: rotated, session-bound, and stored as hashes.

## Authorization

Authorization requires:

- active user account;
- active organization or customer membership;
- active role assignment;
- required permission;
- matching scope;
- resource ownership validation;
- valid business state.

## Session security

Sessions record device, platform, IP address, user agent, expiry, and revocation state.

Sessions may be revoked after:

- logout;
- password change;
- account disablement;
- security incident;
- refresh-token reuse;
- administrator action.

## OTP controls

- short expiry;
- one-time use;
- maximum attempts;
- purpose binding;
- destination binding;
- request rate limits;
- hashed code storage.

## High-risk operations

High-risk operations require dedicated permissions, reason capture, audit logging, and step-up verification when available.

## Audit

Audit records include actor, organization, action, resource, before/after state, scope, IP address, user agent, correlation ID, and timestamp.
'@

    Write-Utf8File "docs\architecture\security-model.md" $securityModel

    Write-Step 4 6 "Writing Mermaid diagrams and architecture decision record"

    $domainDiagram = @'
flowchart TB
    PLATFORM[Solid Tracker Platform]
    ZONE[Zone]
    DEALER[Dealer Organization]
    GROUP[Customer Group]
    CUSTOMER[Customer]
    VEHICLE[Vehicle]
    DEVICE[GPS Device]
    SUBSCRIPTION[Subscription]
    INVOICE[Invoice]
    PAYMENT[Payment]
    COMMISSION[Commission Entry]
    SETTLEMENT[Dealer Settlement]
    TRACCAR[Traccar]
    USER[User]
    ROLE[Role Assignment]

    PLATFORM --> ZONE
    ZONE --> DEALER
    DEALER --> GROUP
    DEALER --> CUSTOMER
    GROUP --> CUSTOMER
    CUSTOMER --> VEHICLE
    VEHICLE --> SUBSCRIPTION
    VEHICLE --> DEVICE
    SUBSCRIPTION --> INVOICE
    PAYMENT --> INVOICE
    PAYMENT --> COMMISSION
    COMMISSION --> SETTLEMENT
    DEVICE --> TRACCAR
    USER --> ROLE
    ROLE --> PLATFORM
    ROLE --> ZONE
    ROLE --> DEALER
    ROLE --> GROUP
    ROLE --> CUSTOMER
    ROLE --> VEHICLE
'@

    Write-Utf8File "docs\diagrams\domain-model.mmd" $domainDiagram

    $erd = @'
erDiagram
    ORGANIZATION ||--o{ ORGANIZATION_MEMBERSHIP : has
    USER ||--o{ ORGANIZATION_MEMBERSHIP : joins
    USER ||--o{ ROLE_ASSIGNMENT : receives
    ROLE ||--o{ ROLE_ASSIGNMENT : assigned
    ROLE ||--o{ ROLE_PERMISSION : contains
    PERMISSION ||--o{ ROLE_PERMISSION : included

    ORGANIZATION ||--o| DEALER_PROFILE : may_have
    ORGANIZATION ||--o{ CUSTOMER_GROUP : owns
    CUSTOMER_GROUP ||--o{ CUSTOMER : groups
    ORGANIZATION ||--o{ CUSTOMER : manages

    CUSTOMER ||--o| INDIVIDUAL_CUSTOMER_PROFILE : profile
    CUSTOMER ||--o| ORGANIZATION_CUSTOMER_PROFILE : profile
    CUSTOMER ||--o{ CUSTOMER_MEMBERSHIP : has
    USER ||--o{ CUSTOMER_MEMBERSHIP : joins
    CUSTOMER ||--o{ CUSTOMER_DEALER_ASSIGNMENT : history

    CUSTOMER ||--o{ VEHICLE : owns
    DEVICE_MODEL ||--o{ DEVICE : classifies
    DEVICE ||--o{ DEVICE_OWNERSHIP_HISTORY : ownership
    DEVICE ||--o{ DEVICE_CUSTODY_HISTORY : custody
    ORGANIZATION ||--o{ DEALER_DEVICE_ALLOCATION : receives
    DEVICE ||--o{ DEALER_DEVICE_ALLOCATION : allocated

    VEHICLE ||--o{ DEVICE_INSTALLATION : receives
    DEVICE ||--o{ DEVICE_INSTALLATION : installed
    VEHICLE ||--o{ VEHICLE_DEVICE_ASSIGNMENT : has
    DEVICE ||--o{ VEHICLE_DEVICE_ASSIGNMENT : assigned

    SERVICE_PLAN ||--o{ SUBSCRIPTION : defines
    CUSTOMER ||--o{ SUBSCRIPTION : owns
    VEHICLE ||--o{ SUBSCRIPTION : covered
    SUBSCRIPTION ||--o{ INVOICE : bills
    INVOICE ||--|{ INVOICE_LINE : contains

    CUSTOMER ||--o{ PAYMENT : makes
    PAYMENT ||--o{ PAYMENT_ALLOCATION : allocates
    INVOICE ||--o{ PAYMENT_ALLOCATION : receives
    PAYMENT ||--o{ PAYMENT_GATEWAY_EVENT : confirmed_by

    COMMISSION_RULE ||--o{ COMMISSION_ENTRY : calculates
    ORGANIZATION ||--o{ COMMISSION_ENTRY : earns
    PAYMENT ||--o{ COMMISSION_ENTRY : triggers
    DEALER_SETTLEMENT ||--|{ DEALER_SETTLEMENT_ITEM : contains
    COMMISSION_ENTRY ||--o| DEALER_SETTLEMENT_ITEM : settled_by
    ORGANIZATION ||--o{ DEALER_SETTLEMENT : receives

    TRACCAR_SERVER ||--o{ TRACCAR_DEVICE_MAPPING : hosts
    DEVICE ||--o{ TRACCAR_DEVICE_MAPPING : maps
    VEHICLE ||--o{ TRACKING_EVENT : generates
    DEVICE ||--o{ TRACKING_EVENT : reports

    CUSTOMER ||--o{ GEOFENCE : owns
    GEOFENCE ||--o{ VEHICLE_GEOFENCE_ASSIGNMENT : applies
    VEHICLE ||--o{ VEHICLE_GEOFENCE_ASSIGNMENT : monitored

    CUSTOMER ||--o{ NOTIFICATION_RULE : configures
    TRACKING_EVENT ||--o{ NOTIFICATION : triggers
    USER ||--o{ NOTIFICATION : receives
    USER ||--o{ AUDIT_LOG : acts
'@

    Write-Utf8File "docs\diagrams\entity-relationship.mmd" $erd

    $adr = @'
# ADR-0001: Core Domain Boundaries

- **Status:** Accepted
- **Date:** 2026-07-14

## Context

Solid Tracker requires customer and dealer management, device installation, subscriptions, online payment, automated dealer commission, Traccar integration, and strict permission boundaries.

Mixing identity, organizations, customers, devices, telemetry, and financial records into a small set of tables would make auditing, transfers, replacements, settlements, and authorization unsafe.

## Decision

The platform will use explicit domain boundaries:

- identity and access;
- dealer and customer management;
- assets and installations;
- subscriptions and billing;
- commission and settlement;
- tracking integration;
- notifications and audit.

The following decisions are accepted:

- dealers are organizations, not users;
- customers may be direct or dealer-managed;
- customer groups belong to dealers;
- customers may be individual or organizational;
- vehicles and devices are separate;
- one active primary tracker per vehicle in Version 1;
- one active vehicle assignment per device;
- one active subscription per vehicle in Version 1;
- PostgreSQL is the business source of truth;
- Traccar is the telemetry source of truth;
- Redis stores temporary operational state;
- Android and web clients access Traccar only through NestJS;
- financial history is append-only;
- authorization uses permissions plus scope.

## Consequences

### Positive

- clear ownership and authorization boundaries;
- complete history for device replacement and customer transfer;
- auditable commission and settlement processing;
- reduced coupling to Traccar;
- support for direct sales and dealer sales;
- future support for multiple Traccar servers.

### Costs

- more entities and relationships;
- more transactional business operations;
- additional authorization checks;
- background synchronization and retry requirements.

These costs are accepted because they prevent data corruption, permission leakage, and financial disputes.
'@

    Write-Utf8File "docs\decisions\ADR-0001-core-domain-boundaries.md" $adr

    Write-Step 5 6 "Validating generated documentation"

    $requiredFiles = @(
        "docs\requirements\actors-and-roles.md",
        "docs\requirements\permission-boundaries.md",
        "docs\requirements\business-rules.md",
        "docs\architecture\domain-model.md",
        "docs\architecture\data-ownership.md",
        "docs\architecture\security-model.md",
        "docs\diagrams\domain-model.mmd",
        "docs\diagrams\entity-relationship.mmd",
        "docs\decisions\ADR-0001-core-domain-boundaries.md"
    )

    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $script:RootPath $file

        if (-not (Test-Path -LiteralPath $fullPath)) {
            throw "Expected generated file is missing: $file"
        }

        if ((Get-Item -LiteralPath $fullPath).Length -eq 0) {
            throw "Generated file is empty: $file"
        }
    }

    $erdContent = Get-Content -LiteralPath "docs\diagrams\entity-relationship.mmd" -Raw

    if (-not $erdContent.Contains("erDiagram")) {
        throw "The ER diagram does not contain a Mermaid erDiagram declaration."
    }

    Write-Host "Documentation validation passed." -ForegroundColor Green

    Write-Step 6 6 "Committing the domain model foundation"

    git add -- `
        "docs/requirements" `
        "docs/architecture" `
        "docs/diagrams" `
        "docs/decisions" `
        "scripts/solid-tracker-domain-model-documentation.ps1"

    git commit -m "docs(domain): define core platform domain model"

    if ($LASTEXITCODE -ne 0) {
        throw "Git commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Domain Model Documentation Ready" -ForegroundColor Cyan
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
    Write-Host "Next development stage:" -ForegroundColor Yellow
    Write-Host "Prisma schema design and first PostgreSQL migration" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "DOMAIN MODEL DOCUMENTATION FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    exit 1
}
