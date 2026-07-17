# Shared Map Provider, Street View, and Traffic Controls

## Scope

The same map controls are available on:

```text
/monitor
/alerts
/tracks
```

## Map providers

The Layers controller opens:

1. Google Map (Street)
2. Google Map (Hybrid)
3. Google Map (Satellite)
4. OpenStreet Map (Hybrid) â€” Esri imagery with labels
5. OpenStreet Map (Satellite) â€” Esri imagery

## Street View

The second controller provides the shared Street View behavior. Depending on
the current branch history, it opens Street View or enables map-point selection.

## Traffic layer

The fourth controller, previously blank, now uses a route icon and controls
Google Maps `TrafficLayer`.

```text
First click  â†’ Show live traffic overlay
Second click â†’ Hide traffic overlay
```

The controller is highlighted blue while traffic is enabled.

Traffic is an overlay and does not change the selected road, hybrid, satellite,
Google, or Esri basemap. The current traffic state is preserved when switching
between basemap providers.

Traffic availability and detail depend on Google coverage for the displayed
area.

## Zoom

Zoom in and zoom out remain integrated at the bottom of the existing right-side
toolbar. The separate bottom-right custom controller remains removed.

## Shared behavior preserved

The feature preserves:

- all configured map providers;
- Street View;
- selected-position focusing;
- location overlays and information windows;
- responsive resizing;
- property-drawer behavior;
- Google and Esri attribution;
- the shared Monitor, Alerts, and Tracks implementation.