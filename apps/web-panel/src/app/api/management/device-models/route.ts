import { NextRequest } from "next/server";
import type {
  CreateDeviceModelInput,
  DeviceNetworkType,
} from "@/lib/management/asset-types";
import {
  backendCreateDeviceModel,
  backendListDeviceModels,
} from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const networkTypes = [
  "GSM_2G",
  "UMTS_3G",
  "LTE_4G",
  "LTE_5G",
  "LORA",
  "SATELLITE",
  "OTHER",
] as const;

function positiveInteger(
  value: string | null,
  fallback: number,
  maximum: number,
) {
  const parsed = Number(value ?? fallback);

  if (!Number.isInteger(parsed) || parsed < 1 || parsed > maximum) {
    return fallback;
  }

  return parsed;
}

function requiredText(
  value: unknown,
  fieldName: string,
  minimumLength: number,
  maximumLength: number,
) {
  if (typeof value !== "string") {
    throw new Error(`${fieldName} is required.`);
  }

  const normalized = value.trim();

  if (
    normalized.length < minimumLength ||
    normalized.length > maximumLength
  ) {
    throw new Error(
      `${fieldName} must contain ${minimumLength} to ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseModel(payload: unknown): CreateDeviceModelInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Device Model request is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const networkType = requiredText(
    value.networkType,
    "Network type",
    2,
    30,
  );

  if (
    !networkTypes.includes(
      networkType as (typeof networkTypes)[number],
    )
  ) {
    throw new Error("Select a valid network type.");
  }

  const capabilities =
    value.capabilities &&
    typeof value.capabilities === "object" &&
    !Array.isArray(value.capabilities)
      ? (value.capabilities as Record<string, unknown>)
      : undefined;

  return {
    manufacturer: requiredText(
      value.manufacturer,
      "Manufacturer",
      2,
      120,
    ),
    modelName: requiredText(
      value.modelName,
      "Model name",
      2,
      160,
    ),
    protocol: requiredText(
      value.protocol,
      "Protocol",
      1,
      100,
    ),
    networkType: networkType as DeviceNetworkType,
    capabilities,
  };
}

export async function GET(request: NextRequest) {
  const page = positiveInteger(
    request.nextUrl.searchParams.get("page"),
    1,
    100_000,
  );
  const pageSize = positiveInteger(
    request.nextUrl.searchParams.get("pageSize"),
    100,
    100,
  );
  const search =
    request.nextUrl.searchParams.get("search")?.trim().slice(0, 160) ||
    undefined;

  return withManagementSession(request, (accessToken) =>
    backendListDeviceModels(accessToken, {
      page,
      pageSize,
      search,
    }),
  );
}

export async function POST(request: NextRequest) {
  let input: CreateDeviceModelInput;

  try {
    input = parseModel(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Device Model request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendCreateDeviceModel(accessToken, input),
  );
}