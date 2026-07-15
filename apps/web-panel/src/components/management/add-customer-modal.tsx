"use client";

import {
  Building2,
  LoaderCircle,
  Network,
  ShieldCheck,
  UserRound,
  X,
} from "lucide-react";
import { useState, type FormEvent } from "react";
import type {
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";
import type {
  CreateIndividualCustomerInput,
  CreateOrganizationCustomerInput,
  CustomerSummary,
} from "@/lib/management/customer-types";

type CustomerType = "INDIVIDUAL" | "ORGANIZATION";
type AssignmentMode = "DIRECT" | "DEALER";

type AddCustomerModalProps = {
  dealers: DealerSummary[];
  canChooseAssignment: boolean;
  onClose: () => void;
  onCreated: (customer: CustomerSummary, provisionOwner: boolean) => void;
};

function optional(value: string) {
  const normalized = value.trim();
  return normalized || undefined;
}

export function AddCustomerModal({
  dealers,
  canChooseAssignment,
  onClose,
  onCreated,
}: AddCustomerModalProps) {
  const fixedDealer = canChooseAssignment ? null : (dealers[0] ?? null);
  const [assignmentMode, setAssignmentMode] = useState<AssignmentMode>(
    canChooseAssignment ? "DIRECT" : "DEALER",
  );
  const [managingDealerId, setManagingDealerId] = useState(
    fixedDealer?.id ?? "",
  );
  const [customerType, setCustomerType] = useState<CustomerType>("INDIVIDUAL");
  const [fullName, setFullName] = useState("");
  const [legalName, setLegalName] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [primaryMobile, setPrimaryMobile] = useState("");
  const [primaryEmail, setPrimaryEmail] = useState("");
  const [dateOfBirth, setDateOfBirth] = useState("");
  const [emergencyContactName, setEmergencyContactName] = useState("");
  const [emergencyContactMobile, setEmergencyContactMobile] = useState("");
  const [registrationNumber, setRegistrationNumber] = useState("");
  const [taxReference, setTaxReference] = useState("");
  const [contactPersonName, setContactPersonName] = useState("");
  const [contactMobile, setContactMobile] = useState("");
  const [contactEmail, setContactEmail] = useState("");
  const [provisionOwner, setProvisionOwner] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const selectedDealerId =
    assignmentMode === "DEALER"
      ? (fixedDealer?.id ?? managingDealerId)
      : undefined;

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (assignmentMode === "DEALER" && !selectedDealerId) {
      setError("Select the Dealer that will manage this Customer.");
      return;
    }

    if (primaryMobile.trim().length < 5) {
      setError("Enter a valid primary mobile number.");
      return;
    }

    let endpoint: string;
    let body: CreateIndividualCustomerInput | CreateOrganizationCustomerInput;

    if (customerType === "INDIVIDUAL") {
      if (fullName.trim().length < 2) {
        setError("Customer full name is required.");
        return;
      }

      endpoint = "/api/management/customers/individual";
      body = {
        fullName: fullName.trim(),
        primaryMobile: primaryMobile.trim(),
        primaryEmail: optional(primaryEmail),
        dateOfBirth: optional(dateOfBirth),
        emergencyContactName: optional(emergencyContactName),
        emergencyContactMobile: optional(emergencyContactMobile),
        managingDealerId: selectedDealerId,
      };
    } else {
      if (legalName.trim().length < 2 || displayName.trim().length < 2) {
        setError("Organization legal name and display name are required.");
        return;
      }

      endpoint = "/api/management/customers/organization";
      body = {
        legalName: legalName.trim(),
        displayName: displayName.trim(),
        primaryMobile: primaryMobile.trim(),
        primaryEmail: optional(primaryEmail),
        registrationNumber: optional(registrationNumber),
        taxReference: optional(taxReference),
        contactPersonName: optional(contactPersonName),
        contactMobile: optional(contactMobile),
        contactEmail: optional(contactEmail),
        managingDealerId: selectedDealerId,
      };
    }

    setSubmitting(true);

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      const result = (await response.json()) as
        CustomerSummary | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in result ? result.message : "Customer creation failed.",
        );
        return;
      }

      onCreated(result as CustomerSummary, provisionOwner);
    } catch {
      setError("The web panel could not reach the Customer service.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2300] grid place-items-center bg-[#17345f]/48 p-5"
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
        aria-labelledby="add-customer-title"
        className="flex max-h-[94vh] w-full max-w-[860px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.32)]"
      >
        <header className="flex h-16 shrink-0 items-center justify-between border-b border-[#dfe6ef] px-6">
          <div>
            <h2
              id="add-customer-title"
              className="text-[17px] font-semibold text-[#344b72]"
            >
              Add Customer
            </h2>
            <p className="mt-0.5 text-[11px] text-[#7c8ba5]">
              Create one Customer and choose Platform or Dealer management.
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close Add Customer dialog"
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

            <section className="md:col-span-2 rounded-[6px] border border-[#dfe6ef] bg-[#f8faff] p-4">
              <div className="flex items-center gap-2">
                <Network className="h-4 w-4 text-[#357cf4]" />
                <h3 className="text-[12px] font-semibold text-[#405779]">
                  Customer assignment
                </h3>
              </div>

              {canChooseAssignment ? (
                <div className="mt-3 grid gap-3 md:grid-cols-2">
                  <button
                    type="button"
                    onClick={() => setAssignmentMode("DIRECT")}
                    className={[
                      "rounded-[5px] border p-4 text-left transition",
                      assignmentMode === "DIRECT"
                        ? "border-[#357cf4] bg-[#edf4ff]"
                        : "border-[#d7e0ec] bg-white",
                    ].join(" ")}
                  >
                    <span className="block text-[12px] font-semibold text-[#405779]">
                      Platform / Direct
                    </span>
                    <span className="mt-1 block text-[10px] leading-4 text-[#7c8ba5]">
                      Solid Tracker directly manages this Customer. No Dealer is
                      assigned.
                    </span>
                  </button>

                  <button
                    type="button"
                    disabled={dealers.length === 0}
                    onClick={() => setAssignmentMode("DEALER")}
                    className={[
                      "rounded-[5px] border p-4 text-left transition disabled:cursor-not-allowed disabled:opacity-50",
                      assignmentMode === "DEALER"
                        ? "border-[#357cf4] bg-[#edf4ff]"
                        : "border-[#d7e0ec] bg-white",
                    ].join(" ")}
                  >
                    <span className="block text-[12px] font-semibold text-[#405779]">
                      Dealer-managed
                    </span>
                    <span className="mt-1 block text-[10px] leading-4 text-[#7c8ba5]">
                      Assign this Customer to one Dealer during creation.
                    </span>
                  </button>
                </div>
              ) : (
                <div className="mt-3 flex items-start gap-3 rounded-[5px] border border-[#cfe0ff] bg-[#edf4ff] px-4 py-3">
                  <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
                  <p className="text-[10px] leading-5 text-[#52698e]">
                    This workspace creates Customers only under{" "}
                    <strong>
                      {fixedDealer?.name ?? "the authenticated Dealer"}
                    </strong>
                    .
                  </p>
                </div>
              )}

              {assignmentMode === "DEALER" && canChooseAssignment ? (
                <label className="mt-4 block">
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Managing Dealer
                  </span>
                  <select
                    required
                    value={managingDealerId}
                    onChange={(event) =>
                      setManagingDealerId(event.target.value)
                    }
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  >
                    <option value="">Select Dealer</option>
                    {dealers.map((dealer) => (
                      <option key={dealer.id} value={dealer.id}>
                        {dealer.name} Â· {dealer.dealerProfile.dealerCode}
                      </option>
                    ))}
                  </select>
                </label>
              ) : null}
            </section>

            <div className="md:col-span-2 grid gap-3 md:grid-cols-2">
              <button
                type="button"
                onClick={() => setCustomerType("INDIVIDUAL")}
                className={[
                  "flex items-start gap-3 rounded-[5px] border p-4 text-left",
                  customerType === "INDIVIDUAL"
                    ? "border-[#357cf4] bg-[#edf4ff]"
                    : "border-[#d7e0ec]",
                ].join(" ")}
              >
                <UserRound className="mt-0.5 h-5 w-5 text-[#357cf4]" />
                <span>
                  <span className="block text-[12px] font-semibold text-[#405779]">
                    Individual
                  </span>
                  <span className="mt-1 block text-[10px] text-[#7c8ba5]">
                    Personal vehicle owner or individual subscriber.
                  </span>
                </span>
              </button>

              <button
                type="button"
                onClick={() => setCustomerType("ORGANIZATION")}
                className={[
                  "flex items-start gap-3 rounded-[5px] border p-4 text-left",
                  customerType === "ORGANIZATION"
                    ? "border-[#357cf4] bg-[#edf4ff]"
                    : "border-[#d7e0ec]",
                ].join(" ")}
              >
                <Building2 className="mt-0.5 h-5 w-5 text-[#357cf4]" />
                <span>
                  <span className="block text-[12px] font-semibold text-[#405779]">
                    Organization
                  </span>
                  <span className="mt-1 block text-[10px] text-[#7c8ba5]">
                    Company, office, institution, or fleet owner.
                  </span>
                </span>
              </button>
            </div>

            {customerType === "INDIVIDUAL" ? (
              <>
                <label className="md:col-span-2">
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Full name
                  </span>
                  <input
                    autoFocus
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
                    Date of birth
                  </span>
                  <input
                    type="date"
                    value={dateOfBirth}
                    onChange={(event) => setDateOfBirth(event.target.value)}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label>
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Emergency contact name
                  </span>
                  <input
                    maxLength={160}
                    value={emergencyContactName}
                    onChange={(event) =>
                      setEmergencyContactName(event.target.value)
                    }
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label className="md:col-span-2">
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Emergency contact mobile
                  </span>
                  <input
                    type="tel"
                    maxLength={30}
                    value={emergencyContactMobile}
                    onChange={(event) =>
                      setEmergencyContactMobile(event.target.value)
                    }
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>
              </>
            ) : (
              <>
                <label className="md:col-span-2">
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Legal name
                  </span>
                  <input
                    autoFocus
                    required
                    minLength={2}
                    maxLength={200}
                    value={legalName}
                    onChange={(event) => setLegalName(event.target.value)}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label className="md:col-span-2">
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Display name
                  </span>
                  <input
                    required
                    minLength={2}
                    maxLength={160}
                    value={displayName}
                    onChange={(event) => setDisplayName(event.target.value)}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label>
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Registration number
                  </span>
                  <input
                    maxLength={100}
                    value={registrationNumber}
                    onChange={(event) =>
                      setRegistrationNumber(event.target.value)
                    }
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label>
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Tax reference
                  </span>
                  <input
                    maxLength={100}
                    value={taxReference}
                    onChange={(event) => setTaxReference(event.target.value)}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label>
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Contact person
                  </span>
                  <input
                    maxLength={160}
                    value={contactPersonName}
                    onChange={(event) =>
                      setContactPersonName(event.target.value)
                    }
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label>
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Contact mobile
                  </span>
                  <input
                    type="tel"
                    maxLength={30}
                    value={contactMobile}
                    onChange={(event) => setContactMobile(event.target.value)}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>

                <label className="md:col-span-2">
                  <span className="text-[11px] font-semibold text-[#405779]">
                    Contact email
                  </span>
                  <input
                    type="email"
                    maxLength={254}
                    value={contactEmail}
                    onChange={(event) => setContactEmail(event.target.value)}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
                  />
                </label>
              </>
            )}

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Primary mobile
              </span>
              <input
                required
                type="tel"
                maxLength={30}
                value={primaryMobile}
                onChange={(event) => setPrimaryMobile(event.target.value)}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label>
              <span className="text-[11px] font-semibold text-[#405779]">
                Primary email
              </span>
              <input
                type="email"
                maxLength={254}
                value={primaryEmail}
                onChange={(event) => setPrimaryEmail(event.target.value)}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[12px] outline-none focus:border-[#357cf4]"
              />
            </label>

            <label className="md:col-span-2 flex cursor-pointer items-center gap-3 rounded-[5px] border border-[#dfe6ef] bg-[#f7f9fc] px-4 py-3">
              <input
                type="checkbox"
                checked={provisionOwner}
                onChange={(event) => setProvisionOwner(event.target.checked)}
                className="h-4 w-4 accent-[#357cf4]"
              />

              <span>
                <span className="block text-[12px] font-semibold text-[#405779]">
                  Provision Customer Owner after creation
                </span>
                <span className="mt-0.5 block text-[10px] text-[#7c8ba5]">
                  Opens the secure login form immediately after the Customer
                  record is created.
                </span>
              </span>
            </label>
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
              className="flex h-9 min-w-[150px] items-center justify-center gap-2 rounded-[3px] bg-[#357cf4] px-6 text-[12px] font-semibold text-white disabled:opacity-60"
            >
              {submitting ? (
                <>
                  <LoaderCircle className="h-4 w-4 animate-spin" />
                  Creating
                </>
              ) : (
                "Create Customer"
              )}
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}