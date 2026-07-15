import { NextRequest } from "next/server";
import type { CreateCustomerOwnerInput } from "@/lib/management/customer-types";
import {
  backendCreateCustomerOwner,
  backendListCustomerMembers,
} from "@/lib/management/customers-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

type RouteContext = {
  params: Promise<{
    customerId: string;
  }>;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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

async function customerIdFrom(context: RouteContext) {
  const { customerId } = await context.params;
  return uuidPattern.test(customerId) ? customerId : null;
}

function parseOwner(payload: unknown): CreateCustomerOwnerInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Customer Owner request is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const email = optionalText(value.email, 254);
  const password = optionalText(value.password, 200);

  if (
    email &&
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new Error("Enter a valid owner email address.");
  }

  if (
    password &&
    (password.length < 12 ||
      !/[a-z]/.test(password) ||
      !/[A-Z]/.test(password) ||
      !/\d/.test(password))
  ) {
    throw new Error(
      "A new owner password must contain at least 12 characters, uppercase, lowercase, and a number.",
    );
  }

  return {
    fullName: requiredText(
      value.fullName,
      "Owner full name",
      2,
      160,
    ),
    mobileNumber: requiredText(
      value.mobileNumber,
      "Owner mobile",
      5,
      30,
    ),
    email,
    password,
    roleCode: "CUSTOMER_OWNER",
  };
}

export async function GET(
  request: NextRequest,
  context: RouteContext,
) {
  const customerId = await customerIdFrom(context);

  if (!customerId) {
    return managementJsonError(
      "The selected Customer identifier is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendListCustomerMembers(accessToken, customerId),
  );
}

export async function POST(
  request: NextRequest,
  context: RouteContext,
) {
  const customerId = await customerIdFrom(context);

  if (!customerId) {
    return managementJsonError(
      "The selected Customer identifier is invalid.",
      400,
    );
  }

  let input: CreateCustomerOwnerInput;

  try {
    input = parseOwner(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Customer Owner request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendCreateCustomerOwner(
      accessToken,
      customerId,
      input,
    ),
  );
}