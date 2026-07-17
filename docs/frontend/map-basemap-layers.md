# Shared Map Providers, Traffic, and My Location

## Scope

The same controls are available on:

```text
/monitor
/alerts
/tracks
```

## Provider list

The provider menu displays only these primary labels:

1. Google Map (Street)
2. Google Map (Hybrid)
3. Google Map (Satellite)
4. OpenStreet Map (Hybrid)
5. OpenStreet Map (Satellite)

Secondary provider descriptions are not shown in the menu.

## Traffic

The traffic-light controller uses Google Maps `TrafficLayer`.

When traffic is active, the layer is detached and reattached after every
basemap change. This refreshes the traffic overlay after switching among Google
Street, Hybrid, and Satellite views.

Traffic remains an overlay and does not replace the selected map provider.
Traffic detail depends on Google coverage for the displayed area.

## My Location

The top controller is the My Location action.

```text
1. Click the top location controller.
2. The browser requests location permission.
3. The map centers on the current coordinates.
4. A blue accuracy circle is displayed.
5. Clicking the circle opens the â€œMy locationâ€ information window.
```

The button is blue while location is being requested and after the current
location is displayed. Permission, timeout, and unavailable-position errors are
shown as a small message over the map.

## Existing behavior preserved

- provider selector;
- Street View;
- traffic toggle;
- integrated zoom controls;
- selected-position focusing;
- responsive resizing;
- Google and Esri attribution;
- Monitor, Alerts, and Tracks consistency.