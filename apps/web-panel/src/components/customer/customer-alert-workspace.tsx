"use client";

import {
  CalendarDays,
  CheckCircle2,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Filter,
  Layers3,
  LocateFixed,
  Map,
  MapPinned,
  MessageSquareText,
  Search,
  SlidersHorizontal,
  Target,
} from "lucide-react";
import {
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { CustomerMonitorRail } from "@/components/customer/customer-monitor-rail";
import { TrackingMapClient } from "@/components/map/tracking-map-client";
import {
  activeDeviceAssignment,
  deviceDisplayName,
} from "@/lib/customer/customer-asset-types";
import { useCustomerAssets } from "@/lib/customer/use-customer-assets";

type CustomerAlertWorkspaceProps = {
  canViewVehicles: boolean;
  canViewLocation: boolean;
  initialVehicleId?: string;
};

type CollapsibleAlertPanelProps = {
  collapsed: boolean;
  children: ReactNode;
  onToggle: () => void;
};

const mapTools = [
  LocateFixed,
  MapPinned,
  SlidersHorizontal,
  Target,
  Layers3,
  Map,
];

function CollapsibleAlertPanel({
  collapsed,
  children,
  onToggle,
}: CollapsibleAlertPanelProps) {
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
            ? "Expand Customer alert panel"
            : "Collapse Customer alert panel"
        }
        title={
          collapsed
            ? "Expand Customer alert panel"
            : "Collapse Customer alert panel"
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

export function CustomerAlertWorkspace({
  canViewVehicles,
  canViewLocation,
  initialVehicleId,
}: CustomerAlertWorkspaceProps) {
  const [basemap, setBasemap] = useState<"map" | "satellite">("map");
  const {
    vehicles,
    loading,
    error,
  } = useCustomerAssets(canViewVehicles);
  const [panelCollapsed, setPanelCollapsed] =
    useState(false);
  const [selectedVehicleId, setSelectedVehicleId] =
    useState(initialVehicleId ?? "");
  const [alertType, setAlertType] =
    useState("all");
  const [startDate, setStartDate] =
    useState("");
  const [endDate, setEndDate] =
    useState("");

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

  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-h-[620px] min-w-[1180px] overflow-hidden bg-white">
      <CustomerMonitorRail activeItem="alerts" />

      <CollapsibleAlertPanel
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
              <label className="flex h-9 items-center rounded-[3px] border border-[#cfd8e7] bg-white px-3">
                <select
                  value={selectedVehicleId}
                  onChange={(event) =>
                    setSelectedVehicleId(
                      event.target.value,
                    )
                  }
                  disabled={loading}
                  className="min-w-0 flex-1 border-0 bg-transparent text-[11px] text-[#405779] outline-none disabled:opacity-60"
                >
                  <option value="">
                    Select device
                  </option>
                  {deviceOptions.map((item) => (
                    <option
                      key={item.vehicle.id}
                      value={item.vehicle.id}
                    >
                      {item.label}
                    </option>
                  ))}
                </select>
                <ChevronDown className="h-4 w-4 text-[#607392]" />
              </label>

              <div className="grid grid-cols-[104px_1fr] gap-2">
                <div className="flex h-8 items-center justify-between rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] text-[#52698e]">
                  Customize
                  <ChevronDown className="h-3.5 w-3.5" />
                </div>

                <label className="flex h-8 items-center rounded-[3px] border border-[#cfd8e7] bg-white px-3">
                  <select
                    value={alertType}
                    onChange={(event) =>
                      setAlertType(
                        event.target.value,
                      )
                    }
                    className="min-w-0 flex-1 border-0 bg-transparent text-[10px] text-[#52698e] outline-none"
                  >
                    <option value="all">
                      All alert types
                    </option>
                    <option value="vibration">
                      Vibration alert
                    </option>
                    <option value="acc-on">
                      ACC ON
                    </option>
                    <option value="acc-off">
                      ACC OFF
                    </option>
                    <option value="overspeed">
                      Overspeed
                    </option>
                  </select>
                  <ChevronDown className="h-3.5 w-3.5 text-[#607392]" />
                </label>
              </div>

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
                    aria-label="Alert start date"
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
                    aria-label="Alert end date"
                  />
                </label>
              </div>

              <button
                type="button"
                disabled
                title="Alert search will activate when the alert backend is connected"
                className="flex h-8 w-full items-center justify-center gap-2 rounded-[3px] bg-[#357cf4] text-[11px] font-semibold text-white shadow-sm disabled:cursor-not-allowed"
              >
                <Search className="h-4 w-4" />
                Search
              </button>

              <div className="flex items-center justify-between pt-1 text-[10px]">
                <button
                  type="button"
                  disabled
                  title="Alert read-state persistence will be connected with the alert backend"
                  className="flex items-center gap-1 font-medium text-[#357cf4]"
                >
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  All read
                </button>

                <Filter className="h-4 w-4 text-[#607392]" />
              </div>
            </header>

            <div className="st-scrollbar flex-1 overflow-y-auto p-3">
              {loading ? (
                <div className="rounded-[5px] border border-[#dfe6ef] bg-white p-5 text-center text-[10px] text-[#71819c]">
                  Loading Customer devices...
                </div>
              ) : error ? (
                <div className="rounded-[5px] border border-red-200 bg-red-50 p-4 text-[10px] leading-5 text-red-700">
                  {error}
                </div>
              ) : (
                <div className="rounded-[5px] border border-[#dfe6ef] bg-white p-5">
                  <div className="mx-auto grid h-10 w-10 place-items-center rounded-full bg-[#edf4ff] text-[#357cf4]">
                    <MessageSquareText className="h-5 w-5" />
                  </div>

                  <h2 className="mt-3 text-center text-[12px] font-semibold text-[#405779]">
                    No alert records available
                  </h2>

                  <p className="mt-2 text-center text-[10px] leading-5 text-[#7f8da4]">
                    The Alerts interface is ready. Real
                    Device events will appear here after
                    the Solid Tracker alert backend is
                    connected.
                  </p>

                  {selectedDevice ? (
                    <div className="mt-4 rounded-[4px] bg-[#f4f7fb] px-3 py-2 text-[10px] text-[#52698e]">
                      Selected:{" "}
                      <strong>
                        {selectedDevice.label}
                      </strong>
                    </div>
                  ) : null}
                </div>
              )}
            </div>
          </div>
        </section>
      </CollapsibleAlertPanel>

      <section className="relative min-w-0 flex-1 overflow-hidden bg-[#eef3f8]">
        <TrackingMapClient
          selectedPosition={null}
          basemap={basemap}
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
          {mapTools.map((Icon, index) => (
            <button
              key={index}
              type="button"
              disabled={
                !canViewLocation && index === 0
              }
              onClick={() => {
                              if (index === 4) {
                                setBasemap("satellite");
                              }

                              if (index === 5) {
                                setBasemap("map");
                              }
                            }}
                            aria-pressed={
                              index === 4
                                ? basemap === "satellite"
                                : index === 5
                                  ? basemap === "map"
                                  : undefined
                            }
                            aria-label={
                              index === 4
                                ? "Satellite view"
                                : index === 5
                                  ? "Map view"
                                  : `Alert map tool ${index + 1}`
                            }
                            title={
                              index === 4
                                ? "Satellite view"
                                : index === 5
                                  ? "Map view"
                                  : undefined
                            }
                            style={
                              (index === 4 &&
                                basemap === "satellite") ||
                              (index === 5 &&
                                basemap === "map")
                                ? {
                                    backgroundColor: "#357cf4",
                                    color: "#ffffff",
                                  }
                                : undefined
                            }
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
              <Icon className="h-4 w-4" />
            </button>
          ))}
        </div>

        <div className="absolute bottom-3 left-3 z-[1000] flex h-8 min-w-[86px] items-center justify-between rounded-[3px] bg-white px-3 text-[10px] text-[#52698e] shadow-[0_2px_8px_rgba(35,61,102,0.16)]">
          <span>0s</span>
          <ChevronDown className="h-3.5 w-3.5" />
        </div>
      </section>
    </div>
  );
}