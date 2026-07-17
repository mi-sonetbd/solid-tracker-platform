# Shared Map Basemap Layers

## Scope

Map and Satellite selection is available on:

```text
/monitor
/alerts
/tracks
```

## Existing toolbar controls

No additional Leaflet layer-control button is rendered.

The existing right-side map toolbar provides the selection:

- `Layers3` selects **Satellite view**;
- `Map` selects **Map view**.

The selected basemap button uses the existing active blue treatment.

## Basemap providers

### Map view

OpenStreetMap street tiles are used.

### Satellite view

Esri World Imagery is used.

## Shared map flow

Each customer workspace owns its selected basemap state and passes it through
`TrackingMapClient` to the shared `TrackingMap` component. The map component
renders exactly one `TileLayer` based on that state.

## Google Maps boundary

Unofficial Google tile URLs are not used. Exact Google imagery requires an
official Google Maps Platform integration with billing, an API key, and Map
Tiles API session handling.

## Leaflet safety

The basemap selection does not change:

- `TrackingMapController`;
- selected-position focus;
- resize handling;
- markers and popups;
- disabled map animations;
- React Leaflet map ownership and teardown behavior.