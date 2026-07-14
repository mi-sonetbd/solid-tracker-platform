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