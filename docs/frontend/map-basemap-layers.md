# Shared Map Provider, Street View, and Traffic Controls

## Scope

The same controls are available on:

```text
/monitor
/alerts
/tracks
```

## Traffic controller

The fourth right-side controller uses a dedicated traffic-light icon and
toggles Google Maps `TrafficLayer`.

```text
Inactive â†’ white button, dark traffic-light icon
Active   â†’ blue button, white traffic-light icon
```

The browser's default black focus outline is removed. Keyboard focus uses a
controlled blue ring.

Traffic is an overlay and does not replace the selected map provider. It
remains compatible with Google Street, Google Hybrid, Google Satellite, Esri
Hybrid, and Esri Satellite.

## Other controls preserved

- provider selector;
- Street View;
- integrated zoom controls;
- selected-position focusing;
- responsive map resize behavior;
- Google and Esri attribution;
- Monitor, Alerts, and Tracks consistency.