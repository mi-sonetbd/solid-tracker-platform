"use client";

import dynamic from "next/dynamic";

const TrackingMap = dynamic(() => import("./tracking-map"), {
  ssr: false,
  loading: () => (
    <div className="grid h-full w-full place-items-center bg-[#a9d5df] text-sm font-semibold text-white">
      Loading mapâ€¦
    </div>
  ),
});

export function TrackingMapClient() {
  return <TrackingMap />;
}