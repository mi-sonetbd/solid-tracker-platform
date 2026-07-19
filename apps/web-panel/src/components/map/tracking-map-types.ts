import type { VehicleType } from "@/lib/management/asset-types";

export type TrackingMapPosition = {
  latitude: number;
  longitude: number;
  vehicleType?: VehicleType;
  label: string;
};

export type TrackingMapBasemap =
  | "google-roadmap"
  | "google-hybrid"
  | "google-satellite"
  | "openstreet-hybrid"
  | "openstreet-satellite";

export type TrackingMapZoomCommand = {
  id: number;
  delta: 1 | -1;
};

export type TrackingMapLocationCommand = {
  id: number;
};

export type TrackingMapLocationStatus =
  | "idle"
  | "locating"
  | "ready"
  | "error";
