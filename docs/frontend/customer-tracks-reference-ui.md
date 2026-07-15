# Customer Tracks Reference UI

## Route

```text
/tracks
```

## Navigation

The Customer Monitor rail provides:

```text
Objects -> /monitor
Alerts  -> /alerts
Tracks  -> /tracks
Multi-track -> future stage
```

The Customer shell treats `/tracks` as part of Monitor, preserving Monitor top
navigation and hiding the legacy shell rail.

## Current data

The Device picker uses real Customer-scoped vehicles with active tracker
assignments.

The page provides the reference-style:

- grouped Device picker;
- track-type selector;
- date range;
- preset period;
- hide/show filters;
- Search and Reset;
- selected Device card;
- collapsible side panel;
- map tools.

## Route history boundary

No location-history endpoint is connected in this stage. Therefore the page
does not fabricate:

- positions;
- route lines;
- trip distance;
- average speed;
- stop duration;
- addresses;
- replay timestamps;
- alerts along the route.

After Search, the page shows `No route history available` until the history
service is integrated.

## Future backend stage

The history service should provide scoped positions, trips, stops, mileage,
speed, heading, event markers, pagination, and replay data.

## Leaflet safety

The page reuses the verified Customer map client and introduces no custom map
teardown or animated focus logic.