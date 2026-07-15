import { NextRequest, NextResponse } from "next/server";
import { authCookieNames } from "@/lib/auth/auth-cookie-names";

const protectedPrefixes = [
  "/monitor",
  "/report",
  "/device",
  "/video",
  "/fleet",
  "/dashboard",
  "/live-tracking",
  "/vehicles",
  "/billing",
  "/customers",
  "/dealers",
  "/reports",
  "/settings",
  "/role-template-pending",
];

function protectedPath(pathname: string) {
  return protectedPrefixes.some(
    (prefix) =>
      pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
}

export function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname;
  const hasAccessToken = Boolean(
    request.cookies.get(authCookieNames.accessToken)?.value,
  );
  const hasRefreshToken = Boolean(
    request.cookies.get(authCookieNames.refreshToken)?.value,
  );

  if (
    protectedPath(pathname) &&
    !hasAccessToken &&
    !hasRefreshToken
  ) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("returnTo", pathname);
    return NextResponse.redirect(loginUrl);
  }

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-solid-tracker-pathname", pathname);

  return NextResponse.next({
    request: {
      headers: requestHeaders,
    },
  });
}

export const config = {
  matcher: [
    "/((?!api|_next/static|_next/image|favicon.ico|.*\\..*).*)",
  ],
};