# Shared Map Provider and Street View Controls

## Scope

The same map controls are available on:

```text
/monitor
/alerts
/tracks
```

## Provider selector

The existing Layers button opens the five-provider radio menu:

1. Google Map (Street)
2. Google Map (Hybrid)
3. Google Map (Satellite)
4. OpenStreet Map (Hybrid) â€” Esri imagery with labels
5. OpenStreet Map (Satellite) â€” Esri imagery

## Street View controller

The second existing right-side map-controller button is the Street View toggle.

```text
First click  â†’ Open nearest Street View
Second click â†’ Exit Street View
```

The button is highlighted blue while Street View is active.

Opening the provider selector exits Street View. Opening Street View closes the
provider selector.

## Street View lookup

The shared map searches for the nearest outdoor panorama within 1,000 meters of
the current map center using `StreetViewService.getPanorama()`.

When imagery is found, the map's default Street View panorama is displayed.
When no panorama exists in the search radius, the map remains visible.

Street View availability depends on Google's imagery coverage for the selected
location.

## Existing behavior preserved

The feature preserves:

- all five basemap providers;
- integrated right-side zoom controls;
- selected-position focusing;
- location overlay and information window;
- responsive resizing;
- property-drawer behavior;
- Google and Esri attribution;
- one shared implementation across Monitor, Alerts, and Tracks.