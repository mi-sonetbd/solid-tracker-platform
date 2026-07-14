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

- **Organization aggregate** â€” organization, dealer profile, memberships.
- **Customer aggregate** â€” customer, type-specific profile, group relationship, customer memberships.
- **Vehicle aggregate** â€” vehicle and current business state.
- **Device aggregate** â€” device, model reference, ownership, custody, and lifecycle.
- **Installation aggregate** â€” installation and vehicle-device assignment transaction.
- **Subscription aggregate** â€” subscription and service period.
- **Invoice aggregate** â€” invoice and invoice lines.
- **Payment aggregate** â€” payment, allocations, and gateway events.
- **Commission aggregate** â€” commission rule snapshot and commission entry.
- **Settlement aggregate** â€” settlement and settlement items.
- **Identity aggregate** â€” user, session, membership, and role assignments.

## Important invariants

- Only one active primary device assignment per vehicle.
- Only one active vehicle assignment per device.
- Only one active tracking subscription per vehicle in Version 1.
- A customer group and customer managing dealer must match.
- A direct customer cannot have a dealer customer group.
- Payment gateway events are idempotent.
- Historical assignment, commission, settlement, and audit records are never hard-deleted.