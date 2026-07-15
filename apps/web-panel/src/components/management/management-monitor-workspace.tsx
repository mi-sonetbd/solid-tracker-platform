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

type CollapsiblePanelProps = {
  expandedWidth: string;
  collapsed: boolean;
  label: string;
  children: React.ReactNode;
  onToggle: () => void;
};

function CollapsiblePanel({
  expandedWidth,
  collapsed,
  label,
  children,
  onToggle,
}: CollapsiblePanelProps) {
  const Icon = collapsed ? ChevronRight : ChevronLeft;

  return (
    <div
      className={[
        "relative h-full shrink-0 overflow-visible transition-[width] duration-150 ease-out",
        collapsed ? "w-[14px]" : expandedWidth,
      ].join(" ")}
    >
      <div className="absolute inset-0 overflow-hidden">
        <div
          className={[
            "h-full transition-[opacity,transform] duration-150 ease-out",
            collapsed
              ? "-translate-x-2 opacity-0 pointer-events-none"
              : "translate-x-0 opacity-100",
          ].join(" ")}
        >
          {children}
        </div>

        <div
          aria-hidden="true"
          className={[
            "absolute inset-y-0 right-0 w-[14px] border-x border-[#cfd9e7] bg-[#e9eef5] transition-opacity duration-100",
            collapsed ? "opacity-100" : "pointer-events-none opacity-0",
          ].join(" ")}
        />
      </div>

      <button
        type="button"
        aria-label={label}
        title={label}
        onClick={onToggle}
        className="absolute right-[-8px] top-1/2 z-[1100] grid h-[64px] w-[16px] -translate-y-1/2 place-items-center rounded-r-[4px] border border-l-0 border-[#314765] bg-[#263b5c] text-[#c6d2e4] shadow-[0_5px_12px_rgba(25,48,82,0.28)] transition-[background-color,transform] duration-100 hover:bg-[#1e304b] active:scale-95"
      >
        <Icon className="h-4 w-4" strokeWidth={2.8} />
      </button>
    </div>
  );
}

export function ManagementMonitorWorkspace() {
  const [accountPanelCollapsed, setAccountPanelCollapsed] =
    useState(false);
  const [devicePanelCollapsed, setDevicePanelCollapsed] =
    useState(false);

  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-w-[1180px] overflow-hidden">
      <ManagementRail />

      <CollapsiblePanel
        expandedWidth="w-[300px]"
        collapsed={accountPanelCollapsed}
        label={
          accountPanelCollapsed
            ? "Expand account list panel"
            : "Collapse account list panel"
        }
        onToggle={() =>
          setAccountPanelCollapsed((value) => !value)
        }
      >
        <div className="h-full w-[300px]">
          <AccountTree compact />
        </div>
      </CollapsiblePanel>

      <CollapsiblePanel
        expandedWidth="w-[455px]"
        collapsed={devicePanelCollapsed}
        label={
          devicePanelCollapsed
            ? "Expand device list panel"
            : "Collapse device list panel"
        }
        onToggle={() =>
          setDevicePanelCollapsed((value) => !value)
        }
      >
        <div className="h-full w-[455px]">
          <ManagedDeviceList />
        </div>
      </CollapsiblePanel>

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