# Customer Vehicle and Tracker Assignment

## Route ownership

Customer asset operations remain inside:

```text
/management/accounts
```

The Customer directory provides an `Assets` action. No duplicate Customer or
vehicle management page is introduced.

## Supported workflow

1. Open a Direct or Dealer-managed Customer.
2. Register one or more vehicles.
3. Review vehicle identity and current primary tracker.
4. Select an installable tracker from the Customer's valid stock scope.
5. Record installation wiring, location, odometer, and notes.
6. Complete the primary tracker assignment transaction.

## Inventory scope

### Platform / Direct Customer

The tracker picker requests unallocated Platform inventory in `IN_STOCK`
lifecycle state. The backend requires Platform scope and rejects any
Dealer-allocated device.

### Dealer-managed Customer

The tracker picker requests `ALLOCATED` inventory belonging to the Customer's
managing Dealer. The backend requires matching Dealer scope and allocation.

## Backend boundaries

```text
GET  /api/v1/vehicles
POST /api/v1/vehicles
GET  /api/v1/devices
POST /api/v1/devices/:deviceId/install
```

The existing backend remains authoritative for:

- permission and scope validation;
- Customer-to-vehicle ownership;
- unique registration, chassis, and engine identity;
- one active primary tracker per vehicle;
- one active vehicle assignment per tracker;
- stock custody and Dealer allocation;
- immutable assignment and audit history.

## Web BFF

Browser requests use:

```text
GET  /api/management/vehicles
POST /api/management/vehicles
GET  /api/management/devices
POST /api/management/devices/:deviceId/install
```

The BFF uses HttpOnly authentication cookies, automatic access-token refresh,
bounded query parameters, UUID validation, and input validation.

## Permissions

```text
vehicle.view
vehicle.create
device.view
device.install
```

Frontend controls are permission-gated. Backend permission and scope checks are
final and authoritative.

## Operational note

This stage consumes existing valid inventory. Platform device registration,
device-model administration, and Dealer allocation remain Device Management
responsibilities and are not duplicated in the Customer workflow.