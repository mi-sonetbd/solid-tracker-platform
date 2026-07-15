import { NextRequest } from "next/server";
import type { AllocateDeviceInput } from "@/lib/management/asset-types";
import { backendAllocateDevice } from "@/lib/management/assets-backend";
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

function optionalText(value: unknown, maximumLength: number) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("An allocation text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `An allocation field exceeds ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseAllocation(payload: unknown): AllocateDeviceInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Dealer allocation request is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const dealerOrganizationId = optionalText(
    value.dealerOrganizationId,
    36,
  );

  if (
    !dealerOrganizationId ||
    !uuidPattern.test(dealerOrganizationId)
  ) {
    throw new Error("Select a valid active Dealer.");
  }

  return {
    dealerOrganizationId,
    notes: optionalText(value.notes, 1000),
  };
}

export async function POST(
  request: NextRequest,
  context: RouteContext,
) {
  const { deviceId } = await context.params;

  if (!uuidPattern.test(deviceId)) {
    return managementJsonError(
      "The selected device identifier is invalid.",
      400,
    );
  }

  let input: AllocateDeviceInput;

  try {
    input = parseAllocation(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Dealer allocation request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendAllocateDevice(accessToken, deviceId, input),
  );
}