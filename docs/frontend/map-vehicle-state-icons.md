# State-Aware Car Map Markers

Solid Tracker uses the supplied transparent top-view car artwork for car and
car-like vehicle markers.

## State mapping

- `moving`: green car;
- `idle`: yellow car;
- `stopped`: red car;
- `offline`: gray car.

## State resolution

The shared live-position resolver applies these rules in order:

1. A position older than 10 minutes is offline.
2. Speed greater than 1 knot is moving.
3. Ignition on with low speed is idle.
4. A recent low-speed position with ignition off or unavailable is stopped.

Traccar speed values are interpreted in their native knot unit.

## Rendering

The original uploads are transparent PNG images, not vector SVG files. They
are stored as optimized 102 x 200 pixel map assets and rendered at 36 x 70
pixels. The map anchor is the center of the car, so the GPS coordinate remains
aligned with the vehicle body.

Motorcycle and CNG markers retain their existing type-specific SVG markers.
