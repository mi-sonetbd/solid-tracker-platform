"use client";

import {
  Eye,
  EyeOff,
  LoaderCircle,
  ShieldCheck,
  UserRoundPlus,
  X,
} from "lucide-react";
import {
  useMemo,
  useState,
  type FormEvent,
} from "react";
import type {
  CreateDealerManagerInput,
  DealerSummary,
  ManagementApiError,
  ProvisionedDealerStaff,
} from "@/lib/management/dealer-types";

type AddDealerManagerModalProps = {
  dealers: DealerSummary[];
  initialDealerId?: string;
  onClose: () => void;
  onCreated: (
    result: ProvisionedDealerStaff,
    dealer: DealerSummary,
  ) => void;
};

type FormState = {
  dealerId: string;
  fullName: string;
  mobileNumber: string;
  email: string;
  existingUser: boolean;
  password: string;
  confirmPassword: string;
};

export function AddDealerManagerModal({
  dealers,
  initialDealerId,
  onClose,
  onCreated,
}: AddDealerManagerModalProps) {
  const [form, setForm] = useState<FormState>({
    dealerId: initialDealerId ?? dealers[0]?.id ?? "",
    fullName: "",
    mobileNumber: "",
    email: "",
    existingUser: false,
    password: "",
    confirmPassword: "",
  });
  const [passwordVisible, setPasswordVisible] =
    useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const selectedDealer = useMemo(
    () =>
      dealers.find((dealer) => dealer.id === form.dealerId) ??
      null,
    [dealers, form.dealerId],
  );

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

    if (!selectedDealer) {
      setError("Select the Dealer that will own this manager.");
      return;
    }

    const fullName = form.fullName.trim();
    const mobileNumber = form.mobileNumber.trim();
    const email = form.email.trim();

    if (fullName.length < 2) {
      setError("Full name must contain at least 2 characters.");
      return;
    }

    if (mobileNumber.length < 5) {
      setError("Enter a valid mobile number.");
      return;
    }

    if (!form.existingUser) {
      if (form.password.length < 12) {
        setError(
          "Temporary password must contain at least 12 characters.",
        );
        return;
      }

      if (form.password !== form.confirmPassword) {
        setError("Password confirmation does not match.");
        return;
      }
    }

    const input: CreateDealerManagerInput = {
      fullName,
      mobileNumber,
      email: email || undefined,
      password: form.existingUser
        ? undefined
        : form.password,
      roleCode: "DEALER_MANAGER",
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        `/api/management/dealers/${selectedDealer.id}/staff`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const result = (await response.json()) as
        | ProvisionedDealerStaff
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result
            ? result.message
            : "Dealer Manager provisioning failed.",
        );
        return;
      }

      onCreated(
        result as ProvisionedDealerStaff,
        selectedDealer,
      );
    } catch {
      setError(
        "The web panel could not reach the Dealer staff service.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2300] grid place-items-center bg-[#17345f]/48 p-5"
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
        aria-labelledby="add-dealer-manager-title"
        className="flex max-h-[94vh] w-full max-w-[760px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.32)]"
      >
        <header className="flex h-16 shrink-0 items-center justify-between border-b border-[#dfe6ef] px-6">
          <div className="flex items-center gap-3">
            <span className="grid h-10 w-10 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
              <UserRoundPlus className="h-5 w-5" />
            </span>

            <div>
              <h2
                id="add-dealer-manager-title"
                className="text-[17px] font-semibold text-[#344b72]"
              >
                Add Dealer Manager
              </h2>
              <p className="mt-0.5 text-[11px] text-[#7c8ba5]">
                Provision a Dealer-scoped management login.
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close Add Dealer Manager dialog"
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
                Dealer <span className="text-red-500">*</span>
              </span>

              <select
                required
                value={form.dealerId}
                onChange={(event) =>
                  updateField("dealerId", event.target.value)
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              >
                <option value="">Select Dealer</option>
                {dealers.map((dealer) => (
                  <option key={dealer.id} value={dealer.id}>
                    {dealer.name} Â· {dealer.dealerProfile.dealerCode}
                  </option>
                ))}
              </select>
            </label>

            <div className="md:col-span-2 rounded-[5px] border border-[#dbe4f0] bg-[#f7f9fc] p-4">
              <p className="text-[11px] font-semibold text-[#405779]">
                Account mode
              </p>

              <div className="mt-3 grid gap-3 md:grid-cols-2">
                <label
                  className={[
                    "cursor-pointer rounded-[5px] border p-4 transition",
                    !form.existingUser
                      ? "border-[#357cf4] bg-[#edf4ff]"
                      : "border-[#d7e0ec] bg-white",
                  ].join(" ")}
                >
                  <input
                    type="radio"
                    name="accountMode"
                    checked={!form.existingUser}
                    onChange={() =>
                      updateField("existingUser", false)
                    }
                    className="sr-only"
                  />

                  <span className="text-[12px] font-semibold text-[#405779]">
                    Create new login
                  </span>
                  <span className="mt-1 block text-[10px] leading-4 text-[#7c8ba5]">
                    Creates a new user and requires a temporary password.
                  </span>
                </label>

                <label
                  className={[
                    "cursor-pointer rounded-[5px] border p-4 transition",
                    form.existingUser
                      ? "border-[#357cf4] bg-[#edf4ff]"
                      : "border-[#d7e0ec] bg-white",
                  ].join(" ")}
                >
                  <input
                    type="radio"
                    name="accountMode"
                    checked={form.existingUser}
                    onChange={() =>
                      updateField("existingUser", true)
                    }
                    className="sr-only"
                  />

                  <span className="text-[12px] font-semibold text-[#405779]">
                    Attach existing user
                  </span>
                  <span className="mt-1 block text-[10px] leading-4 text-[#7c8ba5]">
                    Uses the account already registered with the mobile number.
                  </span>
                </label>
              </div>
            </div>

            <label className="md:col-span-2">
              <span className="text-[11px] font-semibold text-[#405779]">
                Full name <span className="text-red-500">*</span>
              </span>
              <input
                autoFocus
                required
                minLength={2}
                maxLength={160}
                value={form.fullName}
                onChange={(event) =>
                  updateField("fullName", event.target.value)
                }
                placeholder="Dealer Manager full name"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Login mobile <span className="text-red-500">*</span>
              </span>
              <input
                required
                type="tel"
                maxLength={30}
                value={form.mobileNumber}
                onChange={(event) =>
                  updateField(
                    "mobileNumber",
                    event.target.value,
                  )
                }
                placeholder="+8801XXXXXXXXX"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Email
              </span>
              <input
                type="email"
                maxLength={254}
                value={form.email}
                onChange={(event) =>
                  updateField("email", event.target.value)
                }
                placeholder="manager@example.com"
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
              />
            </label>

            {!form.existingUser ? (
              <>
                <label>
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Temporary password{" "}
                    <span className="text-red-500">*</span>
                  </span>

                  <span className="relative mt-2 block">
                    <input
                      required
                      type={
                        passwordVisible ? "text" : "password"
                      }
                      minLength={12}
                      maxLength={200}
                      autoComplete="new-password"
                      value={form.password}
                      onChange={(event) =>
                        updateField(
                          "password",
                          event.target.value,
                        )
                      }
                      placeholder="Minimum 12 characters"
                      className="h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 pr-10 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
                    />

                    <button
                      type="button"
                      onClick={() =>
                        setPasswordVisible((value) => !value)
                      }
                      aria-label={
                        passwordVisible
                          ? "Hide temporary password"
                          : "Show temporary password"
                      }
                      className="absolute inset-y-0 right-0 grid w-10 place-items-center text-[#71819c]"
                    >
                      {passwordVisible ? (
                        <EyeOff className="h-4 w-4" />
                      ) : (
                        <Eye className="h-4 w-4" />
                      )}
                    </button>
                  </span>
                </label>

                <label>
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Confirm password{" "}
                    <span className="text-red-500">*</span>
                  </span>
                  <input
                    required
                    type={
                      passwordVisible ? "text" : "password"
                    }
                    minLength={12}
                    maxLength={200}
                    autoComplete="new-password"
                    value={form.confirmPassword}
                    onChange={(event) =>
                      updateField(
                        "confirmPassword",
                        event.target.value,
                      )
                    }
                    placeholder="Repeat temporary password"
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none transition focus:border-[#357cf4] focus:ring-2 focus:ring-[#357cf4]/10"
                  />
                </label>
              </>
            ) : null}

            <div className="md:col-span-2 flex items-start gap-3 rounded-[5px] border border-[#cfe0ff] bg-[#edf4ff] px-4 py-3">
              <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
              <p className="text-[10px] leading-5 text-[#52698e]">
                The account receives only the system role{" "}
                <strong>DEALER_MANAGER</strong> within the selected
                Dealer scope. Passwords are sent only to the backend,
                hashed there, and are never returned by the API.
              </p>
            </div>
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
              disabled={submitting || dealers.length === 0}
              className="flex h-9 min-w-[165px] items-center justify-center gap-2 rounded-[3px] bg-[#357cf4] px-6 text-[12px] font-semibold text-white transition hover:bg-[#2766d5] disabled:cursor-not-allowed disabled:opacity-60"
            >
              {submitting ? (
                <>
                  <LoaderCircle className="h-4 w-4 animate-spin" />
                  Provisioning
                </>
              ) : (
                "Create Dealer Manager"
              )}
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}