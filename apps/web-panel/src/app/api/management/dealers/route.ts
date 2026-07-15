import { NextRequest } from "next/server";
import type { CreateDealerInput } from "@/lib/management/dealer-types";
import {
  backendCreateDealer,
  backendListDealers,
} from "@/lib/management/dealers-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

function positiveInteger(
  value: string | null,
  fallback: number,
  maximum: number,
) {
  const parsed = Number(value ?? fallback);

  if (
    !Number.isInteger(parsed) ||
    parsed < 1 ||
    parsed > maximum
  ) {
    return fallback;
  }

  return parsed;
}

function optionalText(
  value: unknown,
  maximumLength: number,
): string | undefined {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("A text field contains an invalid value.");
  }

  const normalized = value.trim();

  if (!normalized) {
    return undefined;
  }

  if (normalized.length > maximumLength) {
    throw new Error(
      `A text field exceeds ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseCreateDealerInput(
  payload: unknown,
): CreateDealerInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The dealer request body is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const name = optionalText(value.name, 160);

  if (!name || name.length < 2) {
    throw new Error(
      "Dealer name must contain at least 2 characters.",
    );
  }

  const contactEmail = optionalText(value.contactEmail, 254);

  if (
    contactEmail &&
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)
  ) {
    throw new Error("Enter a valid dealer email address.");
  }

  return {
    name,
    legalName: optionalText(value.legalName, 200),
    tradeLicenseNumber: optionalText(
      value.tradeLicenseNumber,
      100,
    ),
    taxIdentificationNumber: optionalText(
      value.taxIdentificationNumber,
      100,
    ),
    contactMobile: optionalText(value.contactMobile, 30),
    contactEmail,
    commissionEnabled:
      typeof value.commissionEnabled === "boolean"
        ? value.commissionEnabled
        : true,
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
  const rawSearch =
    request.nextUrl.searchParams.get("search")?.trim() ?? "";
  const search = rawSearch.slice(0, 160);

  return withManagementSession(request, (accessToken) =>
    backendListDealers(accessToken, {
      page,
      pageSize,
      search: search || undefined,
    }),
  );
}

export async function POST(request: NextRequest) {
  let input: CreateDealerInput;

  try {
    input = parseCreateDealerInput(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The dealer request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendCreateDealer(accessToken, input),
  );
}