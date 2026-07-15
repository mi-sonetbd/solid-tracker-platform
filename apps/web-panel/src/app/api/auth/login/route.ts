import { NextRequest, NextResponse } from "next/server";
import { applyAuthCookies } from "@/lib/auth/auth-cookies";
import { backendLogin, backendMe } from "@/lib/auth/auth-backend";
import type { LoginRequest } from "@/lib/auth/auth-types";
import {
  resolveWorkspace,
  workspaceRedirect,
} from "@/lib/auth/workspace";

function invalidRequest(message: string) {
  return NextResponse.json({ message }, { status: 400 });
}

export async function POST(request: NextRequest) {
  let body: LoginRequest;

  try {
    body = (await request.json()) as LoginRequest;
  } catch {
    return invalidRequest("The login request is not valid JSON.");
  }

  const mobileNumber = body.mobileNumber?.trim();
  const password = body.password ?? "";

  if (!mobileNumber || mobileNumber.length > 30) {
    return invalidRequest("Enter a valid mobile number.");
  }

  if (password.length < 8 || password.length > 200) {
    return invalidRequest("Enter a valid password.");
  }

  const login = await backendLogin({
    mobileNumber,
    password,
    deviceName:
      request.headers.get("user-agent")?.slice(0, 160) ??
      "Solid Tracker Web",
  });

  if (!login.ok) {
    return NextResponse.json(
      { message: login.message },
      { status: login.status },
    );
  }

  const me = await backendMe(login.data.accessToken);

  if (!me.ok) {
    return NextResponse.json(
      {
        message:
          "Login succeeded, but the account context could not be loaded.",
      },
      { status: 502 },
    );
  }

  const workspace = resolveWorkspace(me.data);
  const redirectTo = workspaceRedirect(workspace);

  const response = NextResponse.json({
    authenticated: true,
    user: me.data,
    workspace,
    redirectTo,
  });

  applyAuthCookies(response, login.data, Boolean(body.rememberMe));

  return response;
}