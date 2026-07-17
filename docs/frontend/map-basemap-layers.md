# Shared Map Provider and Street View Controls

## Scope

The same controls are available on:

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

## Street View point selection

The second right-side controller enables Street View point-selection mode.

```text
1. Click the Street View controller.
2. The controller becomes blue and the map cursor becomes a crosshair.
3. Click the desired location on the map.
4. A blue location marker appears.
5. Solid Tracker searches for the nearest outdoor panorama within 1 km.
6. The panorama opens when coverage exists.
```

When coverage does not exist near the selected point, the map remains visible
and the location marker displays a no-coverage message. Another map point can
then be selected without leaving selection mode.

Clicking the controller again exits Street View, removes the selection marker,
removes the map-click listener, restores the normal cursor, and returns to the
map.

Opening the provider selector also exits Street View selection.

## Existing behavior preserved

The feature preserves:

- all five map providers;
- integrated right-side zoom controls;
- selected-position focusing;
- location overlay and information window;
- responsive resizing and center preservation;
- property-drawer behavior;
- Google and Esri attribution;
- the shared Monitor, Alerts, and Tracks implementation.