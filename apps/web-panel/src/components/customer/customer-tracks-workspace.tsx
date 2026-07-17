"use client";

import {
  CalendarDays,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Clock3,
  Layers3,
  LocateFixed,
  MapPinned,
  Navigation,
  Search,
  SlidersHorizontal,
  X,
} from "lucide-react";
import {
  useMemo,
  useState,
  type ReactNode,
} from "react";
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
} from "@/lib/customer/customer-asset-types";
import { useCustomerAssets } from "@/lib/customer/use-customer-assets";

type CustomerTracksWorkspaceProps = {
  canViewVehicles: boolean;
  canViewLocation: boolean;
  initialVehicleId?: string;
};

type CollapsibleTrackPanelProps = {
  collapsed: boolean;
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

function dateInputValue(date: Date) {
  const year = date.getFullYear();
  const month = String(
    date.getMonth() + 1,
  ).padStart(2, "0");
  const day = String(
    date.getDate(),
  ).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

function CollapsibleTrackPanel({
  collapsed,
  children,
  onToggle,
}: CollapsibleTrackPanelProps) {
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
        aria-label={
          collapsed
            ? "Expand Customer track panel"
            : "Collapse Customer track panel"
        }
        title={
          collapsed
            ? "Expand Customer track panel"
            : "Collapse Customer track panel"
        }
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

export function CustomerTracksWorkspace({
  canViewVehicles,
  canViewLocation,
  initialVehicleId,
}: CustomerTracksWorkspaceProps) {
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
  const [
    isMyLocationEnabled,
    setIsMyLocationEnabled,
  ] = useState(false);
  const isMyLocationActive =
    isMyLocationEnabled;
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
  } = useCustomerAssets(canViewVehicles);

  const threeDaysAgo = useMemo(() => {
    const date = new Date();
    date.setDate(date.getDate() - 3);
    return dateInputValue(date);
  }, []);

  const today = useMemo(
    () => dateInputValue(new Date()),
    [],
  );

  const [panelCollapsed, setPanelCollapsed] =
    useState(false);
  const [devicePickerOpen, setDevicePickerOpen] =
    useState(false);
  const [filtersHidden, setFiltersHidden] =
    useState(false);
  const [selectedVehicleId, setSelectedVehicleId] =
    useState(initialVehicleId ?? "");
  const [trackType, setTrackType] =
    useState("all");
  const [startDate, setStartDate] =
    useState(threeDaysAgo);
  const [endDate, setEndDate] =
    useState(today);
  const [period, setPeriod] =
    useState("last-3-days");
  const [searched, setSearched] =
    useState(false);

  const deviceOptions = useMemo(
    () =>
      vehicles
        .map((vehicle) => ({
          vehicle,
          assignment:
            activeDeviceAssignment(vehicle),
          label: deviceDisplayName(vehicle),
        }))
        .filter((item) =>
          Boolean(item.assignment),
        ),
    [vehicles],
  );

  const selectedDevice = useMemo(
    () =>
      deviceOptions.find(
        (item) =>
          item.vehicle.id === selectedVehicleId,
      ) ?? null,
    [deviceOptions, selectedVehicleId],
  );

  function resetFilters() {
    setSelectedVehicleId("");
    setTrackType("all");
    setStartDate(threeDaysAgo);
    setEndDate(today);
    setPeriod("last-3-days");
    setSearched(false);
  }

  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-h-[620px] min-w-[1180px] overflow-hidden bg-white">
      <CustomerMonitorRail activeItem="tracks" />

      <CollapsibleTrackPanel
        collapsed={panelCollapsed}
        onToggle={() =>
          setPanelCollapsed(
            (current) => !current,
          )
        }
      >
        <section className="h-full border-r border-[#dce4ef] bg-[#f5f7fb] p-2">
          <div className="flex h-full flex-col overflow-hidden rounded-[5px] border border-[#edf1f6] bg-[#f7f9fc] shadow-[0_2px_8px_rgba(35,61,102,0.06)]">
            <header className="space-y-2 border-b border-[#e1e7f0] bg-white p-3">
              <div className="relative">
                <button
                  type="button"
                  onClick={() =>
                    setDevicePickerOpen(
                      (current) => !current,
                    )
                  }
                  className="flex h-9 w-full items-center justify-between rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-left text-[11px] text-[#405779]"
                >
                  <span className="truncate">
                    {selectedDevice
                      ? `${selectedDevice.label} [${selectedDevice.assignment?.device.imei ?? selectedDevice.assignment?.device.deviceCode}]`
                      : "Select device"}
                  </span>
                  {devicePickerOpen ? (
                    <ChevronUp className="h-4 w-4 text-[#607392]" />
                  ) : (
                    <ChevronDown className="h-4 w-4 text-[#607392]" />
                  )}
                </button>

                {devicePickerOpen ? (
                  <div className="absolute left-0 right-0 top-[42px] z-[1300] overflow-hidden rounded-[4px] border border-[#cfd8e7] bg-white shadow-[0_8px_24px_rgba(35,61,102,0.18)]">
                    <label className="m-2 flex h-8 items-center rounded-[3px] border border-[#dce4ef] px-3">
                      <input
                        disabled
                        placeholder="Search device"
                        className="min-w-0 flex-1 border-0 bg-transparent text-[10px] outline-none placeholder:text-[#8b9ab4]"
                      />
                      <Search className="h-3.5 w-3.5 text-[#607392]" />
                    </label>

                    <div className="border-t border-[#edf1f6] px-3 py-2 text-[10px] font-semibold text-[#52698e]">
                      Default Group({deviceOptions.length})
                    </div>

                    <div className="max-h-[220px] overflow-y-auto">
                      {loading ? (
                        <p className="px-3 py-4 text-[10px] text-[#71819c]">
                          Loading devices...
                        </p>
                      ) : deviceOptions.length === 0 ? (
                        <p className="px-3 py-4 text-[10px] text-[#71819c]">
                          No installed tracker is available.
                        </p>
                      ) : (
                        deviceOptions.map((item) => (
                          <button
                            key={item.vehicle.id}
                            type="button"
                            onClick={() => {
                              setSelectedVehicleId(
                                item.vehicle.id,
                              );
                              setDevicePickerOpen(false);
                              setSearched(false);
                            }}
                            className={[
                              "flex w-full items-center gap-2 px-4 py-2 text-left text-[10px] hover:bg-[#f4f7fb]",
                              selectedVehicleId ===
                              item.vehicle.id
                                ? "bg-[#edf4ff] text-[#357cf4]"
                                : "text-[#52698e]",
                            ].join(" ")}
                          >
                            <Navigation className="h-3.5 w-3.5 text-[#ff3152]" />
                            <span className="truncate">
                              {item.label} [
                              {item.assignment?.device.imei ??
                                item.assignment?.device.deviceCode}
                              ]
                            </span>
                          </button>
                        ))
                      )}
                    </div>
                  </div>
                ) : null}
              </div>

              {!filtersHidden ? (
                <>
                  <label className="flex h-8 items-center rounded-[3px] border border-[#cfd8e7] bg-white px-3">
                    <select
                      value={trackType}
                      onChange={(event) =>
                        setTrackType(
                          event.target.value,
                        )
                      }
                      className="min-w-0 flex-1 border-0 bg-transparent text-[10px] text-[#52698e] outline-none"
                    >
                      <option value="all">All</option>
                      <option value="driving">
                        Driving
                      </option>
                      <option value="parking">
                        Parking
                      </option>
                      <option value="alert">
                        Alert related
                      </option>
                    </select>
                    <ChevronDown className="h-3.5 w-3.5 text-[#607392]" />
                  </label>

                  <div className="grid grid-cols-2 gap-2">
                    <label className="flex h-8 items-center gap-2 rounded-[3px] border border-[#cfd8e7] bg-white px-3">
                      <CalendarDays className="h-3.5 w-3.5 text-[#607392]" />
                      <input
                        type="date"
                        value={startDate}
                        onChange={(event) =>
                          setStartDate(
                            event.target.value,
                          )
                        }
                        className="min-w-0 flex-1 border-0 bg-transparent text-[10px] text-[#52698e] outline-none"
                        aria-label="Track start date"
                      />
                    </label>

                    <label className="flex h-8 items-center gap-2 rounded-[3px] border border-[#cfd8e7] bg-white px-3">
                      <CalendarDays className="h-3.5 w-3.5 text-[#607392]" />
                      <input
                        type="date"
                        value={endDate}
                        onChange={(event) =>
                          setEndDate(
                            event.target.value,
                          )
                        }
                        className="min-w-0 flex-1 border-0 bg-transparent text-[10px] text-[#52698e] outline-none"
                        aria-label="Track end date"
                      />
                    </label>
                  </div>

                  <label className="flex h-8 items-center rounded-[3px] border border-[#cfd8e7] bg-white px-3">
                    <Clock3 className="h-3.5 w-3.5 text-[#607392]" />
                    <select
                      value={period}
                      onChange={(event) =>
                        setPeriod(
                          event.target.value,
                        )
                      }
                      className="min-w-0 flex-1 border-0 bg-transparent text-[10px] text-[#52698e] outline-none"
                    >
                      <option value="today">
                        Today
                      </option>
                      <option value="last-3-days">
                        Last 3 days
                      </option>
                      <option value="last-7-days">
                        Last 7 days
                      </option>
                      <option value="custom">
                        Custom
                      </option>
                    </select>
                    <ChevronDown className="h-3.5 w-3.5 text-[#607392]" />
                  </label>
                </>
              ) : null}

              <div className="flex items-center justify-between">
                <button
                  type="button"
                  onClick={() =>
                    setFiltersHidden(
                      (current) => !current,
                    )
                  }
                  className="flex items-center gap-1 text-[10px] font-medium text-[#357cf4]"
                >
                  {filtersHidden ? (
                    <ChevronDown className="h-3.5 w-3.5" />
                  ) : (
                    <ChevronUp className="h-3.5 w-3.5" />
                  )}
                  {filtersHidden
                    ? "Show filters"
                    : "Put away"}
                </button>

                <div className="flex items-center gap-3">
                  <button
                    type="button"
                    onClick={() =>
                      setSearched(true)
                    }
                    disabled={!selectedVehicleId}
                    className="h-8 min-w-[102px] rounded-[3px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:cursor-not-allowed disabled:bg-[#aebed8]"
                  >
                    Search
                  </button>

                  <button
                    type="button"
                    onClick={resetFilters}
                    className="text-[10px] font-medium text-[#357cf4]"
                  >
                    Reset
                  </button>
                </div>
              </div>
            </header>

            <div className="st-scrollbar flex-1 overflow-y-auto p-3">
              {error ? (
                <div className="rounded-[5px] border border-red-200 bg-red-50 p-4 text-[10px] leading-5 text-red-700">
                  {error}
                </div>
              ) : !selectedDevice ? (
                <div className="rounded-[5px] border border-[#dfe6ef] bg-white p-5 text-center text-[10px] leading-5 text-[#71819c]">
                  Select a Customer Device to search
                  its route history.
                </div>
              ) : (
                <div className="rounded-[5px] border border-[#dfe6ef] bg-white p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <h2 className="text-[12px] font-semibold text-[#405779]">
                        {selectedDevice.label}
                      </h2>
                      <p className="mt-1 text-[10px] text-[#8b9ab4]">
                        {selectedDevice.assignment?.device.imei ??
                          selectedDevice.assignment?.device.deviceCode}
                      </p>
                    </div>

                    <button
                      type="button"
                      onClick={() => {
                        setSelectedVehicleId("");
                        setSearched(false);
                      }}
                      aria-label="Clear selected Device"
                      className="grid h-7 w-7 place-items-center rounded-[3px] text-[#71819c] hover:bg-[#f2f6fb]"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </div>

                  {searched ? (
                    <div className="mt-4 rounded-[4px] bg-[#f4f7fb] p-4 text-center">
                      <Navigation className="mx-auto h-5 w-5 text-[#357cf4]" />
                      <h3 className="mt-2 text-[11px] font-semibold text-[#405779]">
                        No route history available
                      </h3>
                      <p className="mt-2 text-[9px] leading-5 text-[#7f8da4]">
                        The Tracks interface is ready.
                        Real positions, trips, mileage,
                        stops, replay, and route lines
                        will appear after the location
                        history backend is connected.
                      </p>
                    </div>
                  ) : (
                    <p className="mt-4 text-[10px] leading-5 text-[#71819c]">
                      Choose a date range and press
                      Search.
                    </p>
                  )}
                </div>
              )}
            </div>
          </div>
        </section>
      </CollapsibleTrackPanel>

      <section className="relative min-w-0 flex-1 overflow-hidden bg-[#eef3f8]">
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
          myLocationActive={
            isMyLocationEnabled
          }
          onMyLocationStatusChange={
            setMyLocationStatus
          }
        />

        <label className="absolute left-3 top-3 z-[1000] flex h-8 w-[220px] items-center rounded-[3px] bg-white px-3 shadow-[0_2px_8px_rgba(35,61,102,0.16)]">
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

        <div className="absolute right-3 top-4 z-[1000] flex flex-col gap-2">
                    <CustomerMapProviderSelector
            id="tracks-map-provider"
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

                  if (isMyLocationEnabled) {
                    setIsMyLocationEnabled(false);
                    setMyLocationStatus(
                      "idle",
                    );
                    setMyLocationCommand(
                      null,
                    );
                  } else {
                    setIsMyLocationEnabled(true);
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
                  ? "tracks-map-provider-panel"
                  : undefined
              }
              aria-label={
                index === 0
                  ? isMyLocationActive
                    ? myLocationStatus ===
                      "locating"
                      ? "Finding my location"
                      : "Hide my location"
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
                        : `Track map tool ${index + 1}`
              }
              title={
                index === 0
                  ? isMyLocationActive
                    ? myLocationStatus ===
                      "locating"
                      ? "Finding my location"
                      : "Hide my location"
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
      </section>
    </div>
  );
}