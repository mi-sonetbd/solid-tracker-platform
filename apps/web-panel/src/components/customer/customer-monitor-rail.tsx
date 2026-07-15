"use client";

import {
  BellRing,
  CarFront,
  MapPinned,
  Route,
} from "lucide-react";

const items = [
  {
    label: "Objects",
    icon: CarFront,
    active: true,
  },
  {
    label: "Alerts",
    icon: BellRing,
    active: false,
  },
  {
    label: "Tracks",
    icon: MapPinned,
    active: false,
  },
  {
    label: "Multi-track",
    icon: Route,
    active: false,
  },
];

export function CustomerMonitorRail() {
  return (
    <aside className="flex h-full w-[86px] shrink-0 flex-col border-r border-[#dce4ef] bg-white px-2 py-4">
      <nav
        className="space-y-4"
        aria-label="Customer monitor tools"
      >
        {items.map((item) => {
          const Icon = item.icon;

          return (
            <button
              key={item.label}
              type="button"
              disabled={!item.active}
              aria-current={
                item.active ? "page" : undefined
              }
              title={
                item.active
                  ? item.label
                  : `${item.label} will be connected in its dedicated stage`
              }
              className={[
                "flex h-[72px] w-full flex-col items-center justify-center gap-2 rounded-[6px] text-[11px] font-semibold transition",
                item.active
                  ? "bg-[#357cf4] text-white shadow-[0_5px_14px_rgba(53,124,244,0.24)]"
                  : "text-[#405779] hover:bg-[#f2f6fb] disabled:cursor-default disabled:opacity-100",
              ].join(" ")}
            >
              <Icon
                className="h-6 w-6"
                strokeWidth={2}
              />
              <span>{item.label}</span>
            </button>
          );
        })}
      </nav>
    </aside>
  );
}