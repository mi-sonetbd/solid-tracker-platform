"use client";

import {
  CheckCircle2,
  CircleAlert,
  LoaderCircle,
  PackagePlus,
  ShieldCheck,
  X,
} from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";
import type {
  BulkDeviceRegistrationResult,
  BulkRegisterDevicesInput,
  DeviceModelSummary,
} from "@/lib/management/asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type BulkDeviceStockIntakeModalProps = {
  models: DeviceModelSummary[];
  onClose: () => void;
  onCompleted: (
    result: BulkDeviceRegistrationResult,
  ) => void;
};

function currentLocalDateTime() {
  const date = new Date();
  const offset = date.getTimezoneOffset() * 60_000;

  return new Date(date.getTime() - offset)
    .toISOString()
    .slice(0, 16);
}

export function BulkDeviceStockIntakeModal({
  models,
  onClose,
  onCompleted,
}: BulkDeviceStockIntakeModalProps) {
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
  const [imeiText, setImeiText] = useState("");
  const [hardwareVersion, setHardwareVersion] =
    useState("");
  const [firmwareVersion, setFirmwareVersion] =
    useState("");
  const [receivedAt, setReceivedAt] = useState(
    currentLocalDateTime(),
  );
  const [result, setResult] =
    useState<BulkDeviceRegistrationResult | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const enteredLines = imeiText.split(/\r?\n/);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setResult(null);

    if (!deviceModelId) {
      setError("Create or select an active Device Model first.");
      return;
    }

    if (!enteredLines.some((line) => line.trim())) {
      setError("Enter at least one IMEI.");
      return;
    }

    if (enteredLines.length > 250) {
      setError("A maximum of 250 IMEI lines is allowed per batch.");
      return;
    }

    const input: BulkRegisterDevicesInput = {
      deviceModelId,
      imeis: enteredLines,
      hardwareVersion: hardwareVersion.trim() || undefined,
      firmwareVersion: firmwareVersion.trim() || undefined,
      receivedAt: receivedAt || undefined,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        "/api/management/devices/bulk",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const payload = (await response.json()) as
        | BulkDeviceRegistrationResult
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in payload
            ? payload.message
            : "Bulk Device intake failed.",
        );
        return;
      }

      const completed =
        payload as BulkDeviceRegistrationResult;

      setResult(completed);
      onCompleted(completed);
    } catch {
      setError(
        "The web panel could not reach the bulk Device intake service.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2700] grid place-items-center bg-[#17345f]/50 p-5"
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
        aria-labelledby="bulk-device-intake-title"
        className="flex max-h-[94vh] w-full max-w-[880px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <PackagePlus className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.12em]">
                Platform Stock
              </span>
            </div>
            <h2
              id="bulk-device-intake-title"
              className="mt-2 text-[18px] font-semibold text-[#2b4065]"
            >
              Bulk Import Devices
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              Select one model and enter one IMEI per line.
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close bulk Device intake"
            className="text-[#71819c]"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form
          onSubmit={submit}
          className="st-scrollbar overflow-y-auto p-6"
        >
          <div className="grid gap-4 md:grid-cols-2">
            <label className="text-[10px] font-semibold text-[#52698e]">
              Device Model
              <select
                value={deviceModelId}
                onChange={(event) =>
                  setDeviceModelId(event.target.value)
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[11px] outline-none"
              >
                <option value="">Select Device Model</option>
                {activeModels.map((model) => (
                  <option key={model.id} value={model.id}>
                    {model.manufacturer} {model.modelName} Â· {model.protocol}
                  </option>
                ))}
              </select>
            </label>

            <label className="text-[10px] font-semibold text-[#52698e]">
              Received date and time
              <input
                type="datetime-local"
                value={receivedAt}
                onChange={(event) =>
                  setReceivedAt(event.target.value)
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[11px] outline-none"
              />
            </label>

            <label className="text-[10px] font-semibold text-[#52698e]">
              Hardware version
              <input
                value={hardwareVersion}
                onChange={(event) =>
                  setHardwareVersion(event.target.value)
                }
                maxLength={60}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[11px] outline-none"
                placeholder="Optional shared hardware version"
              />
            </label>

            <label className="text-[10px] font-semibold text-[#52698e]">
              Firmware version
              <input
                value={firmwareVersion}
                onChange={(event) =>
                  setFirmwareVersion(event.target.value)
                }
                maxLength={60}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[11px] outline-none"
                placeholder="Optional shared firmware version"
              />
            </label>
          </div>

          <label className="mt-5 block text-[10px] font-semibold text-[#52698e]">
            IMEI list
            <textarea
              value={imeiText}
              onChange={(event) =>
                setImeiText(event.target.value)
              }
              rows={11}
              className="mt-2 w-full rounded-[4px] border border-[#cfd8e7] px-3 py-3 font-mono text-[11px] leading-6 outline-none"
              placeholder={"867123456789012\n867123456789013\n867123456789014"}
            />
          </label>

          <div className="mt-3 flex items-center justify-between text-[10px] text-[#71819c]">
            <span>{enteredLines.length} line(s)</span>
            <span>14â€“17 digits per valid IMEI Â· maximum 250</span>
          </div>

          <div className="mt-5 flex items-start gap-2 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
            <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
            The backend normalizes whitespace, reports malformed and duplicate
            lines independently, rejects existing IMEIs through the database
            uniqueness contract, and records an audit entry for every created
            Device.
          </div>

          {error ? (
            <p className="mt-4 rounded-[4px] bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
              {error}
            </p>
          ) : null}

          {result ? (
            <section className="mt-5 rounded-[5px] border border-[#dfe6ef]">
              <header className="flex items-center justify-between border-b border-[#e2e8f1] px-4 py-3 text-[11px] font-semibold text-[#344b72]">
                <span>
                  Created {result.created} Â· Failed {result.failed}
                </span>
                <span>Total {result.total}</span>
              </header>
              <div className="st-scrollbar max-h-56 overflow-y-auto">
                {result.results.map((line, index) => (
                  <div
                    key={`${line.imei}-${index}`}
                    className="flex items-start gap-3 border-b border-[#eef2f7] px-4 py-2 text-[10px]"
                  >
                    {line.status === "CREATED" ? (
                      <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
                    ) : (
                      <CircleAlert className="mt-0.5 h-4 w-4 shrink-0 text-red-600" />
                    )}
                    <span className="w-36 shrink-0 font-mono text-[#344b72]">
                      {line.imei || "(blank)"}
                    </span>
                    <span className="text-[#71819c]">
                      {line.status === "CREATED"
                        ? line.device?.deviceCode ?? "Created"
                        : line.message ?? "Rejected"}
                    </span>
                  </div>
                ))}
              </div>
            </section>
          ) : null}

          <footer className="mt-6 flex justify-end gap-3 border-t border-[#e2e8f1] pt-5">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-10 rounded-[4px] border border-[#cfd8e7] px-5 text-[11px] font-semibold text-[#52698e]"
            >
              Close
            </button>
            <button
              type="submit"
              disabled={
                submitting ||
                activeModels.length === 0
              }
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <PackagePlus className="h-4 w-4" />
              )}
              Import Devices
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}