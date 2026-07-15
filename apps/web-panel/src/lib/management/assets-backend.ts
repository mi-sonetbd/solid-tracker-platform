import "server-only";

import { authConfig } from "@/lib/auth/auth-config";
import type {
  AllocateDeviceInput,
  BulkDeviceRegistrationResult,
  BulkRegisterDevicesInput,
  CreateDeviceModelInput,
  CreateVehicleInput,
  DealerDeviceAllocationResult,
  DeviceInstallationResult,
  DeviceListResponse,
  DeviceModelListResponse,
  DeviceModelSummary,
  DeviceSummary,
  InstallDeviceInput,
  RegisterDeviceInput,
  TransferDevicesInput,
  TransferDevicesResult,
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

export function backendListDeviceModels(
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

  if (query.search) parameters.set("search", query.search);

  return assetRequest<DeviceModelListResponse>(
    accessToken,
    `/device-models?${parameters.toString()}`,
    { method: "GET" },
  );
}

export function backendCreateDeviceModel(
  accessToken: string,
  input: CreateDeviceModelInput,
) {
  return assetRequest<DeviceModelSummary>(
    accessToken,
    "/device-models",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendListVehicles(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    customerId?: string;
    search?: string;
  },
) {
  const parameters = new URLSearchParams({
    page: String(query.page),
    pageSize: String(query.pageSize),
  });

  if (query.customerId) {
    parameters.set("customerId", query.customerId);
  }
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
  return assetRequest<VehicleSummary>(
    accessToken,
    "/vehicles",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendListDevices(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    search?: string;
    lifecycleStatus?: string;
    deviceModelId?: string;
    dealerOrganizationId?: string;
    customerId?: string;
    directCustomers?: boolean;
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
  if (query.deviceModelId) {
    parameters.set("deviceModelId", query.deviceModelId);
  }
  if (query.dealerOrganizationId) {
    parameters.set(
      "dealerOrganizationId",
      query.dealerOrganizationId,
    );
  }
  if (query.customerId) {
    parameters.set("customerId", query.customerId);
  }
  if (query.directCustomers) {
    parameters.set("directCustomers", "true");
  }

  return assetRequest<DeviceListResponse>(
    accessToken,
    `/devices?${parameters.toString()}`,
    { method: "GET" },
  );
}

export function backendRegisterDevice(
  accessToken: string,
  input: RegisterDeviceInput,
) {
  return assetRequest<DeviceSummary>(
    accessToken,
    "/devices",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendBulkRegisterDevices(
  accessToken: string,
  input: BulkRegisterDevicesInput,
) {
  return assetRequest<BulkDeviceRegistrationResult>(
    accessToken,
    "/devices/bulk",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendTransferDevices(
  accessToken: string,
  input: TransferDevicesInput,
) {
  return assetRequest<TransferDevicesResult>(
    accessToken,
    "/devices/transfer",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendAllocateDevice(
  accessToken: string,
  deviceId: string,
  input: AllocateDeviceInput,
) {
  return assetRequest<DealerDeviceAllocationResult>(
    accessToken,
    `/devices/${deviceId}/allocate`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
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