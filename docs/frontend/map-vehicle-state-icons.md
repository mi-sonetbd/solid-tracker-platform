# Vehicle Runtime States

Solid Tracker uses one shared runtime-state resolver for the selected map
marker and the Customer device-panel icon holder.

## State rules

1. No position, no usable timestamp, or no new data for more than five minutes
   is offline and gray.
2. A recent position with speed above one knot is moving and green.
3. A recent stopped position with ignition on is idle and yellow.
4. A recent stopped position with ignition off or unavailable is stopped and
   red.

The offline rule has the highest priority. Stale speed and ignition values
cannot keep a vehicle online.

## Colors

- Moving: `#2f9145`
- Stopped, ignition off: `#ff2344`
- Idle, ignition on: `#ffd900`
- Offline after five minutes: `#a6a8ab`

## Polling

Installed vehicles visible in the Customer device panel refresh their latest
positions every 30 seconds. Customer scope and location permission continue to
be enforced by the authenticated BFF and backend route.

## Map artwork

Car and car-like vehicles use the supplied transparent top-view PNG artwork.
Motorcycle and CNG keep their type-specific SVG marker artwork.
