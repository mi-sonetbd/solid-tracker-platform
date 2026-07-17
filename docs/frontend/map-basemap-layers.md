# Shared Map Controls

## Map-only fullscreen

The third map controller toggles fullscreen for the map workspace element
instead of the complete HTML document.

Fullscreen includes:

- map canvas;
- address search and map dropdown;
- My Location;
- Street View;
- fullscreen controller;
- traffic controller;
- provider selector;
- zoom controls;
- map property drawer.

Fullscreen excludes:

- Solid Tracker top navigation;
- Customer Monitor left rail;
- object/device side panel.

```text
First click  â†’ map workspace enters fullscreen
Second click â†’ map workspace exits fullscreen
Esc key      â†’ exits fullscreen and synchronizes the button
```

A resize event is dispatched after every fullscreen transition so the Google
Maps canvas recalculates its viewport correctly.

## Controller order

1. My Location
2. Street View
3. Map-only fullscreen
4. Traffic
5. Map provider
6. Zoom in
7. Zoom out

The same behavior is used by Monitor, Alerts, and Tracks.