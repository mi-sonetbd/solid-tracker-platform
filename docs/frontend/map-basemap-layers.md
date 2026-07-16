# Shared Map Basemap Layers

## Scope

The shared `TrackingMap` component now provides the same basemap selector on:

```text
/monitor
/alerts
/tracks
```

The same component may also expose the selector on management map workspaces.

## Available views

### Map

OpenStreetMap street tiles remain the default view.

### Satellite

Esri World Imagery provides the satellite imagery view.

## Control placement

The Leaflet layer selector is placed in the bottom-right control stack beside
the existing zoom controls. Existing workspace CSS that moves `.leaflet-right`
controls when a property drawer opens also moves this selector.

## Google Maps boundary

This stage does not use unofficial Google tile URLs. Exact Google basemap tiles
require a Google Maps Platform project, billing, an API key, and Map Tiles API
session handling.

## Leaflet safety

The implementation only replaces the basemap tile declaration. It does not
change:

- position focusing;
- markers or popups;
- resize observers;
- animation safety;
- map ownership or teardown behavior.