"use client";

import {
  Boxes,
  LoaderCircle,
  PackageCheck,
  ShieldCheck,
  X,
} from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";
import type {
  DeviceModelSummary,
  DeviceSummary,
  RegisterDeviceInput,
} from "@/lib/management/asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type DeviceStockIntakeModalProps = {
  models: DeviceModelSummary[];
  onClose: () => void;
  onCreated: (device: DeviceSummary) => void;
  onCreateModel: () => void;
};

function currentLocalDateTime() {
  const date = new Date();
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset)
    .toISOString()
    .slice(0, 16);
}

export function DeviceStockIntakeModal({
  models,
  onClose,
  onCreated,
  onCreateModel,
}: DeviceStockIntakeModalProps) {
  const activeModels = useMemo(
    () =>
      models.filter(
        (model) =>
          !model.status || model.status === "ACTIVE",
      ),
    [models],
  );
  const [deviceModelId, setDeviceModelId] = useState(
    activeModels[0]?.id ?? "",
  );
  const [imei, setImei] = useState("");
  const [serialNumber, setSerialNumber] = useState("");
  const [hardwareVersion, setHardwareVersion] = useState("");
  const [firmwareVersion, setFirmwareVersion] = useState("");
  const [receivedAt, setReceivedAt] = useState(
    currentLocalDateTime(),
  );
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (!deviceModelId) {
      setError("Create or select an active Device Model first.");
      return;
    }

    if (imei && !/^\d{14,17}$/.test(imei.trim())) {
      setError("IMEI must contain 14 to 17 digits.");
      return;
    }

    if (!imei.trim() && !serialNumber.trim()) {
      setError(
        "Enter at least one identity: IMEI or serial number.",
      );
      return;
    }

    const input: RegisterDeviceInput = {
      deviceModelId,
      imei: imei.trim() || undefined,
      serialNumber: serialNumber.trim() || undefined,
      hardwareVersion: hardwareVersion.trim() || undefined,
      firmwareVersion: firmwareVersion.trim() || undefined,
      receivedAt: receivedAt || undefined,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        "/api/management/devices",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const result = (await response.json()) as
        | DeviceSummary
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result
            ? result.message
            : "Device stock intake failed.",
        );
        return;
      }

      onCreated(result as DeviceSummary);
    } catch {
      setError(
        "The web panel could not reach the Device Inventory service.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2600] grid place-items-center bg-[#17345f]/48 p-5"
      role="presentation"
      onMouseDown={(event) => {
        if (
          event.target === event.currentTarget &&
          !submitting
        ) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="device-stock-intake-title"
        className="flex max-h-[94vh] w-full max-w-[760px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <Boxes className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.16em]">
                Platform Inventory
              </span>
            </div>
            <h2
              id="device-stock-intake-title"
              className="mt-2 text-[18px] font-semibold text-[#344b72]"
            >
              Add Device / Stock Intake
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              Receive one physical tracker into Solid Tracker Platform stock.
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

        <form onSubmit={submit} className="st-scrollbar overflow-y-auto p-6">
          {activeModels.length === 0 ? (
            <div className="rounded-[5px] border border-amber-200 bg-amber-50 p-4">
              <p className="text-[11px] font-semibold text-amber-800">
                No active Device Model exists.
              </p>
              <p className="mt-1 text-[10px] leading-5 text-amber-700">
                A physical device cannot enter inventory until its model
                and protocol are defined.
              </p>
              <button
                type="button"
                onClick={onCreateModel}
                className="mt-3 h-9 rounded-[4px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white"
              >
                Create Device Model
              </button>
            </div>
          ) : (
            <>
              <label className="block text-[11px] font-semibold text-[#52698e]">
                Device Model
                <select
                  required
                  value={deviceModelId}
                  onChange={(event) =>
                    setDeviceModelId(event.target.value)
                  }
                  className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[12px] outline-none focus:border-[#357cf4]"
                >
                  {activeModels.map((model) => (
                    <option key={model.id} value={model.id}>
                      {model.manufacturer} {model.modelName} Â·{" "}
                      {model.protocol} Â· {model.modelCode}
                    </option>
                  ))}
                </select>
              </label>

              <div className="mt-4 grid gap-4 md:grid-cols-2">
                <label className="text-[11px] font-semibold text-[#52698e]">
                  IMEI
                  <input
                    inputMode="numeric"
                    pattern="\d{14,17}"
                    maxLength={17}
                    value={imei}
                    onChange={(event) =>
                      setImei(
                        event.target.value.replace(/\D/g, ""),
                      )
                    }
                    placeholder="15-digit IMEI"
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label className="text-[11px] font-semibold text-[#52698e]">
                  Serial number
                  <input
                    maxLength={100}
                    value={serialNumber}
                    onChange={(event) =>
                      setSerialNumber(event.target.value)
                    }
                    placeholder="Manufacturer serial"
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label className="text-[11px] font-semibold text-[#52698e]">
                  Hardware version
                  <input
                    maxLength={60}
                    value={hardwareVersion}
                    onChange={(event) =>
                      setHardwareVersion(event.target.value)
                    }
                    placeholder="V1.0"
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label className="text-[11px] font-semibold text-[#52698e]">
                  Firmware version
                  <input
                    maxLength={60}
                    value={firmwareVersion}
                    onChange={(event) =>
                      setFirmwareVersion(event.target.value)
                    }
                    placeholder="1.2.3"
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label className="md:col-span-2 text-[11px] font-semibold text-[#52698e]">
                  Received date and time
                  <input
                    type="datetime-local"
                    value={receivedAt}
                    onChange={(event) =>
                      setReceivedAt(event.target.value)
                    }
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>
              </div>

              <div className="mt-5 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
                <div className="flex items-center gap-2 font-semibold text-[#344b72]">
                  <ShieldCheck className="h-4 w-4 text-[#357cf4]" />
                  Inventory identity and custody
                </div>
                <p className="mt-1">
                  IMEI and serial number are checked for duplicates. A
                  successful intake creates Platform ownership, Platform
                  custody, an audit entry, and lifecycle status IN_STOCK.
                </p>
              </div>
            </>
          )}

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
              disabled={
                submitting || activeModels.length === 0
              }
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <PackageCheck className="h-4 w-4" />
              )}
              Receive into Stock
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}