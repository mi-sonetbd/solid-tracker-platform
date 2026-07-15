# Shell, Collapse, and Map Stability

## Customer profile menu

The Customer shell now includes:

- Settings
- Sign out
- outside-click dismissal
- Escape-key dismissal

The Customer Settings route remains `/settings`.

## Management monitor panels

The Account List and Device List panels now:

- animate width changes in 150 milliseconds;
- retain a visible 14-pixel rail when collapsed;
- use compact dark boundary handles matching the supplied reference;
- reverse the chevron direction when collapsed;
- expand the map area without unmounting the map.

## Leaflet stability

The shared map now:

- observes container-size changes;
- calls `invalidateSize` without pan animation;
- stops active map animation before size recalculation;
- disables Leaflet zoom, fade, and marker zoom animations;
- removes resize observers and scheduled frames during cleanup.

These protections apply to Customer and Management map routes.