# Customer Account Leaflet Runtime Stability

## Runtime failure

The browser runtime reported:

```text
Cannot read properties of undefined (reading '_leaflet_pos')
```

This class of error occurs when a queued Leaflet animation or DOM-position
calculation continues after React navigation, logout, hot reload, or a layout
transition has already removed a Leaflet pane.

## Root boundary

The selectable Customer map previously focused a position with animated
`setView`. It also relied on Leaflet's internal window-resize scheduling.

The map is shared by Customer and Management monitor routes, so a lifecycle
fault affects both shells.

## Fix

The shared map now:

- disables zoom, fade, marker-zoom, inertia, and internal track-resize queues;
- focuses selected positions with `animate: false`;
- schedules focus and resize through cancellable animation frames;
- verifies both the map container and map pane are connected;
- disconnects `ResizeObserver` and window listeners during cleanup;
- never calls `map.stop()` or `map.remove()` from React effect cleanup;
- treats teardown-time resize and focus as best-effort operations;
- preserves the real-position marker, popup, zoom control, and map selection
  contract.

## Manual regression

Verify these interactions repeatedly:

1. Open Customer `/monitor`.
2. Select and deselect a Device with a real position.
3. Navigate Monitor -> Device -> Fleet -> Report -> Monitor.
4. Open Settings and return.
5. Sign out while Monitor is visible.
6. Sign in again and reopen Monitor.
7. Resize the browser quickly.
8. For management, collapse and expand account and Device panels repeatedly.
9. During development, save a Customer monitor file to trigger hot reload.

No `_leaflet_pos` runtime overlay should appear.