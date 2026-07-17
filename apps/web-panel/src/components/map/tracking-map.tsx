"use client";

import { useEffect } from "react";
import {
  CircleMarker,
  MapContainer,
  Popup,
  TileLayer,
  useMap,
  ZoomControl,
} from "react-leaflet";
import type {
  TrackingMapBasemap,
  TrackingMapPosition,
} from "@/components/map/tracking-map-types";

type TrackingMapProps = {
  selectedPosition?: TrackingMapPosition | null;
  basemap?: TrackingMapBasemap;
};

type TrackingMapControllerProps = {
  selectedPosition: TrackingMapPosition | null;
};

function mapDomIsUsable(
  map: ReturnType<typeof useMap>,
  container: HTMLElement,
) {
  if (!container.isConnected) {
    return false;
  }

  try {
    const mapPane = map.getPane("mapPane");
    return Boolean(mapPane?.isConnected);
  } catch {
    return false;
  }
}

function TrackingMapController({
  selectedPosition,
}: TrackingMapControllerProps) {
  const map = useMap();

  useEffect(() => {
    const container = map.getContainer();
    let disposed = false;
    let animationFrame: number | null = null;

    function scheduleResize() {
      if (disposed) return;

      if (animationFrame !== null) {
        cancelAnimationFrame(animationFrame);
      }

      animationFrame = requestAnimationFrame(() => {
        animationFrame = null;

        if (
          disposed ||
          !mapDomIsUsable(map, container)
        ) {
          return;
        }

        try {
          map.invalidateSize({
            animate: false,
            pan: false,
            debounceMoveend: true,
          });
        } catch {
          // Navigation, logout, and hot reload may remove the
          // Leaflet panes before a queued resize callback runs.
        }
      });
    }

    const resizeObserver =
      typeof ResizeObserver === "undefined"
        ? null
        : new ResizeObserver(scheduleResize);

    resizeObserver?.observe(container);
    window.addEventListener("resize", scheduleResize);
    scheduleResize();

    return () => {
      disposed = true;

      if (animationFrame !== null) {
        cancelAnimationFrame(animationFrame);
      }

      resizeObserver?.disconnect();
      window.removeEventListener(
        "resize",
        scheduleResize,
      );

      // React Leaflet owns map teardown. Never invoke Leaflet's
      // stop or remove methods from this cleanup.
    };
  }, [map]);

  useEffect(() => {
    if (!selectedPosition) return;

    const container = map.getContainer();
    let disposed = false;

    const animationFrame = requestAnimationFrame(() => {
      if (
        disposed ||
        !mapDomIsUsable(map, container)
      ) {
        return;
      }

      try {
        map.setView(
          [
            selectedPosition.latitude,
            selectedPosition.longitude,
          ],
          16,
          {
            animate: false,
          },
        );
      } catch {
        // A route transition may complete between the DOM
        // guard and the imperative Leaflet call.
      }
    });

    return () => {
      disposed = true;
      cancelAnimationFrame(animationFrame);

      // Do not invoke Leaflet during effect cleanup.
    };
  }, [
    map,
    selectedPosition,
  ]);

  return null;
}

export default function TrackingMap({
  selectedPosition = null,
  basemap = "map",
}: TrackingMapProps) {
  return (
    <MapContainer
      center={[20, 0]}
      zoom={2}
      minZoom={2}
      zoomControl={false}
      scrollWheelZoom
      trackResize={false}
      inertia={false}
      zoomAnimation={false}
      fadeAnimation={false}
      markerZoomAnimation={false}
      className="h-full w-full"
    >
      {basemap === "satellite" ? (
        <TileLayer
          attribution='Tiles &copy; Esri &mdash; Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community'
          url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
          maxZoom={19}
        />
      ) : (
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          maxZoom={19}
        />
      )}

      <TrackingMapController
        selectedPosition={selectedPosition}
      />

      {selectedPosition ? (
        <CircleMarker
          key={[
            selectedPosition.latitude,
            selectedPosition.longitude,
          ].join(":")}
          center={[
            selectedPosition.latitude,
            selectedPosition.longitude,
          ]}
          radius={9}
          pathOptions={{
            color: "#ffffff",
            fillColor: "#ff3152",
            fillOpacity: 1,
            weight: 3,
          }}
        >
          <Popup>{selectedPosition.label}</Popup>
        </CircleMarker>
      ) : null}

      <ZoomControl position="bottomright" />
    </MapContainer>
  );
}