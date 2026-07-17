# Shared Google Maps Basemap

## Scope

The shared Google tracking map is used on:

```text
/monitor
/alerts
/tracks
```

## Single basemap toggle

The existing `Layers3` button remains the only basemap control.

```text
Google Roadmap â†’ Google Hybrid
Google Hybrid â†’ Google Roadmap
```

The customer-facing behavior is still described as Map and Satellite.

## Map types

### Map

```text
google.maps.MapTypeId.ROADMAP
```

### Satellite with labels

```text
google.maps.MapTypeId.HYBRID
```

Google `HYBRID` combines satellite imagery with road, place, and other
basemap labels. Plain `SATELLITE` is not used because it omits those labels.

## Loading behavior

Satellite imagery uses photographic tiles and may load more slowly than the
roadmap, especially on the first view or after moving to a new area. The same
Google map instance is retained when changing the map type so the application
does not recreate the map during each toggle.

## Zoom controls

Solid Tracker keeps its custom bottom-right zoom controls. The zoom-out control
uses an ASCII hyphen so it renders correctly regardless of source encoding.

## Existing behavior preserved

The refinement does not change:

- the single `Layers3` toggle;
- selected-position focusing;
- location overlays and information windows;
- resize handling;
- property-drawer control positioning;
- API-key handling;
- Google Maps loading and runtime-error states.