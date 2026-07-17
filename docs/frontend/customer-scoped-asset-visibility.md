# Customer Scoped Assets in the Approved Reference UI

## Non-negotiable UI boundary

The approved Customer interface is preserved for:

```text
/monitor
/device
/report
/fleet
```

Customer asset integration replaces only mock data. It does not replace the
existing navigation, Objects panel, map toolbar, Device table, Report overview,
or Fleet dashboard.

## Authenticated scope

The browser never supplies a Customer ID.

```text
GET /api/customer/assets
    -> GET /api/v1/vehicles
    -> AssetAccessService.vehicleWhere(auth)
```

The backend resolves Customer scope from the authenticated token.

## Monitor behavior

- the existing left Objects panel lists the Customer's real vehicles;
- installed tracker Device code and IMEI are shown under each vehicle;
- clicking an object selects it;
- the existing map remains visible;
- a reference-style property drawer opens from the right;
- no coordinates, marker, speed, or online state are fabricated.

The map component accepts an optional real position. When Traccar integration
provides latitude and longitude, selecting the object automatically focuses the
map and renders the marker.

## Device behavior

The approved Device table is preserved and populated with:

- Customer vehicle registration;
- installed Device code;
- IMEI;
- Device Model;
- installation/activation time.

Unknown subscription fields remain `-` until billing integration exists.

## Report behavior

The approved overview rings and report table are preserved. Scoped vehicles are
listed, while tracking-dependent fields remain unavailable until Traccar data
exists.

## Fleet behavior

The approved Fleet dashboard is preserved. Total Vehicles comes from the
authenticated Customer scope. Distance, driving time, fuel, motion, and alarm
statistics remain zero until telemetry and reporting are connected.

## Next stage

1. create authoritative Device-to-Traccar mapping;
2. synchronize installed tracker IMEI with Traccar;
3. provide latest scoped position;
4. feed that position into the existing selection and drawer contract;
5. connect history, alerts, tracks, and fleet statistics.