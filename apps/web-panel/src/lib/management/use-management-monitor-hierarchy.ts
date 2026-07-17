"use client";

import {
  useEffect,
  useMemo,
  useState,
} from "react";
import type {
  CustomerListResponse,
  CustomerSummary,
} from "@/lib/management/customer-types";
import type {
  DealerListResponse,
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";

type UseManagementMonitorHierarchyInput = {
  canViewDealers: boolean;
  canViewCustomers: boolean;
};

async function readResponse<T extends object>(
  response: Response,
  fallback: string,
): Promise<T> {
  const payload = (await response.json()) as
    | T
    | ManagementApiError;

  if (!response.ok) {
    throw new Error(
      "message" in payload
        ? payload.message
        : fallback,
    );
  }

  return payload as T;
}

async function loadDealers(
  signal: AbortSignal,
): Promise<DealerSummary[]> {
  const firstResponse = await fetch(
    "/api/management/dealers?page=1&pageSize=100",
    {
      cache: "no-store",
      signal,
    },
  );
  const first = await readResponse<DealerListResponse>(
    firstResponse,
    "Dealer hierarchy loading failed.",
  );

  if (first.totalPages <= 1) {
    return first.items;
  }

  const remainingPages = await Promise.all(
    Array.from(
      { length: first.totalPages - 1 },
      (_, index) => index + 2,
    ).map(async (page) => {
      const response = await fetch(
        `/api/management/dealers?page=${page}&pageSize=100`,
        {
          cache: "no-store",
          signal,
        },
      );

      return readResponse<DealerListResponse>(
        response,
        "Dealer hierarchy loading failed.",
      );
    }),
  );

  return [
    ...first.items,
    ...remainingPages.flatMap((page) => page.items),
  ];
}

async function loadCustomers(
  signal: AbortSignal,
): Promise<CustomerSummary[]> {
  const firstResponse = await fetch(
    "/api/management/customers?page=1&pageSize=100",
    {
      cache: "no-store",
      signal,
    },
  );
  const first = await readResponse<CustomerListResponse>(
    firstResponse,
    "Customer hierarchy loading failed.",
  );

  if (first.totalPages <= 1) {
    return first.items;
  }

  const remainingPages = await Promise.all(
    Array.from(
      { length: first.totalPages - 1 },
      (_, index) => index + 2,
    ).map(async (page) => {
      const response = await fetch(
        `/api/management/customers?page=${page}&pageSize=100`,
        {
          cache: "no-store",
          signal,
        },
      );

      return readResponse<CustomerListResponse>(
        response,
        "Customer hierarchy loading failed.",
      );
    }),
  );

  return [
    ...first.items,
    ...remainingPages.flatMap((page) => page.items),
  ];
}

export function useManagementMonitorHierarchy({
  canViewDealers,
  canViewCustomers,
}: UseManagementMonitorHierarchyInput) {
  const [dealers, setDealers] = useState<DealerSummary[]>(
    [],
  );
  const [customers, setCustomers] = useState<
    CustomerSummary[]
  >([]);
  const [loading, setLoading] = useState(
    canViewDealers || canViewCustomers,
  );
  const [error, setError] = useState("");
  const [refreshVersion, setRefreshVersion] =
    useState(0);

  useEffect(() => {
    if (!canViewDealers && !canViewCustomers) {
      return;
    }

    const controller = new AbortController();

    void Promise.all([
      canViewDealers
        ? loadDealers(controller.signal)
        : Promise.resolve([]),
      canViewCustomers
        ? loadCustomers(controller.signal)
        : Promise.resolve([]),
    ])
      .then(([dealerItems, customerItems]) => {
        if (controller.signal.aborted) return;

        setDealers(dealerItems);
        setCustomers(customerItems);
        setError("");
      })
      .catch((requestError: unknown) => {
        if (
          controller.signal.aborted ||
          (requestError instanceof DOMException &&
            requestError.name === "AbortError")
        ) {
          return;
        }

        setError(
          requestError instanceof Error
            ? requestError.message
            : "The account hierarchy could not be loaded.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [
    canViewCustomers,
    canViewDealers,
    refreshVersion,
  ]);

  const synthesizedDealers = useMemo(() => {
    const existingIds = new Set(
      dealers.map((dealer) => dealer.id),
    );
    const additions = new Map<
      string,
      DealerSummary
    >();

    for (const customer of customers) {
      const dealer = customer.managingDealer;

      if (
        !dealer ||
        existingIds.has(dealer.id) ||
        additions.has(dealer.id)
      ) {
        continue;
      }

      additions.set(dealer.id, {
        id: dealer.id,
        code: dealer.code,
        type: "DEALER",
        name: dealer.name,
        legalName: null,
        status: "ACTIVE",
        zoneId: null,
        zone: null,
        dealerProfile: {
          id: dealer.id,
          dealerCode: dealer.code,
          tradeLicenseNumber: null,
          taxIdentificationNumber: null,
          contactMobile: null,
          contactEmail: null,
          commissionEnabled: false,
        },
        createdAt: "",
        updatedAt: "",
        _count: {
          memberships: 0,
          customerGroups: 0,
          managedCustomers: customers.filter(
            (item) =>
              item.managingDealerId === dealer.id,
          ).length,
        },
      });
    }

    return [
      ...dealers,
      ...Array.from(additions.values()),
    ].sort((left, right) =>
      left.name.localeCompare(right.name),
    );
  }, [customers, dealers]);

  const permissionError =
    !canViewDealers && !canViewCustomers
      ? "This account has neither dealer.view nor customer.view permission."
      : "";

  return {
    dealers: synthesizedDealers,
    customers,
    loading:
      canViewDealers || canViewCustomers
        ? loading
        : false,
    error: permissionError || error,
    refresh() {
      setLoading(true);
      setRefreshVersion((current) => current + 1);
    },
  };
}