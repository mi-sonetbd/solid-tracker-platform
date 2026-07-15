"use client";

import {
  Activity,
  Battery,
  CarFront,
  Clock3,
  Cpu,
  MapPin,
  Navigation,
  RadioTower,
  Signal,
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

type CustomerDevicePropertyDrawerProps = {
  vehicle: CustomerVehicleAsset;
  onClose: () => void;
};

export function CustomerDevicePropertyDrawer({
  vehicle,
  onClose,
}: CustomerDevicePropertyDrawerProps) {
  const assignment = activeDeviceAssignment(vehicle);
  const device = assignment?.device ?? null;

  return (
    <aside className="absolute bottom-0 right-0 top-0 z-[1200] w-[370px] overflow-y-auto border-l border-[#dfe6ef] bg-white shadow-[-8px_0_24px_rgba(39,64,105,0.14)]">
      <header className="sticky top-0 z-10 flex items-start justify-between border-b border-[#e2e8f1] bg-white px-5 py-4">
        <div className="min-w-0">
          <h2 className="truncate text-[15px] font-semibold text-[#405779]">
            {deviceDisplayName(vehicle)}
          </h2>
          <p className="mt-1 text-[11px] text-[#8b9ab4]">
            {device?.imei || "No IMEI"}
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

      <div className="space-y-3 p-4">
        <section className="rounded-[6px] border border-[#dfe6ef] p-4">
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-[13px] font-semibold text-[#405779]">
              <WifiOff className="h-4 w-4 text-[#ff5575]" />
              No live position yet
            </span>
            <span className="text-[11px] font-semibold text-[#52698e]">
              Tracking pending
            </span>
          </div>
        </section>

        <section className="rounded-[6px] border border-[#dfe6ef] p-4">
          <h3 className="text-[13px] font-semibold text-[#405779]">
            Position
          </h3>

          <div className="mt-4 space-y-4 text-[11px]">
            <div>
              <p className="text-[#71819c]">Address</p>
              <p className="mt-1 font-semibold leading-5 text-[#405779]">
                No live position has been received from Traccar.
              </p>
            </div>

            <div className="flex items-center justify-between">
              <span className="text-[#71819c]">
                Coordinates
              </span>
              <span className="font-semibold text-[#405779]">
                -
              </span>
            </div>
          </div>
        </section>

        <section className="rounded-[6px] border border-[#dfe6ef] p-4">
          <h3 className="text-[13px] font-semibold text-[#405779]">
            Device
          </h3>

          <dl className="mt-4 space-y-3 text-[11px]">
            <div className="flex items-center justify-between gap-4">
              <dt className="flex items-center gap-2 text-[#71819c]">
                <RadioTower className="h-3.5 w-3.5" />
                GNSS
              </dt>
              <dd className="font-semibold text-[#405779]">-</dd>
            </div>
            <div className="flex items-center justify-between gap-4">
              <dt className="flex items-center gap-2 text-[#71819c]">
                <Signal className="h-3.5 w-3.5" />
                Cellular signal
              </dt>
              <dd className="font-semibold text-[#405779]">-</dd>
            </div>
            <div className="flex items-center justify-between gap-4">
              <dt className="flex items-center gap-2 text-[#71819c]">
                <Clock3 className="h-3.5 w-3.5" />
                Last online
              </dt>
              <dd className="font-semibold text-[#405779]">-</dd>
            </div>
            <div className="flex items-center justify-between gap-4">
              <dt className="flex items-center gap-2 text-[#71819c]">
                <MapPin className="h-3.5 w-3.5" />
                Last fix
              </dt>
              <dd className="font-semibold text-[#405779]">-</dd>
            </div>
          </dl>
        </section>

        <section className="rounded-[6px] border border-[#dfe6ef] p-4">
          <h3 className="text-[13px] font-semibold text-[#405779]">
            Solid Tracker Asset
          </h3>

          <dl className="mt-4 space-y-3 text-[11px]">
            <div className="flex items-center justify-between gap-4">
              <dt className="flex items-center gap-2 text-[#71819c]">
                <CarFront className="h-3.5 w-3.5" />
                Vehicle
              </dt>
              <dd className="text-right font-semibold text-[#405779]">
                {vehicle.registrationNumber ||
                  vehicle.vehicleCode}
              </dd>
            </div>
            <div className="flex items-center justify-between gap-4">
              <dt className="flex items-center gap-2 text-[#71819c]">
                <Cpu className="h-3.5 w-3.5" />
                Model
              </dt>
              <dd className="text-right font-semibold text-[#405779]">
                {device
                  ? `${device.deviceModel.manufacturer} ${device.deviceModel.modelName}`
                  : "-"}
              </dd>
            </div>
            <div className="flex items-center justify-between gap-4">
              <dt className="text-[#71819c]">Lifecycle</dt>
              <dd className="font-semibold text-[#405779]">
                {device
                  ? titleCase(device.lifecycleStatus)
                  : "Not installed"}
              </dd>
            </div>
            <div className="flex items-center justify-between gap-4">
              <dt className="text-[#71819c]">Assigned</dt>
              <dd className="text-right font-semibold text-[#405779]">
                {formatAssetDate(assignment?.startedAt)}
              </dd>
            </div>
          </dl>
        </section>

        <section className="rounded-[6px] border border-[#dfe6ef] p-4">
          <h3 className="text-[13px] font-semibold text-[#405779]">
            Today&apos;s Activity
          </h3>

          <div className="mt-4 grid grid-cols-2 gap-3">
            <div className="rounded-[5px] bg-[#f6f8fb] p-3 text-center">
              <Activity className="mx-auto h-5 w-5 text-[#357cf4]" />
              <p className="mt-2 text-[10px] text-[#71819c]">
                Mileage
              </p>
              <p className="mt-1 text-[12px] font-semibold text-[#405779]">
                No data
              </p>
            </div>
            <div className="rounded-[5px] bg-[#f6f8fb] p-3 text-center">
              <Battery className="mx-auto h-5 w-5 text-[#357cf4]" />
              <p className="mt-2 text-[10px] text-[#71819c]">
                Battery
              </p>
              <p className="mt-1 text-[12px] font-semibold text-[#405779]">
                No data
              </p>
            </div>
          </div>
        </section>

        <div className="grid grid-cols-4 gap-2 border-t border-[#e2e8f1] pt-4 text-center text-[9px] text-[#52698e]">
          {[
            { label: "Live", icon: MapPin },
            { label: "Tracks", icon: Navigation },
            { label: "Device", icon: Cpu },
            { label: "Activity", icon: Activity },
          ].map((item) => (
            <div key={item.label}>
              <item.icon className="mx-auto h-4 w-4 text-[#357cf4]" />
              <p className="mt-1">{item.label}</p>
            </div>
          ))}
        </div>
      </div>
    </aside>
  );
}