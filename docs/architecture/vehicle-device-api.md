# Vehicle and Device API

## Scope

This stage provides REST APIs and transactional application services for:

- vehicle registration and updates;
- scoped vehicle lists and tracker-assignment history;
- device-model administration;
- physical device inventory registration;
- platform-to-dealer allocation;
- dealer-to-platform return;
- installation as the active primary tracker;
- transactional tracker replacement;
- tracker removal;
- ownership, custody, allocation, installation, and assignment history.

No new migration is introduced. The existing asset migration already defines the tables, partial unique indexes, constraints, and validation triggers.

## Authorization

Platform scope administers device models, inventory registration, and dealer allocation.

Dealer scope can access devices allocated to that dealer and trackers installed for customers managed by that dealer.

Customer scope can view devices only through active vehicle assignments.

Direct-customer installation requires platform scope.

IMEI and serial-number identity are immutable through the normal update endpoint.

## Lifecycle

```text
Platform stock
    â†“ allocate
Dealer available stock
    â†“ install
Customer custody and active vehicle assignment
    â†“ remove
Dealer available stock
    â†“ return
Platform stock
```

Ownership and custody are separate. Registration creates platform ownership and custody. Allocation and installation change custody without silently changing legal ownership.

## Replacement transaction

Tracker replacement performs the following in one database transaction:

1. ends the current primary assignment;
2. marks the old installation removed;
3. restores the old device to dealer or platform custody;
4. creates the replacement installation;
5. creates the new primary assignment;
6. moves replacement-device custody to the customer;
7. updates allocation and device lifecycle states;
8. preserves every historical row.

The availability check deliberately ignores the current assignment being replaced while still rejecting every other active primary assignment.

## Endpoints

```text
GET    /api/v1/vehicles
POST   /api/v1/vehicles
GET    /api/v1/vehicles/:vehicleId
PATCH  /api/v1/vehicles/:vehicleId
GET    /api/v1/vehicles/:vehicleId/device-history

GET    /api/v1/device-models
POST   /api/v1/device-models
PATCH  /api/v1/device-models/:deviceModelId

GET    /api/v1/devices
POST   /api/v1/devices
GET    /api/v1/devices/:deviceId
PATCH  /api/v1/devices/:deviceId
POST   /api/v1/devices/:deviceId/allocate
POST   /api/v1/devices/:deviceId/return
POST   /api/v1/devices/:deviceId/install
POST   /api/v1/devices/:deviceId/replace
POST   /api/v1/devices/:deviceId/remove
GET    /api/v1/devices/:deviceId/history
```

## Verification

The E2E workflow covers dealer and customer setup, vehicle registration, device-model creation, two inventory registrations, allocations, installation, replacement, removal, assignment history, and inventory return.