"use client";

import {
  Cpu,
  LoaderCircle,
  RadioTower,
  ShieldCheck,
  X,
} from "lucide-react";
import { useState, type FormEvent } from "react";
import type {
  CreateDeviceModelInput,
  DeviceModelSummary,
  DeviceNetworkType,
} from "@/lib/management/asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type AddDeviceModelModalProps = {
  onClose: () => void;
  onCreated: (model: DeviceModelSummary) => void;
};

const networkTypes: Array<{
  value: DeviceNetworkType;
  label: string;
}> = [
  { value: "GSM_2G", label: "GSM 2G" },
  { value: "UMTS_3G", label: "UMTS 3G" },
  { value: "LTE_4G", label: "LTE 4G" },
  { value: "LTE_5G", label: "LTE 5G" },
  { value: "LORA", label: "LoRa" },
  { value: "SATELLITE", label: "Satellite" },
  { value: "OTHER", label: "Other" },
];

export function AddDeviceModelModal({
  onClose,
  onCreated,
}: AddDeviceModelModalProps) {
  const [manufacturer, setManufacturer] = useState("");
  const [modelName, setModelName] = useState("");
  const [protocol, setProtocol] = useState("osmand");
  const [networkType, setNetworkType] =
    useState<DeviceNetworkType>("GSM_2G");
  const [ignition, setIgnition] = useState(true);
  const [relay, setRelay] = useState(true);
  const [sos, setSos] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (manufacturer.trim().length < 2) {
      setError("Manufacturer must contain at least 2 characters.");
      return;
    }

    if (modelName.trim().length < 2) {
      setError("Model name must contain at least 2 characters.");
      return;
    }

    if (!protocol.trim()) {
      setError("Protocol is required.");
      return;
    }

    const input: CreateDeviceModelInput = {
      manufacturer: manufacturer.trim(),
      modelName: modelName.trim(),
      protocol: protocol.trim(),
      networkType,
      capabilities: {
        ignition,
        relay,
        sos,
      },
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        "/api/management/device-models",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const result = (await response.json()) as
        | DeviceModelSummary
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result
            ? result.message
            : "Device Model creation failed.",
        );
        return;
      }

      onCreated(result as DeviceModelSummary);
    } catch {
      setError(
        "The web panel could not reach the Device Model service.",
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
        aria-labelledby="add-device-model-title"
        className="flex max-h-[94vh] w-full max-w-[720px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <Cpu className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.16em]">
                Platform Catalog
              </span>
            </div>
            <h2
              id="add-device-model-title"
              className="mt-2 text-[18px] font-semibold text-[#344b72]"
            >
              Add Device Model
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              Define the tracker model before receiving physical inventory.
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
          <div className="grid gap-4 md:grid-cols-2">
            <label className="text-[11px] font-semibold text-[#52698e]">
              Manufacturer
              <input
                autoFocus
                required
                minLength={2}
                maxLength={120}
                value={manufacturer}
                onChange={(event) =>
                  setManufacturer(event.target.value)
                }
                placeholder="Concox"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Model name
              <input
                required
                minLength={2}
                maxLength={160}
                value={modelName}
                onChange={(event) =>
                  setModelName(event.target.value)
                }
                placeholder="GT06N"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Traccar protocol
              <input
                required
                minLength={1}
                maxLength={100}
                value={protocol}
                onChange={(event) =>
                  setProtocol(event.target.value)
                }
                placeholder="gt06"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="text-[11px] font-semibold text-[#52698e]">
              Network type
              <select
                value={networkType}
                onChange={(event) =>
                  setNetworkType(
                    event.target.value as DeviceNetworkType,
                  )
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[12px] outline-none focus:border-[#357cf4]"
              >
                {networkTypes.map((item) => (
                  <option key={item.value} value={item.value}>
                    {item.label}
                  </option>
                ))}
              </select>
            </label>
          </div>

          <div className="mt-5">
            <p className="text-[11px] font-semibold text-[#52698e]">
              Supported wiring and features
            </p>

            <div className="mt-3 grid gap-3 md:grid-cols-3">
              {[
                {
                  label: "Ignition",
                  checked: ignition,
                  setter: setIgnition,
                },
                {
                  label: "Relay",
                  checked: relay,
                  setter: setRelay,
                },
                {
                  label: "SOS",
                  checked: sos,
                  setter: setSos,
                },
              ].map((item) => (
                <label
                  key={item.label}
                  className="flex items-center gap-3 rounded-[5px] border border-[#dfe6ef] p-3 text-[11px] font-semibold text-[#52698e]"
                >
                  <input
                    type="checkbox"
                    checked={item.checked}
                    onChange={(event) =>
                      item.setter(event.target.checked)
                    }
                  />
                  {item.label}
                </label>
              ))}
            </div>
          </div>

          <div className="mt-5 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
            <div className="flex items-center gap-2 font-semibold text-[#344b72]">
              <ShieldCheck className="h-4 w-4 text-[#357cf4]" />
              Platform-only catalog
            </div>
            <p className="mt-1">
              Device Models are global Platform records. Duplicate
              manufacturer and model combinations are rejected by the
              backend.
            </p>
          </div>

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
              disabled={submitting}
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <RadioTower className="h-4 w-4" />
              )}
              Create Model
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}