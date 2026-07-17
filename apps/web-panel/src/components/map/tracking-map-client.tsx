"use client";

import dynamic from "next/dynamic";
import type {
  TrackingMapBasemap,
  TrackingMapPosition,
  TrackingMapZoomCommand,
} from "@/components/map/tracking-map-types";

type TrackingMapClientProps = {
  selectedPosition?: TrackingMapPosition | null;
  basemap?: TrackingMapBasemap;
  zoomCommand?: TrackingMapZoomCommand | null;
};

const TrackingMap = dynamic<TrackingMapClientProps>(
  () => import("./tracking-map"),
  {
    ssr: false,
    loading: () => (
      <div className="grid h-full w-full place-items-center bg-[#a9d5df] text-sm font-semibold text-white">
        Loading map...
      </div>
    ),
  },
);

export function TrackingMapClient(
  props: TrackingMapClientProps,
) {
  return <TrackingMap {...props} />;
}