"use client";

import {
  Eye,
  EyeOff,
  KeyRound,
  LoaderCircle,
  RefreshCw,
  ShieldCheck,
  X,
} from "lucide-react";
import { useState, type FormEvent } from "react";
import type {
  CreateCustomerOwnerInput,
  CustomerSummary,
  ProvisionedCustomerMember,
} from "@/lib/management/customer-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type AddCustomerOwnerModalProps = {
  customer: CustomerSummary;
  onClose: () => void;
  onCreated: (member: ProvisionedCustomerMember) => void;
};

function customerName(customer: CustomerSummary) {
  return (
    customer.individualProfile?.fullName ??
    customer.organizationProfile?.displayName ??
    customer.customerCode
  );
}

function generatedPassword() {
  const random = new Uint32Array(3);
  crypto.getRandomValues(random);

  return `Solid${random[0].toString(36)}A${random[1]
    .toString(36)
    .toUpperCase()}9${random[2].toString(36)}`;
}

export function AddCustomerOwnerModal({
  customer,
  onClose,
  onCreated,
}: AddCustomerOwnerModalProps) {
  const [existingUser, setExistingUser] = useState(false);
  const [fullName, setFullName] = useState(customerName(customer));
  const [mobileNumber, setMobileNumber] = useState(
    customer.primaryMobile ?? "",
  );
  const [email, setEmail] = useState(customer.primaryEmail ?? "");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  function generate() {
    const value = generatedPassword();
    setPassword(value);
    setConfirmPassword(value);
    setPasswordVisible(true);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (fullName.trim().length < 2) {
      setError("Owner full name must contain at least 2 characters.");
      return;
    }

    if (mobileNumber.trim().length < 5) {
      setError("Enter a valid owner mobile number.");
      return;
    }

    if (!existingUser) {
      if (
        password.length < 12 ||
        !/[a-z]/.test(password) ||
        !/[A-Z]/.test(password) ||
        !/\d/.test(password)
      ) {
        setError(
          "Password must contain at least 12 characters, uppercase, lowercase, and a number.",
        );
        return;
      }

      if (password !== confirmPassword) {
        setError("Password confirmation does not match.");
        return;
      }
    }

    const input: CreateCustomerOwnerInput = {
      fullName: fullName.trim(),
      mobileNumber: mobileNumber.trim(),
      email: email.trim() || undefined,
      password: existingUser ? undefined : password,
      roleCode: "CUSTOMER_OWNER",
      isPrimary: true,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        `/api/management/customers/${customer.id}/members`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const result = (await response.json()) as
        ProvisionedCustomerMember | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result
            ? result.message
            : "Customer Owner provisioning failed.",
        );
        return;
      }

      onCreated(result as ProvisionedCustomerMember);
    } catch {
      setError("The web panel could not reach the Customer member service.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2400] grid place-items-center bg-[#17345f]/48 p-5"
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
        aria-labelledby="customer-owner-title"
        className="flex max-h-[94vh] w-full max-w-[700px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.32)]"
      >
        <header className="flex h-16 shrink-0 items-center justify-between border-b border-[#dfe6ef] px-6">
          <div className="flex items-center gap-3">
            <span className="grid h-10 w-10 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
              <KeyRound className="h-5 w-5" />
            </span>

            <div>
              <h2
                id="customer-owner-title"
                className="text-[17px] font-semibold text-[#344b72]"
              >
                Provision Customer Owner
              </h2>
              <p className="mt-0.5 text-[11px] text-[#7c8ba5]">
                {customerName(customer)} Â· {customer.customerCode}
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close Customer Owner dialog"
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

            <div className="md:col-span-2 grid gap-3 md:grid-cols-2">
              <button
                type="button"
                onClick={() => setExistingUser(false)}
                className={[
                  "rounded-[5px] border p-4 text-left transition",
                  !existingUser
                    ? "border-[#357cf4] bg-[#edf4ff]"
                    : "border-[#d7e0ec] bg-white",
                ].join(" ")}
              >
                <span className="block text-[12px] font-semibold text-[#405779]">
                  Create new login
                </span>
                <span className="mt-1 block text-[10px] leading-4 text-[#7c8ba5]">
                  Creates a new Customer Owner identity with a temporary
                  password.
                </span>
              </button>

              <button
                type="button"
                onClick={() => setExistingUser(true)}
                className={[
                  "rounded-[5px] border p-4 text-left transition",
                  existingUser
                    ? "border-[#357cf4] bg-[#edf4ff]"
                    : "border-[#d7e0ec] bg-white",
                ].join(" ")}
              >
                <span className="block text-[12px] font-semibold text-[#405779]">
                  Attach existing user
                </span>
                <span className="mt-1 block text-[10px] leading-4 text-[#7c8ba5]">
                  Attaches the existing Solid Tracker identity matched by
                  mobile.
                </span>
              </button>
            </div>

            <label className="md:col-span-2">
              <span className="text-[11px] font-semibold text-[#405779]">
                Owner full name
              </span>
              <input
                required
                minLength={2}
                maxLength={160}
                value={fullName}
                onChange={(event) => setFullName(event.target.value)}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Login mobile
              </span>
              <input
                required
                type="tel"
                maxLength={30}
                value={mobileNumber}
                onChange={(event) => setMobileNumber(event.target.value)}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Email
              </span>
              <input
                type="email"
                maxLength={254}
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            {!existingUser ? (
              <>
                <label>
                  <span className="flex items-center justify-between text-[11px] font-semibold text-[#405779]">
                    Temporary password
                    <button
                      type="button"
                      onClick={generate}
                      className="flex items-center gap-1 text-[10px] text-[#357cf4]"
                    >
                      <RefreshCw className="h-3 w-3" />
                      Generate
                    </button>
                  </span>

                  <span className="relative mt-2 block">
                    <input
                      required
                      type={passwordVisible ? "text" : "password"}
                      minLength={12}
                      maxLength={200}
                      autoComplete="new-password"
                      value={password}
                      onChange={(event) => setPassword(event.target.value)}
                      className="h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 pr-10 text-[12px] outline-none focus:border-[#357cf4]"
                    />

                    <button
                      type="button"
                      onClick={() => setPasswordVisible((value) => !value)}
                      className="absolute inset-y-0 right-0 grid w-10 place-items-center text-[#71819c]"
                      aria-label={
                        passwordVisible ? "Hide password" : "Show password"
                      }
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
                    Confirm password
                  </span>
                  <input
                    required
                    type={passwordVisible ? "text" : "password"}
                    minLength={12}
                    maxLength={200}
                    value={confirmPassword}
                    onChange={(event) => setConfirmPassword(event.target.value)}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>
              </>
            ) : null}

            <div className="md:col-span-2 flex items-start gap-3 rounded-[5px] border border-[#cfe0ff] bg-[#edf4ff] px-4 py-3">
              <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
              <p className="text-[10px] leading-5 text-[#52698e]">
                This login receives <strong>CUSTOMER_OWNER</strong>
                only within this Customer scope. Customer Owners route to the
                Customer web panel and cannot access Platform or Dealer records.
              </p>
            </div>
          </div>

          <footer className="sticky bottom-0 flex h-16 items-center justify-end gap-3 border-t border-[#dfe6ef] bg-white px-6">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-9 rounded-[3px] border border-[#cfd8e7] px-6 text-[12px] font-semibold text-[#52698e]"
            >
              Cancel
            </button>

            <button
              type="submit"
              disabled={submitting}
              className="flex h-9 min-w-[165px] items-center justify-center gap-2 rounded-[3px] bg-[#357cf4] px-6 text-[12px] font-semibold text-white disabled:opacity-60"
            >
              {submitting ? (
                <>
                  <LoaderCircle className="h-4 w-4 animate-spin" />
                  Provisioning
                </>
              ) : (
                "Provision Owner"
              )}
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}