"use client";

import {
  Activity,
  BarChart3,
  Boxes,
  CarFront,
  CircleAlert,
  Clock3,
  Cpu,
  FileBarChart,
  Gauge,
  LoaderCircle,
  MapPin,
  RadioTower,
  RefreshCw,
  Search,
  ShieldCheck,
  WifiOff,
} from "lucide-react";
import {
  useEffect,
  useMemo,
  useState,
  type FormEvent,
} from "react";
import { TrackingMapClient } from "@/components/map/tracking-map-client";
import {
  activeDeviceAssignment,
  normalizeCustomerVehicle,
  titleCase,
  vehicleDisplayName,
  type CustomerAssetListResponse,
  type CustomerAssetView,
  type CustomerVehicleAsset,
} from "@/lib/customer/customer-asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type CustomerAssetWorkspaceProps = {
  view: CustomerAssetView;
  canViewVehicles: boolean;
  canViewLocation: boolean;
  canViewHistory: boolean;
};

const viewCopy: Record<
  CustomerAssetView,
  {
    title: string;
    description: string;
  }
> = {
  monitor: {
    title: "Vehicle Monitor",
    description:
      "Your vehicles and installed trackers. Live positions will appear after Traccar synchronization.",
  },
  device: {
    title: "My Devices",
    description:
      "Installed tracker identity, model, lifecycle state, and vehicle assignment.",
  },
  report: {
    title: "Vehicle Reports",
    description:
      "Reports are restricted to your own vehicles and become available when tracking data is connected.",
  },
  fleet: {
    title: "My Fleet",
    description:
      "Every vehicle in your Customer account and its primary tracker status.",
  },
};

function formatDate(value?: string | null) {
  if (!value) return "-";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return "-";

  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function vehicleTypeIcon(vehicle: CustomerVehicleAsset) {
  return vehicle.vehicleType === "MOTORCYCLE"
    ? "Motorcycle"
    : titleCase(vehicle.vehicleType);
}

function trackingState(
  vehicle: CustomerVehicleAsset,
) {
  const assignment = activeDeviceAssignment(vehicle);

  if (!assignment) {
    return {
      label: "Tracker not installed",
      className: "bg-amber-50 text-amber-700",
    };
  }

  return {
    label: "No live position yet",
    className: "bg-slate-100 text-slate-600",
  };
}

function SummaryCard({
  label,
  value,
  detail,
  icon: Icon,
}: {
  label: string;
  value: number;
  detail: string;
  icon: typeof CarFront;
}) {
  return (
    <article className="rounded-[7px] border border-[#dfe6ef] bg-white p-4 shadow-sm">
      <div className="flex items-center justify-between">
        <p className="text-[10px] font-semibold uppercase tracking-[0.12em] text-[#8b9ab4]">
          {label}
        </p>
        <Icon className="h-4 w-4 text-[#357cf4]" />
      </div>
      <p className="mt-2 text-[26px] font-semibold text-[#344b72]">
        {value}
      </p>
      <p className="mt-1 text-[10px] text-[#7d8ca6]">
        {detail}
      </p>
    </article>
  );
}

export function CustomerAssetWorkspace({
  view,
  canViewVehicles,
  canViewLocation,
  canViewHistory,
}: CustomerAssetWorkspaceProps) {
  const [vehicles, setVehicles] = useState<CustomerVehicleAsset[]>([]);
  const [loading, setLoading] = useState(canViewVehicles);
  const [error, setError] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [activeSearch, setActiveSearch] = useState("");
  const [refreshVersion, setRefreshVersion] = useState(0);
  const copy = viewCopy[view];

  useEffect(() => {
    if (!canViewVehicles) return;

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: "1",
      pageSize: "100",
    });

    if (activeSearch) {
      parameters.set("search", activeSearch);
    }

    fetch(`/api/customer/assets?${parameters.toString()}`, {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | CustomerAssetListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Customer assets could not be loaded.",
          );
        }

        return payload as CustomerAssetListResponse;
      })
      .then((payload) => {
        setVehicles(
          payload.items.map(normalizeCustomerVehicle),
        );
        setError("");
      })
      .catch((requestError: unknown) => {
        if (
          requestError instanceof DOMException &&
          requestError.name === "AbortError"
        ) {
          return;
        }

        setVehicles([]);
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Customer assets could not be loaded.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [
    activeSearch,
    canViewVehicles,
    refreshVersion,
  ]);

  const statistics = useMemo(() => {
    const installed = vehicles.filter(
      (vehicle) => Boolean(activeDeviceAssignment(vehicle)),
    ).length;

    return {
      totalVehicles: vehicles.length,
      installed,
      withoutTracker: vehicles.length - installed,
      livePositions: 0,
    };
  }, [vehicles]);

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setActiveSearch(searchInput.trim());
  }

  function refresh() {
    setLoading(true);
    setRefreshVersion((current) => current + 1);
  }

  if (!canViewVehicles) {
    return (
      <main className="grid min-h-[calc(100vh-var(--st-topbar-height))] place-items-center bg-[#eef2f7] p-6">
        <section className="max-w-[520px] rounded-[8px] border border-[#dfe6ef] bg-white p-8 text-center shadow-sm">
          <ShieldCheck className="mx-auto h-9 w-9 text-[#8ea0ba]" />
          <h1 className="mt-4 text-[18px] font-semibold text-[#344b72]">
            Vehicle access is unavailable
          </h1>
          <p className="mt-2 text-[11px] leading-5 text-[#71819c]">
            This Customer login does not currently have vehicle.view permission.
          </p>
        </section>
      </main>
    );
  }

  return (
    <main className="st-scrollbar min-h-[calc(100vh-var(--st-topbar-height))] overflow-auto bg-[#eef2f7] p-4">
      <section className="mx-auto max-w-[1600px]">
        <header className="flex flex-wrap items-start justify-between gap-4 rounded-[8px] bg-white px-5 py-4 shadow-sm">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              {view === "monitor" ? (
                <Activity className="h-5 w-5" />
              ) : view === "device" ? (
                <Cpu className="h-5 w-5" />
              ) : view === "report" ? (
                <BarChart3 className="h-5 w-5" />
              ) : (
                <CarFront className="h-5 w-5" />
              )}
              <span className="text-[10px] font-semibold uppercase tracking-[0.18em]">
                Customer Scope
              </span>
            </div>
            <h1 className="mt-2 text-[19px] font-semibold text-[#344b72]">
              {copy.title}
            </h1>
            <p className="mt-1 text-[11px] text-[#71819c]">
              {copy.description}
            </p>
          </div>

          <div className="flex items-center gap-2">
            <form onSubmit={search} className="flex">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#8b9ab4]" />
                <input
                  value={searchInput}
                  onChange={(event) =>
                    setSearchInput(event.target.value)
                  }
                  placeholder="Vehicle, registration, chassis, engine"
                  className="h-9 w-[290px] rounded-l-[4px] border border-[#cfd8e7] pl-10 pr-3 text-[11px] outline-none focus:border-[#357cf4]"
                />
              </div>
              <button
                type="submit"
                className="h-9 rounded-r-[4px] bg-[#52698e] px-4 text-[11px] font-semibold text-white"
              >
                Search
              </button>
            </form>

            <button
              type="button"
              onClick={refresh}
              disabled={loading}
              className="flex h-9 items-center gap-2 rounded-[4px] border border-[#cfd8e7] bg-white px-4 text-[11px] font-semibold text-[#52698e]"
            >
              <RefreshCw
                className={[
                  "h-4 w-4",
                  loading ? "animate-spin" : "",
                ].join(" ")}
              />
              Refresh
            </button>
          </div>
        </header>

        {error ? (
          <div className="mt-4 flex items-center gap-2 rounded-[5px] border border-red-200 bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
            <CircleAlert className="h-4 w-4" />
            {error}
          </div>
        ) : null}

        <div className="mt-4 grid gap-4 md:grid-cols-4">
          <SummaryCard
            label="Vehicles"
            value={statistics.totalVehicles}
            detail="Authenticated Customer scope"
            icon={CarFront}
          />
          <SummaryCard
            label="Installed trackers"
            value={statistics.installed}
            detail="Active primary assignments"
            icon={Cpu}
          />
          <SummaryCard
            label="Without tracker"
            value={statistics.withoutTracker}
            detail="Vehicle exists, tracker absent"
            icon={Boxes}
          />
          <SummaryCard
            label="Live positions"
            value={statistics.livePositions}
            detail="Traccar connection pending"
            icon={MapPin}
          />
        </div>

        {view === "monitor" ? (
          <MonitorView
            vehicles={vehicles}
            loading={loading}
            canViewLocation={canViewLocation}
          />
        ) : view === "device" ? (
          <DeviceView
            vehicles={vehicles}
            loading={loading}
          />
        ) : view === "report" ? (
          <ReportView
            vehicles={vehicles}
            loading={loading}
            canViewHistory={canViewHistory}
          />
        ) : (
          <FleetView
            vehicles={vehicles}
            loading={loading}
          />
        )}
      </section>
    </main>
  );
}

function LoadingState() {
  return (
    <div className="flex min-h-[320px] items-center justify-center gap-2 text-[11px] text-[#71819c]">
      <LoaderCircle className="h-5 w-5 animate-spin text-[#357cf4]" />
      Loading authenticated Customer assets
    </div>
  );
}

function EmptyState() {
  return (
    <div className="grid min-h-[320px] place-items-center text-center">
      <div>
        <CarFront className="mx-auto h-10 w-10 text-[#b5c2d5]" />
        <p className="mt-3 text-[12px] font-semibold text-[#52698e]">
          No vehicle belongs to this Customer account
        </p>
        <p className="mt-1 text-[10px] text-[#8b9ab4]">
          Ask the Platform or managing Dealer to assign a vehicle.
        </p>
      </div>
    </div>
  );
}

function MonitorView({
  vehicles,
  loading,
  canViewLocation,
}: {
  vehicles: CustomerVehicleAsset[];
  loading: boolean;
  canViewLocation: boolean;
}) {
  return (
    <section className="mt-4 grid min-h-[590px] overflow-hidden rounded-[8px] border border-[#dfe6ef] bg-white shadow-sm lg:grid-cols-[370px_1fr]">
      <aside className="st-scrollbar overflow-y-auto border-r border-[#dfe6ef]">
        <header className="sticky top-0 z-10 border-b border-[#e2e8f1] bg-white px-4 py-3">
          <p className="text-[11px] font-semibold text-[#405779]">
            My Vehicles
          </p>
          <p className="mt-1 text-[9px] text-[#8b9ab4]">
            {vehicles.length} scoped vehicle
            {vehicles.length === 1 ? "" : "s"}
          </p>
        </header>

        {loading ? (
          <LoadingState />
        ) : vehicles.length === 0 ? (
          <EmptyState />
        ) : (
          vehicles.map((vehicle) => {
            const assignment =
              activeDeviceAssignment(vehicle);
            const state = trackingState(vehicle);

            return (
              <article
                key={vehicle.id}
                className="border-b border-[#edf1f6] px-4 py-4 hover:bg-[#f8faff]"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate text-[12px] font-semibold text-[#405779]">
                      {vehicleDisplayName(vehicle)}
                    </p>
                    <p className="mt-1 text-[9px] text-[#8b9ab4]">
                      {vehicle.vehicleCode} Â·{" "}
                      {vehicleTypeIcon(vehicle)}
                    </p>
                  </div>
                  <span className="rounded-full bg-emerald-50 px-2 py-1 text-[8px] font-semibold text-emerald-700">
                    {vehicle.status}
                  </span>
                </div>

                <div className="mt-3 rounded-[5px] bg-[#f5f8fc] p-3 text-[9px] text-[#657795]">
                  <p>
                    Tracker:{" "}
                    <span className="font-semibold text-[#405779]">
                      {assignment?.device.deviceCode ??
                        "Not installed"}
                    </span>
                  </p>
                  <p className="mt-1">
                    IMEI:{" "}
                    {assignment?.device.imei ?? "-"}
                  </p>
                </div>

                <div className="mt-3 flex items-center justify-between">
                  <span
                    className={[
                      "rounded-full px-2 py-1 text-[8px] font-semibold",
                      state.className,
                    ].join(" ")}
                  >
                    {state.label}
                  </span>
                  <span className="text-[8px] text-[#8b9ab4]">
                    Last update: -
                  </span>
                </div>
              </article>
            );
          })
        )}
      </aside>

      <div className="relative min-h-[590px] overflow-hidden">
        <TrackingMapClient />

        <div className="pointer-events-none absolute left-4 top-4 z-[800] max-w-[360px] rounded-[7px] border border-[#d8e4f4] bg-white/95 p-4 shadow-lg backdrop-blur">
          <div className="flex items-center gap-2 text-[#357cf4]">
            <RadioTower className="h-4 w-4" />
            <p className="text-[10px] font-semibold uppercase tracking-[0.13em]">
              Tracking connection
            </p>
          </div>

          <p className="mt-2 text-[12px] font-semibold text-[#405779]">
            {canViewLocation
              ? "No live position yet"
              : "Location permission unavailable"}
          </p>
          <p className="mt-1 text-[10px] leading-5 text-[#71819c]">
            Vehicle and tracker assignments are real. Map markers,
            speed, ignition, and last-update time will appear after the
            installed tracker is synchronized with Traccar.
          </p>
        </div>
      </div>
    </section>
  );
}

function DeviceView({
  vehicles,
  loading,
}: {
  vehicles: CustomerVehicleAsset[];
  loading: boolean;
}) {
  return (
    <section className="mt-4 overflow-hidden rounded-[8px] border border-[#dfe6ef] bg-white shadow-sm">
      {loading ? (
        <LoadingState />
      ) : vehicles.length === 0 ? (
        <EmptyState />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1150px] text-left text-[10px]">
            <thead className="bg-[#f4f7fb] text-[#52698e]">
              <tr>
                {[
                  "Vehicle",
                  "Vehicle Code",
                  "Tracker",
                  "IMEI",
                  "Device Model",
                  "Firmware",
                  "Lifecycle",
                  "Assignment",
                  "Tracking",
                ].map((heading) => (
                  <th
                    key={heading}
                    className="px-4 py-3 font-semibold"
                  >
                    {heading}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody>
              {vehicles.map((vehicle) => {
                const assignment =
                  activeDeviceAssignment(vehicle);
                const device = assignment?.device ?? null;

                return (
                  <tr
                    key={vehicle.id}
                    className="border-t border-[#e2e8f1] text-[#52698e]"
                  >
                    <td className="px-4 py-4">
                      <p className="font-semibold text-[#405779]">
                        {vehicleDisplayName(vehicle)}
                      </p>
                      <p className="mt-1 text-[9px] text-[#8b9ab4]">
                        {vehicleTypeIcon(vehicle)}
                      </p>
                    </td>
                    <td className="px-4 py-4 font-medium text-[#357cf4]">
                      {vehicle.vehicleCode}
                    </td>
                    <td className="px-4 py-4 font-semibold text-[#405779]">
                      {device?.deviceCode ?? "Not installed"}
                    </td>
                    <td className="px-4 py-4">
                      {device?.imei ?? "-"}
                    </td>
                    <td className="px-4 py-4">
                      {device
                        ? `${device.deviceModel.manufacturer} ${device.deviceModel.modelName}`
                        : "-"}
                    </td>
                    <td className="px-4 py-4">
                      {device?.firmwareVersion ?? "-"}
                    </td>
                    <td className="px-4 py-4">
                      <span
                        className={[
                          "rounded-full px-2 py-1 text-[9px] font-semibold",
                          device
                            ? "bg-sky-50 text-sky-700"
                            : "bg-amber-50 text-amber-700",
                        ].join(" ")}
                      >
                        {device
                          ? titleCase(
                              device.lifecycleStatus,
                            )
                          : "No Device"}
                      </span>
                    </td>
                    <td className="px-4 py-4">
                      {assignment
                        ? `Active since ${formatDate(
                            assignment.startedAt,
                          )}`
                        : "-"}
                    </td>
                    <td className="px-4 py-4">
                      <span className="inline-flex items-center gap-1.5 text-[#7d8ca6]">
                        <WifiOff className="h-3.5 w-3.5" />
                        No live data
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function FleetView({
  vehicles,
  loading,
}: {
  vehicles: CustomerVehicleAsset[];
  loading: boolean;
}) {
  return (
    <section className="mt-4 overflow-hidden rounded-[8px] border border-[#dfe6ef] bg-white shadow-sm">
      {loading ? (
        <LoadingState />
      ) : vehicles.length === 0 ? (
        <EmptyState />
      ) : (
        <div className="grid gap-4 p-5 md:grid-cols-2 xl:grid-cols-3">
          {vehicles.map((vehicle) => {
            const assignment =
              activeDeviceAssignment(vehicle);
            const device = assignment?.device ?? null;

            return (
              <article
                key={vehicle.id}
                className="rounded-[7px] border border-[#dfe6ef] p-4 transition hover:border-[#a9c9fb] hover:shadow-sm"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex min-w-0 items-center gap-3">
                    <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
                      <CarFront className="h-5 w-5" />
                    </div>
                    <div className="min-w-0">
                      <h2 className="truncate text-[12px] font-semibold text-[#405779]">
                        {vehicleDisplayName(vehicle)}
                      </h2>
                      <p className="mt-1 text-[9px] text-[#8b9ab4]">
                        {vehicle.vehicleCode}
                      </p>
                    </div>
                  </div>
                  <span className="rounded-full bg-emerald-50 px-2 py-1 text-[8px] font-semibold text-emerald-700">
                    {vehicle.status}
                  </span>
                </div>

                <dl className="mt-4 grid grid-cols-2 gap-3 text-[9px]">
                  <div>
                    <dt className="text-[#8b9ab4]">Type</dt>
                    <dd className="mt-1 font-semibold text-[#52698e]">
                      {vehicleTypeIcon(vehicle)}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-[#8b9ab4]">Registration</dt>
                    <dd className="mt-1 font-semibold text-[#52698e]">
                      {vehicle.registrationNumber ?? "-"}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-[#8b9ab4]">Manufacturer</dt>
                    <dd className="mt-1 font-semibold text-[#52698e]">
                      {vehicle.manufacturer ?? "-"}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-[#8b9ab4]">Model</dt>
                    <dd className="mt-1 font-semibold text-[#52698e]">
                      {vehicle.modelName ?? "-"}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-[#8b9ab4]">Tracker</dt>
                    <dd className="mt-1 font-semibold text-[#52698e]">
                      {device?.deviceCode ?? "Not installed"}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-[#8b9ab4]">Tracking</dt>
                    <dd className="mt-1 font-semibold text-[#7d8ca6]">
                      No live data
                    </dd>
                  </div>
                </dl>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}

function ReportView({
  vehicles,
  loading,
  canViewHistory,
}: {
  vehicles: CustomerVehicleAsset[];
  loading: boolean;
  canViewHistory: boolean;
}) {
  const reportCards = [
    {
      title: "Trip Report",
      description:
        "Journey start, end, distance, and duration.",
      icon: Gauge,
    },
    {
      title: "Stop Report",
      description:
        "Parking and idle periods for scoped vehicles.",
      icon: Clock3,
    },
    {
      title: "Event Report",
      description:
        "Ignition, geofence, SOS, and tracker events.",
      icon: Activity,
    },
    {
      title: "Distance Report",
      description:
        "Daily and period distance summaries.",
      icon: FileBarChart,
    },
  ];

  return (
    <>
      <section className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        {reportCards.map((report) => (
          <article
            key={report.title}
            className="rounded-[7px] border border-[#dfe6ef] bg-white p-4 shadow-sm"
          >
            <report.icon className="h-5 w-5 text-[#357cf4]" />
            <h2 className="mt-3 text-[12px] font-semibold text-[#405779]">
              {report.title}
            </h2>
            <p className="mt-1 text-[9px] leading-5 text-[#7d8ca6]">
              {report.description}
            </p>
            <span className="mt-4 inline-flex rounded-full bg-slate-100 px-2 py-1 text-[8px] font-semibold text-slate-600">
              {canViewHistory
                ? "Waiting for tracking data"
                : "History permission unavailable"}
            </span>
          </article>
        ))}
      </section>

      <section className="mt-4 overflow-hidden rounded-[8px] border border-[#dfe6ef] bg-white shadow-sm">
        <header className="border-b border-[#e2e8f1] px-5 py-4">
          <h2 className="text-[12px] font-semibold text-[#405779]">
            Report Asset Scope
          </h2>
          <p className="mt-1 text-[9px] text-[#8b9ab4]">
            Only these authenticated Customer vehicles can appear in reports.
          </p>
        </header>

        {loading ? (
          <LoadingState />
        ) : vehicles.length === 0 ? (
          <EmptyState />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[940px] text-left text-[10px]">
              <thead className="bg-[#f4f7fb] text-[#52698e]">
                <tr>
                  {[
                    "Vehicle",
                    "Vehicle Code",
                    "Tracker",
                    "IMEI",
                    "Trip Data",
                    "Position History",
                    "Report Status",
                  ].map((heading) => (
                    <th
                      key={heading}
                      className="px-4 py-3 font-semibold"
                    >
                      {heading}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {vehicles.map((vehicle) => {
                  const assignment =
                    activeDeviceAssignment(vehicle);
                  const device = assignment?.device ?? null;

                  return (
                    <tr
                      key={vehicle.id}
                      className="border-t border-[#e2e8f1] text-[#52698e]"
                    >
                      <td className="px-4 py-4 font-semibold text-[#405779]">
                        {vehicleDisplayName(vehicle)}
                      </td>
                      <td className="px-4 py-4 text-[#357cf4]">
                        {vehicle.vehicleCode}
                      </td>
                      <td className="px-4 py-4">
                        {device?.deviceCode ?? "Not installed"}
                      </td>
                      <td className="px-4 py-4">
                        {device?.imei ?? "-"}
                      </td>
                      <td className="px-4 py-4">No data</td>
                      <td className="px-4 py-4">No data</td>
                      <td className="px-4 py-4">
                        <span className="rounded-full bg-slate-100 px-2 py-1 text-[8px] font-semibold text-slate-600">
                          Traccar pending
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}