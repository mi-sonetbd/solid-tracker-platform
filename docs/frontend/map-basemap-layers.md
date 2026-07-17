# Shared Map Provider Selector

## Scope

The same provider selector is available on:

```text
/monitor
/alerts
/tracks
```

## Provider choices

1. **Google Map (Street)**
   - Google `ROADMAP`.
2. **Google Map (Hybrid)**
   - Google satellite imagery with Google road and place labels.
3. **Google Map (Satellite)**
   - Google satellite imagery without the hybrid label overlay.
4. **OpenStreet Map (Hybrid)**
   - Esri World Imagery with Esri World Boundaries and Places labels.
5. **OpenStreet Map (Satellite)**
   - Esri World Imagery without the reference-label overlay.

Google Map (Street) means the normal Google road map. It does not enable the
separate Street View panorama experience.

OpenStreetMap does not provide an official satellite imagery service. The
non-Google satellite choices use Esri services and display the real provider
under the customer-facing menu name.

## Controls

The provider radio menu opens from the existing Layers icon.

Zoom in and zoom out remain integrated into the existing right-side toolbar.
The separate bottom-right custom zoom control remains removed.

Google built-in default controls remain disabled. Required Google attribution,
map-data, terms, and provider notices remain visible.