"use client";

import {
  Building2,
  CheckCircle2,
  CirclePlus,
  Filter,
  LoaderCircle,
  Network,
  RefreshCw,
  Search,
  ShieldCheck,
  UserRound,
  UserRoundPlus,
  UsersRound,
} from "lucide-react";
import { useEffect, useMemo, useState, type FormEvent } from "react";
import { AddCustomerModal } from "@/components/management/add-customer-modal";
import { AddCustomerOwnerModal } from "@/components/management/add-customer-owner-modal";
import { AddDealerManagerModal } from "@/components/management/add-dealer-manager-modal";
import { AddDealerModal } from "@/components/management/add-dealer-modal";
import { AccountTree } from "@/components/management/account-tree";
import { CustomerAssetsModal } from "@/components/management/customer-assets-modal";
import { CustomerMembersModal } from "@/components/management/customer-members-modal";
import { DealerStaffModal } from "@/components/management/dealer-staff-modal";
import type {
  CustomerListResponse,
  CustomerSummary,
  ProvisionedCustomerMember,
} from "@/lib/management/customer-types";
import type {
  DealerListResponse,
  DealerSummary,
  ManagementApiError,
  ProvisionedDealerStaff,
} from "@/lib/management/dealer-types";

type DirectoryTab = "DEALERS" | "CUSTOMERS";
type CustomerAssignmentFilter = "ALL" | "DIRECT" | "DEALER";

type AccountManagementWorkspaceProps = {
  workspace: string;
  canCreateDealer: boolean;
  canViewDealers: boolean;
  canCreateCustomer: boolean;
  canViewCustomers: boolean;
  canManageDealerStaff: boolean;
  canManageCustomerMembers: boolean;
  canChooseCustomerAssignment: boolean;
  canViewVehicles: boolean;
  canCreateVehicles: boolean;
  canViewDevices: boolean;
  canInstallDevices: boolean;
};

function formatDate(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "-";
  }

  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
  }).format(date);
}

function customerName(customer: CustomerSummary) {
  return (
    customer.individualProfile?.fullName ??
    customer.organizationProfile?.displayName ??
    customer.customerCode
  );
}

function withCustomerCounts(customer: CustomerSummary) {
  return {
    ...customer,
    _count: {
      memberships: customer._count?.memberships ?? 0,
      vehicles: customer._count?.vehicles ?? 0,
      billingSubscriptions: customer._count?.billingSubscriptions ?? 0,
    },
  };
}

export function AccountManagementWorkspace({
  workspace,
  canCreateDealer,
  canViewDealers,
  canCreateCustomer,
  canViewCustomers,
  canManageDealerStaff,
  canManageCustomerMembers,
  canChooseCustomerAssignment,
  canViewVehicles,
  canCreateVehicles,
  canViewDevices,
  canInstallDevices,
}: AccountManagementWorkspaceProps) {
  const [directoryTab, setDirectoryTab] = useState<DirectoryTab>("DEALERS");
  const [addDealerOpen, setAddDealerOpen] = useState(false);
  const [addCustomerOpen, setAddCustomerOpen] = useState(false);
  const [managerDealerId, setManagerDealerId] = useState<string | null>(null);
  const [managerModalOpen, setManagerModalOpen] = useState(false);
  const [staffDealer, setStaffDealer] = useState<DealerSummary | null>(null);
  const [staffRefreshVersion, setStaffRefreshVersion] = useState(0);
  const [membersCustomer, setMembersCustomer] =
    useState<CustomerSummary | null>(null);
  const [ownerCustomer, setOwnerCustomer] = useState<CustomerSummary | null>(
    null,
  );
  const [assetsCustomer, setAssetsCustomer] =
    useState<CustomerSummary | null>(null);
  const [memberRefreshVersion, setMemberRefreshVersion] = useState(0);
  const [dealers, setDealers] = useState<DealerSummary[]>([]);
  const [loadingDealers, setLoadingDealers] = useState(canViewDealers);
  const [dealerError, setDealerError] = useState("");
  const [successMessage, setSuccessMessage] = useState("");
  const [dealerSearchInput, setDealerSearchInput] = useState("");
  const [activeDealerSearch, setActiveDealerSearch] = useState("");
  const [dealerTotal, setDealerTotal] = useState(0);
  const [dealerRefreshVersion, setDealerRefreshVersion] = useState(0);

  const [customers, setCustomers] = useState<CustomerSummary[]>([]);
  const [loadingCustomers, setLoadingCustomers] = useState(canViewCustomers);
  const [customerError, setCustomerError] = useState("");
  const [customerSearchInput, setCustomerSearchInput] = useState("");
  const [activeCustomerSearch, setActiveCustomerSearch] = useState("");
  const [customerTypeFilter, setCustomerTypeFilter] = useState("");
  const [customerStatusFilter, setCustomerStatusFilter] = useState("");
  const [customerAssignmentFilter, setCustomerAssignmentFilter] =
    useState<CustomerAssignmentFilter>("ALL");
  const [customerDealerFilter, setCustomerDealerFilter] = useState("");
  const [customerTotal, setCustomerTotal] = useState(0);
  const [customerRefreshVersion, setCustomerRefreshVersion] = useState(0);

  useEffect(() => {
    if (!canViewDealers) {
      return;
    }

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: "1",
      pageSize: "100",
    });

    if (activeDealerSearch) {
      parameters.set("search", activeDealerSearch);
    }

    void fetch(`/api/management/dealers?${parameters.toString()}`, {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const result = (await response.json()) as
          DealerListResponse | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in result ? result.message : "Dealer loading failed.",
          );
        }

        if (controller.signal.aborted) {
          return;
        }

        const list = result as DealerListResponse;
        setDealers(list.items);
        setDealerTotal(list.total);
        setDealerError("");
      })
      .catch((error: unknown) => {
        if (
          controller.signal.aborted ||
          (error instanceof DOMException && error.name === "AbortError")
        ) {
          return;
        }

        setDealerError(
          error instanceof Error
            ? error.message
            : "The web panel could not load the Dealer directory.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoadingDealers(false);
        }
      });

    return () => {
      controller.abort();
    };
  }, [activeDealerSearch, canViewDealers, dealerRefreshVersion]);

  useEffect(() => {
    if (!canViewCustomers) {
      return;
    }

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: "1",
      pageSize: "100",
    });

    if (activeCustomerSearch) {
      parameters.set("search", activeCustomerSearch);
    }

    if (customerTypeFilter) {
      parameters.set("customerType", customerTypeFilter);
    }

    if (customerStatusFilter) {
      parameters.set("status", customerStatusFilter);
    }

    if (customerDealerFilter) {
      parameters.set("managingDealerId", customerDealerFilter);
    }

    void fetch(`/api/management/customers?${parameters.toString()}`, {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const result = (await response.json()) as
          CustomerListResponse | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in result ? result.message : "Customer loading failed.",
          );
        }

        if (controller.signal.aborted) {
          return;
        }

        const list = result as CustomerListResponse;
        setCustomers(list.items.map(withCustomerCounts));
        setCustomerTotal(list.total);
        setCustomerError("");
      })
      .catch((error: unknown) => {
        if (
          controller.signal.aborted ||
          (error instanceof DOMException && error.name === "AbortError")
        ) {
          return;
        }

        setCustomerError(
          error instanceof Error
            ? error.message
            : "The web panel could not load the Customer directory.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoadingCustomers(false);
        }
      });

    return () => {
      controller.abort();
    };
  }, [
    activeCustomerSearch,
    canViewCustomers,
    customerDealerFilter,
    customerRefreshVersion,
    customerStatusFilter,
    customerTypeFilter,
  ]);

  const visibleCustomers = useMemo(() => {
    if (customerAssignmentFilter === "DIRECT") {
      return customers.filter((customer) => customer.managingDealerId === null);
    }

    if (customerAssignmentFilter === "DEALER") {
      return customers.filter((customer) => customer.managingDealerId !== null);
    }

    return customers;
  }, [customerAssignmentFilter, customers]);

  const customerCreationUnavailable =
    !canCreateCustomer ||
    (!canChooseCustomerAssignment && dealers.length === 0);

  function searchDealers(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setDealerError("");
    setLoadingDealers(true);
    setActiveDealerSearch(dealerSearchInput.trim());
    setDealerRefreshVersion((current) => current + 1);
  }

  function refreshDealers() {
    setDealerError("");
    setLoadingDealers(true);
    setDealerRefreshVersion((current) => current + 1);
  }

  function searchCustomers(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCustomerError("");
    setLoadingCustomers(true);
    setActiveCustomerSearch(customerSearchInput.trim());
    setCustomerRefreshVersion((current) => current + 1);
  }

  function refreshCustomers() {
    setCustomerError("");
    setLoadingCustomers(true);
    setCustomerRefreshVersion((current) => current + 1);
  }

  function dealerCreated(dealer: DealerSummary) {
    setAddDealerOpen(false);
    setSuccessMessage(
      `${dealer.name} was created successfully as ${dealer.dealerProfile.dealerCode}.`,
    );
    setDealerSearchInput("");
    setActiveDealerSearch("");
    setDealers((current) => [
      dealer,
      ...current.filter((item) => item.id !== dealer.id),
    ]);
    setDealerTotal((current) => current + 1);
  }

  function openManagerModal(dealerId?: string) {
    setManagerDealerId(dealerId ?? null);
    setManagerModalOpen(true);
  }

  function managerCreated(
    result: ProvisionedDealerStaff,
    dealer: DealerSummary,
  ) {
    setManagerModalOpen(false);
    setManagerDealerId(null);
    setSuccessMessage(
      `${result.user.fullName} is now a Dealer Manager for ${dealer.name}. Login mobile: ${result.user.mobileNumber}.`,
    );
    setDealers((current) =>
      current.map((item) =>
        item.id === dealer.id
          ? {
              ...item,
              _count: {
                memberships: (item._count?.memberships ?? 0) + 1,
                customerGroups: item._count?.customerGroups ?? 0,
                managedCustomers: item._count?.managedCustomers ?? 0,
              },
            }
          : item,
      ),
    );
    setStaffRefreshVersion((value) => value + 1);
  }

  function customerCreated(customer: CustomerSummary, provisionOwner: boolean) {
    const normalizedCustomer = withCustomerCounts(customer);
    setAddCustomerOpen(false);
    setDirectoryTab("CUSTOMERS");
    setSuccessMessage(
      `${customerName(customer)} was created as ${customer.customerCode} under ${customer.managingDealer?.name ?? "Solid Tracker Platform"}.`,
    );
    setCustomers((current) => [
      normalizedCustomer,
      ...current.filter((item) => item.id !== customer.id),
    ]);
    setCustomerTotal((current) => current + 1);

    if (customer.managingDealerId) {
      setDealers((current) =>
        current.map((dealer) =>
          dealer.id === customer.managingDealerId
            ? {
                ...dealer,
                _count: {
                  memberships: dealer._count?.memberships ?? 0,
                  customerGroups: dealer._count?.customerGroups ?? 0,
                  managedCustomers: (dealer._count?.managedCustomers ?? 0) + 1,
                },
              }
            : dealer,
        ),
      );
    }

    if (provisionOwner) {
      setOwnerCustomer(normalizedCustomer);
    }
  }

  function customerVehicleCountChanged(
    customerId: string,
    count: number,
  ) {
    setCustomers((current) =>
      current.map((customer) =>
        customer.id === customerId
          ? {
              ...customer,
              _count: {
                memberships: customer._count?.memberships ?? 0,
                vehicles: count,
                billingSubscriptions:
                  customer._count?.billingSubscriptions ?? 0,
              },
            }
          : customer,
      ),
    );
  }

  function ownerCreated(member: ProvisionedCustomerMember) {
    const customer = ownerCustomer;
    setOwnerCustomer(null);
    setMemberRefreshVersion((value) => value + 1);
    setCustomerRefreshVersion((value) => value + 1);
    setSuccessMessage(
      `${member.user.fullName} is now the primary Customer Owner${customer ? ` for ${customerName(customer)}` : ""}. Login mobile: ${member.user.mobileNumber}.`,
    );
  }

  return (
    <>
      <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-w-[1180px] overflow-hidden p-2">
        <AccountTree />

        <section className="st-scrollbar min-w-0 flex-1 overflow-auto rounded-r-[6px] bg-white p-5">
          <div className="flex items-start justify-between border-b border-[#e2e8f1] pb-4">
            <div>
              <h1 className="text-[18px] font-semibold text-[#344b72]">
                Account Management
              </h1>
              <p className="mt-1 text-[12px] text-[#71819c]">
                Create Dealers and Customers, assign management scope, and
                provision account access.
              </p>
            </div>

            <span className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[10px] font-semibold text-[#357cf4]">
              {workspace}
            </span>
          </div>

          {successMessage ? (
            <div className="mt-4 flex items-start gap-3 rounded-[5px] border border-emerald-200 bg-emerald-50 px-4 py-3 text-[12px] text-emerald-800">
              <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{successMessage}</span>
            </div>
          ) : null}

          <div className="mt-5 grid gap-4 lg:grid-cols-3">
            <article className="rounded-[6px] border border-[#dfe6ef] p-5">
              <div className="grid h-11 w-11 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
                <Building2 className="h-5 w-5" />
              </div>

              <h2 className="mt-4 text-[14px] font-semibold text-[#405779]">
                Dealer Account
              </h2>

              <p className="mt-2 min-h-12 text-[11px] leading-5 text-[#71819c]">
                Create a Dealer organization with business identity, contact,
                and commission settings.
              </p>

              <button
                type="button"
                disabled={!canCreateDealer}
                onClick={() => setAddDealerOpen(true)}
                className="mt-4 flex h-9 items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:cursor-not-allowed disabled:bg-[#b8c7dc]"
              >
                <CirclePlus className="h-4 w-4" />
                Add Dealer
              </button>

              {!canCreateDealer ? (
                <p className="mt-2 text-[10px] text-[#9a6a36]">
                  Requires platform scope and dealer.manage permission.
                </p>
              ) : null}
            </article>

            <article className="rounded-[6px] border border-[#dfe6ef] p-5">
              <div className="grid h-11 w-11 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
                <UserRoundPlus className="h-5 w-5" />
              </div>

              <h2 className="mt-4 text-[14px] font-semibold text-[#405779]">
                Customer Account
              </h2>

              <p className="mt-2 min-h-12 text-[11px] leading-5 text-[#71819c]">
                Create an Individual or Organization Customer as Direct or
                Dealer-managed.
              </p>

              <button
                type="button"
                disabled={customerCreationUnavailable}
                onClick={() => setAddCustomerOpen(true)}
                className="mt-4 flex h-9 items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:cursor-not-allowed disabled:bg-[#b8c7dc]"
              >
                <CirclePlus className="h-4 w-4" />
                Add Customer
              </button>

              {!canCreateCustomer ? (
                <p className="mt-2 text-[10px] text-[#9a6a36]">
                  Requires customer.create permission.
                </p>
              ) : !canChooseCustomerAssignment && dealers.length === 0 ? (
                <p className="mt-2 text-[10px] text-[#9a6a36]">
                  The authenticated Dealer scope could not be loaded.
                </p>
              ) : null}
            </article>

            <article className="rounded-[6px] border border-[#dfe6ef] p-5">
              <div className="grid h-11 w-11 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
                <UsersRound className="h-5 w-5" />
              </div>

              <h2 className="mt-4 text-[14px] font-semibold text-[#405779]">
                Dealer Manager
              </h2>

              <p className="mt-2 min-h-12 text-[11px] leading-5 text-[#71819c]">
                Create a Dealer-scoped login with the system Dealer Manager
                role.
              </p>

              <button
                type="button"
                disabled={!canManageDealerStaff || dealers.length === 0}
                onClick={() => openManagerModal()}
                className="mt-4 flex h-9 items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:cursor-not-allowed disabled:bg-[#b8c7dc]"
              >
                <CirclePlus className="h-4 w-4" />
                Add Dealer Manager
              </button>

              {!canManageDealerStaff ? (
                <p className="mt-2 text-[10px] text-[#9a6a36]">
                  Requires dealer.staff.manage permission.
                </p>
              ) : dealers.length === 0 ? (
                <p className="mt-2 text-[10px] text-[#9a6a36]">
                  Create or load a Dealer before adding staff.
                </p>
              ) : null}
            </article>
          </div>

          <section className="mt-5 overflow-hidden rounded-[6px] border border-[#dfe6ef]">
            <header className="flex flex-wrap items-center justify-between gap-3 border-b border-[#e2e8f1] px-5 py-3">
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setDirectoryTab("DEALERS")}
                  className={[
                    "flex h-9 items-center gap-2 rounded-[4px] px-4 text-[11px] font-semibold transition",
                    directoryTab === "DEALERS"
                      ? "bg-[#357cf4] text-white"
                      : "bg-[#edf2f8] text-[#52698e]",
                  ].join(" ")}
                >
                  <Building2 className="h-4 w-4" />
                  Dealer Directory
                </button>

                <button
                  type="button"
                  onClick={() => setDirectoryTab("CUSTOMERS")}
                  className={[
                    "flex h-9 items-center gap-2 rounded-[4px] px-4 text-[11px] font-semibold transition",
                    directoryTab === "CUSTOMERS"
                      ? "bg-[#357cf4] text-white"
                      : "bg-[#edf2f8] text-[#52698e]",
                  ].join(" ")}
                >
                  <UserRound className="h-4 w-4" />
                  Customer Directory
                </button>
              </div>

              <span className="text-[10px] text-[#7c8ba5]">
                One account workspace Â· scope-controlled data
              </span>
            </header>

            {directoryTab === "DEALERS" ? (
              <section>
                <header className="flex flex-wrap items-center justify-between gap-3 border-b border-[#e2e8f1] px-5 py-4">
                  <div>
                    <div className="flex items-center gap-2">
                      <ShieldCheck className="h-5 w-5 text-[#357cf4]" />
                      <h2 className="text-[14px] font-semibold text-[#405779]">
                        Dealer Directory
                      </h2>
                    </div>
                    <p className="mt-1 text-[10px] text-[#7c8ba5]">
                      {dealerTotal} Dealer account{dealerTotal === 1 ? "" : "s"}{" "}
                      within the authenticated scope.
                    </p>
                  </div>

                  <form
                    onSubmit={searchDealers}
                    className="flex items-center gap-2"
                  >
                    <label className="flex h-9 w-[270px] items-center rounded-[4px] border border-[#cfd8e7] px-3">
                      <input
                        value={dealerSearchInput}
                        onChange={(event) =>
                          setDealerSearchInput(event.target.value)
                        }
                        placeholder="Search Dealer name or code"
                        className="min-w-0 flex-1 border-0 bg-transparent text-[11px] outline-none"
                      />
                      <Search className="h-4 w-4 text-[#607392]" />
                    </label>

                    <button
                      type="submit"
                      disabled={!canViewDealers}
                      className="h-9 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
                    >
                      Search
                    </button>

                    <button
                      type="button"
                      disabled={!canViewDealers || loadingDealers}
                      onClick={refreshDealers}
                      aria-label="Refresh Dealer directory"
                      className="grid h-9 w-9 place-items-center rounded-[3px] border border-[#cfd8e7] text-[#52698e] disabled:opacity-50"
                    >
                      <RefreshCw
                        className={[
                          "h-4 w-4",
                          loadingDealers ? "animate-spin" : "",
                        ].join(" ")}
                      />
                    </button>
                  </form>
                </header>

                {dealerError ? (
                  <div
                    role="alert"
                    className="m-5 rounded-[4px] border border-red-200 bg-red-50 px-4 py-3 text-[12px] text-red-700"
                  >
                    {dealerError}
                  </div>
                ) : null}

                {!canViewDealers ? (
                  <div className="p-8 text-center text-[12px] text-[#7c8ba5]">
                    This account does not have dealer.view permission.
                  </div>
                ) : loadingDealers ? (
                  <div className="flex min-h-[210px] items-center justify-center gap-2 text-[12px] text-[#71819c]">
                    <LoaderCircle className="h-5 w-5 animate-spin text-[#357cf4]" />
                    Loading Dealer directory
                  </div>
                ) : dealers.length === 0 ? (
                  <div className="p-10 text-center">
                    <Building2 className="mx-auto h-9 w-9 text-[#b5c2d5]" />
                    <p className="mt-3 text-[12px] font-semibold text-[#52698e]">
                      No Dealer accounts found
                    </p>
                    <p className="mt-1 text-[10px] text-[#8b9ab4]">
                      Create the first Dealer or change the search term.
                    </p>
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full min-w-[1080px] text-left text-[11px]">
                      <thead className="bg-[#edf2f8] text-[#405779]">
                        <tr>
                          {[
                            "Dealer",
                            "Dealer code",
                            "Contact",
                            "Commission",
                            "Customers",
                            "Staff",
                            "Status",
                            "Created",
                            "Actions",
                          ].map((heading) => (
                            <th
                              key={heading}
                              className="px-4 py-3 font-semibold"
                            >
                              {heading}
                            </th>
                          ))}
                        </tr>
                      </thead>

                      <tbody>
                        {dealers.map((dealer) => (
                          <tr
                            key={dealer.id}
                            className="border-t border-[#e2e8f1] text-[#52698e] hover:bg-[#f8faff]"
                          >
                            <td className="px-4 py-4">
                              <p className="font-semibold text-[#405779]">
                                {dealer.name}
                              </p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {dealer.legalName || dealer.code}
                              </p>
                            </td>

                            <td className="px-4 py-4 font-medium text-[#357cf4]">
                              {dealer.dealerProfile.dealerCode}
                            </td>

                            <td className="px-4 py-4">
                              <p>{dealer.dealerProfile.contactMobile || "-"}</p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {dealer.dealerProfile.contactEmail || "-"}
                              </p>
                            </td>

                            <td className="px-4 py-4">
                              <span
                                className={[
                                  "rounded-full px-2 py-1 text-[9px] font-semibold",
                                  dealer.dealerProfile.commissionEnabled
                                    ? "bg-emerald-50 text-emerald-700"
                                    : "bg-slate-100 text-slate-600",
                                ].join(" ")}
                              >
                                {dealer.dealerProfile.commissionEnabled
                                  ? "Enabled"
                                  : "Disabled"}
                              </span>
                            </td>

                            <td className="px-4 py-4">
                              {dealer._count?.managedCustomers ?? 0}
                            </td>

                            <td className="px-4 py-4">
                              {dealer._count?.memberships ?? 0}
                            </td>

                            <td className="px-4 py-4">
                              <span className="rounded-full bg-[#eaf2ff] px-2 py-1 text-[9px] font-semibold text-[#357cf4]">
                                {dealer.status}
                              </span>
                            </td>

                            <td className="px-4 py-4">
                              {formatDate(dealer.createdAt)}
                            </td>

                            <td className="px-4 py-4">
                              <div className="flex items-center gap-2">
                                <button
                                  type="button"
                                  disabled={!canManageDealerStaff}
                                  onClick={() => setStaffDealer(dealer)}
                                  className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[10px] font-semibold text-[#52698e] disabled:opacity-50"
                                >
                                  Staff
                                </button>

                                <button
                                  type="button"
                                  disabled={!canManageDealerStaff}
                                  onClick={() => openManagerModal(dealer.id)}
                                  className="h-8 rounded-[3px] bg-[#357cf4] px-3 text-[10px] font-semibold text-white disabled:bg-[#b8c7dc]"
                                >
                                  Add Manager
                                </button>
                              </div>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>
            ) : (
              <section>
                <header className="border-b border-[#e2e8f1] px-5 py-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2">
                        <Network className="h-5 w-5 text-[#357cf4]" />
                        <h2 className="text-[14px] font-semibold text-[#405779]">
                          Customer Directory
                        </h2>
                      </div>
                      <p className="mt-1 text-[10px] text-[#7c8ba5]">
                        Showing {visibleCustomers.length} of {customerTotal}{" "}
                        scoped Customer account{customerTotal === 1 ? "" : "s"}.
                      </p>
                    </div>

                    <form
                      onSubmit={searchCustomers}
                      className="flex items-center gap-2"
                    >
                      <label className="flex h-9 w-[270px] items-center rounded-[4px] border border-[#cfd8e7] px-3">
                        <input
                          value={customerSearchInput}
                          onChange={(event) =>
                            setCustomerSearchInput(event.target.value)
                          }
                          placeholder="Name, code, mobile, or email"
                          className="min-w-0 flex-1 border-0 bg-transparent text-[11px] outline-none"
                        />
                        <Search className="h-4 w-4 text-[#607392]" />
                      </label>

                      <button
                        type="submit"
                        disabled={!canViewCustomers}
                        className="h-9 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
                      >
                        Search
                      </button>

                      <button
                        type="button"
                        disabled={!canViewCustomers || loadingCustomers}
                        onClick={refreshCustomers}
                        aria-label="Refresh Customer directory"
                        className="grid h-9 w-9 place-items-center rounded-[3px] border border-[#cfd8e7] text-[#52698e] disabled:opacity-50"
                      >
                        <RefreshCw
                          className={[
                            "h-4 w-4",
                            loadingCustomers ? "animate-spin" : "",
                          ].join(" ")}
                        />
                      </button>
                    </form>
                  </div>

                  <div className="mt-4 flex flex-wrap items-center gap-2">
                    <span className="flex items-center gap-1 text-[10px] font-semibold text-[#607392]">
                      <Filter className="h-3.5 w-3.5" />
                      Filters
                    </span>

                    <select
                      value={customerAssignmentFilter}
                      onChange={(event) => {
                        const value = event.target
                          .value as CustomerAssignmentFilter;
                        setCustomerAssignmentFilter(value);

                        if (value === "DIRECT" && customerDealerFilter) {
                          setCustomerDealerFilter("");
                          setLoadingCustomers(true);
                        }
                      }}
                      className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] text-[#52698e]"
                    >
                      <option value="ALL">All assignments</option>
                      <option value="DIRECT">Direct / Platform</option>
                      <option value="DEALER">Dealer-managed</option>
                    </select>

                    <select
                      value={customerDealerFilter}
                      onChange={(event) => {
                        const dealerId = event.target.value;
                        setCustomerDealerFilter(dealerId);

                        if (dealerId) {
                          setCustomerAssignmentFilter("DEALER");
                        }

                        setLoadingCustomers(true);
                      }}
                      className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] text-[#52698e]"
                    >
                      <option value="">All Dealers</option>
                      {dealers.map((dealer) => (
                        <option key={dealer.id} value={dealer.id}>
                          {dealer.name}
                        </option>
                      ))}
                    </select>

                    <select
                      value={customerTypeFilter}
                      onChange={(event) => {
                        setCustomerTypeFilter(event.target.value);
                        setLoadingCustomers(true);
                      }}
                      className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] text-[#52698e]"
                    >
                      <option value="">All types</option>
                      <option value="INDIVIDUAL">Individual</option>
                      <option value="ORGANIZATION">Organization</option>
                    </select>

                    <select
                      value={customerStatusFilter}
                      onChange={(event) => {
                        setCustomerStatusFilter(event.target.value);
                        setLoadingCustomers(true);
                      }}
                      className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] text-[#52698e]"
                    >
                      <option value="">Current statuses</option>
                      <option value="PENDING">Pending</option>
                      <option value="ACTIVE">Active</option>
                      <option value="SUSPENDED">Suspended</option>
                      <option value="ARCHIVED">Archived</option>
                    </select>
                  </div>
                </header>

                {customerError ? (
                  <div
                    role="alert"
                    className="m-5 rounded-[4px] border border-red-200 bg-red-50 px-4 py-3 text-[12px] text-red-700"
                  >
                    {customerError}
                  </div>
                ) : null}

                {!canViewCustomers ? (
                  <div className="p-8 text-center text-[12px] text-[#7c8ba5]">
                    This account does not have customer.view permission.
                  </div>
                ) : loadingCustomers ? (
                  <div className="flex min-h-[230px] items-center justify-center gap-2 text-[12px] text-[#71819c]">
                    <LoaderCircle className="h-5 w-5 animate-spin text-[#357cf4]" />
                    Loading Customer directory
                  </div>
                ) : visibleCustomers.length === 0 ? (
                  <div className="p-10 text-center">
                    <UserRound className="mx-auto h-9 w-9 text-[#b5c2d5]" />
                    <p className="mt-3 text-[12px] font-semibold text-[#52698e]">
                      No Customer accounts found
                    </p>
                    <p className="mt-1 text-[10px] text-[#8b9ab4]">
                      Add a Customer or change the active filters.
                    </p>
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full min-w-[1320px] text-left text-[11px]">
                      <thead className="bg-[#edf2f8] text-[#405779]">
                        <tr>
                          {[
                            "Customer",
                            "Customer code",
                            "Type",
                            "Assignment",
                            "Dealer",
                            "Contact",
                            "Members",
                            "Vehicles",
                            "Status",
                            "Created",
                            "Actions",
                          ].map((heading) => (
                            <th
                              key={heading}
                              className="px-4 py-3 font-semibold"
                            >
                              {heading}
                            </th>
                          ))}
                        </tr>
                      </thead>

                      <tbody>
                        {visibleCustomers.map((customer) => (
                          <tr
                            key={customer.id}
                            className="border-t border-[#e2e8f1] text-[#52698e] hover:bg-[#f8faff]"
                          >
                            <td className="px-4 py-4">
                              <p className="font-semibold text-[#405779]">
                                {customerName(customer)}
                              </p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {customer.organizationProfile?.legalName ??
                                  customer.acquisitionSource}
                              </p>
                            </td>

                            <td className="px-4 py-4 font-medium text-[#357cf4]">
                              {customer.customerCode}
                            </td>

                            <td className="px-4 py-4">
                              {customer.customerType}
                            </td>

                            <td className="px-4 py-4">
                              <span
                                className={[
                                  "rounded-full px-2 py-1 text-[9px] font-semibold",
                                  customer.managingDealerId
                                    ? "bg-violet-50 text-violet-700"
                                    : "bg-cyan-50 text-cyan-700",
                                ].join(" ")}
                              >
                                {customer.managingDealerId
                                  ? "DEALER"
                                  : "PLATFORM / DIRECT"}
                              </span>
                            </td>

                            <td className="px-4 py-4">
                              <p className="font-medium text-[#405779]">
                                {customer.managingDealer?.name ??
                                  "Solid Tracker Platform"}
                              </p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {customer.managingDealer?.code ?? "DIRECT"}
                              </p>
                            </td>

                            <td className="px-4 py-4">
                              <p>{customer.primaryMobile || "-"}</p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {customer.primaryEmail || "-"}
                              </p>
                            </td>

                            <td className="px-4 py-4">
                              {customer._count?.memberships ?? 0}
                            </td>

                            <td className="px-4 py-4">
                              {customer._count?.vehicles ?? 0}
                            </td>

                            <td className="px-4 py-4">
                              <span className="rounded-full bg-emerald-50 px-2 py-1 text-[9px] font-semibold text-emerald-700">
                                {customer.status}
                              </span>
                            </td>

                            <td className="px-4 py-4">
                              {formatDate(customer.createdAt)}
                            </td>

                            <td className="px-4 py-4">
                              <div className="flex items-center gap-2">
                                <button
                                  type="button"
                                  disabled={!canViewVehicles}
                                  onClick={() => setAssetsCustomer(customer)}
                                  className="h-8 rounded-[3px] border border-[#9fc2f8] bg-[#f5f9ff] px-3 text-[10px] font-semibold text-[#357cf4] disabled:border-[#dfe6ef] disabled:bg-[#f4f6f9] disabled:text-[#9aacbf]"
                                >
                                  Assets
                                </button>

                                <button
                                  type="button"
                                  onClick={() => setMembersCustomer(customer)}
                                  className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[10px] font-semibold text-[#52698e]"
                                >
                                  Members
                                </button>

                                <button
                                  type="button"
                                  disabled={!canManageCustomerMembers}
                                  onClick={() => setOwnerCustomer(customer)}
                                  className="h-8 rounded-[3px] bg-[#357cf4] px-3 text-[10px] font-semibold text-white disabled:bg-[#b8c7dc]"
                                >
                                  Owner Login
                                </button>
                              </div>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>
            )}
          </section>
        </section>
      </div>

      {addDealerOpen ? (
        <AddDealerModal
          onClose={() => setAddDealerOpen(false)}
          onCreated={dealerCreated}
        />
      ) : null}

      {addCustomerOpen ? (
        <AddCustomerModal
          dealers={dealers}
          canChooseAssignment={canChooseCustomerAssignment}
          onClose={() => setAddCustomerOpen(false)}
          onCreated={customerCreated}
        />
      ) : null}

      {staffDealer ? (
        <DealerStaffModal
          dealer={staffDealer}
          canManageStaff={canManageDealerStaff}
          refreshVersion={staffRefreshVersion}
          onAddManager={() => openManagerModal(staffDealer.id)}
          onClose={() => setStaffDealer(null)}
        />
      ) : null}

      {managerModalOpen ? (
        <AddDealerManagerModal
          dealers={dealers}
          initialDealerId={managerDealerId ?? undefined}
          onClose={() => {
            setManagerModalOpen(false);
            setManagerDealerId(null);
          }}
          onCreated={managerCreated}
        />
      ) : null}

      {assetsCustomer ? (
        <CustomerAssetsModal
          customer={assetsCustomer}
          canCreateVehicles={canCreateVehicles}
          canViewDevices={canViewDevices}
          canInstallDevices={canInstallDevices}
          onClose={() => setAssetsCustomer(null)}
          onVehicleCountChange={customerVehicleCountChanged}
        />
      ) : null}

      {membersCustomer ? (
        <CustomerMembersModal
          customer={membersCustomer}
          canManageMembers={canManageCustomerMembers}
          refreshVersion={memberRefreshVersion}
          onAddOwner={() => setOwnerCustomer(membersCustomer)}
          onClose={() => setMembersCustomer(null)}
        />
      ) : null}

      {ownerCustomer ? (
        <AddCustomerOwnerModal
          customer={ownerCustomer}
          onClose={() => setOwnerCustomer(null)}
          onCreated={ownerCreated}
        />
      ) : null}
    </>
  );
}