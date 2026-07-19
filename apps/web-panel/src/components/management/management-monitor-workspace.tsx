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
import {
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { CustomerDevicePropertyDrawer } from "@/components/customer/customer-device-property-drawer";
import { ManagedDeviceList } from "@/components/management/managed-device-list";
import { ManagementMonitorAccountTree } from "@/components/management/management-monitor-account-tree";
import { ManagementRail } from "@/components/management/management-rail";
import { TrackingMapClient } from "@/components/map/tracking-map-client";
import type { TrackingMapPosition } from "@/components/map/tracking-map-types";
import {
  type ManagementMonitorScope,
  type ManagementMonitorVehicle,
} from "@/lib/management/monitor-types";
import { useManagementMonitorAssets } from "@/lib/management/use-management-monitor-assets";
import { useManagementMonitorHierarchy } from "@/lib/management/use-management-monitor-hierarchy";
import { useManagementLivePosition } from "@/lib/management/use-management-live-position";

const mapTools = [
  Target,
  MapPinned,
  Layers3,
  SlidersHorizontal,
  Map,
];

type ManagementMonitorWorkspaceProps = {
  workspace: string;
  canViewDealers: boolean;
  canViewCustomers: boolean;
  canViewVehicles: boolean;
  canViewLocation: boolean;
};

type CollapsiblePanelProps = {
  expandedWidth: string;
  collapsed: boolean;
  label: string;
  children: ReactNode;
  onToggle: () => void;
};

function CollapsiblePanel({
  expandedWidth,
  collapsed,
  label,
  children,
  onToggle,
}: CollapsiblePanelProps) {
  const Icon = collapsed
    ? ChevronRight
    : ChevronLeft;

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
            collapsed
              ? "opacity-100"
              : "pointer-events-none opacity-0",
          ].join(" ")}
        />
      </div>

      <button
        type="button"
        aria-label={label}
        title={label}
        onClick={onToggle}
        className="absolute left-full top-1/2 z-[1100] grid h-[64px] w-[16px] -translate-y-1/2 place-items-center rounded-r-[4px] border border-l-0 border-[#314765] bg-[#263b5c] text-[#c6d2e4] shadow-[0_5px_12px_rgba(25,48,82,0.28)] transition-[background-color,transform] duration-100 hover:bg-[#1e304b] active:scale-95"
      >
        <Icon
          className="h-4 w-4"
          strokeWidth={2.8}
        />
      </button>
    </div>
  );
}

export function ManagementMonitorWorkspace({
  workspace,
  canViewDealers,
  canViewCustomers,
  canViewVehicles,
  canViewLocation,
}: ManagementMonitorWorkspaceProps) {
  const platformWorkspace =
    workspace === "SUPER_ADMIN" ||
    workspace === "ADMIN";
  const [accountPanelCollapsed, setAccountPanelCollapsed] =
    useState(false);
  const [devicePanelCollapsed, setDevicePanelCollapsed] =
    useState(false);
  const [selectedScope, setSelectedScope] =
    useState<ManagementMonitorScope>({
      key: "platform",
      type: "PLATFORM",
      id: null,
      label: platformWorkspace
        ? "Solid Tracker"
        : "Authenticated scope",
    });
  const [selectedVehicle, setSelectedVehicle] =
    useState<ManagementMonitorVehicle | null>(
      null,
    );
  const [drawerOpen, setDrawerOpen] =
    useState(false);

  const hierarchy =
    useManagementMonitorHierarchy({
      canViewDealers,
      canViewCustomers,
    });
  const assets = useManagementMonitorAssets({
    scope: selectedScope,
    customers: hierarchy.customers,
    hierarchyLoading: hierarchy.loading,
    canViewVehicles,
  });
  const live = useManagementLivePosition({
    vehicleId: selectedVehicle?.id ?? null,
    enabled: canViewLocation && Boolean(selectedVehicle),
  });
  const selectedPosition = useMemo<TrackingMapPosition | null>(
    () =>
      live.position
        ? {
            latitude: live.position.latitude,
            longitude: live.position.longitude,
            vehicleType: selectedVehicle?.vehicleType,
            label:
              selectedVehicle?.registrationNumber ||
              selectedVehicle?.vehicleCode ||
              "Tracked vehicle",
          }
        : null,
    [live.position, selectedVehicle],
  );

  const selectedScopeLabel = useMemo(() => {
    if (selectedScope.type !== "PLATFORM") {
      return selectedScope.label;
    }

    if (platformWorkspace) {
      return "Solid Tracker";
    }

    if (hierarchy.dealers.length === 1) {
      return hierarchy.dealers[0].name;
    }

    return "Authenticated scope";
  }, [
    hierarchy.dealers,
    platformWorkspace,
    selectedScope,
  ]);

  function selectScope(
    scope: ManagementMonitorScope,
  ) {
    setSelectedScope(scope);
    setSelectedVehicle(null);
    setDrawerOpen(false);
    assets.prepareScopeChange();
  }

  function selectVehicle(
    vehicle: ManagementMonitorVehicle,
  ) {
    setSelectedVehicle(vehicle);
    setDrawerOpen(true);
  }

  function refreshHierarchy() {
    hierarchy.refresh();
    assets.prepareScopeChange();
  }

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
          setAccountPanelCollapsed(
            (value) => !value,
          )
        }
      >
        <ManagementMonitorAccountTree
          workspace={workspace}
          dealers={hierarchy.dealers}
          customers={hierarchy.customers}
          loading={hierarchy.loading}
          error={hierarchy.error}
          selectedScope={selectedScope}
          onSelectScope={selectScope}
          onRefresh={refreshHierarchy}
        />
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
          setDevicePanelCollapsed(
            (value) => !value,
          )
        }
      >
        <ManagedDeviceList
          scopeLabel={selectedScopeLabel}
          vehicles={assets.vehicles}
          loading={
            assets.loading ||
            hierarchy.loading
          }
          error={
            hierarchy.error || assets.error
          }
          selectedVehicleId={
            selectedVehicle?.id ?? null
          }
          liveVehicleId={
            live.position ? selectedVehicle?.id ?? null : null
          }
          onSelectVehicle={selectVehicle}
          onRefresh={assets.refresh}
        />
      </CollapsiblePanel>

      <section className="relative min-w-0 flex-1 overflow-hidden">
        <TrackingMapClient selectedPosition={selectedPosition} />

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
                index === 2
                  ? "bg-[#357cf4] text-white"
                  : "",
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

        {selectedVehicle && drawerOpen ? (
          <CustomerDevicePropertyDrawer
            vehicle={selectedVehicle}
            livePosition={live.position}
            liveLoading={live.loading}
            liveError={live.error}
            onClose={() => setDrawerOpen(false)}
          />
        ) : null}

        {selectedVehicle &&
        drawerOpen &&
        canViewLocation &&
        !live.position ? (
          <div className="pointer-events-none absolute bottom-4 left-1/2 z-[1000] -translate-x-1/2 rounded-[4px] bg-[#405779]/90 px-4 py-2 text-[10px] font-medium text-white shadow-lg">
            {live.loading
              ? "Loading live Traccar position..."
              : live.error || "No live Traccar position is available yet."}
          </div>
        ) : null}
      </section>
    </div>
  );
}