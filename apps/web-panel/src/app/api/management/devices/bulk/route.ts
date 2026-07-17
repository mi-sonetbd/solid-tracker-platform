import { NextRequest } from "next/server";
import type { BulkRegisterDevicesInput } from "@/lib/management/asset-types";
import { backendBulkRegisterDevices } from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function optionalText(value: unknown, maximumLength: number) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("A bulk intake text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `A bulk intake field exceeds ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseInput(payload: unknown): BulkRegisterDevicesInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The bulk stock intake request is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const deviceModelId = optionalText(value.deviceModelId, 36);

  if (!deviceModelId || !uuidPattern.test(deviceModelId)) {
    throw new Error("Select a valid active Device Model.");
  }

  if (
    !Array.isArray(value.imeis) ||
    value.imeis.length < 1 ||
    value.imeis.length > 250 ||
    value.imeis.some(
      (item) =>
        typeof item !== "string" ||
        item.length > 32,
    )
  ) {
    throw new Error(
      "Enter between 1 and 250 IMEI lines.",
    );
  }

  const receivedAt = optionalText(value.receivedAt, 50);

  if (receivedAt && Number.isNaN(new Date(receivedAt).getTime())) {
    throw new Error("Enter a valid received date and time.");
  }

  return {
    deviceModelId,
    imeis: value.imeis as string[],
    hardwareVersion: optionalText(value.hardwareVersion, 60),
    firmwareVersion: optionalText(value.firmwareVersion, 60),
    receivedAt: receivedAt
      ? new Date(receivedAt).toISOString()
      : undefined,
  };
}

export async function POST(request: NextRequest) {
  let input: BulkRegisterDevicesInput;

  try {
    input = parseInput(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The bulk stock intake request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendBulkRegisterDevices(accessToken, input),
  );
}