import { NextRequest } from "next/server";
import type { CreateIndividualCustomerInput } from "@/lib/management/customer-types";
import { backendCreateIndividualCustomer } from "@/lib/management/customers-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

function optionalText(
  value: unknown,
  maximumLength: number,
) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("An optional text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `A text field exceeds ${maximumLength} characters.`,
    );
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

function parseInput(
  payload: unknown,
): CreateIndividualCustomerInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Customer request body is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const primaryEmail = optionalText(value.primaryEmail, 254);

  if (
    primaryEmail &&
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(primaryEmail)
  ) {
    throw new Error("Enter a valid Customer email address.");
  }

  return {
    fullName: requiredText(value.fullName, "Full name", 2, 160),
    primaryMobile: requiredText(
      value.primaryMobile,
      "Primary mobile",
      5,
      30,
    ),
    primaryEmail,
    dateOfBirth: optionalText(value.dateOfBirth, 30),
    emergencyContactName: optionalText(
      value.emergencyContactName,
      160,
    ),
    emergencyContactMobile: optionalText(
      value.emergencyContactMobile,
      30,
    ),
  };
}

export async function POST(request: NextRequest) {
  let input: CreateIndividualCustomerInput;

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
    backendCreateIndividualCustomer(accessToken, input),
  );
}