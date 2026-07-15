import { NextRequest, NextResponse } from "next/server";
import { backendRefresh } from "@/lib/auth/auth-backend";
import { authCookieNames } from "@/lib/auth/auth-cookie-names";
import {
  applyAuthCookies,
  clearAuthCookies,
} from "@/lib/auth/auth-cookies";
import type { BackendTokenResponse } from "@/lib/auth/auth-types";
import type {
  CreateDealerInput,
  ManagementApiError,
} from "@/lib/management/dealer-types";
import {
  backendCreateDealer,
  backendListDealers,
  type DealerBackendResult,
} from "@/lib/management/dealers-backend";

function jsonError(message: string, status: number) {
  return NextResponse.json<ManagementApiError>(
    { message },
    {
      status,
      headers: {
        "Cache-Control": "no-store",
      },
    },
  );
}

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

async function withDealerSession<T>(
  request: NextRequest,
  operation: (
    accessToken: string,
  ) => Promise<DealerBackendResult<T>>,
) {
  const accessToken = request.cookies.get(
    authCookieNames.accessToken,
  )?.value;
  const refreshToken = request.cookies.get(
    authCookieNames.refreshToken,
  )?.value;
  const rememberMe =
    request.cookies.get(authCookieNames.rememberMe)?.value === "1";

  if (!accessToken && !refreshToken) {
    return jsonError("Authentication is required.", 401);
  }

  let tokens: BackendTokenResponse | null = null;
  let result = accessToken
    ? await operation(accessToken)
    : null;

  if (
    (!result || (!result.ok && result.status === 401)) &&
    refreshToken
  ) {
    const refreshed = await backendRefresh(refreshToken);

    if (!refreshed.ok) {
      const response = jsonError(
        "The authenticated session has expired.",
        401,
      );
      clearAuthCookies(response);
      return response;
    }

    tokens = refreshed.data;
    result = await operation(tokens.accessToken);
  }

  if (!result) {
    const response = jsonError(
      "The authenticated session is unavailable.",
      401,
    );
    clearAuthCookies(response);
    return response;
  }

  if (!result.ok) {
    const response = jsonError(result.message, result.status);

    if (result.status === 401) {
      clearAuthCookies(response);
    }

    return response;
  }

  const response = NextResponse.json(result.data, {
    status: result.status,
    headers: {
      "Cache-Control": "no-store",
    },
  });

  if (tokens) {
    applyAuthCookies(response, tokens, rememberMe);
  }

  return response;
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

  return withDealerSession(request, (accessToken) =>
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
    return jsonError(
      error instanceof Error
        ? error.message
        : "The dealer request is invalid.",
      400,
    );
  }

  return withDealerSession(request, (accessToken) =>
    backendCreateDealer(accessToken, input),
  );
}