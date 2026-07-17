import { NextRequest } from "next/server";
import type { TransferDevicesInput } from "@/lib/management/asset-types";
import { backendTransferDevices } from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function parseInput(payload: unknown): TransferDevicesInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Device transfer request is invalid.");
  }

  const value = payload as Record<string, unknown>;

  if (
    !Array.isArray(value.deviceIds) ||
    value.deviceIds.length < 1 ||
    value.deviceIds.length > 100 ||
    value.deviceIds.some(
      (item) =>
        typeof item !== "string" ||
        !uuidPattern.test(item),
    )
  ) {
    throw new Error(
      "Select between 1 and 100 valid Devices.",
    );
  }

  if (
    value.targetType !== "DEALER" &&
    value.targetType !== "CUSTOMER"
  ) {
    throw new Error("Select a valid transfer target type.");
  }

  if (
    typeof value.targetId !== "string" ||
    !uuidPattern.test(value.targetId)
  ) {
    throw new Error("Select a valid transfer destination.");
  }

  const notes =
    typeof value.notes === "string"
      ? value.notes.trim().slice(0, 1000) || undefined
      : undefined;

  return {
    deviceIds: value.deviceIds as string[],
    targetType: value.targetType,
    targetId: value.targetId,
    notes,
  };
}

export async function POST(request: NextRequest) {
  let input: TransferDevicesInput;

  try {
    input = parseInput(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Device transfer request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendTransferDevices(accessToken, input),
  );
}