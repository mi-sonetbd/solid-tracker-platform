"use client";

import Link from "next/link";
import {
  Building2,
  CheckCircle2,
  CirclePlus,
  LoaderCircle,
  RefreshCw,
  Search,
  ShieldCheck,
  UserRoundPlus,
  UsersRound,
} from "lucide-react";
import {
  useEffect,
  useState,
  type FormEvent,
} from "react";
import { AddDealerManagerModal } from "@/components/management/add-dealer-manager-modal";
import { AddDealerModal } from "@/components/management/add-dealer-modal";
import { AccountTree } from "@/components/management/account-tree";
import { DealerStaffModal } from "@/components/management/dealer-staff-modal";
import type {
  DealerListResponse,
  DealerSummary,
  ManagementApiError,
  ProvisionedDealerStaff,
} from "@/lib/management/dealer-types";

type AccountManagementWorkspaceProps = {
  workspace: string;
  canCreateDealer: boolean;
  canViewDealers: boolean;
  canCreateCustomer: boolean;
  canManageDealerStaff: boolean;
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

export function AccountManagementWorkspace({
  workspace,
  canCreateDealer,
  canViewDealers,
  canCreateCustomer,
  canManageDealerStaff,
}: AccountManagementWorkspaceProps) {
  const [addDealerOpen, setAddDealerOpen] = useState(false);
  const [managerDealerId, setManagerDealerId] = useState<
    string | null
  >(null);
  const [managerModalOpen, setManagerModalOpen] =
    useState(false);
  const [staffDealer, setStaffDealer] =
    useState<DealerSummary | null>(null);
  const [staffRefreshVersion, setStaffRefreshVersion] =
    useState(0);
  const [dealers, setDealers] = useState<DealerSummary[]>([]);
  const [loadingDealers, setLoadingDealers] =
    useState(canViewDealers);
  const [dealerError, setDealerError] = useState("");
  const [successMessage, setSuccessMessage] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [activeSearch, setActiveSearch] = useState("");
  const [dealerTotal, setDealerTotal] = useState(0);
  const [refreshVersion, setRefreshVersion] = useState(0);

  useEffect(() => {
    if (!canViewDealers) {
      return;
    }

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: "1",
      pageSize: "100",
    });

    if (activeSearch) {
      parameters.set("search", activeSearch);
    }

    void fetch(
      `/api/management/dealers?${parameters.toString()}`,
      {
        cache: "no-store",
        signal: controller.signal,
      },
    )
      .then(async (response) => {
        const result = (await response.json()) as
          | DealerListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in result
              ? result.message
              : "Dealer loading failed.",
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
          (error instanceof DOMException &&
            error.name === "AbortError")
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
  }, [activeSearch, canViewDealers, refreshVersion]);

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setDealerError("");
    setLoadingDealers(true);
    setActiveSearch(searchInput.trim());
    setRefreshVersion((current) => current + 1);
  }

  function refreshDealers() {
    setDealerError("");
    setLoadingDealers(true);
    setRefreshVersion((current) => current + 1);
  }

  function dealerCreated(dealer: DealerSummary) {
    setAddDealerOpen(false);
    setSuccessMessage(
      `${dealer.name} was created successfully as ${dealer.dealerProfile.dealerCode}.`,
    );
    setSearchInput("");
    setActiveSearch("");
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
                memberships:
                  (item._count?.memberships ?? 0) + 1,
                customerGroups:
                  item._count?.customerGroups ?? 0,
                managedCustomers:
                  item._count?.managedCustomers ?? 0,
              },
            }
          : item,
      ),
    );
    setStaffRefreshVersion((value) => value + 1);
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
                Create Dealers and organize their Customer and user access.
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
                Create a Dealer organization with business identity, contact, and commission settings.
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
                Add a Customer, login membership, and Dealer assignment in the next operation stage.
              </p>

              {canCreateCustomer ? (
                <Link
                  href="/management/customers"
                  className="mt-4 flex h-9 w-fit items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white"
                >
                  <CirclePlus className="h-4 w-4" />
                  Manage Direct Customers
                </Link>
              ) : (
                <button
                  type="button"
                  disabled
                  className="mt-4 flex h-9 items-center gap-2 rounded-[3px] bg-[#b8c7dc] px-4 text-[11px] font-semibold text-white"
                >
                  <CirclePlus className="h-4 w-4" />
                  Add Customer
                </button>
              )}
            </article>

            <article className="rounded-[6px] border border-[#dfe6ef] p-5">
              <div className="grid h-11 w-11 place-items-center rounded-full bg-[#eaf2ff] text-[#357cf4]">
                <UsersRound className="h-5 w-5" />
              </div>

              <h2 className="mt-4 text-[14px] font-semibold text-[#405779]">
                Dealer Manager
              </h2>

              <p className="mt-2 min-h-12 text-[11px] leading-5 text-[#71819c]">
                Create a Dealer-scoped login with the system Dealer Manager role.
              </p>

              <button
                type="button"
                disabled={
                  !canManageDealerStaff || dealers.length === 0
                }
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
            <header className="flex flex-wrap items-center justify-between gap-3 border-b border-[#e2e8f1] px-5 py-4">
              <div>
                <div className="flex items-center gap-2">
                  <ShieldCheck className="h-5 w-5 text-[#357cf4]" />
                  <h2 className="text-[14px] font-semibold text-[#405779]">
                    Dealer Directory
                  </h2>
                </div>
                <p className="mt-1 text-[10px] text-[#7c8ba5]">
                  {dealerTotal} Dealer account{dealerTotal === 1 ? "" : "s"} within the authenticated scope.
                </p>
              </div>

              <form
                onSubmit={search}
                className="flex items-center gap-2"
              >
                <label className="flex h-9 w-[270px] items-center rounded-[4px] border border-[#cfd8e7] px-3">
                  <input
                    value={searchInput}
                    onChange={(event) =>
                      setSearchInput(event.target.value)
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
                          <p>
                            {dealer.dealerProfile.contactMobile || "-"}
                          </p>
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
                              onClick={() =>
                                setStaffDealer(dealer)
                              }
                              className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[10px] font-semibold text-[#52698e] disabled:opacity-50"
                            >
                              Staff
                            </button>

                            <button
                              type="button"
                              disabled={!canManageDealerStaff}
                              onClick={() =>
                                openManagerModal(dealer.id)
                              }
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
        </section>
      </div>

      {addDealerOpen ? (
        <AddDealerModal
          onClose={() => setAddDealerOpen(false)}
          onCreated={dealerCreated}
        />
      ) : null}

      {staffDealer ? (
        <DealerStaffModal
          dealer={staffDealer}
          canManageStaff={canManageDealerStaff}
          refreshVersion={staffRefreshVersion}
          onAddManager={() =>
            openManagerModal(staffDealer.id)
          }
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
    </>
  );
}