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