import "server-only";

import { authConfig } from "@/lib/auth/auth-config";
import type {
  CreateCustomerOwnerInput,
  CreateIndividualCustomerInput,
  CreateOrganizationCustomerInput,
  CustomerListResponse,
  CustomerMember,
  CustomerSummary,
  ProvisionedCustomerMember,
} from "@/lib/management/customer-types";
import type { ManagementBackendResult } from "@/lib/management/dealer-types";

async function parseResponse(response: Response): Promise<unknown> {
  const contentType = response.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    return response.json();
  }

  const text = await response.text();
  return text || null;
}

function errorMessage(payload: unknown, fallback: string) {
  if (
    payload &&
    typeof payload === "object" &&
    "message" in payload
  ) {
    const value = (payload as { message?: unknown }).message;

    if (Array.isArray(value)) {
      return value
        .filter((item) => typeof item === "string")
        .join(" ");
    }

    if (typeof value === "string") {
      return value;
    }
  }

  return fallback;
}

async function customerRequest<T>(
  accessToken: string,
  path: string,
  init: RequestInit,
): Promise<ManagementBackendResult<T>> {
  try {
    const response = await fetch(
      `${authConfig.apiBaseUrl}${path}`,
      {
        ...init,
        cache: "no-store",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${accessToken}`,
          ...init.headers,
        },
      },
    );

    const payload = await parseResponse(response);

    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        message: errorMessage(
          payload,
          "The Solid Tracker Customer API rejected the request.",
        ),
        details: payload,
      };
    }

    return {
      ok: true,
      status: response.status,
      data: payload as T,
    };
  } catch (error) {
    return {
      ok: false,
      status: 503,
      message:
        error instanceof Error
          ? error.message
          : "The Solid Tracker Customer API is unavailable.",
    };
  }
}

export function backendListCustomers(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    search?: string;
    customerType?: string;
    status?: string;
  },
) {
  const parameters = new URLSearchParams({
    page: String(query.page),
    pageSize: String(query.pageSize),
  });

  if (query.search) parameters.set("search", query.search);
  if (query.customerType) {
    parameters.set("customerType", query.customerType);
  }
  if (query.status) parameters.set("status", query.status);

  return customerRequest<CustomerListResponse>(
    accessToken,
    `/customers?${parameters.toString()}`,
    {
      method: "GET",
    },
  );
}

export function backendCreateIndividualCustomer(
  accessToken: string,
  input: CreateIndividualCustomerInput,
) {
  return customerRequest<CustomerSummary>(
    accessToken,
    "/customers/individual",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendCreateOrganizationCustomer(
  accessToken: string,
  input: CreateOrganizationCustomerInput,
) {
  return customerRequest<CustomerSummary>(
    accessToken,
    "/customers/organization",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendListCustomerMembers(
  accessToken: string,
  customerId: string,
) {
  return customerRequest<CustomerMember[]>(
    accessToken,
    `/customers/${customerId}/members`,
    {
      method: "GET",
    },
  );
}

export function backendCreateCustomerOwner(
  accessToken: string,
  customerId: string,
  input: CreateCustomerOwnerInput,
) {
  return customerRequest<ProvisionedCustomerMember>(
    accessToken,
    `/customers/${customerId}/members`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}