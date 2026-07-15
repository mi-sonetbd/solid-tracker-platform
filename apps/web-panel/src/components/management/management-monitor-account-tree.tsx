"use client";

import {
  Building2,
  ChevronDown,
  ChevronRight,
  Download,
  LoaderCircle,
  RefreshCw,
  Search,
  UserRound,
  UsersRound,
} from "lucide-react";
import {
  useMemo,
  useState,
} from "react";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type { DealerSummary } from "@/lib/management/dealer-types";
import {
  customerDisplayName,
  type ManagementMonitorScope,
} from "@/lib/management/monitor-types";

type ManagementMonitorAccountTreeProps = {
  workspace: string;
  dealers: DealerSummary[];
  customers: CustomerSummary[];
  loading: boolean;
  error: string;
  selectedScope: ManagementMonitorScope;
  onSelectScope: (
    scope: ManagementMonitorScope,
  ) => void;
  onRefresh: () => void;
};

function selectedClass(
  selected: boolean,
) {
  return selected
    ? "bg-[#eaf2ff] text-[#357cf4]"
    : "text-[#52698e] hover:bg-[#f1f5fb]";
}

function customerCountText(
  customer: CustomerSummary,
) {
  return `${customer._count?.vehicles ?? 0}`;
}

export function ManagementMonitorAccountTree({
  workspace,
  dealers,
  customers,
  loading,
  error,
  selectedScope,
  onSelectScope,
  onRefresh,
}: ManagementMonitorAccountTreeProps) {
  const platformWorkspace =
    workspace === "SUPER_ADMIN" ||
    workspace === "ADMIN";
  const [query, setQuery] = useState("");
  const [rootOpen, setRootOpen] = useState(true);
  const [directOpen, setDirectOpen] =
    useState(true);
  const [dealersOpen, setDealersOpen] =
    useState(true);
  const [openDealers, setOpenDealers] =
    useState<Set<string>>(new Set());

  const normalizedQuery =
    query.trim().toLowerCase();

  const directCustomers = useMemo(
    () =>
      customers
        .filter(
          (customer) =>
            customer.managingDealerId === null,
        )
        .filter((customer) => {
          if (!normalizedQuery) return true;

          return [
            customerDisplayName(customer),
            customer.customerCode,
            customer.primaryMobile,
            customer.primaryEmail,
          ]
            .filter(Boolean)
            .join(" ")
            .toLowerCase()
            .includes(normalizedQuery);
        })
        .sort((left, right) =>
          customerDisplayName(left).localeCompare(
            customerDisplayName(right),
          ),
        ),
    [customers, normalizedQuery],
  );

  const dealerRows = useMemo(
    () =>
      dealers
        .map((dealer) => {
          const dealerCustomers = customers
            .filter(
              (customer) =>
                customer.managingDealerId ===
                dealer.id,
            )
            .filter((customer) => {
              if (!normalizedQuery) return true;

              return [
                customerDisplayName(customer),
                customer.customerCode,
                customer.primaryMobile,
                customer.primaryEmail,
              ]
                .filter(Boolean)
                .join(" ")
                .toLowerCase()
                .includes(normalizedQuery);
            })
            .sort((left, right) =>
              customerDisplayName(
                left,
              ).localeCompare(
                customerDisplayName(right),
              ),
            );

          const dealerMatches = [
            dealer.name,
            dealer.code,
            dealer.dealerProfile.dealerCode,
          ]
            .join(" ")
            .toLowerCase()
            .includes(normalizedQuery);

          return {
            dealer,
            customers: dealerCustomers,
            visible:
              !normalizedQuery ||
              dealerMatches ||
              dealerCustomers.length > 0,
          };
        })
        .filter((row) => row.visible)
        .sort((left, right) =>
          left.dealer.name.localeCompare(
            right.dealer.name,
          ),
        ),
    [customers, dealers, normalizedQuery],
  );

  const scopedRootLabel =
    platformWorkspace
      ? "Solid Tracker"
      : dealers.length === 1
        ? dealers[0].name
        : "Managed Accounts";

  function toggleDealer(dealerId: string) {
    setOpenDealers((current) => {
      const next = new Set(current);

      if (next.has(dealerId)) {
        next.delete(dealerId);
      } else {
        next.add(dealerId);
      }

      return next;
    });
  }

  function customerRow(
    customer: CustomerSummary,
    depthClass: string,
  ) {
    const scope: ManagementMonitorScope = {
      key: `customer:${customer.id}`,
      type: "CUSTOMER",
      id: customer.id,
      label: customerDisplayName(customer),
    };

    return (
      <button
        key={customer.id}
        type="button"
        onClick={() => onSelectScope(scope)}
        className={[
          "flex min-h-8 w-full items-center gap-2 rounded-[3px] py-1 pr-2 text-left",
          depthClass,
          selectedClass(
            selectedScope.key === scope.key,
          ),
        ].join(" ")}
      >
        <UserRound className="h-4 w-4 shrink-0 text-[#29a8ef]" />
        <span className="min-w-0 flex-1 truncate">
          {customerDisplayName(customer)}
        </span>
        <span className="shrink-0 text-[9px] text-[#8b9ab4]">
          ({customerCountText(customer)})
        </span>
      </button>
    );
  }

  const rootScope: ManagementMonitorScope = {
    key: "platform",
    type: "PLATFORM",
    id: null,
    label: scopedRootLabel,
  };

  return (
    <aside className="flex h-full w-[300px] min-h-0 flex-col border-r border-[#dfe6ef] bg-white">
      <div className="flex h-12 items-center justify-between border-b border-[#e2e8f1] px-4">
        <h2 className="text-[13px] font-semibold text-[#344b72]">
          Account List
        </h2>

        <button
          type="button"
          onClick={onRefresh}
          disabled={loading}
          aria-label="Refresh account hierarchy"
          className="text-[#607392] disabled:opacity-50"
        >
          <RefreshCw
            className={[
              "h-4 w-4",
              loading ? "animate-spin" : "",
            ].join(" ")}
          />
        </button>
      </div>

      <div className="p-3">
        <label className="flex h-8 items-center rounded-[3px] border border-[#cfd8e7]">
          <input
            value={query}
            onChange={(event) =>
              setQuery(event.target.value)
            }
            className="min-w-0 flex-1 border-0 bg-transparent px-3 text-[11px] outline-none placeholder:text-[#8b9ab4]"
            placeholder="Customer, Dealer, code, or mobile"
          />
          <Search className="h-4 w-4 text-[#607392]" />
          <span className="grid h-8 w-10 place-items-center bg-[#357cf4] text-white">
            <Download className="h-4 w-4" />
          </span>
        </label>
      </div>

      <div className="st-scrollbar flex-1 overflow-y-auto px-3 pb-3 text-[11px]">
        <div
          className={[
            "flex min-h-9 items-center rounded-[3px] font-semibold",
            selectedClass(
              selectedScope.key === rootScope.key,
            ),
          ].join(" ")}
        >
          <button
            type="button"
            onClick={() =>
              setRootOpen((value) => !value)
            }
            aria-label={
              rootOpen
                ? "Collapse root hierarchy"
                : "Expand root hierarchy"
            }
            className="grid h-9 w-8 shrink-0 place-items-center"
          >
            {rootOpen ? (
              <ChevronDown className="h-3.5 w-3.5" />
            ) : (
              <ChevronRight className="h-3.5 w-3.5" />
            )}
          </button>

          <button
            type="button"
            onClick={() =>
              onSelectScope(rootScope)
            }
            className="flex min-w-0 flex-1 items-center gap-2 py-2 pr-2 text-left"
          >
            <UsersRound className="h-4 w-4 shrink-0 text-[#ff9b24]" />
            <span className="min-w-0 flex-1 truncate">
              {scopedRootLabel}
            </span>
            <span className="shrink-0 text-[9px] text-[#8b9ab4]">
              ({customers.length})
            </span>
          </button>
        </div>

        {loading ? (
          <div className="flex min-h-32 items-center justify-center gap-2 text-[10px] text-[#71819c]">
            <LoaderCircle className="h-4 w-4 animate-spin text-[#357cf4]" />
            Loading hierarchy
          </div>
        ) : error ? (
          <div className="mt-2 rounded-[4px] border border-red-200 bg-red-50 p-3 text-[10px] leading-5 text-red-700">
            {error}
          </div>
        ) : rootOpen ? (
          <div className="ml-4 mt-1 space-y-1">
            {platformWorkspace ? (
              <>
                <div
                  className={[
                    "flex min-h-8 items-center rounded-[3px]",
                    selectedClass(
                      selectedScope.key === "direct",
                    ),
                  ].join(" ")}
                >
                  <button
                    type="button"
                    onClick={() =>
                      setDirectOpen(
                        (value) => !value,
                      )
                    }
                    className="grid h-8 w-7 shrink-0 place-items-center"
                    aria-label={
                      directOpen
                        ? "Collapse direct Customers"
                        : "Expand direct Customers"
                    }
                  >
                    {directOpen ? (
                      <ChevronDown className="h-3 w-3" />
                    ) : (
                      <ChevronRight className="h-3 w-3" />
                    )}
                  </button>

                  <button
                    type="button"
                    onClick={() =>
                      onSelectScope({
                        key: "direct",
                        type: "DIRECT",
                        id: null,
                        label: "Direct Customers",
                      })
                    }
                    className="flex min-w-0 flex-1 items-center gap-2 py-1 pr-2 text-left"
                  >
                    <Building2 className="h-4 w-4 text-[#ff9b24]" />
                    <span className="min-w-0 flex-1 truncate">
                      Direct Customers
                    </span>
                    <span className="text-[9px] text-[#8b9ab4]">
                      ({directCustomers.length})
                    </span>
                  </button>
                </div>

                {directOpen ? (
                  <div className="space-y-1">
                    {directCustomers.map(
                      (customer) =>
                        customerRow(
                          customer,
                          "pl-10",
                        ),
                    )}

                    {directCustomers.length === 0 ? (
                      <p className="py-2 pl-10 text-[9px] text-[#9aa8bd]">
                        No direct Customer
                      </p>
                    ) : null}
                  </div>
                ) : null}

                <div className="flex min-h-8 items-center rounded-[3px] text-[#52698e] hover:bg-[#f1f5fb]">
                  <button
                    type="button"
                    onClick={() =>
                      setDealersOpen(
                        (value) => !value,
                      )
                    }
                    className="grid h-8 w-7 shrink-0 place-items-center"
                    aria-label={
                      dealersOpen
                        ? "Collapse Dealers"
                        : "Expand Dealers"
                    }
                  >
                    {dealersOpen ? (
                      <ChevronDown className="h-3 w-3" />
                    ) : (
                      <ChevronRight className="h-3 w-3" />
                    )}
                  </button>

                  <span className="flex min-w-0 flex-1 items-center gap-2 py-1 pr-2">
                    <UsersRound className="h-4 w-4 text-[#ff9b24]" />
                    <span className="min-w-0 flex-1 truncate">
                      Dealers
                    </span>
                    <span className="text-[9px] text-[#8b9ab4]">
                      ({dealerRows.length})
                    </span>
                  </span>
                </div>
              </>
            ) : null}

            {(!platformWorkspace || dealersOpen) ? (
              <div
                className={[
                  "space-y-1",
                  platformWorkspace ? "pl-3" : "",
                ].join(" ")}
              >
                {dealerRows.map(
                  ({ dealer, customers: items }) => {
                    const open =
                      openDealers.has(dealer.id) ||
                      Boolean(normalizedQuery);
                    const dealerScope: ManagementMonitorScope =
                      {
                        key: `dealer:${dealer.id}`,
                        type: "DEALER",
                        id: dealer.id,
                        label: dealer.name,
                      };

                    return (
                      <div key={dealer.id}>
                        <div
                          className={[
                            "flex min-h-8 items-center rounded-[3px]",
                            selectedClass(
                              selectedScope.key ===
                                dealerScope.key,
                            ),
                          ].join(" ")}
                        >
                          <button
                            type="button"
                            onClick={() =>
                              toggleDealer(dealer.id)
                            }
                            className="grid h-8 w-7 shrink-0 place-items-center"
                            aria-label={
                              open
                                ? `Collapse ${dealer.name}`
                                : `Expand ${dealer.name}`
                            }
                          >
                            {open ? (
                              <ChevronDown className="h-3 w-3" />
                            ) : (
                              <ChevronRight className="h-3 w-3" />
                            )}
                          </button>

                          <button
                            type="button"
                            onClick={() =>
                              onSelectScope(
                                dealerScope,
                              )
                            }
                            className="flex min-w-0 flex-1 items-center gap-2 py-1 pr-2 text-left"
                          >
                            <Building2 className="h-4 w-4 shrink-0 text-[#ff9b24]" />
                            <span className="min-w-0 flex-1 truncate">
                              {dealer.name}
                            </span>
                            <span className="shrink-0 text-[9px] text-[#8b9ab4]">
                              ({items.length})
                            </span>
                          </button>
                        </div>

                        {open ? (
                          <div className="space-y-1">
                            {items.map((customer) =>
                              customerRow(
                                customer,
                                "pl-10",
                              ),
                            )}

                            {items.length === 0 ? (
                              <p className="py-2 pl-10 text-[9px] text-[#9aa8bd]">
                                No scoped Customer
                              </p>
                            ) : null}
                          </div>
                        ) : null}
                      </div>
                    );
                  },
                )}

                {dealerRows.length === 0 ? (
                  <p className="py-3 pl-7 text-[9px] text-[#9aa8bd]">
                    No Dealer in this scope
                  </p>
                ) : null}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
    </aside>
  );
}