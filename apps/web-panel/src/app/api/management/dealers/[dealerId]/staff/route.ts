import { NextRequest } from "next/server";
import type { CreateDealerManagerInput } from "@/lib/management/dealer-types";
import {
  backendCreateDealerManager,
  backendListDealerStaff,
} from "@/lib/management/dealers-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

type RouteContext = {
  params: Promise<{
    dealerId: string;
  }>;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function text(
  value: unknown,
  fieldName: string,
  minimumLength: number,
  maximumLength: number,
) {
  if (typeof value !== "string") {
    throw new Error(`${fieldName} is required.`);
  }

  const normalized = value.trim();

  if (
    normalized.length < minimumLength ||
    normalized.length > maximumLength
  ) {
    throw new Error(
      `${fieldName} must contain ${minimumLength}-${maximumLength} characters.`,
    );
  }

  return normalized;
}

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

  if (!normalized) {
    return undefined;
  }

  if (normalized.length > maximumLength) {
    throw new Error(
      `An optional text field exceeds ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseDealerManager(
  payload: unknown,
): CreateDealerManagerInput {
  if (!payload || typeof payload !== "object") {
    throw new Error(
      "The Dealer Manager request body is invalid.",
    );
  }

  const value = payload as Record<string, unknown>;
  const email = optionalText(value.email, 254);
  const password = optionalText(value.password, 200);

  if (
    email &&
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new Error("Enter a valid email address.");
  }

  if (password && password.length < 12) {
    throw new Error(
      "A new Dealer Manager password must contain at least 12 characters.",
    );
  }

  return {
    fullName: text(value.fullName, "Full name", 2, 160),
    mobileNumber: text(
      value.mobileNumber,
      "Mobile number",
      5,
      30,
    ),
    email,
    password,
    roleCode: "DEALER_MANAGER",
  };
}

async function dealerIdFrom(context: RouteContext) {
  const { dealerId } = await context.params;

  if (!uuidPattern.test(dealerId)) {
    return null;
  }

  return dealerId;
}

export async function GET(
  request: NextRequest,
  context: RouteContext,
) {
  const dealerId = await dealerIdFrom(context);

  if (!dealerId) {
    return managementJsonError(
      "The selected Dealer identifier is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendListDealerStaff(accessToken, dealerId),
  );
}

export async function POST(
  request: NextRequest,
  context: RouteContext,
) {
  const dealerId = await dealerIdFrom(context);

  if (!dealerId) {
    return managementJsonError(
      "The selected Dealer identifier is invalid.",
      400,
    );
  }

  let input: CreateDealerManagerInput;

  try {
    input = parseDealerManager(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Dealer Manager request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendCreateDealerManager(
      accessToken,
      dealerId,
      input,
    ),
  );
}