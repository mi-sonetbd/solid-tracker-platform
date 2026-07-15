"use client";

import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Layers3,
  Map,
  MapPinned,
  Search,
  SlidersHorizontal,
  Target,
} from "lucide-react";
import { useState } from "react";
import { AccountTree } from "@/components/management/account-tree";
import { ManagedDeviceList } from "@/components/management/managed-device-list";
import { ManagementRail } from "@/components/management/management-rail";
import { TrackingMapClient } from "@/components/map/tracking-map-client";

const mapTools = [
  Target,
  MapPinned,
  Layers3,
  SlidersHorizontal,
  Map,
];

type CollapseToggleProps = {
  collapsed: boolean;
  side: "left" | "right";
  label: string;
  onClick: () => void;
};

function CollapseToggle({
  collapsed,
  side,
  label,
  onClick,
}: CollapseToggleProps) {
  const LeftIcon = side === "left" ? ChevronRight : ChevronLeft;
  const RightIcon = side === "left" ? ChevronLeft : ChevronRight;
  const Icon = collapsed ? LeftIcon : RightIcon;

  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      className={[
        "absolute top-1/2 z-[1100] grid h-12 w-6 -translate-y-1/2 place-items-center rounded-full bg-[#223654] text-white shadow-[0_8px_18px_rgba(18,44,86,0.26)] transition hover:bg-[#1a2a43]",
        side === "left" ? "-right-3" : "-right-3",
      ].join(" ")}
    >
      <Icon className="h-4 w-4" strokeWidth={2.5} />
    </button>
  );
}

export function ManagementMonitorWorkspace() {
  const [accountPanelCollapsed, setAccountPanelCollapsed] =
    useState(false);
  const [devicePanelCollapsed, setDevicePanelCollapsed] =
    useState(false);

  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-w-[1380px] overflow-hidden">
      <ManagementRail />

      <div className="relative flex h-full shrink-0">
        {!accountPanelCollapsed ? <AccountTree compact /> : null}

        <div
          className={[
            "relative h-full shrink-0 transition-all duration-200",
            accountPanelCollapsed ? "w-0" : "w-0",
          ].join(" ")}
        >
          <CollapseToggle
            collapsed={accountPanelCollapsed}
            side="left"
            label={
              accountPanelCollapsed
                ? "Expand account list panel"
                : "Collapse account list panel"
            }
            onClick={() =>
              setAccountPanelCollapsed((value) => !value)
            }
          />
        </div>
      </div>

      <div className="relative flex h-full shrink-0">
        {!devicePanelCollapsed ? <ManagedDeviceList /> : null}

        <div
          className={[
            "relative h-full shrink-0 transition-all duration-200",
            devicePanelCollapsed ? "w-0" : "w-0",
          ].join(" ")}
        >
          <CollapseToggle
            collapsed={devicePanelCollapsed}
            side="right"
            label={
              devicePanelCollapsed
                ? "Expand device list panel"
                : "Collapse device list panel"
            }
            onClick={() =>
              setDevicePanelCollapsed((value) => !value)
            }
          />
        </div>
      </div>

      <section className="relative min-w-0 flex-1 overflow-hidden">
        <TrackingMapClient />

        <div className="absolute left-3 top-3 z-[1000] flex items-center gap-2">
          <label className="flex h-8 w-[255px] items-center rounded-[3px] bg-white px-3 shadow-sm">
            <input
              className="min-w-0 flex-1 border-0 bg-transparent text-[11px] outline-none placeholder:text-[#8b9ab4]"
              placeholder="Please enter address"
            />
            <Search className="h-4 w-4 text-[#357cf4]" />
          </label>

          <button
            type="button"
            className="flex h-8 min-w-[92px] items-center justify-between rounded-[3px] bg-white px-3 text-[11px] text-[#52698e] shadow-sm"
          >
            Default
            <ChevronDown className="h-4 w-4" />
          </button>
        </div>

        <div className="absolute right-3 top-4 z-[1000] flex flex-col gap-2">
          {mapTools.map((Icon, index) => (
            <button
              key={index}
              type="button"
              className={[
                "grid h-8 w-8 place-items-center rounded-[3px] bg-white text-[#405779] shadow-sm",
                index === 2 ? "bg-[#357cf4] text-white" : "",
              ].join(" ")}
            >
              <Icon className="h-4 w-4" />
            </button>
          ))}
        </div>

        <select className="absolute bottom-14 left-4 z-[1000] h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[11px] text-[#52698e] shadow-sm">
          <option>8s</option>
          <option>10s</option>
          <option>20s</option>
        </select>
      </section>
    </div>
  );
}