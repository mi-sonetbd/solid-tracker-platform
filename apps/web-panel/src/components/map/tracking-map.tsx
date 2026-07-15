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
    let animationFrame = 0;

    function refreshMapSize() {
      cancelAnimationFrame(animationFrame);

      animationFrame = requestAnimationFrame(() => {
        if (!container.isConnected) {
          return;
        }

        map.stop();
        map.invalidateSize({
          animate: false,
          pan: false,
          debounceMoveend: true,
        });
      });
    }

    const observer =
      typeof ResizeObserver === "undefined"
        ? null
        : new ResizeObserver(refreshMapSize);

    observer?.observe(container);
    window.addEventListener("resize", refreshMapSize);
    refreshMapSize();

    return () => {
      cancelAnimationFrame(animationFrame);
      observer?.disconnect();
      window.removeEventListener("resize", refreshMapSize);
      map.stop();
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