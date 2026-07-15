"use client";

import {
  ArrowUp,
  Car,
  ChevronDown,
  CirclePlus,
  Eye,
  Filter,
  Heart,
  Layers3,
  ListFilter,
  LoaderCircle,
  Map,
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
} from "react";
import { CustomerDevicePropertyDrawer } from "@/components/customer/customer-device-property-drawer";
import { TrackingMapClient } from "@/components/map/tracking-map-client";
import {
  activeDeviceAssignment,
  deviceDisplayName,
  formatAssetDate,
} from "@/lib/customer/customer-asset-types";
import { useCustomerAssets } from "@/lib/customer/use-customer-assets";

type CustomerMonitorWorkspaceProps = {
  canViewVehicles: boolean;
  canViewLocation: boolean;
  initialVehicleId?: string;
};

const mapTools = [
  Target,
  MapPinned,
  SlidersHorizontal,
  Layers3,
  Map,
  ListFilter,
];

export function CustomerMonitorWorkspace({
  canViewVehicles,
  canViewLocation,
  initialVehicleId,
}: CustomerMonitorWorkspaceProps) {
  const {
    vehicles,
    loading,
    error,
    refresh,
  } = useCustomerAssets(canViewVehicles);
  const [search, setSearch] = useState("");
  const [selectedVehicleId, setSelectedVehicleId] =
    useState<string | null>(initialVehicleId ?? null);
  const [drawerOpen, setDrawerOpen] = useState(
    Boolean(initialVehicleId),
  );

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
        (vehicle) => vehicle.id === selectedVehicleId,
      ) ?? null,
    [selectedVehicleId, vehicles],
  );


  const installedCount = vehicles.filter((vehicle) =>
    Boolean(activeDeviceAssignment(vehicle)),
  ).length;

  function selectVehicle(vehicleId: string) {
    setSelectedVehicleId(vehicleId);
    setDrawerOpen(true);
  }

  return (
    <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-h-[620px] bg-white">
      <section className="relative w-[350px] shrink-0 border-r border-[#dde5ef] bg-[#f6f8fb] p-2">
        <div className="flex h-full flex-col overflow-hidden rounded-[5px] bg-[#f7f9fc]">
          <div className="border-b border-[#e1e7f0] bg-white px-3 pb-2 pt-3">
            <label className="flex h-8 items-center rounded-[3px] border border-[#cfd8e7] px-3">
              <input
                value={search}
                onChange={(event) =>
                  setSearch(event.target.value)
                }
                className="min-w-0 flex-1 border-0 bg-transparent text-[12px] outline-none placeholder:text-[#8b9ab4]"
                placeholder="Please enter the device name or IMEI"
              />
              <Search className="h-4 w-4 text-[#607392]" />
            </label>

            <button
              type="button"
              className="mt-2 flex h-7 items-center gap-1 rounded-[3px] border border-[#357cf4] px-2 text-[12px] font-medium text-[#357cf4]"
            >
              <CirclePlus className="h-4 w-4" />
              Add group
            </button>

            <div className="mt-2 flex items-center justify-between text-[11px] text-[#637493]">
              <div className="flex items-center gap-2.5">
                <span className="rounded-[3px] bg-[#edf2f8] px-2 py-1 font-semibold text-[#344b72]">
                  All {vehicles.length}
                </span>

                <span
                  className="flex items-center gap-0.5 font-semibold text-[#30b56a]"
                  title="Online devices"
                >
                  <ArrowUp className="h-3 w-3" strokeWidth={2.8} />
                  0
                </span>

                <span
                  className="flex items-center gap-0.5 font-semibold text-[#ff5b75]"
                  title="Alert devices"
                >
                  <Heart className="h-3 w-3" fill="currentColor" />
                  0
                </span>

                <span
                  className="flex items-center gap-0.5 font-semibold text-[#344b72]"
                  title="Tracking data unavailable"
                >
                  <Signal className="h-3 w-3" />
                  {installedCount}
                </span>
              </div>

              <div className="flex items-center gap-2.5">
                <Eye className="h-3.5 w-3.5" />
                <Filter className="h-3.5 w-3.5" />
                <ListFilter className="h-3.5 w-3.5" />
                <button
                  type="button"
                  onClick={refresh}
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
          </div>

          <div className="flex h-9 items-center justify-between bg-[#edf1f7] px-3 text-[11px] font-medium text-[#536889]">
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
                        selectVehicle(vehicle.id)
                      }
                      className={[
                        "block w-full border-b border-[#e2e8f1] px-3 py-3 text-left last:border-b-0",
                        selected
                          ? "bg-[#edf4ff]"
                          : "bg-white hover:bg-[#f8faff]",
                      ].join(" ")}
                    >
                      <div className="flex items-start gap-3">
                        <div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-[#ff3152] text-white">
                          <Car
                            className="h-5 w-5"
                            fill="currentColor"
                          />
                        </div>

                        <div className="min-w-0 flex-1">
                          <div className="flex items-center justify-between gap-2">
                            <h2 className="truncate text-[12px] font-bold text-[#405779]">
                              {deviceDisplayName(vehicle)}
                            </h2>
                            <span className="shrink-0 text-[10px] text-[#637493]">
                              {assignment
                                ? "No data"
                                : "No tracker"}
                            </span>
                          </div>

                          <p className="mt-1 truncate text-[10px] text-[#9aa8bd]">
                            {assignment
                              ? `${assignment.device.deviceCode} | ${assignment.device.imei || "No IMEI"}`
                              : vehicle.vehicleCode}
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

        <button
          type="button"
          aria-label="Collapse object panel"
          className="absolute -right-[7px] top-1/2 z-[1001] grid h-36 w-[8px] -translate-y-1/2 place-items-center rounded-r bg-[#d9e3f2] text-[#6e80a0]"
        >
          {"<"}
        </button>
      </section>

      <section className="relative min-w-0 flex-1 overflow-hidden">
        <TrackingMapClient selectedPosition={null} />

        <div className="absolute left-3 top-3 z-[1000] flex items-center gap-2">
          <label className="flex h-8 w-[220px] items-center rounded-[3px] bg-white px-3 shadow-sm">
            <input
              className="min-w-0 flex-1 border-0 bg-transparent text-[12px] outline-none placeholder:text-[#8b9ab4]"
              placeholder="Please enter address"
            />
            <Search className="h-4 w-4 text-[#357cf4]" />
          </label>

          <button
            type="button"
            className="flex h-8 min-w-[84px] items-center justify-between rounded-[3px] bg-white px-3 text-[12px] text-[#5c6f8e] shadow-sm"
          >
            Default
            <ChevronDown className="h-4 w-4" />
          </button>
        </div>

        <div className="absolute right-2.5 top-4 z-[1000] flex flex-col gap-1.5">
          {mapTools.map((Icon, index) => (
            <button
              key={index}
              type="button"
              className={[
                "grid h-8 w-8 place-items-center rounded-[3px] bg-white text-[#405779] shadow-sm",
                index === 3
                  ? "bg-[#357cf4] text-white"
                  : "",
              ].join(" ")}
            >
              <Icon className="h-4 w-4" />
            </button>
          ))}
        </div>

        <select className="absolute bottom-14 left-4 z-[1000] h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[12px] text-[#5c6f8e] shadow-sm">
          <option>20s</option>
          <option>10s</option>
          <option>30s</option>
        </select>

        {selectedVehicle && drawerOpen ? (
          <CustomerDevicePropertyDrawer
            vehicle={selectedVehicle}
            onClose={() => setDrawerOpen(false)}
          />
        ) : null}

        {selectedVehicle &&
        drawerOpen &&
        canViewLocation ? (
          <div className="pointer-events-none absolute bottom-4 left-1/2 z-[1000] -translate-x-1/2 rounded-[4px] bg-[#405779]/90 px-4 py-2 text-[10px] font-medium text-white shadow-lg">
            No real Traccar position exists yet. The selected
            device is ready for automatic map focusing when a
            position arrives.
          </div>
        ) : null}
      </section>
    </div>
  );
}