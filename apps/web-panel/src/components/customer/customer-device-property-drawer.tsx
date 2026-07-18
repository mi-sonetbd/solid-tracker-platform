"use client";

import {
  Activity,
  Battery,
  CarFront,
  Clock3,
  Cpu,
  Gauge,
  MapPin,
  Navigation,
  RadioTower,
  Send,
  Settings2,
  Share2,
  Signal,
  Thermometer,
  Wifi,
  WifiOff,
  X,
} from "lucide-react";
import {
  activeDeviceAssignment,
  deviceDisplayName,
  formatAssetDate,
  titleCase,
  type CustomerVehicleAsset,
} from "@/lib/customer/customer-asset-types";
import type { TrackingLivePosition } from "@/lib/tracking/live-position-types";

type CustomerDevicePropertyDrawerProps = {
  vehicle: CustomerVehicleAsset;
  livePosition?: TrackingLivePosition | null;
  liveLoading?: boolean;
  liveError?: string;
  onClose: () => void;
};

function DetailRow({
  label,
  value,
  icon: Icon,
}: {
  label: string;
  value: string;
  icon?: typeof Cpu;
}) {
  return (
    <div className="flex items-center justify-between gap-4">
      <dt className="flex items-center gap-2 text-[#71819c]">
        {Icon ? (
          <Icon className="h-3.5 w-3.5" />
        ) : null}
        {label}
      </dt>
      <dd className="text-right font-semibold text-[#405779]">
        {value}
      </dd>
    </div>
  );
}

function formatTrackingDate(value?: string | null) {
  if (!value) return "-";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "-" : date.toLocaleString("en-GB");
}

export function CustomerDevicePropertyDrawer({
  vehicle,
  livePosition = null,
  liveLoading = false,
  liveError = "",
  onClose,
}: CustomerDevicePropertyDrawerProps) {
  const assignment = activeDeviceAssignment(vehicle);
  const device = assignment?.device ?? null;
  const hasPosition = Boolean(livePosition);
  const coordinates = livePosition
    ? `${livePosition.latitude.toFixed(6)}, ${livePosition.longitude.toFixed(6)}`
    : "-";
  const satellites = livePosition?.attributes?.sat ??
    livePosition?.attributes?.satellites ?? "-";

  return (
    <aside className="absolute bottom-0 right-0 top-0 z-[1200] w-[350px] overflow-y-auto border-l border-[#dfe6ef] bg-[#f8fafc] shadow-[-8px_0_24px_rgba(39,64,105,0.14)]">
      <header className="sticky top-0 z-10 flex items-start justify-between border-b border-[#e2e8f1] bg-white px-4 py-3">
        <div className="min-w-0">
          <h2 className="truncate text-[14px] font-semibold text-[#405779]">
            {deviceDisplayName(vehicle)}
          </h2>
          <p className="mt-1 truncate text-[10px] text-[#8b9ab4]">
            {device?.imei ||
              device?.deviceCode ||
              "No tracker installed"}
          </p>
        </div>

        <button
          type="button"
          onClick={onClose}
          aria-label="Close device properties"
          className="grid h-8 w-8 place-items-center rounded-[3px] text-[#52698e] hover:bg-[#edf4ff]"
        >
          <X className="h-4 w-4" />
        </button>
      </header>

      <div className="space-y-2.5 p-3">
        <section className="rounded-[6px] border border-[#dfe6ef] bg-white p-4">
          <div className="flex items-center justify-between gap-3">
            <span className="flex min-w-0 items-center gap-2 text-[12px] font-semibold text-[#405779]">
              <span
                className={[
                  "grid h-5 w-5 shrink-0 place-items-center rounded-full text-white",
                  hasPosition ? "bg-[#30b56a]" : "bg-[#ff3152]",
                ].join(" ")}
              >
                {hasPosition ? <Wifi className="h-3 w-3" /> : <WifiOff className="h-3 w-3" />}
              </span>
              <span className="truncate">
                {hasPosition ? "Live position received" : "No live position yet"}
              </span>
            </span>

            <span className="shrink-0 text-[10px] font-semibold text-[#52698e]">
              {hasPosition ? "Online" : liveLoading ? "Loading" : liveError ? "Unavailable" : "Tracking pending"}
            </span>
          </div>
        </section>

        <section className="rounded-[6px] border border-[#dfe6ef] bg-white p-4">
          <h3 className="text-[12px] font-semibold text-[#405779]">
            Address
          </h3>

          <p className="mt-3 text-[11px] font-semibold leading-5 text-[#405779]">
            {livePosition?.address || (hasPosition ? "Latest Traccar position" : "No live location has been received for this installed tracker.")}
          </p>

          <div className="mt-4 flex items-center justify-between">
            <span className="text-[10px] text-[#71819c]">
              Coordinates
            </span>
            <span className="text-[10px] font-semibold text-[#405779]">
              {coordinates}
            </span>
          </div>
        </section>

        <section className="rounded-[6px] border border-[#dfe6ef] bg-white p-4">
          <h3 className="text-[12px] font-semibold text-[#405779]">
            Device
          </h3>

          <dl className="mt-4 space-y-3 text-[10px]">
            <DetailRow
              icon={RadioTower}
              label="GNSS"
              value={hasPosition ? "Fixed" : "-"}
            />
            <DetailRow
              icon={Signal}
              label="Visible satellites"
              value={String(satellites)}
            />
            <DetailRow
              label="Cellular signal strength"
              value="-"
            />
            <DetailRow
              icon={Clock3}
              label="Last online"
              value={formatTrackingDate(livePosition?.serverTime)}
            />
            <DetailRow
              icon={MapPin}
              label="Last fix"
              value={formatTrackingDate(livePosition?.fixTime)}
            />
          </dl>
        </section>

        <section className="rounded-[6px] border border-[#dfe6ef] bg-white p-4">
          <h3 className="text-[12px] font-semibold text-[#405779]">
            Solid Tracker Asset
          </h3>

          <dl className="mt-4 space-y-3 text-[10px]">
            <DetailRow
              icon={CarFront}
              label="Vehicle"
              value={
                vehicle.registrationNumber ||
                vehicle.vehicleCode
              }
            />
            <DetailRow
              icon={Cpu}
              label="Model"
              value={
                device
                  ? `${device.deviceModel.manufacturer} ${device.deviceModel.modelName}`
                  : "-"
              }
            />
            <DetailRow
              label="Lifecycle"
              value={
                device
                  ? titleCase(
                      device.lifecycleStatus,
                    )
                  : "Not installed"
              }
            />
            <DetailRow
              label="Assigned"
              value={formatAssetDate(
                assignment?.startedAt,
              )}
            />
          </dl>
        </section>

        <section className="rounded-[6px] border border-[#dfe6ef] bg-white p-4">
          <h3 className="text-[12px] font-semibold text-[#405779]">
            Today&apos;s Activity
          </h3>

          <dl className="mt-4 space-y-3 text-[10px]">
            <DetailRow
              icon={Gauge}
              label="Today's mileage"
              value="-"
            />
            <DetailRow
              icon={Battery}
              label="Vehicle battery voltage"
              value="-"
            />
          </dl>
        </section>

        <section className="grid grid-cols-2 divide-x divide-[#e2e8f1] rounded-[6px] border border-[#dfe6ef] bg-white py-4 text-center">
          <div>
            <Thermometer className="mx-auto h-6 w-6 text-[#357cf4]" />
            <p className="mt-2 text-[10px] font-semibold text-[#405779]">
              N/A
            </p>
          </div>
          <div>
            <Activity className="mx-auto h-6 w-6 text-[#357cf4]" />
            <p className="mt-2 text-[10px] font-semibold text-[#405779]">
              N/A
            </p>
          </div>
        </section>

        <div className="grid grid-cols-6 gap-1 border-t border-[#e2e8f1] pt-3 text-center text-[8px] text-[#52698e]">
          {[
            { label: "Live", icon: MapPin },
            { label: "Tracks", icon: Navigation },
            { label: "Device", icon: Cpu },
            { label: "Command", icon: Send },
            { label: "Configure", icon: Settings2 },
            { label: "Share", icon: Share2 },
          ].map((item) => (
            <button
              key={item.label}
              type="button"
              disabled
              title={`${item.label} will be connected in a dedicated stage`}
              className="rounded-[4px] py-2"
            >
              <item.icon className="mx-auto h-4 w-4 text-[#357cf4]" />
              <p className="mt-1">{item.label}</p>
            </button>
          ))}
        </div>

        <button
          type="button"
          disabled
          title="Dashboard settings will be connected later"
          className="mx-auto block h-8 rounded-[4px] bg-[#357cf4] px-5 text-[10px] font-semibold text-white"
        >
          Dashboard setting
        </button>
      </div>
    </aside>
  );
}