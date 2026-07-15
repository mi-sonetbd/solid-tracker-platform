# Customer Scoped Asset Visibility

## Customer routes

Real Solid Tracker asset records are now shown on:

```text
/monitor
/device
/report
/fleet
```

## Scope boundary

The browser does not submit a Customer identifier.

The Customer BFF calls:

```text
GET /api/v1/vehicles
```

without `customerId`. The backend derives effective scope from the authenticated
access token through `AssetAccessService.vehicleWhere(auth)`.

For Customer roles, the backend restricts results to:

```text
customerId IN authenticated customerIds and CUSTOMER role scopes
```

A Customer cannot select or override another Customer ID in the browser.

## Vehicle projection

Each scoped vehicle includes its active `VehicleDeviceAssignment`, the assigned
Device, and the Device Model. Therefore Customer users can see their installed
tracker through `vehicle.view` without receiving general Platform or Dealer
inventory access.

This is intentional because Customer roles do not need `device.view` over stock
inventory.

## Current page behavior

### Monitor

- real Customer vehicles;
- real active tracker assignment;
- real Device code and IMEI;
- no fabricated map marker;
- `No live position yet` until Traccar synchronization.

### Device

- vehicle-to-tracker relationship;
- IMEI;
- Device Model;
- firmware;
- lifecycle and assignment status.

### Fleet

- all scoped Customer vehicles;
- registration and vehicle identity;
- installed or missing tracker state.

### Report

- only authenticated Customer vehicles appear;
- report types are visible;
- tracking-dependent fields show `No data` and `Traccar pending`.

## Permissions

```text
vehicle.view
vehicle.location.view
vehicle.history.view
```

Every Customer route also calls `requireCustomerSession()` on the server.

## Next stage

1. synchronize each installed Device with Traccar;
2. store the Traccar Device mapping;
3. read latest position and history;
4. render real markers, speed, ignition, online state, trips, stops, and events.