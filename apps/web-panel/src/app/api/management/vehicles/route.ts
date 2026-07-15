import { NextRequest } from "next/server";
import type {
  CreateVehicleInput,
  VehicleType,
} from "@/lib/management/asset-types";
import {
  backendCreateVehicle,
  backendListVehicles,
} from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const vehicleTypes = [
  "CAR",
  "MOTORCYCLE",
  "BUS",
  "TRUCK",
  "CNG",
  "PICKUP",
  "MICROBUS",
  "AMBULANCE",
  "CONSTRUCTION_EQUIPMENT",
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

function optionalText(value: unknown, maximumLength: number) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("A vehicle text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(`A vehicle field exceeds ${maximumLength} characters.`);
  }

  return normalized;
}

function parseVehicle(payload: unknown): CreateVehicleInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The vehicle request body is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const customerId = optionalText(value.customerId, 36);
  const vehicleType = optionalText(value.vehicleType, 40);
  const manufacturingYear =
    value.manufacturingYear === undefined ||
    value.manufacturingYear === null ||
    value.manufacturingYear === ""
      ? undefined
      : Number(value.manufacturingYear);

  if (!customerId || !uuidPattern.test(customerId)) {
    throw new Error("The selected Customer identifier is invalid.");
  }

  if (
    !vehicleType ||
    !vehicleTypes.includes(vehicleType as (typeof vehicleTypes)[number])
  ) {
    throw new Error("Select a valid vehicle type.");
  }

  if (
    manufacturingYear !== undefined &&
    (!Number.isInteger(manufacturingYear) ||
      manufacturingYear < 1886 ||
      manufacturingYear > 2100)
  ) {
    throw new Error("Manufacturing year must be between 1886 and 2100.");
  }

  return {
    customerId,
    vehicleType: vehicleType as VehicleType,
    registrationNumber: optionalText(value.registrationNumber, 100),
    manufacturer: optionalText(value.manufacturer, 120),
    modelName: optionalText(value.modelName, 120),
    manufacturingYear,
    color: optionalText(value.color, 60),
    chassisNumber: optionalText(value.chassisNumber, 120),
    engineNumber: optionalText(value.engineNumber, 120),
  };
}

export async function GET(request: NextRequest) {
  const customerId =
    request.nextUrl.searchParams.get("customerId")?.trim() ?? "";

  if (!uuidPattern.test(customerId)) {
    return managementJsonError(
      "The selected Customer identifier is invalid.",
      400,
    );
  }

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

  return withManagementSession(request, (accessToken) =>
    backendListVehicles(accessToken, {
      page,
      pageSize,
      customerId,
      search,
    }),
  );
}

export async function POST(request: NextRequest) {
  let input: CreateVehicleInput;

  try {
    input = parseVehicle(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The vehicle request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendCreateVehicle(accessToken, input),
  );
}