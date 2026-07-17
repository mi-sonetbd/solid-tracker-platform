# Leaflet Unmount and Panel Handle Fix

## Leaflet lifecycle

React Leaflet owns creation and removal of the Leaflet Map instance.

The custom resize controller must not call `map.stop()` or `map.remove()` in
effect cleanup. During navigation, logout, and development hot reload, the map
pane may already have been removed before custom cleanup runs.

The resize controller now:

- marks itself disposed before cleanup;
- cancels its pending animation frame;
- disconnects `ResizeObserver`;
- removes the window resize listener;
- verifies the map container is still connected;
- treats resize invalidation as best-effort during teardown.

## Collapse handles

Each handle now uses `left: 100%` relative to its panel. Therefore, the left
edge of the handle begins exactly at the right edge of the panel or collapsed
rail, matching the supplied reference.

Collapsed panels retain a visible 14-pixel rail.