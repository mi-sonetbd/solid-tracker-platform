# Tracking and Traccar Operations API

## Scope

This stage exposes the existing Traccar integration foundation through authenticated REST APIs and secure webhook processing.

It implements encrypted Traccar credentials, server health checks, physical-device synchronization, live positions, bounded history, normalized events, secure webhook ingestion, geofences, notification rules, device commands, integration jobs, authorization scope, audit records, and full E2E coverage.

No Prisma migration is introduced. The existing tracking foundation already contains the required tables, constraints, indexes, and validation triggers.

## System boundary

```text
GPS device
    â†“ protocol
Traccar
    â†“ REST and webhook integration
Solid Tracker NestJS API
    â†“ authenticated business API
Android, web, dealer, customer, and operations clients
```

Clients do not connect directly to Traccar.

## Audit scope

The shared identity audit model supports platform, zone, dealer, customer-group, customer, vehicle, and self scopes.

Tracking command audits use the assigned vehicle when present. Platform-only commands without a vehicle use platform scope. A non-platform device command without a vehicle remains identifiable through its resource type and resource ID without inventing an unsupported device scope.

Platform-only Traccar device synchronization and disable operations use platform audit scope.

## Command safety

Engine cutoff and restore require command permission, engine-control permission, an active vehicle-device assignment, approval by a different authorized user, and an unexpired approval window.

## Credential security

Traccar credentials are encrypted with AES-256-GCM. The runtime environment stores the encryption key and webhook secret. API responses never expose encrypted credential material.