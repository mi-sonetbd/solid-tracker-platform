"use client";

import {
  Cpu,
  LoaderCircle,
  RefreshCw,
  ShieldCheck,
  X,
} from "lucide-react";
import {
  useEffect,
  useMemo,
  useState,
  type FormEvent,
} from "react";
import type {
  DeviceInstallationResult,
  DeviceListResponse,
  DeviceSummary,
  InstallDeviceInput,
  VehicleSummary,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type InstallCustomerDeviceModalProps = {
  customer: CustomerSummary;
  vehicle: VehicleSummary;
  canViewDevices: boolean;
  onClose: () => void;
  onInstalled: (result: DeviceInstallationResult) => void;
};

function customerName(customer: CustomerSummary) {
  return (
    customer.individualProfile?.fullName ??
    customer.organizationProfile?.displayName ??
    customer.customerCode
  );
}

function deviceLabel(device: DeviceSummary) {
  return [
    device.deviceCode,
    device.imei ? `IMEI ${device.imei}` : null,
    `${device.deviceModel.manufacturer} ${device.deviceModel.modelName}`,
  ]
    .filter(Boolean)
    .join(" Â· ");
}

function optionalNumber(value: string) {
  if (!value.trim()) return undefined;
  return Number(value);
}

export function InstallCustomerDeviceModal({
  customer,
  vehicle,
  canViewDevices,
  onClose,
  onInstalled,
}: InstallCustomerDeviceModalProps) {
  const [devices, setDevices] = useState<DeviceSummary[]>([]);
  const [selectedDeviceId, setSelectedDeviceId] = useState("");
  const [loading, setLoading] = useState(canViewDevices);
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [latitude, setLatitude] = useState("");
  const [longitude, setLongitude] = useState("");
  const [odometerReading, setOdometerReading] = useState("");
  const [powerConnectionType, setPowerConnectionType] =
    useState("BATTERY_DIRECT");
  const [ignitionConnected, setIgnitionConnected] = useState(true);
  const [relayConnected, setRelayConnected] = useState(false);
  const [sosConnected, setSosConnected] = useState(false);
  const [notes, setNotes] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!canViewDevices) return;

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: "1",
      pageSize: "100",
      lifecycleStatus: customer.managingDealerId
        ? "ALLOCATED"
        : "IN_STOCK",
    });

    if (customer.managingDealerId) {
      parameters.set(
        "dealerOrganizationId",
        customer.managingDealerId,
      );
    }

    fetch(`/api/management/devices?${parameters.toString()}`, {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | DeviceListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Available tracker loading failed.",
          );
        }

        return payload as DeviceListResponse;
      })
      .then((payload) => {
        const available = payload.items.filter(
          (device) => (device.vehicleAssignments?.length ?? 0) === 0,
        );
        setDevices(available);
        setSelectedDeviceId((current) =>
          available.some((device) => device.id === current)
            ? current
            : (available[0]?.id ?? ""),
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

        setDevices([]);
        setSelectedDeviceId("");
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Available tracker loading failed.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [
    canViewDevices,
    customer.managingDealerId,
    refreshVersion,
  ]);

  const selectedDevice = useMemo(
    () => devices.find((device) => device.id === selectedDeviceId) ?? null,
    [devices, selectedDeviceId],
  );

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (!selectedDeviceId) {
      setError("Select an available tracker.");
      return;
    }

    const parsedLatitude = optionalNumber(latitude);
    const parsedLongitude = optionalNumber(longitude);
    const parsedOdometer = optionalNumber(odometerReading);

    if (
      parsedLatitude !== undefined &&
      (!Number.isFinite(parsedLatitude) ||
        parsedLatitude < -90 ||
        parsedLatitude > 90)
    ) {
      setError("Latitude must be between -90 and 90.");
      return;
    }

    if (
      parsedLongitude !== undefined &&
      (!Number.isFinite(parsedLongitude) ||
        parsedLongitude < -180 ||
        parsedLongitude > 180)
    ) {
      setError("Longitude must be between -180 and 180.");
      return;
    }

    if (
      parsedOdometer !== undefined &&
      (!Number.isFinite(parsedOdometer) || parsedOdometer < 0)
    ) {
      setError("Odometer reading cannot be negative.");
      return;
    }

    const input: InstallDeviceInput = {
      vehicleId: vehicle.id,
      latitude: parsedLatitude,
      longitude: parsedLongitude,
      odometerReading: parsedOdometer,
      powerConnectionType: powerConnectionType.trim() || undefined,
      ignitionConnected,
      relayConnected,
      sosConnected,
      installationNotes: notes.trim() || undefined,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        `/api/management/devices/${selectedDeviceId}/install`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const result = (await response.json()) as
        | DeviceInstallationResult
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result
            ? result.message
            : "Tracker installation failed.",
        );
        return;
      }

      onInstalled(result as DeviceInstallationResult);
    } catch {
      setError("The web panel could not reach the installation service.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2700] grid place-items-center bg-[#17345f]/52 p-5"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !submitting) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="install-tracker-title"
        className="flex max-h-[94vh] w-full max-w-[820px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <Cpu className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.16em]">
                Tracker Installation
              </span>
            </div>
            <h2
              id="install-tracker-title"
              className="mt-2 text-[18px] font-semibold text-[#344b72]"
            >
              Install Primary Tracker
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              {customerName(customer)} Â·{" "}
              {vehicle.registrationNumber || vehicle.vehicleCode}
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            className="grid h-9 w-9 place-items-center rounded-full text-[#71819c] hover:bg-[#f2f6fb]"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form
          onSubmit={submit}
          className="st-scrollbar overflow-y-auto px-6 py-5"
        >
          <div className="flex items-end gap-3">
            <label className="min-w-0 flex-1 text-[11px] font-semibold text-[#52698e]">
              Available tracker
              <select
                value={selectedDeviceId}
                onChange={(event) =>
                  setSelectedDeviceId(event.target.value)
                }
                disabled={loading || devices.length === 0}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[12px] outline-none focus:border-[#357cf4]"
              >
                {devices.length === 0 ? (
                  <option value="">No installable tracker available</option>
                ) : null}
                {devices.map((device) => (
                  <option key={device.id} value={device.id}>
                    {deviceLabel(device)}
                  </option>
                ))}
              </select>
            </label>

            <button
              type="button"
              onClick={() => {
                setLoading(true);
                setRefreshVersion((value) => value + 1);
              }}
              disabled={loading}
              className="grid h-10 w-10 place-items-center rounded-[4px] border border-[#cfd8e7] text-[#357cf4]"
              title="Refresh available tracker stock"
            >
              <RefreshCw
                className={["h-4 w-4", loading ? "animate-spin" : ""].join(
                  " ",
                )}
              />
            </button>
          </div>

          {selectedDevice ? (
            <div className="mt-4 grid gap-3 rounded-[5px] border border-[#dbe7f7] bg-[#f7faff] p-4 text-[10px] text-[#52698e] md:grid-cols-3">
              <div>
                <p className="font-semibold text-[#344b72]">Device</p>
                <p className="mt-1">{selectedDevice.deviceCode}</p>
              </div>
              <div>
                <p className="font-semibold text-[#344b72]">IMEI</p>
                <p className="mt-1">{selectedDevice.imei || "-"}</p>
              </div>
              <div>
                <p className="font-semibold text-[#344b72]">Stock scope</p>
                <p className="mt-1">
                  {customer.managingDealerId
                    ? selectedDevice.dealerAllocations?.[0]
                        ?.dealerOrganization.name ?? "Selected Dealer"
                    : "Solid Tracker Platform"}
                </p>
              </div>
            </div>
          ) : null}

          <div className="mt-5 grid gap-4 md:grid-cols-3">
            <label className="text-[11px] font-semibold text-[#52698e]">
              Latitude
              <input
                type="number"
                step="any"
                value={latitude}
                onChange={(event) => setLatitude(event.target.value)}
                placeholder="23.8103"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Longitude
              <input
                type="number"
                step="any"
                value={longitude}
                onChange={(event) => setLongitude(event.target.value)}
                placeholder="90.4125"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Odometer
              <input
                type="number"
                min={0}
                step="0.01"
                value={odometerReading}
                onChange={(event) =>
                  setOdometerReading(event.target.value)
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>
          </div>

          <label className="mt-4 block text-[11px] font-semibold text-[#52698e]">
            Power connection
            <select
              value={powerConnectionType}
              onChange={(event) =>
                setPowerConnectionType(event.target.value)
              }
              className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[12px] outline-none focus:border-[#357cf4]"
            >
              <option value="BATTERY_DIRECT">Battery direct</option>
              <option value="IGNITION_LINE">Ignition line</option>
              <option value="OBD">OBD</option>
              <option value="OTHER">Other</option>
            </select>
          </label>

          <div className="mt-4 grid gap-3 md:grid-cols-3">
            {[
              {
                label: "Ignition connected",
                checked: ignitionConnected,
                setter: setIgnitionConnected,
              },
              {
                label: "Relay connected",
                checked: relayConnected,
                setter: setRelayConnected,
              },
              {
                label: "SOS connected",
                checked: sosConnected,
                setter: setSosConnected,
              },
            ].map((item) => (
              <label
                key={item.label}
                className="flex items-center gap-3 rounded-[5px] border border-[#dfe6ef] p-3 text-[11px] font-semibold text-[#52698e]"
              >
                <input
                  type="checkbox"
                  checked={item.checked}
                  onChange={(event) => item.setter(event.target.checked)}
                />
                {item.label}
              </label>
            ))}
          </div>

          <label className="mt-4 block text-[11px] font-semibold text-[#52698e]">
            Installation notes
            <textarea
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              maxLength={2000}
              rows={3}
              className="mt-2 w-full rounded-[4px] border border-[#cfd8e7] px-3 py-2 text-[12px] outline-none focus:border-[#357cf4]"
            />
          </label>

          <div className="mt-5 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
            <div className="flex items-center gap-2 font-semibold text-[#344b72]">
              <ShieldCheck className="h-4 w-4 text-[#357cf4]" />
              Authoritative stock and scope checks
            </div>
            <p className="mt-1">
              Direct Customers use unallocated Platform stock. Dealer-managed
              Customers use stock allocated to the same Dealer. The backend
              rejects mismatched custody, installed devices, and vehicles that
              already have an active primary tracker.
            </p>
          </div>

          {!loading && devices.length === 0 ? (
            <p className="mt-4 rounded-[4px] bg-amber-50 px-4 py-3 text-[11px] font-medium text-amber-800">
              No installable tracker is available in this Customer&apos;s
              stock scope. Register Platform inventory or allocate inventory
              to the managing Dealer from Device Management first.
            </p>
          ) : null}

          {error ? (
            <p className="mt-4 rounded-[4px] bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
              {error}
            </p>
          ) : null}

          <footer className="mt-6 flex justify-end gap-3 border-t border-[#e2e8f1] pt-5">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-10 rounded-[4px] border border-[#cfd8e7] px-5 text-[11px] font-semibold text-[#52698e]"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting || loading || devices.length === 0}
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <Cpu className="h-4 w-4" />
              )}
              Install Tracker
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}