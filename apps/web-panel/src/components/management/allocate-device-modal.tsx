"use client";

import {
  Building2,
  LoaderCircle,
  PackageOpen,
  ShieldCheck,
  X,
} from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import type {
  AllocateDeviceInput,
  DealerDeviceAllocationResult,
  DeviceSummary,
} from "@/lib/management/asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type DealerOption = {
  id: string;
  code: string;
  name: string;
  status?: string;
};

type DealerListPayload = {
  items: DealerOption[];
};

type AllocateDeviceModalProps = {
  device: DeviceSummary;
  onClose: () => void;
  onAllocated: (
    allocation: DealerDeviceAllocationResult,
  ) => void;
};

export function AllocateDeviceModal({
  device,
  onClose,
  onAllocated,
}: AllocateDeviceModalProps) {
  const [dealers, setDealers] = useState<DealerOption[]>([]);
  const [dealerOrganizationId, setDealerOrganizationId] =
    useState("");
  const [notes, setNotes] = useState("");
  const [loadingDealers, setLoadingDealers] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const controller = new AbortController();

    fetch("/api/management/dealers?page=1&pageSize=100", {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | DealerListPayload
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Dealer loading failed.",
          );
        }

        return payload as DealerListPayload;
      })
      .then((payload) => {
        const active = payload.items.filter(
          (dealer) =>
            !dealer.status || dealer.status === "ACTIVE",
        );
        setDealers(active);
        setDealerOrganizationId(active[0]?.id ?? "");
      })
      .catch((requestError: unknown) => {
        if (
          requestError instanceof DOMException &&
          requestError.name === "AbortError"
        ) {
          return;
        }

        setError(
          requestError instanceof Error
            ? requestError.message
            : "Dealer loading failed.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoadingDealers(false);
        }
      });

    return () => controller.abort();
  }, []);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (!dealerOrganizationId) {
      setError("Select an active Dealer.");
      return;
    }

    const input: AllocateDeviceInput = {
      dealerOrganizationId,
      notes: notes.trim() || undefined,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        `/api/management/devices/${device.id}/allocate`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const result = (await response.json()) as
        | DealerDeviceAllocationResult
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result
            ? result.message
            : "Dealer allocation failed.",
        );
        return;
      }

      onAllocated(
        result as DealerDeviceAllocationResult,
      );
    } catch {
      setError(
        "The web panel could not reach the Device Allocation service.",
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
        aria-labelledby="allocate-device-title"
        className="flex max-h-[94vh] w-full max-w-[680px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <PackageOpen className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.16em]">
                Dealer Stock
              </span>
            </div>
            <h2
              id="allocate-device-title"
              className="mt-2 text-[18px] font-semibold text-[#344b72]"
            >
              Allocate Device to Dealer
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              {device.deviceCode} Â· IMEI {device.imei || "-"}
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
          <label className="block text-[11px] font-semibold text-[#52698e]">
            Active Dealer
            <select
              required
              value={dealerOrganizationId}
              onChange={(event) =>
                setDealerOrganizationId(event.target.value)
              }
              disabled={
                loadingDealers || dealers.length === 0
              }
              className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[12px] outline-none focus:border-[#357cf4]"
            >
              {dealers.length === 0 ? (
                <option value="">No active Dealer available</option>
              ) : null}
              {dealers.map((dealer) => (
                <option key={dealer.id} value={dealer.id}>
                  {dealer.name} Â· {dealer.code}
                </option>
              ))}
            </select>
          </label>

          <label className="mt-4 block text-[11px] font-semibold text-[#52698e]">
            Allocation notes
            <textarea
              rows={4}
              maxLength={1000}
              value={notes}
              onChange={(event) =>
                setNotes(event.target.value)
              }
              placeholder="Delivery reference, batch, condition, or custody note"
              className="mt-2 w-full rounded-[4px] border border-[#cfd8e7] px-3 py-2 text-[12px] outline-none focus:border-[#357cf4]"
            />
          </label>

          <div className="mt-5 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
            <div className="flex items-center gap-2 font-semibold text-[#344b72]">
              <ShieldCheck className="h-4 w-4 text-[#357cf4]" />
              Custody transfer
            </div>
            <p className="mt-1">
              Allocation transfers custody to the selected Dealer,
              changes lifecycle status to ALLOCATED, and preserves
              Platform ownership history. Installed or already allocated
              devices are rejected.
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
              disabled={
                submitting ||
                loadingDealers ||
                dealers.length === 0
              }
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <Building2 className="h-4 w-4" />
              )}
              Allocate to Dealer
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}