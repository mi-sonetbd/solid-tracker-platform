import "server-only";

import type { NextResponse } from "next/server";
import { authConfig } from "@/lib/auth/auth-config";
import { authCookieNames } from "@/lib/auth/auth-cookie-names";
import type { BackendTokenResponse } from "@/lib/auth/auth-types";

const secure = process.env.NODE_ENV === "production";

const commonOptions = {
  httpOnly: true,
  sameSite: "lax" as const,
  secure,
  path: "/",
};

export function applyAuthCookies(
  response: NextResponse,
  tokens: BackendTokenResponse,
  rememberMe: boolean,
) {
  response.cookies.set(
    authCookieNames.accessToken,
    tokens.accessToken,
    {
      ...commonOptions,
      maxAge: authConfig.accessCookieMaxAge,
    },
  );

  response.cookies.set(
    authCookieNames.refreshToken,
    tokens.refreshToken,
    {
      ...commonOptions,
      ...(rememberMe
        ? { maxAge: authConfig.refreshCookieMaxAge }
        : {}),
    },
  );

  if (rememberMe) {
    response.cookies.set(authCookieNames.rememberMe, "1", {
      ...commonOptions,
      maxAge: authConfig.refreshCookieMaxAge,
    });
  } else {
    response.cookies.delete(authCookieNames.rememberMe);
  }
}

export function clearAuthCookies(response: NextResponse) {
  response.cookies.delete(authCookieNames.accessToken);
  response.cookies.delete(authCookieNames.refreshToken);
  response.cookies.delete(authCookieNames.rememberMe);
}