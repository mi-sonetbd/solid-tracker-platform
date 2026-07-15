import { NextRequest } from "next/server";
import type { RegisterDeviceInput } from "@/lib/management/asset-types";
import {
  backendListDevices,
  backendRegisterDevice,
} from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const lifecycleStatuses = [
  "RECEIVED",
  "IN_STOCK",
  "RESERVED",
  "ALLOCATED",
  "INSTALLED",
  "UNDER_REPAIR",
  "LOST",
  "DAMAGED",
  "RETIRED",
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

function optionalText(value: unknown, maximumLength: number) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("An inventory text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `An inventory field exceeds ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseDevice(payload: unknown): RegisterDeviceInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The stock intake request is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const deviceModelId = optionalText(value.deviceModelId, 36);
  const imei = optionalText(value.imei, 17);
  const serialNumber = optionalText(value.serialNumber, 100);
  const receivedAt = optionalText(value.receivedAt, 50);

  if (!deviceModelId || !uuidPattern.test(deviceModelId)) {
    throw new Error("Select a valid active Device Model.");
  }

  if (imei && !/^\d{14,17}$/.test(imei)) {
    throw new Error("IMEI must contain 14 to 17 digits.");
  }

  if (!imei && !serialNumber) {
    throw new Error(
      "Enter at least one device identity: IMEI or serial number.",
    );
  }

  if (receivedAt && Number.isNaN(new Date(receivedAt).getTime())) {
    throw new Error("Enter a valid received date and time.");
  }

  return {
    deviceModelId,
    imei,
    serialNumber,
    hardwareVersion: optionalText(value.hardwareVersion, 60),
    firmwareVersion: optionalText(value.firmwareVersion, 60),
    receivedAt: receivedAt
      ? new Date(receivedAt).toISOString()
      : undefined,
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
    20,
    100,
  );
  const search =
    request.nextUrl.searchParams.get("search")?.trim().slice(0, 160) ||
    undefined;
  const lifecycleStatus =
    request.nextUrl.searchParams.get("lifecycleStatus")?.trim() ||
    undefined;
  const deviceModelId =
    request.nextUrl.searchParams.get("deviceModelId")?.trim() ||
    undefined;
  const dealerOrganizationId =
    request.nextUrl.searchParams.get("dealerOrganizationId")?.trim() ||
    undefined;

  if (
    lifecycleStatus &&
    !lifecycleStatuses.includes(
      lifecycleStatus as (typeof lifecycleStatuses)[number],
    )
  ) {
    return managementJsonError(
      "The device lifecycle filter is invalid.",
      400,
    );
  }

  for (const identifier of [
    deviceModelId,
    dealerOrganizationId,
  ]) {
    if (identifier && !uuidPattern.test(identifier)) {
      return managementJsonError(
        "A selected inventory identifier is invalid.",
        400,
      );
    }
  }

  return withManagementSession(request, (accessToken) =>
    backendListDevices(accessToken, {
      page,
      pageSize,
      search,
      lifecycleStatus,
      deviceModelId,
      dealerOrganizationId,
    }),
  );
}

export async function POST(request: NextRequest) {
  let input: RegisterDeviceInput;

  try {
    input = parseDevice(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The stock intake request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendRegisterDevice(accessToken, input),
  );
}