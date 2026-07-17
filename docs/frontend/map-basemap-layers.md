# Shared Map Controls

## Scope

The same map controls are available on:

```text
/monitor
/alerts
/tracks
```

## Fullscreen controller

The third controller, previously the settings/sliders button, is now the
fullscreen toggle.

```text
First click  â†’ enter browser fullscreen
Second click â†’ exit browser fullscreen
Esc key      â†’ exit fullscreen and reset the button
```

The controller uses a fullscreen icon while inactive and an exit-fullscreen
icon while active. The button is white with a dark icon while inactive and blue
with a white icon while fullscreen is active.

The implementation listens for the browser `fullscreenchange` event, so the
button remains synchronized when fullscreen is exited with the keyboard.

## Controller order

1. My Location
2. Street View
3. Fullscreen
4. Traffic
5. Map provider
6. Zoom in
7. Zoom out

## Existing behavior preserved

- toggleable My Location;
- Street View point selection;
- Google traffic overlay;
- provider selector;
- Google and Esri map providers;
- integrated zoom controls;
- Monitor, Alerts, and Tracks consistency.