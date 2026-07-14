# Tracking Integration Foundation

## Scope

This migration introduces:

- `TraccarServer`
- `TraccarDeviceMapping`
- `TrackingEvent`
- `Geofence`
- `VehicleGeofenceAssignment`
- `NotificationRule`
- `Notification`
- `DeviceCommandRequest`
- `IntegrationJob`

## System ownership

```text
Traccar
â†’ raw positions, routes, trips, stops, and native telemetry

Solid Tracker PostgreSQL
â†’ device mappings, normalized business events, geofences,
  notification history, command requests, and integration jobs

Redis
â†’ latest telemetry cache, online/offline cache, cooldown state,
  queues, locks, and command timeouts
```

Android and web clients communicate with NestJS. NestJS applies authentication, permissions, scope, customer ownership, subscription entitlement, and safety rules before calling Traccar.

## Traccar servers and mappings

Multiple Traccar servers are represented, while only one active server may be marked as the default.

A device may have one mapping per server. Only one active primary mapping may exist for a device across the platform.

External Traccar IDs remain separate from Solid Tracker business IDs.

## Tracking events

A normalized tracking event records:

- customer;
- vehicle;
- device;
- source Traccar server and event ID;
- deduplication key;
- event type and severity;
- optional coordinates;
- occurrence and receipt times;
- processing and acknowledgement state.

The combination of Traccar server and external event ID is unique. A second deterministic deduplication key protects integrations where no reliable external event ID is available.

## Geofences

Solid Tracker owns geofence business configuration. Traccar performs geographic detection.

A geofence and assigned vehicle must belong to the same customer. Only one active assignment may exist for a given geofence and vehicle pair.

## Notifications

Notification rules specify:

- event type and minimum severity;
- channel;
- recipient strategy;
- optional vehicle boundary;
- quiet hours;
- cooldown;
- optional daily limit.

Notification records preserve rendered content and provider delivery history.

## Device commands

Every command preserves:

- requester;
- device and optional vehicle;
- parameters and business reason;
- Traccar server and command ID;
- approval and execution timestamps;
- final status and failure details.

Engine cutoff and engine restore commands require approval by another user and require the device to be actively assigned to the selected vehicle.

## Integration jobs

Integration jobs provide durable PostgreSQL history for asynchronous work. Redis may execute the live queue, while PostgreSQL retains idempotency, attempt counts, scheduling, status, error, result, entity, and correlation data.

## Database enforcement

PostgreSQL enforces:

- one active default Traccar server;
- one active primary mapping per device;
- event customer/vehicle consistency;
- mapping/server consistency;
- geofence/vehicle ownership;
- notification recipient consistency;
- safe command approval;
- active device/vehicle command assignment;
- integration retry and status invariants.