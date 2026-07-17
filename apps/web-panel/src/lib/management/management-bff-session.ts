import "server-only";

import {
  NextRequest,
  NextResponse,
} from "next/server";
import { backendRefresh } from "@/lib/auth/auth-backend";
import { authCookieNames } from "@/lib/auth/auth-cookie-names";
import {
  applyAuthCookies,
  clearAuthCookies,
} from "@/lib/auth/auth-cookies";
import type { BackendTokenResponse } from "@/lib/auth/auth-types";
import type {
  ManagementApiError,
  ManagementBackendResult,
} from "@/lib/management/dealer-types";

export function managementJsonError(
  message: string,
  status: number,
) {
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

export async function withManagementSession<T>(
  request: NextRequest,
  operation: (
    accessToken: string,
  ) => Promise<ManagementBackendResult<T>>,
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
    return managementJsonError(
      "Authentication is required.",
      401,
    );
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
      const response = managementJsonError(
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
    const response = managementJsonError(
      "The authenticated session is unavailable.",
      401,
    );
    clearAuthCookies(response);
    return response;
  }

  if (!result.ok) {
    const response = managementJsonError(
      result.message,
      result.status,
    );

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