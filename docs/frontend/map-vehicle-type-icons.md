# Vehicle-Type Map Markers

The selected live vehicle marker now uses a vehicle-specific icon instead of
the previous circular overlay.

## Marker mapping

- `MOTORCYCLE` uses a motorcycle icon.
- `CNG` uses a CNG/auto-rickshaw icon.
- `CAR` and every remaining vehicle type use the car icon as a safe fallback.

## Rendering

The shared Google Maps renderer creates an inline SVG data-URI marker. No
external image hosting or additional package is required.

The marker keeps the existing behavior:

- map focus and zoom;
- clickable vehicle label;
- Customer Monitor support;
- Management Monitor support;
- map provider, traffic, Street View, fullscreen, and My Location controls.

The marker color is neutral Solid Tracker blue so online, offline, and alert
status colors can be introduced independently later.
