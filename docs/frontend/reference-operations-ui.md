# Solid Tracker Reference Operations UI

## Visual reference

The first professional web-panel interface is based on the supplied GPS
platform screenshots.

The implementation follows their useful operational patterns:

- persistent blue top navigation;
- Solid Tracker branded logo area;
- section-specific vertical navigation;
- object panel beside a full map workspace;
- report overview rings and status table;
- device search, batch actions, and device table;
- fleet dashboard cards, reminders, charts, and rankings.

## Branding and ownership

The Tracksolid name, logo, proprietary graphics, and source code are not copied.
Solid Tracker uses its own branding, React components, icons, Tailwind styles,
navigation model, and application source.

## Routes

- `/monitor`
- `/report`
- `/device`
- `/video`
- `/fleet`

Compatibility redirects remain for:

- `/dashboard` â†’ `/fleet`
- `/live-tracking` â†’ `/monitor`
- `/vehicles` â†’ `/device`

## Data state

The current screen data is representative UI data. Backend integration,
authentication, authorization, live device state, and WebSocket tracking are
the next implementation stages.