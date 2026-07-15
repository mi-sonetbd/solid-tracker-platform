import { NextRequest } from "next/server";
import type { InstallDeviceInput } from "@/lib/management/asset-types";
import { backendInstallDevice } from "@/lib/management/assets-backend";
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
    throw new Error("An installation text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `An installation field exceeds ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function optionalNumber(
  value: unknown,
  fieldName: string,
  minimum: number,
  maximum: number,
) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  const parsed = Number(value);

  if (!Number.isFinite(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(
      `${fieldName} must be between ${minimum} and ${maximum}.`,
    );
  }

  return parsed;
}

function optionalBoolean(value: unknown) {
  return typeof value === "boolean" ? value : undefined;
}

function parseInstallation(payload: unknown): InstallDeviceInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The tracker installation request is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const vehicleId = optionalText(value.vehicleId, 36);

  if (!vehicleId || !uuidPattern.test(vehicleId)) {
    throw new Error("The selected vehicle identifier is invalid.");
  }

  return {
    vehicleId,
    latitude: optionalNumber(value.latitude, "Latitude", -90, 90),
    longitude: optionalNumber(value.longitude, "Longitude", -180, 180),
    odometerReading: optionalNumber(
      value.odometerReading,
      "Odometer reading",
      0,
      100_000_000,
    ),
    powerConnectionType: optionalText(value.powerConnectionType, 80),
    ignitionConnected: optionalBoolean(value.ignitionConnected),
    relayConnected: optionalBoolean(value.relayConnected),
    sosConnected: optionalBoolean(value.sosConnected),
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
      "The selected device identifier is invalid.",
      400,
    );
  }

  let input: InstallDeviceInput;

  try {
    input = parseInstallation(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The tracker installation request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendInstallDevice(accessToken, deviceId, input),
  );
}