# Shared Map Basemap Layers

## Scope

A single basemap toggle is available on:

```text
/monitor
/alerts
/tracks
```

## Existing toolbar toggle

No native Leaflet layer selector and no separate Map button are rendered.

The existing `Layers3` toolbar button toggles:

```text
Map â†’ Satellite
Satellite â†’ Map
```

Its accessible label and tooltip describe the next available view.

The button is highlighted blue while Satellite is active and returns to its
normal appearance while Map is active.

## Basemap providers

- Map: OpenStreetMap
- Satellite: Esri World Imagery

## Shared map flow

Each customer workspace owns the current basemap and passes it through
`TrackingMapClient` to `TrackingMap`. The shared map renders one tile layer.

## Leaflet safety

The toggle does not change:

- `TrackingMapController`;
- position focusing;
- resize handling;
- markers and popups;
- disabled map animations;
- React Leaflet map ownership or teardown behavior.