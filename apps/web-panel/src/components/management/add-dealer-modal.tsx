"use client";

import {
  Building2,
  Check,
  LoaderCircle,
  X,
} from "lucide-react";
import {
  useState,
  type FormEvent,
} from "react";
import type {
  CreateDealerInput,
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";

type AddDealerModalProps = {
  onClose: () => void;
  onCreated: (dealer: DealerSummary) => void;
};

type FormState = {
  name: string;
  legalName: string;
  tradeLicenseNumber: string;
  taxIdentificationNumber: string;
  contactMobile: string;
  contactEmail: string;
  commissionEnabled: boolean;
};

const initialForm: FormState = {
  name: "",
  legalName: "",
  tradeLicenseNumber: "",
  taxIdentificationNumber: "",
  contactMobile: "",
  contactEmail: "",
  commissionEnabled: true,
};

function optionalValue(value: string) {
  const normalized = value.trim();
  return normalized || undefined;
}

export function AddDealerModal({
  onClose,
  onCreated,
}: AddDealerModalProps) {
  const [form, setForm] = useState<FormState>(initialForm);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  function updateField<Key extends keyof FormState>(
    key: Key,
    value: FormState[Key],
  ) {
    setForm((current) => ({
      ...current,
      [key]: value,
    }));
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    const name = form.name.trim();

    if (name.length < 2) {
      setError("Dealer name must contain at least 2 characters.");
      return;
    }

    const input: CreateDealerInput = {
      name,
      legalName: optionalValue(form.legalName),
      tradeLicenseNumber: optionalValue(
        form.tradeLicenseNumber,
      ),
      taxIdentificationNumber: optionalValue(
        form.taxIdentificationNumber,
      ),
      contactMobile: optionalValue(form.contactMobile),
      contactEmail: optionalValue(form.contactEmail),
      commissionEnabled: form.commissionEnabled,
    };

    setSubmitting(true);

    try {
      const response = await fetch("/api/management/dealers", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(input),
      });

      const result = (await response.json()) as
        | DealerSummary
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result
            ? result.message
            : "Dealer creation failed.",
        );
        return;
      }

      onCreated(result as DealerSummary);
    } catch {
      setError(
        "The web panel could not reach the Dealer service.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2100] grid place-items-center bg-[#17345f]/45 p-5"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="add-dealer-title"
        className="flex max-h-[92vh] w-full max-w-[760px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex h-16 shrink-0 items-center justify-between border-b border-[#dfe6ef] px-6">
          <div className="flex items-center gap-3">
            <span className="grid h-10 w-10 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
              <Building2 className="h-5 w-5" />
            </span>
            <div>
              <h2
                id="add-dealer-title"
                className="text-[17px] font-semibold text-[#344b72]"
              >
                Add Dealer
              </h2>
              <p className="mt-0.5 text-[11px] text-[#7c8ba5]">
                Create a platform-managed Dealer organization.
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close Add Dealer dialog"
            className="text-[#71819c] disabled:opacity-50"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form
          onSubmit={submit}
          className="st-scrollbar min-h-0 overflow-y-auto"
        >
          <div className="grid gap-5 p-6 md:grid-cols-2">
            {error ? (
              <div
                role="alert"
                className="md:col-span-2 rounded-[4px] border border-red-200 bg-red-50 px-4 py-3 text-[12px] text-red-700"
              >
                {error}
              </div>
            ) : null}

            <label className="md:col-span-2">
              <span className="text-[11px] font-semibold text-[#405779]">
                Dealer name <span className="text-red-500">*</span>
              </span>
              <input
                autoFocus
                required
                minLength={2}
                maxLength={160}
                value={form.name}
                onChange={(event) =>
                  updateField("name", event.target.value)
                }
                placeholder="Example: Dhaka Central Dealer"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            <label className="md:col-span-2">
              <span className="text-[11px] font-semibold text-[#405779]">
                Legal business name
              </span>
              <input
                maxLength={200}
                value={form.legalName}
                onChange={(event) =>
                  updateField("legalName", event.target.value)
                }
                placeholder="Registered company name"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Contact mobile
              </span>
              <input
                type="tel"
                maxLength={30}
                value={form.contactMobile}
                onChange={(event) =>
                  updateField(
                    "contactMobile",
                    event.target.value,
                  )
                }
                placeholder="01XXXXXXXXX"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Contact email
              </span>
              <input
                type="email"
                maxLength={254}
                value={form.contactEmail}
                onChange={(event) =>
                  updateField(
                    "contactEmail",
                    event.target.value,
                  )
                }
                placeholder="dealer@example.com"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Trade license number
              </span>
              <input
                maxLength={100}
                value={form.tradeLicenseNumber}
                onChange={(event) =>
                  updateField(
                    "tradeLicenseNumber",
                    event.target.value,
                  )
                }
                placeholder="Optional"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Tax identification number
              </span>
              <input
                maxLength={100}
                value={form.taxIdentificationNumber}
                onChange={(event) =>
                  updateField(
                    "taxIdentificationNumber",
                    event.target.value,
                  )
                }
                placeholder="Optional"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            <label className="md:col-span-2 flex cursor-pointer items-center gap-3 rounded-[5px] border border-[#dfe6ef] bg-[#f7f9fc] px-4 py-3">
              <input
                type="checkbox"
                checked={form.commissionEnabled}
                onChange={(event) =>
                  updateField(
                    "commissionEnabled",
                    event.target.checked,
                  )
                }
                className="sr-only"
              />

              <span
                className={[
                  "grid h-5 w-5 place-items-center rounded-[3px] border transition",
                  form.commissionEnabled
                    ? "border-[#357cf4] bg-[#357cf4] text-white"
                    : "border-[#b8c4d6] bg-white text-transparent",
                ].join(" ")}
              >
                <Check className="h-3.5 w-3.5" strokeWidth={3} />
              </span>

              <span>
                <span className="block text-[12px] font-semibold text-[#405779]">
                  Enable dealer commission
                </span>
                <span className="mt-0.5 block text-[10px] text-[#7c8ba5]">
                  Commission calculation remains subject to package and billing configuration.
                </span>
              </span>
            </label>
          </div>

          <footer className="sticky bottom-0 flex h-16 items-center justify-end gap-3 border-t border-[#dfe6ef] bg-white px-6">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-9 rounded-[3px] border border-[#cfd8e7] px-6 text-[12px] font-semibold text-[#52698e] disabled:opacity-50"
            >
              Cancel
            </button>

            <button
              type="submit"
              disabled={submitting}
              className="flex h-9 min-w-[132px] items-center justify-center gap-2 rounded-[3px] bg-[#357cf4] px-6 text-[12px] font-semibold text-white transition hover:bg-[#2766d5] disabled:cursor-not-allowed disabled:opacity-60"
            >
              {submitting ? (
                <>
                  <LoaderCircle className="h-4 w-4 animate-spin" />
                  Creating
                </>
              ) : (
                "Create Dealer"
              )}
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}