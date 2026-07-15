"use client";

import {
  BellRing,
  CarFront,
  MapPinned,
  Route,
} from "lucide-react";
import Link from "next/link";

export type CustomerMonitorRailItem =
  | "objects"
  | "alerts"
  | "tracks"
  | "multi-track";

type CustomerMonitorRailProps = {
  activeItem: CustomerMonitorRailItem;
};

const items = [
  {
    id: "objects" as const,
    label: "Objects",
    icon: CarFront,
    href: "/monitor",
    operational: true,
  },
  {
    id: "alerts" as const,
    label: "Alerts",
    icon: BellRing,
    href: "/alerts",
    operational: true,
  },
  {
    id: "tracks" as const,
    label: "Tracks",
    icon: MapPinned,
    href: "/tracks",
    operational: true,
  },
  {
    id: "multi-track" as const,
    label: "Multi-track",
    icon: Route,
    href: null,
    operational: false,
  },
];

export function CustomerMonitorRail({
  activeItem,
}: CustomerMonitorRailProps) {
  return (
    <aside className="flex h-full w-[86px] shrink-0 flex-col border-r border-[#dce4ef] bg-white px-2 py-4">
      <nav
        className="space-y-4"
        aria-label="Customer monitor tools"
      >
        {items.map((item) => {
          const Icon = item.icon;
          const active = item.id === activeItem;
          const className = [
            "flex h-[72px] w-full flex-col items-center justify-center gap-2 rounded-[6px] text-[11px] font-semibold transition",
            active
              ? "bg-[#357cf4] text-white shadow-[0_5px_14px_rgba(53,124,244,0.24)]"
              : "text-[#405779] hover:bg-[#f2f6fb]",
            item.operational
              ? ""
              : "cursor-default",
          ].join(" ");

          const content = (
            <>
              <Icon
                className="h-6 w-6"
                strokeWidth={2}
              />
              <span>{item.label}</span>
            </>
          );

          if (item.operational && item.href) {
            return (
              <Link
                key={item.id}
                href={item.href}
                aria-current={
                  active ? "page" : undefined
                }
                className={className}
              >
                {content}
              </Link>
            );
          }

          return (
            <button
              key={item.id}
              type="button"
              disabled
              title={`${item.label} will be connected in its dedicated stage`}
              className={className}
            >
              {content}
            </button>
          );
        })}
      </nav>
    </aside>
  );
}