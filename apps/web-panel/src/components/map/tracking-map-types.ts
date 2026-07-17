export type TrackingMapPosition = {
  latitude: number;
  longitude: number;
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