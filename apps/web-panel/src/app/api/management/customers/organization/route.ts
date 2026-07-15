import { NextRequest } from "next/server";
import type { CreateOrganizationCustomerInput } from "@/lib/management/customer-types";
import { backendCreateOrganizationCustomer } from "@/lib/management/customers-backend";
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
    throw new Error("An optional text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(`A text field exceeds ${maximumLength} characters.`);
  }

  return normalized;
}

function requiredText(
  value: unknown,
  fieldName: string,
  minimumLength: number,
  maximumLength: number,
) {
  const normalized = optionalText(value, maximumLength);

  if (!normalized || normalized.length < minimumLength) {
    throw new Error(
      `${fieldName} must contain at least ${minimumLength} characters.`,
    );
  }

  return normalized;
}

function parseInput(payload: unknown): CreateOrganizationCustomerInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Customer request body is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const primaryEmail = optionalText(value.primaryEmail, 254);
  const contactEmail = optionalText(value.contactEmail, 254);
  const managingDealerId = optionalText(value.managingDealerId, 36);

  for (const email of [primaryEmail, contactEmail]) {
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new Error("Enter a valid email address.");
    }
  }

  if (managingDealerId && !uuidPattern.test(managingDealerId)) {
    throw new Error("The selected Dealer identifier is invalid.");
  }

  return {
    legalName: requiredText(value.legalName, "Legal name", 2, 200),
    displayName: requiredText(value.displayName, "Display name", 2, 160),
    primaryMobile: requiredText(value.primaryMobile, "Primary mobile", 5, 30),
    primaryEmail,
    registrationNumber: optionalText(value.registrationNumber, 100),
    taxReference: optionalText(value.taxReference, 100),
    contactPersonName: optionalText(value.contactPersonName, 160),
    contactMobile: optionalText(value.contactMobile, 30),
    contactEmail,
    managingDealerId,
  };
}

export async function POST(request: NextRequest) {
  let input: CreateOrganizationCustomerInput;

  try {
    input = parseInput(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Customer request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendCreateOrganizationCustomer(accessToken, input),
  );
}