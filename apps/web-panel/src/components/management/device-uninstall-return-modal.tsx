"use client";

import {
  Building2,
  CircleAlert,
  Cpu,
  LoaderCircle,
  RotateCcw,
  ShieldCheck,
  Unlink,
  X,
} from "lucide-react";
import { useState, type FormEvent } from "react";
import type {
  DeviceAssignmentEndReason,
  DeviceRemovalReason,
  DeviceSummary,
  RemoveDeviceInput,
} from "@/lib/management/asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

export type DeviceLifecycleActionResult = {
  message: string;
  warning?: string;
};

type DeviceUninstallReturnModalProps = {
  device: DeviceSummary;
  onClose: () => void;
  onCompleted: (
    result: DeviceLifecycleActionResult,
  ) => void;
};

const assignmentEndReasons: Array<{
  value: DeviceAssignmentEndReason;
  label: string;
}> = [
  {
    value: "CUSTOMER_REQUEST",
    label: "Customer request",
  },
  {
    value: "DEVICE_FAILURE",
    label: "Device failure",
  },
  {
    value: "DEVICE_REPLACEMENT",
    label: "Device replacement",
  },
  {
    value: "VEHICLE_TRANSFER",
    label: "Vehicle transfer",
  },
  {
    value: "VEHICLE_SOLD",
    label: "Vehicle sold",
  },
  {
    value: "SUBSCRIPTION_CANCELLED",
    label: "Subscription cancelled",
  },
  {
    value: "TRANSFER_TO_ANOTHER_VEHICLE",
    label: "Transfer to another vehicle",
  },
  {
    value: "LOST",
    label: "Device lost",
  },
  {
    value: "OTHER",
    label: "Other",
  },
];

const removalReasons: Array<{
  value: DeviceRemovalReason;
  label: string;
}> = [
  {
    value: "CUSTOMER_REQUEST",
    label: "Customer request",
  },
  {
    value: "VEHICLE_SOLD",
    label: "Vehicle sold",
  },
  {
    value: "DEVICE_FAILURE",
    label: "Device failure",
  },
  {
    value: "WARRANTY_REPLACEMENT",
    label: "Warranty replacement",
  },
  {
    value: "SUBSCRIPTION_CANCELLED",
    label: "Subscription cancelled",
  },
  {
    value: "TRANSFER_TO_ANOTHER_VEHICLE",
    label: "Transfer to another vehicle",
  },
  {
    value: "LOST",
    label: "Device lost",
  },
  {
    value: "OTHER",
    label: "Other",
  },
];

function activeAssignment(device: DeviceSummary) {
  return (
    device.vehicleAssignments?.find(
      (assignment) => assignment.status === "ACTIVE",
    ) ??
    device.vehicleAssignments?.[0] ??
    null
  );
}

function activeAllocation(device: DeviceSummary) {
  return (
    device.dealerAllocations?.find((allocation) =>
      ["ALLOCATED", "AVAILABLE", "INSTALLED"].includes(
        allocation.status,
      ),
    ) ??
    device.dealerAllocations?.[0] ??
    null
  );
}

function responseMessage(
  payload: unknown,
  fallback: string,
) {
  if (
    payload &&
    typeof payload === "object" &&
    "message" in payload
  ) {
    const value = (payload as ManagementApiError).message;

    if (typeof value === "string" && value.trim()) {
      return value;
    }
  }

  return fallback;
}

async function readPayload(response: Response) {
  return response.json().catch(() => null) as Promise<unknown>;
}

export function DeviceUninstallReturnModal({
  device,
  onClose,
  onCompleted,
}: DeviceUninstallReturnModalProps) {
  const assignment = activeAssignment(device);
  const allocation = activeAllocation(device);
  const installed =
    device.lifecycleStatus === "INSTALLED" ||
    Boolean(assignment);
  const returnOnly = !installed && Boolean(allocation);
  const vehicle = assignment?.vehicle;

  const [assignmentEndReason, setAssignmentEndReason] =
    useState<DeviceAssignmentEndReason>("CUSTOMER_REQUEST");
  const [removalReason, setRemovalReason] =
    useState<DeviceRemovalReason>("CUSTOMER_REQUEST");
  const [returnAfterRemoval, setReturnAfterRemoval] =
    useState(false);
  const [notes, setNotes] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  async function returnToPlatform() {
    const response = await fetch(
      `/api/management/devices/${device.id}/return`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          notes: notes.trim() || undefined,
        }),
      },
    );
    const payload = await readPayload(response);

    if (!response.ok) {
      throw new Error(
        responseMessage(
          payload,
          "The Device could not be returned to Platform stock.",
        ),
      );
    }
  }

  async function submit(
    event: FormEvent<HTMLFormElement>,
  ) {
    event.preventDefault();
    setError("");
    setSubmitting(true);

    try {
      if (returnOnly) {
        await returnToPlatform();

        onCompleted({
          message:
            `${device.deviceCode} was returned to Solid Tracker Platform stock.`,
        });
        return;
      }

      if (!installed) {
        throw new Error(
          "This Device is neither installed nor eligible for a Dealer-to-Platform return.",
        );
      }

      const removeInput: RemoveDeviceInput = {
        assignmentEndReason,
        removalReason,
        notes: notes.trim() || undefined,
      };
      const removeResponse = await fetch(
        `/api/management/devices/${device.id}/remove`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(removeInput),
        },
      );
      const removePayload = await readPayload(removeResponse);

      if (!removeResponse.ok) {
        throw new Error(
          responseMessage(
            removePayload,
            "The installed Device could not be uninstalled.",
          ),
        );
      }

      if (returnAfterRemoval && allocation) {
        try {
          await returnToPlatform();
        } catch (returnError) {
          onCompleted({
            message:
              `${device.deviceCode} was uninstalled and restored to Dealer stock.`,
            warning:
              returnError instanceof Error
                ? `Automatic Platform return failed: ${returnError.message}`
                : "Automatic Platform return failed.",
          });
          return;
        }

        onCompleted({
          message:
            `${device.deviceCode} was uninstalled and returned to Platform stock.`,
        });
        return;
      }

      onCompleted({
        message: allocation
          ? `${device.deviceCode} was uninstalled and restored to Dealer stock.`
          : `${device.deviceCode} was uninstalled and restored to Platform stock.`,
      });
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "The Device lifecycle action failed.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[90] grid place-items-center bg-[#07101d]/75 p-4 backdrop-blur-[1px]"
      role="dialog"
      aria-modal="true"
      aria-labelledby="device-uninstall-return-title"
    >
      <section className="max-h-[94vh] w-full max-w-[920px] overflow-auto rounded-[4px] border border-[#343e4d] bg-[#171b20] text-[#d7deea] shadow-2xl">
        <header className="flex items-center justify-between border-b border-[#303846] px-6 py-4">
          <div>
            <p className="text-[9px] font-semibold uppercase tracking-[0.16em] text-[#74829a]">
              Device lifecycle
            </p>
            <h2
              id="device-uninstall-return-title"
              className="mt-1 text-[15px] font-semibold text-white"
            >
              {returnOnly
                ? "Return Device to Platform"
                : "Uninstall / Return Device"}
            </h2>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            className="grid h-9 w-9 place-items-center rounded-[3px] text-[#8e9aae] hover:bg-white/5 hover:text-white disabled:opacity-50"
            aria-label="Close uninstall and return modal"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form onSubmit={submit} className="p-6">
          <div className="grid gap-5 lg:grid-cols-[0.9fr_1.1fr]">
            <section className="rounded-[4px] border border-[#303846] bg-[#12161b] p-5">
              <div className="flex items-center gap-3">
                <div className="grid h-10 w-10 place-items-center rounded-full bg-[#0e5fe5]/15 text-[#2f83ff]">
                  <Cpu className="h-5 w-5" />
                </div>
                <div className="min-w-0">
                  <p className="truncate text-[13px] font-semibold text-white">
                    {device.deviceCode}
                  </p>
                  <p className="mt-1 truncate text-[10px] text-[#8491a6]">
                    IMEI {device.imei || "-"}
                  </p>
                </div>
              </div>

              <dl className="mt-5 space-y-3 text-[10px]">
                <div className="flex justify-between gap-4 border-b border-[#252d38] pb-3">
                  <dt className="text-[#74829a]">Device Model</dt>
                  <dd className="text-right font-medium text-[#d7deea]">
                    {device.deviceModel.manufacturer}{" "}
                    {device.deviceModel.modelName}
                  </dd>
                </div>

                <div className="flex justify-between gap-4 border-b border-[#252d38] pb-3">
                  <dt className="text-[#74829a]">Lifecycle</dt>
                  <dd className="text-right font-medium text-[#d7deea]">
                    {device.lifecycleStatus.replaceAll("_", " ")}
                  </dd>
                </div>

                <div className="flex justify-between gap-4 border-b border-[#252d38] pb-3">
                  <dt className="text-[#74829a]">Vehicle</dt>
                  <dd className="text-right font-medium text-[#d7deea]">
                    {vehicle
                      ? vehicle.registrationNumber ||
                        vehicle.vehicleCode
                      : "-"}
                  </dd>
                </div>

                <div className="flex justify-between gap-4">
                  <dt className="text-[#74829a]">Dealer custody</dt>
                  <dd className="text-right font-medium text-[#d7deea]">
                    {allocation?.dealerOrganization.name ||
                      "No active Dealer allocation"}
                  </dd>
                </div>
              </dl>

              <div className="mt-5 flex items-start gap-2 rounded-[3px] border border-[#203b61] bg-[#0e2038] p-4 text-[9px] leading-5 text-[#9fc4f6]">
                <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#2f83ff]" />
                The backend closes active assignment and installation history
                before restoring valid custody. A Dealer return is rejected
                until the Device has been uninstalled.
              </div>
            </section>

            <section className="rounded-[4px] border border-[#303846] bg-[#12161b] p-5">
              {installed ? (
                <div className="grid gap-4 sm:grid-cols-2">
                  <label className="text-[10px] font-semibold text-[#aeb9c9]">
                    Assignment end reason
                    <select
                      value={assignmentEndReason}
                      onChange={(event) =>
                        setAssignmentEndReason(
                          event.target
                            .value as DeviceAssignmentEndReason,
                        )
                      }
                      disabled={submitting}
                      className="mt-2 h-10 w-full rounded-[3px] border border-[#3b4554] bg-[#1a2028] px-3 text-[11px] text-white outline-none focus:border-[#2f83ff]"
                    >
                      {assignmentEndReasons.map((reason) => (
                        <option
                          key={reason.value}
                          value={reason.value}
                        >
                          {reason.label}
                        </option>
                      ))}
                    </select>
                  </label>

                  <label className="text-[10px] font-semibold text-[#aeb9c9]">
                    Removal reason
                    <select
                      value={removalReason}
                      onChange={(event) =>
                        setRemovalReason(
                          event.target
                            .value as DeviceRemovalReason,
                        )
                      }
                      disabled={submitting}
                      className="mt-2 h-10 w-full rounded-[3px] border border-[#3b4554] bg-[#1a2028] px-3 text-[11px] text-white outline-none focus:border-[#2f83ff]"
                    >
                      {removalReasons.map((reason) => (
                        <option
                          key={reason.value}
                          value={reason.value}
                        >
                          {reason.label}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>
              ) : (
                <div className="flex items-start gap-3 rounded-[3px] border border-[#5b421b] bg-[#2b2113] p-4">
                  <Building2 className="mt-0.5 h-5 w-5 shrink-0 text-[#ffad42]" />
                  <div>
                    <p className="text-[11px] font-semibold text-[#ffd18d]">
                      Dealer inventory return
                    </p>
                    <p className="mt-1 text-[9px] leading-5 text-[#c3aa84]">
                      This Device has no active vehicle assignment. Confirming
                      will close its Dealer allocation and restore Platform
                      custody.
                    </p>
                  </div>
                </div>
              )}

              <label className="mt-4 block text-[10px] font-semibold text-[#aeb9c9]">
                Operational notes
                <textarea
                  rows={5}
                  maxLength={installed ? 2000 : 1000}
                  value={notes}
                  onChange={(event) =>
                    setNotes(event.target.value)
                  }
                  disabled={submitting}
                  placeholder="Removal condition, technician note, return reference, or other audit detail"
                  className="mt-2 w-full resize-y rounded-[3px] border border-[#3b4554] bg-[#1a2028] px-3 py-3 text-[11px] text-white outline-none placeholder:text-[#667287] focus:border-[#2f83ff]"
                />
                <span className="mt-1 block text-right text-[8px] font-normal text-[#667287]">
                  {notes.length} / {installed ? 2000 : 1000}
                </span>
              </label>

              {installed && allocation ? (
                <label className="mt-4 flex cursor-pointer items-start gap-3 rounded-[3px] border border-[#303846] bg-[#181e26] p-4">
                  <input
                    type="checkbox"
                    checked={returnAfterRemoval}
                    onChange={(event) =>
                      setReturnAfterRemoval(
                        event.target.checked,
                      )
                    }
                    disabled={submitting}
                    className="mt-0.5 h-4 w-4 accent-[#2f83ff]"
                  />
                  <span>
                    <span className="flex items-center gap-2 text-[10px] font-semibold text-white">
                      <RotateCcw className="h-4 w-4 text-[#2f83ff]" />
                      Return to Platform after uninstall
                    </span>
                    <span className="mt-1 block text-[9px] leading-5 text-[#8491a6]">
                      Runs the required two-step operation: first uninstall,
                      then close Dealer allocation and restore Platform stock.
                    </span>
                  </span>
                </label>
              ) : null}

              {!installed && !returnOnly ? (
                <div className="mt-4 flex items-start gap-2 rounded-[3px] border border-red-900/70 bg-red-950/30 p-4 text-[9px] leading-5 text-red-300">
                  <CircleAlert className="mt-0.5 h-4 w-4 shrink-0" />
                  This Device has no active installation or returnable Dealer
                  allocation.
                </div>
              ) : null}

              {error ? (
                <p className="mt-4 rounded-[3px] border border-red-900/70 bg-red-950/40 px-4 py-3 text-[10px] font-medium text-red-300">
                  {error}
                </p>
              ) : null}
            </section>
          </div>

          <footer className="mt-6 flex justify-end gap-3 border-t border-[#303846] pt-5">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-10 rounded-[3px] border border-[#495365] px-6 text-[11px] font-semibold text-[#c7cfdb] hover:bg-white/5 disabled:opacity-50"
            >
              Cancel
            </button>

            <button
              type="submit"
              disabled={
                submitting ||
                (!installed && !returnOnly)
              }
              className="flex h-10 items-center gap-2 rounded-[3px] bg-[#075ee8] px-7 text-[11px] font-semibold text-white hover:bg-[#0a67f4] disabled:bg-[#3a465a] disabled:text-[#7f8ba0]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : returnOnly ? (
                <RotateCcw className="h-4 w-4" />
              ) : (
                <Unlink className="h-4 w-4" />
              )}
              {submitting
                ? "Processing..."
                : returnOnly
                  ? "Confirm Return"
                  : returnAfterRemoval
                    ? "Uninstall and Return"
                    : "Confirm Uninstall"}
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}