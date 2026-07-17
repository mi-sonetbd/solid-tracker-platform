import { NextRequest } from "next/server";
import type {
  DeviceAssignmentEndReason,
  DeviceRemovalReason,
  RemoveDeviceInput,
} from "@/lib/management/asset-types";
import { backendRemoveDevice } from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

type RouteContext = {
  params: Promise<{
    deviceId: string;
  }>;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const assignmentEndReasons = [
  "DEVICE_FAILURE",
  "DEVICE_REPLACEMENT",
  "VEHICLE_TRANSFER",
  "VEHICLE_SOLD",
  "CUSTOMER_REQUEST",
  "SUBSCRIPTION_CANCELLED",
  "TRANSFER_TO_ANOTHER_VEHICLE",
  "LOST",
  "OTHER",
] as const;

const removalReasons = [
  "CUSTOMER_REQUEST",
  "VEHICLE_SOLD",
  "DEVICE_FAILURE",
  "WARRANTY_REPLACEMENT",
  "SUBSCRIPTION_CANCELLED",
  "TRANSFER_TO_ANOTHER_VEHICLE",
  "LOST",
  "OTHER",
] as const;

function optionalText(value: unknown, maximumLength: number) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("The removal notes are invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `Removal notes cannot exceed ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseInput(payload: unknown): RemoveDeviceInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Device uninstall request is invalid.");
  }

  const value = payload as Record<string, unknown>;

  if (
    typeof value.assignmentEndReason !== "string" ||
    !assignmentEndReasons.includes(
      value.assignmentEndReason as DeviceAssignmentEndReason,
    )
  ) {
    throw new Error("Select a valid assignment end reason.");
  }

  if (
    typeof value.removalReason !== "string" ||
    !removalReasons.includes(
      value.removalReason as DeviceRemovalReason,
    )
  ) {
    throw new Error("Select a valid Device removal reason.");
  }

  return {
    assignmentEndReason:
      value.assignmentEndReason as DeviceAssignmentEndReason,
    removalReason:
      value.removalReason as DeviceRemovalReason,
    notes: optionalText(value.notes, 2000),
  };
}

async function deviceIdFrom(context: RouteContext) {
  const { deviceId } = await context.params;
  return uuidPattern.test(deviceId) ? deviceId : null;
}

export async function POST(
  request: NextRequest,
  context: RouteContext,
) {
  const deviceId = await deviceIdFrom(context);

  if (!deviceId) {
    return managementJsonError(
      "The selected Device identifier is invalid.",
      400,
    );
  }

  let input: RemoveDeviceInput;

  try {
    input = parseInput(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Device uninstall request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendRemoveDevice(accessToken, deviceId, input),
  );
}