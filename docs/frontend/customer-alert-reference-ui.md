# Customer Alerts Reference UI

## Route

```text
/alerts
```

## Navigation

The Customer Monitor rail now provides two operational routes:

```text
Objects -> /monitor
Alerts  -> /alerts
```

Tracks and Multi-track remain visible but disabled until their dedicated
development stages.

The Customer shell treats `/alerts` as part of the Monitor section, so the
Monitor top navigation remains active and the legacy shell rail stays hidden.

## Current data

The page uses real Customer-scoped vehicles and installed trackers in the
Device selector.

The reference-style UI includes:

- Device selector;
- alert type selector;
- start and end date filters;
- collapsible filter panel;
- map workspace;
- map tools;
- read-state and search placeholders.

## Data integrity

The Customer alert backend has not been implemented. The page therefore does
not fabricate vibration, ACC, overspeed, timestamps, locations, or unread
records.

The feed displays a truthful empty state until the alert service is connected.

## Leaflet safety

The Alerts page reuses the verified Customer Leaflet map client and introduces
no animated focus or custom map teardown behavior.