import "server-only";

import { authConfig } from "@/lib/auth/auth-config";
import type {
  CreateDealerInput,
  DealerListResponse,
  DealerSummary,
} from "@/lib/management/dealer-types";

export type DealerBackendResult<T> =
  | {
      ok: true;
      status: number;
      data: T;
    }
  | {
      ok: false;
      status: number;
      message: string;
      details?: unknown;
    };

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

async function dealerRequest<T>(
  accessToken: string,
  path: string,
  init: RequestInit,
): Promise<DealerBackendResult<T>> {
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
          "The Solid Tracker Dealer API rejected the request.",
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
          : "The Solid Tracker Dealer API is unavailable.",
    };
  }
}

export function backendListDealers(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    search?: string;
  },
) {
  const parameters = new URLSearchParams({
    page: String(query.page),
    pageSize: String(query.pageSize),
  });

  if (query.search) {
    parameters.set("search", query.search);
  }

  return dealerRequest<DealerListResponse>(
    accessToken,
    `/dealers?${parameters.toString()}`,
    {
      method: "GET",
    },
  );
}

export function backendCreateDealer(
  accessToken: string,
  input: CreateDealerInput,
) {
  return dealerRequest<DealerSummary>(
    accessToken,
    "/dealers",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}