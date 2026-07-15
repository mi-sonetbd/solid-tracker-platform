"use client";

import {
  Building2,
  CheckCircle2,
  CirclePlus,
  Filter,
  LoaderCircle,
  RefreshCw,
  Search,
  UserRound,
  UsersRound,
} from "lucide-react";
import {
  useEffect,
  useMemo,
  useState,
  type FormEvent,
} from "react";
import { AddCustomerOwnerModal } from "@/components/management/add-customer-owner-modal";
import { AddDirectCustomerModal } from "@/components/management/add-direct-customer-modal";
import { CustomerMembersModal } from "@/components/management/customer-members-modal";
import type {
  CustomerListResponse,
  CustomerSummary,
  ProvisionedCustomerMember,
} from "@/lib/management/customer-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type DirectCustomerWorkspaceProps = {
  workspace: string;
  canCreateDirectCustomer: boolean;
  canViewCustomers: boolean;
  canManageMembers: boolean;
};

function customerName(customer: CustomerSummary) {
  return (
    customer.individualProfile?.fullName ??
    customer.organizationProfile?.displayName ??
    customer.customerCode
  );
}

function formatDate(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return "-";

  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
  }).format(date);
}

export function DirectCustomerWorkspace({
  workspace,
  canCreateDirectCustomer,
  canViewCustomers,
  canManageMembers,
}: DirectCustomerWorkspaceProps) {
  const [customers, setCustomers] = useState<CustomerSummary[]>(
    [],
  );
  const [loading, setLoading] = useState(canViewCustomers);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [searchInput, setSearchInput] = useState("");
  const [activeSearch, setActiveSearch] = useState("");
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [showAllScoped, setShowAllScoped] = useState(false);
  const [addCustomerOpen, setAddCustomerOpen] =
    useState(false);
  const [ownerCustomer, setOwnerCustomer] =
    useState<CustomerSummary | null>(null);
  const [membersCustomer, setMembersCustomer] =
    useState<CustomerSummary | null>(null);
  const [memberRefreshVersion, setMemberRefreshVersion] =
    useState(0);

  useEffect(() => {
    if (!canViewCustomers) return;

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: "1",
      pageSize: "100",
    });

    if (activeSearch) {
      parameters.set("search", activeSearch);
    }

    void fetch(
      `/api/management/customers?${parameters.toString()}`,
      {
        cache: "no-store",
        signal: controller.signal,
      },
    )
      .then(async (response) => {
        const result = (await response.json()) as
          | CustomerListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in result
              ? result.message
              : "Customer loading failed.",
          );
        }

        if (!controller.signal.aborted) {
          setCustomers(
            (result as CustomerListResponse).items,
          );
          setError("");
        }
      })
      .catch((reason: unknown) => {
        if (
          controller.signal.aborted ||
          (reason instanceof DOMException &&
            reason.name === "AbortError")
        ) {
          return;
        }

        setError(
          reason instanceof Error
            ? reason.message
            : "The Customer directory is unavailable.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [activeSearch, canViewCustomers, refreshVersion]);

  const visibleCustomers = useMemo(
    () =>
      showAllScoped
        ? customers
        : customers.filter(
            (customer) => customer.managingDealerId === null,
          ),
    [customers, showAllScoped],
  );

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError("");
    setActiveSearch(searchInput.trim());
    setRefreshVersion((value) => value + 1);
  }

  function customerCreated(
    customer: CustomerSummary,
    provisionOwner: boolean,
  ) {
    setAddCustomerOpen(false);
    setCustomers((current) => [
      customer,
      ...current.filter((item) => item.id !== customer.id),
    ]);
    setSuccess(
      `${customerName(customer)} was created as ${customer.customerCode} under Platform management.`,
    );

    if (provisionOwner) {
      setOwnerCustomer(customer);
    }
  }

  function ownerCreated(member: ProvisionedCustomerMember) {
    const customer = ownerCustomer;
    setOwnerCustomer(null);
    setSuccess(
      `${member.user.fullName} is now the Customer Owner. Login mobile: ${member.user.mobileNumber}.`,
    );

    if (customer) {
      setCustomers((current) =>
        current.map((item) =>
          item.id === customer.id
            ? {
                ...item,
                _count: {
                  memberships:
                    (item._count?.memberships ?? 0) + 1,
                  vehicles: item._count?.vehicles ?? 0,
                  billingSubscriptions:
                    item._count?.billingSubscriptions ?? 0,
                },
              }
            : item,
        ),
      );
    }

    setMemberRefreshVersion((value) => value + 1);
  }

  const directCount = customers.filter(
    (customer) => customer.managingDealerId === null,
  ).length;

  return (
    <>
      <div className="st-scrollbar h-[calc(100vh-var(--st-topbar-height))] overflow-auto bg-[#eef2f7] p-5">
        <section className="mx-auto max-w-[1500px] rounded-[8px] bg-white p-5 shadow-sm">
          <header className="flex flex-wrap items-start justify-between gap-4 border-b border-[#e2e8f1] pb-4">
            <div>
              <h1 className="text-[19px] font-semibold text-[#344b72]">
                Direct Customer Management
              </h1>
              <p className="mt-1 text-[12px] text-[#71819c]">
                Complete Platform-managed Customers and their primary login identities.
              </p>
            </div>

            <div className="flex items-center gap-3">
              <span className="rounded-full bg-[#eaf2ff] px-3 py-1 text-[10px] font-semibold text-[#357cf4]">
                {workspace}
              </span>

              <button
                type="button"
                disabled={!canCreateDirectCustomer}
                onClick={() => setAddCustomerOpen(true)}
                className="flex h-9 items-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
              >
                <CirclePlus className="h-4 w-4" />
                Add Direct Customer
              </button>
            </div>
          </header>

          {success ? (
            <div className="mt-4 flex items-start gap-3 rounded-[5px] border border-emerald-200 bg-emerald-50 px-4 py-3 text-[12px] text-emerald-800">
              <CheckCircle2 className="mt-0.5 h-4 w-4" />
              {success}
            </div>
          ) : null}

          {error ? (
            <div className="mt-4 rounded-[5px] border border-red-200 bg-red-50 px-4 py-3 text-[12px] text-red-700">
              {error}
            </div>
          ) : null}

          <div className="mt-5 grid gap-4 md:grid-cols-3">
            <article className="rounded-[6px] border border-[#dfe6ef] p-4">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-[#8b9ab4]">
                Direct Customers
              </p>
              <p className="mt-2 text-[28px] font-semibold text-[#357cf4]">
                {directCount}
              </p>
            </article>

            <article className="rounded-[6px] border border-[#dfe6ef] p-4">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-[#8b9ab4]">
                Individuals
              </p>
              <p className="mt-2 text-[28px] font-semibold text-[#344b72]">
                {
                  customers.filter(
                    (customer) =>
                      customer.managingDealerId === null &&
                      customer.customerType === "INDIVIDUAL",
                  ).length
                }
              </p>
            </article>

            <article className="rounded-[6px] border border-[#dfe6ef] p-4">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-[#8b9ab4]">
                Organizations
              </p>
              <p className="mt-2 text-[28px] font-semibold text-[#344b72]">
                {
                  customers.filter(
                    (customer) =>
                      customer.managingDealerId === null &&
                      customer.customerType === "ORGANIZATION",
                  ).length
                }
              </p>
            </article>
          </div>

          <section className="mt-5 overflow-hidden rounded-[6px] border border-[#dfe6ef]">
            <header className="flex flex-wrap items-center justify-between gap-3 border-b border-[#e2e8f1] px-5 py-4">
              <div>
                <h2 className="text-[14px] font-semibold text-[#405779]">
                  Customer Directory
                </h2>
                <p className="mt-1 text-[10px] text-[#7c8ba5]">
                  Direct Customers are shown by default.
                </p>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() =>
                    setShowAllScoped((value) => !value)
                  }
                  className={[
                    "flex h-9 items-center gap-2 rounded-[3px] border px-3 text-[10px] font-semibold",
                    showAllScoped
                      ? "border-[#357cf4] bg-[#edf4ff] text-[#357cf4]"
                      : "border-[#cfd8e7] text-[#52698e]",
                  ].join(" ")}
                >
                  <Filter className="h-4 w-4" />
                  {showAllScoped
                    ? "All scoped Customers"
                    : "Direct only"}
                </button>

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
                      placeholder="Name, code, mobile, email"
                      className="min-w-0 flex-1 border-0 bg-transparent text-[11px] outline-none"
                    />
                    <Search className="h-4 w-4 text-[#607392]" />
                  </label>

                  <button
                    type="submit"
                    className="h-9 rounded-[3px] bg-[#357cf4] px-4 text-[11px] font-semibold text-white"
                  >
                    Search
                  </button>

                  <button
                    type="button"
                    disabled={loading}
                    onClick={() => {
                      setLoading(true);
                      setRefreshVersion((value) => value + 1);
                    }}
                    className="grid h-9 w-9 place-items-center rounded-[3px] border border-[#cfd8e7] text-[#52698e]"
                  >
                    <RefreshCw
                      className={[
                        "h-4 w-4",
                        loading ? "animate-spin" : "",
                      ].join(" ")}
                    />
                  </button>
                </form>
              </div>
            </header>

            {!canViewCustomers ? (
              <div className="p-10 text-center text-[12px] text-[#7c8ba5]">
                This account does not have customer.view permission.
              </div>
            ) : loading ? (
              <div className="flex min-h-[280px] items-center justify-center gap-2 text-[12px] text-[#71819c]">
                <LoaderCircle className="h-5 w-5 animate-spin text-[#357cf4]" />
                Loading Customers
              </div>
            ) : visibleCustomers.length === 0 ? (
              <div className="p-12 text-center">
                <UsersRound className="mx-auto h-10 w-10 text-[#b5c2d5]" />
                <p className="mt-3 text-[12px] font-semibold text-[#52698e]">
                  No matching Customers
                </p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[1120px] text-left text-[11px]">
                  <thead className="bg-[#edf2f8] text-[#405779]">
                    <tr>
                      {[
                        "Customer",
                        "Code",
                        "Type",
                        "Management",
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
                          <div className="flex items-center gap-2">
                            {customer.customerType ===
                            "INDIVIDUAL" ? (
                              <UserRound className="h-4 w-4 text-[#357cf4]" />
                            ) : (
                              <Building2 className="h-4 w-4 text-[#357cf4]" />
                            )}
                            <div>
                              <p className="font-semibold text-[#405779]">
                                {customerName(customer)}
                              </p>
                              <p className="mt-1 text-[9px] text-[#8b9ab4]">
                                {customer.primaryEmail || "-"}
                              </p>
                            </div>
                          </div>
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
                              customer.managingDealerId === null
                                ? "bg-indigo-50 text-indigo-700"
                                : "bg-amber-50 text-amber-700",
                            ].join(" ")}
                          >
                            {customer.managingDealerId === null
                              ? "Platform / Direct"
                              : customer.managingDealer?.name ??
                                "Dealer"}
                          </span>
                        </td>

                        <td className="px-4 py-4">
                          {customer.primaryMobile || "-"}
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
                              onClick={() =>
                                setMembersCustomer(customer)
                              }
                              className="h-8 rounded-[3px] border border-[#cfd8e7] px-3 text-[10px] font-semibold text-[#52698e]"
                            >
                              Members
                            </button>

                            <button
                              type="button"
                              disabled={!canManageMembers}
                              onClick={() =>
                                setOwnerCustomer(customer)
                              }
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
        </section>
      </div>

      {addCustomerOpen ? (
        <AddDirectCustomerModal
          onClose={() => setAddCustomerOpen(false)}
          onCreated={customerCreated}
        />
      ) : null}

      {membersCustomer ? (
        <CustomerMembersModal
          customer={membersCustomer}
          canManageMembers={canManageMembers}
          refreshVersion={memberRefreshVersion}
          onAddOwner={() =>
            setOwnerCustomer(membersCustomer)
          }
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