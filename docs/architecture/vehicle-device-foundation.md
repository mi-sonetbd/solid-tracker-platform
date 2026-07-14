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
    â†“
Vehicle
    â†“
VehicleDeviceAssignment
    â†“
Device
    â†“
DeviceModel
```

## Version 1 assignment invariants

- One device may have only one active vehicle assignment.
- One vehicle may have only one active `PRIMARY` assignment.
- `SECONDARY` and `BACKUP` types are represented for future use.
- Historical assignments remain after removal or replacement.
- An assignment linked to an installation must use the same vehicle and device.

## Ownership and custody

Ownership and custody are separate histories.

Only one current ownership entry and one current custody entry may exist for each device.

## Dealer allocation

A device can be allocated to only one dealer at a time while its allocation remains active. Dealer allocations must reference an organization whose type is `DEALER`.

## Installation lifecycle

Installation records preserve the installer, dealer, physical installation time, connection details, verification, removal time, and removal reason.

Completed or removed installations require an installation timestamp. Removed installations require both a removal timestamp and removal reason.

## Device identity

- `deviceCode` is the Solid Tracker business identifier.
- `imei` is stored as text and is unique when present.
- `serialNumber` is unique when present.
- Device lifecycle state is separate from future Traccar online/offline state.

## Database enforcement

Prisma defines the relational structure. PostgreSQL partial unique indexes, check constraints, and triggers enforce cross-row and polymorphic business rules.

Five trigger names are installed. Each trigger handles both `INSERT` and `UPDATE`; therefore, `information_schema.triggers` exposes ten event rows. Verification must count distinct trigger names rather than raw rows.