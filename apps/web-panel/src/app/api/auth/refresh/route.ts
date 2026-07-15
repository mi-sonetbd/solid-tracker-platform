import { NextRequest, NextResponse } from "next/server";
import { backendRefresh } from "@/lib/auth/auth-backend";
import {
  applyAuthCookies,
  clearAuthCookies,
} from "@/lib/auth/auth-cookies";
import { authCookieNames } from "@/lib/auth/auth-cookie-names";

function safeReturnTo(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return "/monitor";
  }

  return value;
}

export async function GET(request: NextRequest) {
  const returnTo = safeReturnTo(
    request.nextUrl.searchParams.get("returnTo"),
  );
  const refreshToken = request.cookies.get(
    authCookieNames.refreshToken,
  )?.value;
  const rememberMe =
    request.cookies.get(authCookieNames.rememberMe)?.value === "1";

  if (!refreshToken) {
    const response = NextResponse.redirect(
      new URL("/login?reason=session-expired", request.url),
    );
    clearAuthCookies(response);
    return response;
  }

  const refreshed = await backendRefresh(refreshToken);

  if (!refreshed.ok) {
    const response = NextResponse.redirect(
      new URL("/login?reason=session-expired", request.url),
    );
    clearAuthCookies(response);
    return response;
  }

  const response = NextResponse.redirect(
    new URL(returnTo, request.url),
  );

  applyAuthCookies(response, refreshed.data, rememberMe);
  return response;
}