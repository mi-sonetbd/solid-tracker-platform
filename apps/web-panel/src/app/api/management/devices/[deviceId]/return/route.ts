import { NextRequest } from "next/server";
import type { ReturnDeviceInput } from "@/lib/management/asset-types";
import { backendReturnDevice } from "@/lib/management/assets-backend";
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
    throw new Error("The return notes are invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `Return notes cannot exceed ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseInput(payload: unknown): ReturnDeviceInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Device return request is invalid.");
  }

  const value = payload as Record<string, unknown>;

  return {
    notes: optionalText(value.notes, 1000),
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

  let input: ReturnDeviceInput;

  try {
    input = parseInput(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Device return request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendReturnDevice(accessToken, deviceId, input),
  );
}