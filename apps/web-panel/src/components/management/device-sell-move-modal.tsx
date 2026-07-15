"use client";

import {
  Building2,
  Cpu,
  LoaderCircle,
  MoveRight,
  ShieldCheck,
  UserRound,
  X,
} from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";
import type {
  DeviceSummary,
  TransferDevicesInput,
  TransferDevicesResult,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type {
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";
import { customerDisplayName } from "@/lib/management/monitor-types";

type DeviceSellMoveModalProps = {
  selectedDevices: DeviceSummary[];
  availableDevices: DeviceSummary[];
  dealers: DealerSummary[];
  customers: CustomerSummary[];
  onClose: () => void;
  onCompleted: (
    result: TransferDevicesResult,
  ) => void;
};

function deviceLabel(device: DeviceSummary) {
  return [
    device.deviceCode,
    device.imei ? `IMEI ${device.imei}` : null,
    `${device.deviceModel.manufacturer} ${device.deviceModel.modelName}`,
  ]
    .filter(Boolean)
    .join(" Â· ");
}

export function DeviceSellMoveModal({
  selectedDevices,
  availableDevices,
  dealers,
  customers,
  onClose,
  onCompleted,
}: DeviceSellMoveModalProps) {
  const defaultType =
    customers.length > 0 ? "CUSTOMER" : "DEALER";
  const [targetType, setTargetType] =
    useState<"DEALER" | "CUSTOMER">(defaultType);
  const [targetId, setTargetId] = useState(
    defaultType === "CUSTOMER"
      ? customers[0]?.id ?? ""
      : dealers[0]?.id ?? "",
  );
  const [selectedIds, setSelectedIds] = useState(
    () => new Set(selectedDevices.map((device) => device.id)),
  );
  const [imeiInput, setImeiInput] = useState("");
  const [notes, setNotes] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const devices = useMemo(
    () =>
      availableDevices.filter((device) =>
        selectedIds.has(device.id),
      ),
    [availableDevices, selectedIds],
  );

  const destinations =
    targetType === "CUSTOMER"
      ? customers
      : dealers;

  function removeDevice(deviceId: string) {
    setSelectedIds((current) => {
      const next = new Set(current);
      next.delete(deviceId);
      return next;
    });
  }

  function addByImei() {
    const normalized = imeiInput.trim();

    if (!normalized) return;

    const device = availableDevices.find(
      (item) => item.imei === normalized,
    );

    if (!device) {
      setError(
        "That IMEI is not present in the currently loaded scoped page.",
      );
      return;
    }

    setSelectedIds((current) => {
      const next = new Set(current);
      next.add(device.id);
      return next;
    });
    setImeiInput("");
    setError("");
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (devices.length === 0) {
      setError("Select at least one Device.");
      return;
    }

    const blocked = devices.some(
      (device) =>
        (device.vehicleAssignments?.length ?? 0) > 0 ||
        !["RECEIVED", "IN_STOCK", "ALLOCATED"].includes(
          device.lifecycleStatus,
        ),
    );

    if (blocked) {
      setError(
        "Installed or lifecycle-blocked Devices must be removed or repaired before transfer.",
      );
      return;
    }

    if (!targetId) {
      setError("Select a destination.");
      return;
    }

    const input: TransferDevicesInput = {
      deviceIds: devices.map((device) => device.id),
      targetType,
      targetId,
      notes: notes.trim() || undefined,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        "/api/management/devices/transfer",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const payload = (await response.json()) as
        | TransferDevicesResult
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in payload
            ? payload.message
            : "Device transfer failed.",
        );
        return;
      }

      onCompleted(payload as TransferDevicesResult);
    } catch {
      setError(
        "The web panel could not reach the Device transfer service.",
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
        aria-labelledby="device-sell-move-title"
        className="flex max-h-[94vh] w-full max-w-[980px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <MoveRight className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.12em]">
                Lifecycle Transfer
              </span>
            </div>
            <h2
              id="device-sell-move-title"
              className="mt-2 text-[18px] font-semibold text-[#2b4065]"
            >
              Sell / Move Devices
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              Move selected stock to a permitted Dealer or Customer.
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close Device transfer"
            className="text-[#71819c]"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form
          onSubmit={submit}
          className="st-scrollbar overflow-y-auto p-6"
        >
          <div className="grid gap-6 lg:grid-cols-2">
            <section>
              <h3 className="text-[12px] font-semibold text-[#344b72]">
                Selected Devices ({devices.length})
              </h3>

              <div className="mt-3 flex h-10 overflow-hidden rounded-[4px] border border-[#cfd8e7]">
                <input
                  value={imeiInput}
                  onChange={(event) =>
                    setImeiInput(event.target.value)
                  }
                  className="min-w-0 flex-1 px-3 text-[11px] outline-none"
                  placeholder="Add IMEI from current scoped page"
                />
                <button
                  type="button"
                  onClick={addByImei}
                  className="bg-[#357cf4] px-4 text-[10px] font-semibold text-white"
                >
                  Add
                </button>
              </div>

              <div className="st-scrollbar mt-3 max-h-80 overflow-y-auto rounded-[5px] border border-[#dfe6ef]">
                {devices.map((device) => (
                  <div
                    key={device.id}
                    className="flex items-start gap-3 border-b border-[#eef2f7] px-4 py-3"
                  >
                    <Cpu className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[10px] font-semibold text-[#344b72]">
                        {deviceLabel(device)}
                      </p>
                      <p className="mt-1 text-[9px] text-[#8b9ab4]">
                        {device.lifecycleStatus}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => removeDevice(device.id)}
                      className="text-[10px] font-semibold text-red-600"
                    >
                      Remove
                    </button>
                  </div>
                ))}

                {devices.length === 0 ? (
                  <p className="px-4 py-8 text-center text-[10px] text-[#8b9ab4]">
                    No Device selected.
                  </p>
                ) : null}
              </div>
            </section>

            <section>
              <h3 className="text-[12px] font-semibold text-[#344b72]">
                Destination
              </h3>

              <div className="mt-3 grid gap-4">
                <label className="text-[10px] font-semibold text-[#52698e]">
                  Destination type
                  <select
                    value={targetType}
                    onChange={(event) => {
                      const nextType = event.target.value as
                        | "DEALER"
                        | "CUSTOMER";

                      setTargetType(nextType);
                      setTargetId(
                        nextType === "CUSTOMER"
                          ? customers[0]?.id ?? ""
                          : dealers[0]?.id ?? "",
                      );
                    }}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[11px] outline-none"
                  >
                    <option
                      value="CUSTOMER"
                      disabled={customers.length === 0}
                    >
                      Customer
                    </option>
                    <option
                      value="DEALER"
                      disabled={dealers.length === 0}
                    >
                      Dealer
                    </option>
                  </select>
                </label>

                <label className="text-[10px] font-semibold text-[#52698e]">
                  Destination account
                  <select
                    value={targetId}
                    onChange={(event) =>
                      setTargetId(event.target.value)
                    }
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[11px] outline-none"
                  >
                    <option value="">Select destination</option>
                    {targetType === "CUSTOMER"
                      ? customers.map((customer) => (
                          <option
                            key={customer.id}
                            value={customer.id}
                          >
                            {customerDisplayName(customer)}
                            {customer.managingDealer?.name
                              ? ` Â· ${customer.managingDealer.name}`
                              : " Â· Direct"}
                          </option>
                        ))
                      : dealers.map((dealer) => (
                          <option
                            key={dealer.id}
                            value={dealer.id}
                          >
                            {dealer.name} Â· {dealer.code}
                          </option>
                        ))}
                  </select>
                </label>

                <label className="text-[10px] font-semibold text-[#52698e]">
                  Transfer notes
                  <textarea
                    value={notes}
                    onChange={(event) =>
                      setNotes(event.target.value)
                    }
                    maxLength={1000}
                    rows={5}
                    className="mt-2 w-full rounded-[4px] border border-[#cfd8e7] px-3 py-3 text-[11px] outline-none"
                    placeholder="Sale reference, delivery note, or operational reason"
                  />
                </label>
              </div>

              <div className="mt-5 flex items-start gap-2 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
                <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
                The backend independently validates source scope and destination
                scope, blocks installed Devices, closes active ownership,
                custody, and Dealer allocation rows, creates new history, and
                records a Device transfer audit event.
              </div>

              <div className="mt-4 grid grid-cols-2 gap-3 text-[10px]">
                <div className="rounded-[4px] border border-[#e2e8f1] p-3">
                  <Building2 className="h-4 w-4 text-[#ff9b24]" />
                  <p className="mt-2 font-semibold text-[#344b72]">
                    Dealer destination
                  </p>
                  <p className="mt-1 leading-5 text-[#71819c]">
                    Creates Dealer ownership, custody, and available stock.
                  </p>
                </div>
                <div className="rounded-[4px] border border-[#e2e8f1] p-3">
                  <UserRound className="h-4 w-4 text-[#29a8ef]" />
                  <p className="mt-2 font-semibold text-[#344b72]">
                    Customer destination
                  </p>
                  <p className="mt-1 leading-5 text-[#71819c]">
                    Creates Customer ownership and custody before installation.
                  </p>
                </div>
              </div>
            </section>
          </div>

          {error ? (
            <p className="mt-5 rounded-[4px] bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
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
                submitting ||
                devices.length === 0 ||
                destinations.length === 0 ||
                !targetId
              }
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <MoveRight className="h-4 w-4" />
              )}
              Confirm Sell / Move
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}