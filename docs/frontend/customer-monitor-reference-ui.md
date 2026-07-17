# Customer Monitor Reference UI

## Scope

The Customer `/monitor` route follows the supplied GPS platform reference while
retaining Solid Tracker branding, authenticated Customer scope, and current
backend data contracts.

## Layout

```text
Customer top navigation
    â†“
Monitor tool rail
    â†“
Collapsible Customer object list
    â†“
Leaflet map workspace
    â†“
Selected Device property drawer
```

## Tool rail

The left rail contains the reference categories:

- Objects;
- Alerts;
- Tracks;
- Multi-track.

Only Objects is operational in this stage. Future categories are visible but
do not simulate backend functionality.

## Collapsible object list

The Customer object panel uses the same handle dimensions, colors, icon weight,
transition, collapsed rail, and map-expansion behavior used by Super Admin
Monitor.

## Data integrity

The interface displays real scoped Customer vehicles, installed tracker
identity, IMEI, lifecycle, assignment date, and Device Model.

It does not invent:

- online state;
- location or address;
- satellites;
- cellular signal;
- mileage;
- battery voltage;
- environmental sensor values.

Unavailable tracking values remain `-`, `N/A`, or `No live position yet`.

## Leaflet safety

This UI keeps the previously verified map implementation:

- non-animated selection focus;
- disabled Leaflet teardown animation queues;
- cancellable resize callbacks;
- React Leaflet ownership of map removal.

## Manual review

1. Open `/monitor`.
2. Collapse and expand the object list repeatedly.
3. Select several Customer vehicles.
4. Open and close the property drawer.
5. Resize the browser.
6. Navigate Monitor -> Device -> Fleet -> Report -> Monitor.
7. Sign out while the map is visible.
8. Confirm no `_leaflet_pos` runtime overlay appears.
## Shell rail ownership

Customer Monitor owns the dedicated reference-style Objects, Alerts, Tracks,
and Multi-track rail. The older Customer shell section rail is hidden while
Monitor is active, and the shell content offset is reset.

The existing Customer shell rail remains unchanged on Report, Device, Video,
and Fleet.