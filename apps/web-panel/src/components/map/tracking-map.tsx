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
import type { TrackingMapPosition } from "@/components/map/tracking-map-types";

type TrackingMapProps = {
  selectedPosition?: TrackingMapPosition | null;
};

function SelectedPositionFocus({
  position,
}: {
  position: TrackingMapPosition;
}) {
  const map = useMap();

  useEffect(() => {
    map.setView(
      [position.latitude, position.longitude],
      16,
      {
        animate: true,
      },
    );
  }, [
    map,
    position.latitude,
    position.longitude,
  ]);

  return null;
}

export default function TrackingMap({
  selectedPosition = null,
}: TrackingMapProps) {
  return (
    <MapContainer
      center={[20, 0]}
      zoom={2}
      minZoom={2}
      zoomControl={false}
      scrollWheelZoom
      className="h-full w-full"
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />

      {selectedPosition ? (
        <>
          <SelectedPositionFocus
            position={selectedPosition}
          />
          <CircleMarker
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
        </>
      ) : null}

      <ZoomControl position="bottomright" />
    </MapContainer>
  );
}