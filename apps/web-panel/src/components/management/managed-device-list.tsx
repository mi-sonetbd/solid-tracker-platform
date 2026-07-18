"use client";

import {
  ArrowUp,
  CarFront,
  ChevronDown,
  CirclePlus,
  Eye,
  Filter,
  Heart,
  ListFilter,
  LoaderCircle,
  MapPin,
  MoreVertical,
  Pencil,
  RefreshCw,
  Search,
  Signal,
} from "lucide-react";
import {
  useMemo,
  useState,
} from "react";
import {
  activeMonitorAssignment,
  formatMonitorDate,
  monitorVehicleDisplayName,
  type ManagementMonitorVehicle,
} from "@/lib/management/monitor-types";

type ManagedDeviceListProps = {
  scopeLabel: string;
  vehicles: ManagementMonitorVehicle[];
  loading: boolean;
  error: string;
  selectedVehicleId: string | null;
  liveVehicleId: string | null;
  onSelectVehicle: (
    vehicle: ManagementMonitorVehicle,
  ) => void;
  onRefresh: () => void;
};

export function ManagedDeviceList({
  scopeLabel,
  vehicles,
  loading,
  error,
  selectedVehicleId,
  liveVehicleId,
  onSelectVehicle,
  onRefresh,
}: ManagedDeviceListProps) {
  const [search, setSearch] = useState("");

  const installedAssets = useMemo(
    () =>
      vehicles
        .map((vehicle) => ({
          vehicle,
          assignment:
            activeMonitorAssignment(vehicle),
        }))
        .filter(
          (
            item,
          ): item is {
            vehicle: ManagementMonitorVehicle;
            assignment: NonNullable<
              typeof item.assignment
            >;
          } => Boolean(item.assignment),
        ),
    [vehicles],
  );

  const filteredAssets = useMemo(() => {
    const query = search.trim().toLowerCase();

    if (!query) return installedAssets;

    return installedAssets.filter(
      ({ vehicle, assignment }) =>
        [
          vehicle.registrationNumber,
          vehicle.vehicleCode,
          vehicle.monitorCustomer.name,
          vehicle.monitorCustomer.code,
          assignment.device.deviceCode,
          assignment.device.imei,
          assignment.device.serialNumber,
          assignment.device.deviceModel
            .manufacturer,
          assignment.device.deviceModel.modelName,
        ]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
          .includes(query),
    );
  }, [installedAssets, search]);

  return (
    <section className="flex h-full w-[455px] shrink-0 flex-col border-r border-[#dfe6ef] bg-[#f8fafc]">
      <div className="border-b border-[#e2e8f1] bg-white p-3">
        <h2 className="truncate text-[13px] font-semibold text-[#405779]">
          {scopeLabel} (Installed {installedAssets.length} / Vehicles {vehicles.length})
        </h2>

        <label className="mt-3 flex h-8 items-center rounded-[3px] border border-[#cfd8e7] px-3">
          <input
            value={search}
            onChange={(event) =>
              setSearch(event.target.value)
            }
            className="min-w-0 flex-1 border-0 bg-transparent text-[11px] outline-none placeholder:text-[#8b9ab4]"
            placeholder="Device, IMEI, vehicle, or Customer"
          />
          <Search className="h-4 w-4 text-[#607392]" />
        </label>

        <button
          type="button"
          className="mt-3 flex h-7 items-center gap-1 rounded-[3px] border border-[#357cf4] px-2 text-[11px] text-[#357cf4]"
        >
          <CirclePlus className="h-4 w-4" />
          Add group
        </button>

        <div className="mt-3 flex items-center justify-between text-[11px]">
          <div className="flex items-center gap-3">
            <span className="rounded bg-[#edf2f8] px-2 py-1 font-semibold">
              All {filteredAssets.length}
            </span>
            <span
              className="flex items-center gap-0.5 text-[#30b56a]"
              title="Online data will come from Traccar"
            >
              <ArrowUp className="h-3 w-3" />-
            </span>
            <span
              className="flex items-center gap-0.5 text-[#ff5575]"
              title="Alert data will come from tracking events"
            >
              <Heart
                className="h-3 w-3"
                fill="currentColor"
              />
              -
            </span>
            <span
              className="flex items-center gap-0.5 text-[#52698e]"
              title="Signal data will come from Traccar"
            >
              <Signal className="h-3 w-3" />-
            </span>
          </div>

          <div className="flex items-center gap-3 text-[#607392]">
            <Eye className="h-3.5 w-3.5" />
            <Filter className="h-3.5 w-3.5" />
            <ListFilter className="h-3.5 w-3.5" />
            <button
              type="button"
              onClick={onRefresh}
              disabled={loading}
              aria-label="Refresh scoped devices"
              className="text-[#357cf4] disabled:opacity-50"
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

      <div className="flex h-10 items-center justify-between border-b border-[#e2e8f1] bg-[#edf2f8] px-4 text-[11px] font-semibold">
        <span className="flex items-center gap-2">
          <ChevronDown className="h-3.5 w-3.5" />
          Default group ({filteredAssets.length})
        </span>
        <span className="flex items-center gap-3">
          <Eye className="h-3.5 w-3.5" />
          <MoreVertical className="h-4 w-4" />
        </span>
      </div>

      <div className="st-scrollbar flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex min-h-64 items-center justify-center gap-2 text-[11px] text-[#71819c]">
            <LoaderCircle className="h-4 w-4 animate-spin text-[#357cf4]" />
            Loading scoped devices
          </div>
        ) : error ? (
          <div className="m-3 rounded-[4px] border border-red-200 bg-red-50 p-3 text-[10px] leading-5 text-red-700">
            {error}
          </div>
        ) : filteredAssets.length === 0 ? (
          <div className="m-3 rounded-[4px] border border-[#dfe6ef] bg-white p-5 text-center text-[10px] leading-5 text-[#71819c]">
            No installed tracker exists in the selected account scope.
          </div>
        ) : (
          filteredAssets.map(
            ({ vehicle, assignment }) => {
              const selected =
                selectedVehicleId === vehicle.id;

              return (
                <button
                  key={assignment.id}
                  type="button"
                  onClick={() =>
                    onSelectVehicle(vehicle)
                  }
                  className={[
                    "block w-full border-b border-[#e2e8f1] px-4 py-4 text-left",
                    selected
                      ? "bg-[#edf4ff]"
                      : "bg-white hover:bg-[#f8faff]",
                  ].join(" ")}
                >
                  <div className="flex items-start gap-3">
                    <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#dfe9fb] text-[#357cf4]">
                      <CarFront className="h-5 w-5" />
                    </div>

                    <div className="min-w-0 flex-1">
                      <div className="flex items-center justify-between gap-2">
                        <h3 className="truncate text-[13px] font-semibold text-[#405779]">
                          {monitorVehicleDisplayName(
                            vehicle,
                          )}
                        </h3>
                        <span
                          className={[
                            "shrink-0 text-[10px] font-semibold",
                            liveVehicleId === vehicle.id
                              ? "text-[#30b56a]"
                              : "text-[#637493]",
                          ].join(" ")}
                        >
                          {liveVehicleId === vehicle.id
                            ? "Live"
                            : "No live data"}
                        </span>
                      </div>

                      <p className="mt-1 truncate text-[10px] text-[#8b9ab4]">
                        {assignment.device.deviceCode}
                        {" | "}
                        {assignment.device.imei ||
                          "No IMEI"}
                      </p>

                      <p className="mt-1 truncate text-[9px] text-[#8b9ab4]">
                        {vehicle.monitorCustomer.name}
                        {" | "}
                        {formatMonitorDate(
                          assignment.startedAt,
                        )}
                      </p>

                      <div className="mt-3 flex items-center justify-end gap-4 text-[#71819c]">
                        <Heart
                          className="h-3.5 w-3.5"
                          fill="#c8d0dd"
                        />
                        <Pencil className="h-3.5 w-3.5" />
                        <MapPin className="h-3.5 w-3.5" />
                        <Eye className="h-3.5 w-3.5" />
                      </div>
                    </div>

                    <MoreVertical className="h-4 w-4 text-[#607392]" />
                  </div>
                </button>
              );
            },
          )
        )}
      </div>
    </section>
  );
}