# Device Model, Stock Intake, and Dealer Allocation

## Route

All inventory operations are centralized inside:

```text
/management/device
```

## Workflow

```text
Device Model
    â†“
Platform Stock Intake
    â†“
IN_STOCK
    â”œâ”€â”€ install for Direct Customer
    â””â”€â”€ allocate to Dealer
              â†“
          ALLOCATED / AVAILABLE
              â†“
          install for Dealer Customer
```

## Device Model

Platform users with `device.register` can create a Device Model containing:

- manufacturer;
- model name;
- Traccar protocol;
- network type;
- supported ignition, relay, and SOS capabilities.

Backend endpoint:

```text
POST /api/v1/device-models
```

## Stock intake

A physical tracker is received with:

- active Device Model;
- IMEI and/or serial number;
- hardware version;
- firmware version;
- received date.

Backend endpoint:

```text
POST /api/v1/devices
```

A successful registration creates:

- generated device code;
- Platform ownership history;
- Platform custody history;
- lifecycle status `IN_STOCK`;
- immutable audit event `device.registered`.

IMEI and serial number are unique inventory identities.

## Dealer allocation

Only uninstalled Platform stock in `RECEIVED` or `IN_STOCK` state may be
allocated.

Backend endpoint:

```text
POST /api/v1/devices/:deviceId/allocate
```

A successful allocation creates:

- Dealer allocation code;
- Dealer custody history;
- allocation status `AVAILABLE`;
- device lifecycle `ALLOCATED`;
- audit event `device.allocated`.

Ownership remains Platform ownership. Allocation is a custody operation.

## BFF routes

```text
GET  /api/management/device-models
POST /api/management/device-models
GET  /api/management/devices
POST /api/management/devices
POST /api/management/devices/:deviceId/allocate
```

The BFF reads HttpOnly authentication cookies, refreshes expired access tokens,
validates identifiers and input lengths, and forwards requests to the
authoritative backend.

## Authorization

```text
device.view
device.register
```

Device Model creation, inventory registration, and Dealer allocation also
require Platform scope. Dealer users see only inventory in their effective
scope and cannot create Platform stock.

## Customer installation integration

Direct Customers consume unallocated `IN_STOCK` Platform devices.

Dealer-managed Customers consume `ALLOCATED` devices belonging to the same
Dealer.

The Customer installation form sends `installationNotes`, matching the backend
DTO exactly.