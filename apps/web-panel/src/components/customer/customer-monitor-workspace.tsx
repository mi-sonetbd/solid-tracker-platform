"use client";

import {
  ArrowDownAZ,
  ArrowUp,
  CarFront,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  CirclePlus,
  Eye,
  Filter,
  Heart,
  Layers3,
  LoaderCircle,
  LocateFixed,
  MapPinned,
  MoreVertical,
  Pencil,
  RefreshCw,
  Search,
  Signal,
  SlidersHorizontal,
  Target,
} from "lucide-react";
import {
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { CustomerDevicePropertyDrawer } from "@/components/customer/customer-device-property-drawer";
import { CustomerMonitorRail } from "@/components/customer/customer-monitor-rail";
import { CustomerMapProviderSelector } from "@/components/customer/customer-map-provider-selector";
import { CustomerMapTrafficLightIcon } from "@/components/customer/customer-map-traffic-light-icon";
import { TrackingMapClient } from "@/components/map/tracking-map-client";
import type {
  TrackingMapBasemap,
  TrackingMapLocationCommand,
  TrackingMapLocationStatus,
  TrackingMapZoomCommand,
} from "@/components/map/tracking-map-types";
import {
  activeDeviceAssignment,
  deviceDisplayName,
  formatAssetDate,
  type CustomerVehicleAsset,
} from "@/lib/customer/customer-asset-types";
import { useCustomerAssets } from "@/lib/customer/use-customer-assets";

type CustomerMonitorWorkspaceProps = {
  canViewVehicles: boolean;
  canViewLocation: boolean;
  initialVehicleId?: string;
};

type CollapsibleObjectPanelProps = {
  collapsed: boolean;
  label: string;
  children: ReactNode;
  onToggle: () => void;
};

const mapTools = [
  LocateFixed,
  MapPinned,
  SlidersHorizontal,
  CustomerMapTrafficLightIcon,
  Layers3,
];

function CollapsibleObjectPanel({
  collapsed,
  label,
  children,
  onToggle,
}: CollapsibleObjectPanelProps) {
  const Icon = collapsed
    ? ChevronRight
    : ChevronLeft;

  return (
    <div
      className={[
        "relative h-full shrink-0 overflow-visible transition-[width] duration-150 ease-out",
        collapsed ? "w-[14px]" : "w-[350px]",
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

function CustomerObjectPanel({
  vehicles,
  filteredVehicles,
  loading,
  error,
  search,
  selectedVehicleId,
  onSearch,
  onSelectVehicle,
  onRefresh,
}: {
  vehicles: CustomerVehicleAsset[];
  filteredVehicles: CustomerVehicleAsset[];
  loading: boolean;
  error: string;
  search: string;
  selectedVehicleId: string | null;
  onSearch: (value: string) => void;
  onSelectVehicle: (vehicleId: string) => void;
  onRefresh: () => void;
}) {
  const installedCount = vehicles.filter((vehicle) =>
    Boolean(activeDeviceAssignment(vehicle)),
  ).length;

  return (
    <section className="h-full border-r border-[#dce4ef] bg-[#f5f7fb] p-2">
      <div className="flex h-full flex-col overflow-hidden rounded-[5px] border border-[#edf1f6] bg-[#f7f9fc] shadow-[0_2px_8px_rgba(35,61,102,0.06)]">
        <header className="border-b border-[#e1e7f0] bg-white px-3 pb-2.5 pt-3">
          <label className="flex h-8 items-center rounded-[3px] border border-[#cfd8e7] bg-white px-3">
            <input
              value={search}
              onChange={(event) =>
                onSearch(event.target.value)
              }
              className="min-w-0 flex-1 border-0 bg-transparent text-[11px] text-[#405779] outline-none placeholder:text-[#8b9ab4]"
              placeholder="Please enter the device name or IMEI"
            />
            <Search className="h-4 w-4 text-[#607392]" />
          </label>

          <button
            type="button"
            disabled
            title="Customer grouping will be connected in a dedicated stage"
            className="mt-2 flex h-7 items-center gap-1 rounded-[3px] border border-[#357cf4] px-2 text-[11px] font-medium text-[#357cf4]"
          >
            <CirclePlus className="h-4 w-4" />
            Add group
          </button>

          <div className="mt-2.5 flex items-center justify-between text-[10px] text-[#637493]">
            <div className="flex items-center gap-2.5">
              <span className="rounded-[3px] bg-[#edf2f8] px-2 py-1 font-semibold text-[#344b72]">
                All {vehicles.length}
              </span>

              <span
                className="flex items-center gap-0.5 font-semibold text-[#30b56a]"
                title="Online data will be connected with live tracking"
              >
                <ArrowUp
                  className="h-3 w-3"
                  strokeWidth={2.8}
                />
                0
              </span>

              <span
                className="flex items-center gap-0.5 font-semibold text-[#ff5b75]"
                title="Alert data will be connected later"
              >
                <Heart
                  className="h-3 w-3"
                  fill="currentColor"
                />
                0
              </span>

              <span
                className="flex items-center gap-0.5 font-semibold text-[#344b72]"
                title="Installed trackers"
              >
                <Signal className="h-3 w-3" />
                {installedCount}
              </span>
            </div>

            <div className="flex items-center gap-2.5">
              <Eye className="h-3.5 w-3.5" />
              <Filter className="h-3.5 w-3.5" />
              <ArrowDownAZ className="h-3.5 w-3.5" />
              <button
                type="button"
                onClick={onRefresh}
                aria-label="Refresh Customer devices"
                className="text-[#357cf4]"
              >
                <RefreshCw
                  className={[
                    "h-3.5 w-3.5",
                    loading ? "animate-spin" : "",
                  ].join(" ")}
                />
              </button>
            </div>
          </div>
        </header>

        <div className="flex h-9 items-center justify-between border-b border-[#e0e6ef] bg-[#edf1f7] px-3 text-[10px] font-medium text-[#536889]">
          <div className="flex items-center gap-2">
            <ChevronDown className="h-3.5 w-3.5" />
            <span>
              Default group({filteredVehicles.length})
            </span>
          </div>

          <div className="flex items-center gap-3">
            <Eye className="h-3.5 w-3.5" />
            <MoreVertical className="h-4 w-4" />
          </div>
        </div>

        <div className="st-scrollbar flex-1 overflow-y-auto bg-[#f7f9fc] p-3">
          {loading ? (
            <div className="flex min-h-[220px] items-center justify-center gap-2 text-[11px] text-[#71819c]">
              <LoaderCircle className="h-4 w-4 animate-spin text-[#357cf4]" />
              Loading devices
            </div>
          ) : error ? (
            <div className="rounded-[4px] border border-red-200 bg-red-50 p-3 text-[10px] leading-5 text-red-700">
              {error}
            </div>
          ) : filteredVehicles.length === 0 ? (
            <div className="rounded-[4px] border border-[#dfe6ef] bg-white p-5 text-center text-[10px] leading-5 text-[#71819c]">
              No Customer vehicle matches this search.
            </div>
          ) : (
            <div className="overflow-hidden rounded-[4px] border border-[#dfe6ef] bg-white">
              {filteredVehicles.map((vehicle) => {
                const assignment =
                  activeDeviceAssignment(vehicle);
                const selected =
                  selectedVehicleId === vehicle.id;

                return (
                  <button
                    key={vehicle.id}
                    type="button"
                    onClick={() =>
                      onSelectVehicle(vehicle.id)
                    }
                    className={[
                      "block w-full border-b border-[#e2e8f1] px-3 py-3 text-left last:border-b-0",
                      selected
                        ? "bg-[#edf4ff]"
                        : "bg-white hover:bg-[#f8faff]",
                    ].join(" ")}
                  >
                    <div className="flex items-start gap-3">
                      <div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-[#ff3152] text-white shadow-[0_2px_7px_rgba(255,49,82,0.22)]">
                        <CarFront
                          className="h-5 w-5"
                          strokeWidth={2.2}
                        />
                      </div>

                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-2">
                          <h2 className="truncate text-[12px] font-bold text-[#367cf6]">
                            {deviceDisplayName(vehicle)}
                          </h2>
                          <span className="shrink-0 text-[9px] text-[#637493]">
                            {assignment
                              ? "No live data"
                              : "No tracker"}
                          </span>
                        </div>

                        <p className="mt-1 truncate text-[10px] text-[#9aa8bd]">
                          {assignment?.device.imei ||
                            assignment?.device.deviceCode ||
                            vehicle.vehicleCode}
                        </p>

                        <p className="mt-1 text-[9px] text-[#9aa8bd]">
                          {assignment
                            ? formatAssetDate(
                                assignment.startedAt,
                              )
                            : "Tracker not installed"}
                        </p>

                        <div className="mt-3 flex items-center justify-end gap-3.5 text-[#8090aa]">
                          <Heart
                            className="h-3.5 w-3.5"
                            fill="#c8d0dd"
                          />
                          <Pencil className="h-3.5 w-3.5" />
                          <Target className="h-3.5 w-3.5" />
                          <Eye className="h-3.5 w-3.5" />
                        </div>
                      </div>

                      <MoreVertical className="h-4 w-4 text-[#4a5f80]" />
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </section>
  );
}

export function CustomerMonitorWorkspace({
  canViewVehicles,
  canViewLocation,
  initialVehicleId,
}: CustomerMonitorWorkspaceProps) {
  const [basemap, setBasemap] =
    useState<TrackingMapBasemap>(
      "google-hybrid",
    );
  const [
    isBasemapMenuOpen,
    setIsBasemapMenuOpen,
  ] = useState(false);
  const [zoomCommand, setZoomCommand] =
    useState<TrackingMapZoomCommand | null>(
      null,
    );
  const [
    myLocationCommand,
    setMyLocationCommand,
  ] = useState<TrackingMapLocationCommand | null>(
    null,
  );
  const [
    myLocationStatus,
    setMyLocationStatus,
  ] = useState<TrackingMapLocationStatus>(
    "idle",
  );
  const isMyLocationActive =
    myLocationStatus === "locating" ||
    myLocationStatus === "ready";
  const [
    isStreetViewActive,
    setIsStreetViewActive,
  ] = useState(false);
  const [
    isTrafficActive,
    setIsTrafficActive,
  ] = useState(false);
  const {
    vehicles,
    loading,
    error,
    refresh,
  } = useCustomerAssets(canViewVehicles);
  const [search, setSearch] = useState("");
  const [objectPanelCollapsed, setObjectPanelCollapsed] =
    useState(false);
  const [selectedVehicleId, setSelectedVehicleId] =
    useState<string | null>(
      initialVehicleId ?? null,
    );
  const [drawerOpen, setDrawerOpen] =
    useState(Boolean(initialVehicleId));

  const filteredVehicles = useMemo(() => {
    const query = search.trim().toLowerCase();

    if (!query) return vehicles;

    return vehicles.filter((vehicle) => {
      const assignment =
        activeDeviceAssignment(vehicle);
      const searchable = [
        vehicle.vehicleCode,
        vehicle.registrationNumber,
        vehicle.manufacturer,
        vehicle.modelName,
        assignment?.device.deviceCode,
        assignment?.device.imei,
        assignment?.device.serialNumber,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return searchable.includes(query);
    });
  }, [search, vehicles]);

  const selectedVehicle = useMemo(
    () =>
      vehicles.find(
        (vehicle) =>
          vehicle.id === selectedVehicleId,
      ) ?? null,
    [selectedVehicleId, vehicles],
  );


  function selectVehicle(vehicleId: string) {
    setSelectedVehicleId(vehicleId);
    setDrawerOpen(true);
  }

  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-h-[620px] min-w-[1180px] overflow-hidden bg-white">
      <CustomerMonitorRail activeItem="objects" />

      <CollapsibleObjectPanel
        collapsed={objectPanelCollapsed}
        label={
          objectPanelCollapsed
            ? "Expand Customer object panel"
            : "Collapse Customer object panel"
        }
        onToggle={() =>
          setObjectPanelCollapsed(
            (current) => !current,
          )
        }
      >
        <CustomerObjectPanel
          vehicles={vehicles}
          filteredVehicles={filteredVehicles}
          loading={loading}
          error={error}
          search={search}
          selectedVehicleId={selectedVehicleId}
          onSearch={setSearch}
          onSelectVehicle={selectVehicle}
          onRefresh={refresh}
        />
      </CollapsibleObjectPanel>

      <section
        className={[
          "relative min-w-0 flex-1 overflow-hidden bg-[#eef3f8]",
          "[&_.solid-tracker-map-controls]:transition-[right] [&_.solid-tracker-map-controls]:duration-150",
          drawerOpen && selectedVehicle
            ? "[&_.solid-tracker-map-controls]:right-[350px]"
            : "[&_.solid-tracker-map-controls]:right-0",
        ].join(" ")}
      >
        <TrackingMapClient
          selectedPosition={null}
          basemap={basemap}
          zoomCommand={zoomCommand}
          streetViewActive={
            isStreetViewActive
          }
          trafficActive={
            isTrafficActive
          }
          myLocationCommand={
            myLocationCommand
          }
          onMyLocationStatusChange={
            setMyLocationStatus
          }
        />

        <div className="absolute left-3 top-3 z-[1000] flex items-center gap-2">
          <label className="flex h-8 w-[220px] items-center rounded-[3px] bg-white px-3 shadow-[0_2px_8px_rgba(35,61,102,0.16)]">
            <input
              disabled={!canViewLocation}
              className="min-w-0 flex-1 border-0 bg-transparent text-[11px] outline-none placeholder:text-[#8b9ab4] disabled:cursor-not-allowed"
              placeholder={
                canViewLocation
                  ? "Please enter address"
                  : "Location permission unavailable"
              }
            />
            <Search className="h-4 w-4 text-[#357cf4]" />
          </label>

          <button
            type="button"
            className="flex h-8 min-w-[86px] items-center justify-between rounded-[3px] bg-white px-3 text-[11px] text-[#52698e] shadow-[0_2px_8px_rgba(35,61,102,0.16)]"
          >
            Default
            <ChevronDown className="h-4 w-4" />
          </button>
        </div>

        <div
          className={[
            "absolute top-4 z-[1000] flex flex-col gap-2 transition-[right] duration-150",
            drawerOpen && selectedVehicle
              ? "right-[362px]"
              : "right-3",
          ].join(" ")}
        >
                    <CustomerMapProviderSelector
            id="monitor-map-provider"
            open={isBasemapMenuOpen}
            value={basemap}
            onChange={(nextBasemap) => {
              setBasemap(nextBasemap);
              setIsBasemapMenuOpen(false);
            }}
          />

{mapTools.map((Icon, index) => (
            <button
              key={index}
              type="button"
              disabled={
                !canViewLocation && index === 0
              }
              onClick={() => {
                if (index === 0) {
                  setIsBasemapMenuOpen(false);
                  setIsStreetViewActive(false);
                  setMyLocationStatus(
                    "locating",
                  );
                  setMyLocationCommand(
                    (current) => ({
                      id:
                        (current?.id ?? 0) +
                        1,
                    }),
                  );
                }

                if (index === 1) {
                  setIsBasemapMenuOpen(false);
                  setIsStreetViewActive(
                    (current) => !current,
                  );
                }

                if (index === 3) {
                  setIsTrafficActive(
                    (current) => !current,
                  );
                }

                if (index === 4) {
                  setIsStreetViewActive(false);
                  setIsBasemapMenuOpen(
                    (current) => !current,
                  );
                }
              }}
              aria-pressed={
                index === 0
                  ? isMyLocationActive
                  : index === 1
                    ? isStreetViewActive
                    : index === 3
                      ? isTrafficActive
                      : undefined
              }
              aria-expanded={
                index === 4
                  ? isBasemapMenuOpen
                  : undefined
              }
              aria-controls={
                index === 4
                  ? "monitor-map-provider-panel"
                  : undefined
              }
              aria-label={
                index === 0
                  ? myLocationStatus ===
                    "locating"
                    ? "Finding my location"
                    : "Show my location"
                  : index === 1
                    ? isStreetViewActive
                      ? "Exit Street View"
                      : "Select Street View point"
                    : index === 3
                      ? isTrafficActive
                        ? "Hide traffic"
                        : "Show traffic"
                      : index === 4
                        ? "Choose map provider"
                        : `Map tool ${index + 1}`
              }
              title={
                index === 0
                  ? myLocationStatus ===
                    "locating"
                    ? "Finding my location"
                    : "Show my location"
                  : index === 1
                    ? isStreetViewActive
                      ? "Exit Street View"
                      : "Select Street View point"
                    : index === 3
                      ? isTrafficActive
                        ? "Hide traffic"
                        : "Show traffic"
                      : index === 4
                        ? "Choose map provider"
                        : undefined
              }
              data-my-location-toggle={
                index === 0
                  ? "true"
                  : undefined
              }
              data-street-view-toggle={
                index === 1
                  ? "true"
                  : undefined
              }
              data-traffic-toggle={
                index === 3
                  ? "true"
                  : undefined
              }
              data-basemap-selector={
                index === 4
                  ? "true"
                  : undefined
              }
              style={{
                backgroundColor:
                  (index === 0 &&
                    isMyLocationActive) ||
                  (index === 1 &&
                    isStreetViewActive) ||
                  (index === 3 &&
                    isTrafficActive) ||
                  (index === 4 &&
                    isBasemapMenuOpen)
                    ? "#357cf4"
                    : "#ffffff",
                color:
                  (index === 0 &&
                    isMyLocationActive) ||
                  (index === 1 &&
                    isStreetViewActive) ||
                  (index === 3 &&
                    isTrafficActive) ||
                  (index === 4 &&
                    isBasemapMenuOpen)
                    ? "#ffffff"
                    : "#52698e",
                borderColor:
                  (index === 0 &&
                    isMyLocationActive) ||
                  (index === 1 &&
                    isStreetViewActive) ||
                  (index === 3 &&
                    isTrafficActive) ||
                  (index === 4 &&
                    isBasemapMenuOpen)
                    ? "#357cf4"
                    : "#d7dfeb",
              }}
              className={[
                "grid h-8 w-8 place-items-center rounded-[3px] border border-[#e1e7f0] bg-white text-[#405779] shadow-[0_2px_8px_rgba(35,61,102,0.16)]",
                index === 3
                  ? "bg-[#357cf4] text-white"
                  : "",
                !canViewLocation && index === 0
                  ? "cursor-not-allowed opacity-50"
                  : "",
              ].join(" ")}
            >
              <Icon className="h-4 w-4 outline-none focus:outline-none focus-visible:ring-2 focus-visible:ring-[#9fc1ff] focus-visible:ring-offset-0" />
            </button>
          ))}

          <button
            type="button"
            aria-label="Zoom in"
            title="Zoom in"
            onClick={() =>
              setZoomCommand((current) => ({
                id: (current?.id ?? 0) + 1,
                delta: 1,
              }))
            }
            className="grid h-8 w-8 place-items-center rounded-[3px] border border-[#d7dfeb] bg-white text-[20px] font-medium leading-none text-[#52698e] shadow-[0_2px_8px_rgba(35,61,102,0.16)] transition hover:bg-[#f2f6fb]"
          >
            <span aria-hidden="true">+</span>
          </button>

          <button
            type="button"
            aria-label="Zoom out"
            title="Zoom out"
            onClick={() =>
              setZoomCommand((current) => ({
                id: (current?.id ?? 0) + 1,
                delta: -1,
              }))
            }
            className="grid h-8 w-8 place-items-center rounded-[3px] border border-[#d7dfeb] bg-white text-[20px] font-medium leading-none text-[#52698e] shadow-[0_2px_8px_rgba(35,61,102,0.16)] transition hover:bg-[#f2f6fb]"
          >
            <span aria-hidden="true">-</span>
          </button>
        </div>

        <div className="absolute bottom-3 left-3 z-[1000] flex h-8 min-w-[86px] items-center justify-between rounded-[3px] bg-white px-3 text-[10px] text-[#52698e] shadow-[0_2px_8px_rgba(35,61,102,0.16)]">
          <span>0s</span>
          <ChevronDown className="h-3.5 w-3.5" />
        </div>

        {!canViewLocation ? (
          <div className="absolute bottom-3 left-1/2 z-[1000] -translate-x-1/2 rounded-[4px] bg-[#263b5c]/92 px-4 py-2 text-[10px] font-medium text-white shadow-lg">
            Location permission is unavailable for this Customer account.
          </div>
        ) : null}

        {drawerOpen && selectedVehicle ? (
          <CustomerDevicePropertyDrawer
            vehicle={selectedVehicle}
            onClose={() => setDrawerOpen(false)}
          />
        ) : null}
      </section>
    </div>
  );
}