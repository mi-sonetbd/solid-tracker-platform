"use client";

import {
  useEffect,
  useMemo,
  useState,
} from "react";
import type {
  VehicleListResponse,
  VehicleSummary,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";
import {
  customerDisplayName,
  type ManagementMonitorScope,
  type ManagementMonitorVehicle,
} from "@/lib/management/monitor-types";

type UseManagementMonitorAssetsInput = {
  scope: ManagementMonitorScope;
  customers: CustomerSummary[];
  hierarchyLoading: boolean;
  canViewVehicles: boolean;
};

async function readVehiclePage(
  customerId: string,
  page: number,
  signal: AbortSignal,
): Promise<VehicleListResponse> {
  const parameters = new URLSearchParams({
    customerId,
    page: String(page),
    pageSize: "100",
  });
  const response = await fetch(
    `/api/management/vehicles?${parameters.toString()}`,
    {
      cache: "no-store",
      signal,
    },
  );
  const payload = (await response.json()) as
    | VehicleListResponse
    | ManagementApiError;

  if (!response.ok) {
    throw new Error(
      "message" in payload
        ? payload.message
        : "Scoped vehicle loading failed.",
    );
  }

  return payload as VehicleListResponse;
}

async function loadCustomerVehicles(
  customer: CustomerSummary,
  signal: AbortSignal,
): Promise<ManagementMonitorVehicle[]> {
  const first = await readVehiclePage(
    customer.id,
    1,
    signal,
  );

  const additionalPages =
    first.totalPages <= 1
      ? []
      : await Promise.all(
          Array.from(
            { length: first.totalPages - 1 },
            (_, index) => index + 2,
          ).map((page) =>
            readVehiclePage(
              customer.id,
              page,
              signal,
            ),
          ),
        );

  const items: VehicleSummary[] = [
    ...first.items,
    ...additionalPages.flatMap(
      (page) => page.items,
    ),
  ];

  return items.map((vehicle) => ({
    ...vehicle,
    monitorCustomer: {
      id: customer.id,
      code: customer.customerCode,
      name: customerDisplayName(customer),
      managingDealerId:
        customer.managingDealerId,
      managingDealerName:
        customer.managingDealer?.name ?? null,
    },
  }));
}

function customersForScope(
  scope: ManagementMonitorScope,
  customers: CustomerSummary[],
) {
  if (scope.type === "CUSTOMER") {
    return customers.filter(
      (customer) => customer.id === scope.id,
    );
  }

  if (scope.type === "DEALER") {
    return customers.filter(
      (customer) =>
        customer.managingDealerId === scope.id,
    );
  }

  if (scope.type === "DIRECT") {
    return customers.filter(
      (customer) =>
        customer.managingDealerId === null,
    );
  }

  return customers;
}

async function loadInBatches(
  customers: CustomerSummary[],
  signal: AbortSignal,
) {
  const result: ManagementMonitorVehicle[] = [];
  const batchSize = 8;

  for (
    let index = 0;
    index < customers.length;
    index += batchSize
  ) {
    if (signal.aborted) break;

    const batch = customers.slice(
      index,
      index + batchSize,
    );
    const vehicles = await Promise.all(
      batch.map((customer) =>
        loadCustomerVehicles(customer, signal),
      ),
    );

    result.push(...vehicles.flat());
  }

  return result;
}

export function useManagementMonitorAssets({
  scope,
  customers,
  hierarchyLoading,
  canViewVehicles,
}: UseManagementMonitorAssetsInput) {
  const [vehicles, setVehicles] = useState<
    ManagementMonitorVehicle[]
  >([]);
  const [loading, setLoading] = useState(
    canViewVehicles,
  );
  const [error, setError] = useState("");
  const [refreshVersion, setRefreshVersion] =
    useState(0);

  const scopedCustomers = useMemo(
    () => customersForScope(scope, customers),
    [customers, scope],
  );

  useEffect(() => {
    if (!canViewVehicles || hierarchyLoading) {
      return;
    }

    const controller = new AbortController();

    void Promise.resolve()
      .then(() =>
        loadInBatches(
          scopedCustomers,
          controller.signal,
        ),
      )
      .then((items) => {
        if (controller.signal.aborted) return;

        setVehicles(
          items.sort((left, right) => {
            const leftName =
              left.registrationNumber ??
              left.vehicleCode;
            const rightName =
              right.registrationNumber ??
              right.vehicleCode;

            return leftName.localeCompare(rightName);
          }),
        );
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

        setVehicles([]);
        setError(
          requestError instanceof Error
            ? requestError.message
            : "The scoped vehicle list could not be loaded.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [
    canViewVehicles,
    hierarchyLoading,
    refreshVersion,
    scopedCustomers,
  ]);

  return {
    vehicles:
      canViewVehicles ? vehicles : [],
    loading:
      canViewVehicles ? loading : false,
    error: canViewVehicles
      ? error
      : "This account does not have vehicle.view permission.",
    prepareScopeChange() {
      setLoading(true);
      setError("");
    },
    refresh() {
      setLoading(true);
      setError("");
      setRefreshVersion((current) => current + 1);
    },
  };
}