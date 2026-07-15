import "server-only";

import { authConfig } from "@/lib/auth/auth-config";
import type {
  CreateVehicleInput,
  DeviceInstallationResult,
  DeviceListResponse,
  InstallDeviceInput,
  VehicleListResponse,
  VehicleSummary,
} from "@/lib/management/asset-types";
import type { ManagementBackendResult } from "@/lib/management/dealer-types";

async function parseResponse(response: Response): Promise<unknown> {
  const text = await response.text();

  if (!text) return null;

  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text;
  }
}

function errorMessage(payload: unknown, fallback: string) {
  if (payload && typeof payload === "object" && "message" in payload) {
    const value = (payload as { message?: unknown }).message;

    if (Array.isArray(value)) {
      return value.filter((item) => typeof item === "string").join(" ");
    }

    if (typeof value === "string") {
      return value;
    }
  }

  return fallback;
}

async function assetRequest<T>(
  accessToken: string,
  path: string,
  init: RequestInit,
): Promise<ManagementBackendResult<T>> {
  try {
    const response = await fetch(`${authConfig.apiBaseUrl}${path}`, {
      ...init,
      cache: "no-store",
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${accessToken}`,
        ...init.headers,
      },
    });

    const payload = await parseResponse(response);

    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        message: errorMessage(
          payload,
          "The Solid Tracker Asset API rejected the request.",
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
          : "The Solid Tracker Asset API is unavailable.",
    };
  }
}

export function backendListVehicles(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    customerId: string;
    search?: string;
  },
) {
  const parameters = new URLSearchParams({
    page: String(query.page),
    pageSize: String(query.pageSize),
    customerId: query.customerId,
  });

  if (query.search) parameters.set("search", query.search);

  return assetRequest<VehicleListResponse>(
    accessToken,
    `/vehicles?${parameters.toString()}`,
    { method: "GET" },
  );
}

export function backendCreateVehicle(
  accessToken: string,
  input: CreateVehicleInput,
) {
  return assetRequest<VehicleSummary>(accessToken, "/vehicles", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(input),
  });
}

export function backendListDevices(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    search?: string;
    lifecycleStatus?: string;
    dealerOrganizationId?: string;
  },
) {
  const parameters = new URLSearchParams({
    page: String(query.page),
    pageSize: String(query.pageSize),
  });

  if (query.search) parameters.set("search", query.search);
  if (query.lifecycleStatus) {
    parameters.set("lifecycleStatus", query.lifecycleStatus);
  }
  if (query.dealerOrganizationId) {
    parameters.set("dealerOrganizationId", query.dealerOrganizationId);
  }

  return assetRequest<DeviceListResponse>(
    accessToken,
    `/devices?${parameters.toString()}`,
    { method: "GET" },
  );
}

export function backendInstallDevice(
  accessToken: string,
  deviceId: string,
  input: InstallDeviceInput,
) {
  return assetRequest<DeviceInstallationResult>(
    accessToken,
    `/devices/${deviceId}/install`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}