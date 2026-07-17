import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { backendLogout } from "@/lib/auth/auth-backend";
import { clearAuthCookies } from "@/lib/auth/auth-cookies";
import { authCookieNames } from "@/lib/auth/auth-cookie-names";

export async function POST() {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get(
    authCookieNames.accessToken,
  )?.value;

  if (accessToken) {
    await backendLogout(accessToken);
  }

  const response = NextResponse.json({
    authenticated: false,
    redirectTo: "/login",
  });

  clearAuthCookies(response);
  return response;
}