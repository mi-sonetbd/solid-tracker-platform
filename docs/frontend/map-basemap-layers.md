# Shared Google Maps Basemap

## Scope

The shared tracking map uses Google Maps JavaScript API on:

```text
/monitor
/alerts
/tracks
```

The same shared component is also used by compatible management workspaces.

## Basemap toggle

The existing `Layers3` toolbar button remains the only basemap control.

```text
Google Roadmap â†’ Google Satellite
Google Satellite â†’ Google Roadmap
```

No native Google map-type control and no second map button are shown.

The button uses its active blue treatment while Satellite is selected.

## Google map types

- `google.maps.MapTypeId.ROADMAP`
- `google.maps.MapTypeId.SATELLITE`

OpenStreetMap and Esri World Imagery are no longer rendered by the shared map.

## API loading

The web panel loads Maps JavaScript API through:

```text
@googlemaps/js-api-loader
```

The API key is read only from:

```text
NEXT_PUBLIC_GOOGLE_MAPS_API_KEY
```

The key must remain in the Git-ignored `apps/web-panel/.env.local` file and
must be restricted to approved website referrers and Maps JavaScript API.

## Map behavior preserved

The Google renderer preserves:

- selected-position focus at zoom 16;
- a clickable red location circle;
- an information window containing the position label;
- responsive map resizing;
- custom bottom-right zoom controls;
- property-drawer control offset;
- the existing Monitor, Alerts, and Tracks basemap state;
- truthful loading and configuration-error states.

## Controls

Google's native map-type, Street View, fullscreen, and zoom controls are
disabled. Solid Tracker owns the existing basemap toggle and custom zoom
controls so the customer interface remains consistent.