"use client";

import { useEffect } from "react";
import {
  MapContainer,
  TileLayer,
  ZoomControl,
  useMap,
} from "react-leaflet";

function MapResizeController() {
  const map = useMap();

  useEffect(() => {
    const container = map.getContainer();
    let disposed = false;
    let animationFrame: number | null = null;

    function refreshMapSize() {
      if (disposed) {
        return;
      }

      if (animationFrame !== null) {
        cancelAnimationFrame(animationFrame);
      }

      animationFrame = requestAnimationFrame(() => {
        animationFrame = null;

        if (disposed || !container.isConnected) {
          return;
        }

        try {
          map.invalidateSize({
            animate: false,
            pan: false,
            debounceMoveend: true,
          });
        } catch {
          return;
        }
      });
    }

    const observer =
      typeof ResizeObserver === "undefined"
        ? null
        : new ResizeObserver(refreshMapSize);

    observer?.observe(container);
    window.addEventListener("resize", refreshMapSize);
    map.whenReady(refreshMapSize);

    return () => {
      disposed = true;

      if (animationFrame !== null) {
        cancelAnimationFrame(animationFrame);
      }

      observer?.disconnect();
      window.removeEventListener("resize", refreshMapSize);

      // React Leaflet owns Map removal. Do not call map.stop() or
      // map.remove() here because the map pane may already be gone.
    };
  }, [map]);

  return null;
}

export default function TrackingMap() {
  return (
    <MapContainer
      center={[20, 0]}
      zoom={2}
      minZoom={2}
      zoomControl={false}
      scrollWheelZoom
      zoomAnimation={false}
      fadeAnimation={false}
      markerZoomAnimation={false}
      className="h-full w-full"
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <MapResizeController />
      <ZoomControl position="bottomright" />
    </MapContainer>
  );
}