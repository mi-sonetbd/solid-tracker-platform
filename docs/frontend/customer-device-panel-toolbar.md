# Customer Device Panel Toolbar

## Scope

The customer Monitor device panel now uses the compact toolbar shown in the
approved reference interface.

The existing search box, **Add group** action, grouping structure, device
cards, map behavior, and backend API contracts remain unchanged.

## Primary counters

The left side contains:

1. **All**
2. **Online**
3. **Following**
4. **Offline**

Each counter is calculated from the current customer device collection. The
selected counter filters the rendered device list immediately.

## Right-side controls

### Invisible devices

The eye control toggles whether hidden or invisible devices are included.

### Movement filter

The filter popup contains:

- All
- Moving
- Idling
- Static

Each item displays its current count and uses the same colored circular status
indicator as the approved reference.

### Sorting

The sorting popup contains:

- Name Aâ€“Z
- Name Zâ€“A
- Last update newest
- Last update oldest

Sorting applies inside device groups while preserving the existing group and
card structures.

### Refresh

Refresh recomputes the client-side view and requests a Next.js route refresh.
It does not change the backend API contract.

## Data compatibility

The toolbar reads commonly used device fields without requiring a schema
migration. It supports direct device arrays and grouped arrays containing
nested device collections under keys such as `devices`, `items`, `children`,
`objects`, `vehicles`, `trackers`, or `rows`.