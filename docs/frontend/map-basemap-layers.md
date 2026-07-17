# Shared Map Provider Selector

## Scope

The same provider selector is available on:

```text
/monitor
/alerts
/tracks
```

## Reference-style selector

Clicking the existing Layers icon opens a white radio-list panel beside the
right-side toolbar. Selecting an option applies it immediately and closes the
panel.

## Provider choices

1. **Google Map (Hybrid)**
   - Google satellite imagery with Google road and place labels.
2. **Google Map (Satellite)**
   - Google satellite imagery without the hybrid label overlay.
3. **OpenStreet Map (Hybrid)**
   - Esri World Imagery with Esri World Boundaries and Places labels.
4. **OpenStreet Map (Satellite)**
   - Esri World Imagery without the reference-label overlay.

OpenStreetMap does not provide an official satellite imagery service. The menu
keeps the requested customer-facing OpenStreet names and shows the actual Esri
provider beneath the non-Google choices.

## Integrated controls

The separate bottom-right Solid Tracker zoom stack is removed from the shared
map renderer.

Zoom in and zoom out are placed at the bottom of the existing right-side
toolbar, matching the supplied reference interface.

Google's built-in default controls remain disabled. Required Google attribution,
map-data, terms, and provider notices remain visible.

## Shared behavior

The shared map preserves:

- Google Hybrid;
- Google Satellite;
- Esri World Imagery;
- Esri imagery with reference labels;
- selected-position focusing;
- location overlay and information window;
- resize handling;
- property-drawer behavior;
- one map instance while changing providers;
- toolbar-driven zoom commands.