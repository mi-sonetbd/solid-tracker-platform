import { NextRequest, NextResponse } from "next/server";
import {
  backendMe,
  backendRefresh,
} from "@/lib/auth/auth-backend";
import {
  applyAuthCookies,
  clearAuthCookies,
} from "@/lib/auth/auth-cookies";
import { authCookieNames } from "@/lib/auth/auth-cookie-names";
import {
  resolveWorkspace,
  workspaceRedirect,
} from "@/lib/auth/workspace";

function unauthenticated() {
  const response = NextResponse.json(
    {
      authenticated: false,
      message: "Authentication is required.",
    },
    { status: 401 },
  );

  clearAuthCookies(response);
  return response;
}

export async function GET(request: NextRequest) {
  const accessToken = request.cookies.get(
    authCookieNames.accessToken,
  )?.value;
  const refreshToken = request.cookies.get(
    authCookieNames.refreshToken,
  )?.value;
  const rememberMe =
    request.cookies.get(authCookieNames.rememberMe)?.value === "1";

  if (accessToken) {
    const me = await backendMe(accessToken);

    if (me.ok) {
      const workspace = resolveWorkspace(me.data);

      return NextResponse.json({
        authenticated: true,
        user: me.data,
        workspace,
        redirectTo: workspaceRedirect(workspace),
      });
    }

    if (me.status !== 401) {
      return NextResponse.json(
        { message: me.message },
        { status: me.status },
      );
    }
  }

  if (!refreshToken) {
    return unauthenticated();
  }

  const refreshed = await backendRefresh(refreshToken);

  if (!refreshed.ok) {
    return unauthenticated();
  }

  const me = await backendMe(refreshed.data.accessToken);

  if (!me.ok) {
    return unauthenticated();
  }

  const workspace = resolveWorkspace(me.data);
  const response = NextResponse.json({
    authenticated: true,
    user: me.data,
    workspace,
    redirectTo: workspaceRedirect(workspace),
  });

  applyAuthCookies(response, refreshed.data, rememberMe);
  return response;
}