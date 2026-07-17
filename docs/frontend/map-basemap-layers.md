# Shared Map Providers, Traffic, and My Location

## Scope

The same controls are available on:

```text
/monitor
/alerts
/tracks
```

## My Location toggle

The top map controller now uses an explicit enabled/disabled state.

```text
First click  â†’ request and display My Location
Second click â†’ hide My Location and remove its marker
Third click  â†’ request and display My Location again
```

The controller remains blue while My Location is enabled. After a successful
request, the button label becomes **Hide my location** instead of remaining
stuck in a permanent ready state.

Disabling the controller:

- removes the blue accuracy circle;
- closes the My Location information window;
- resets the location status to idle;
- clears the current location command.

## Other map behavior preserved

- Google traffic refresh after basemap changes;
- provider list without secondary descriptions;
- Google Street, Hybrid, and Satellite;
- Esri Hybrid and Satellite;
- Street View point selection;
- integrated zoom controls;
- responsive map resize behavior;
- Monitor, Alerts, and Tracks consistency.