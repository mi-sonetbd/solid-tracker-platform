import "server-only";

import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { backendMe } from "@/lib/auth/auth-backend";
import { authCookieNames } from "@/lib/auth/auth-cookie-names";
import type {
  BackendAuthContext,
  WorkspaceKind,
} from "@/lib/auth/auth-types";
import {
  resolveWorkspace,
  workspaceRedirect,
} from "@/lib/auth/workspace";

type ServerSession = {
  user: BackendAuthContext;
  workspace: WorkspaceKind;
};

function loginRedirect(pathname: string) {
  return `/login?returnTo=${encodeURIComponent(pathname)}`;
}

async function currentPathname() {
  const headerStore = await headers();
  return (
    headerStore.get("x-solid-tracker-pathname") ?? "/monitor"
  );
}

export async function requireAnySession(): Promise<ServerSession> {
  const cookieStore = await cookies();
  const pathname = await currentPathname();
  const accessToken = cookieStore.get(
    authCookieNames.accessToken,
  )?.value;
  const refreshToken = cookieStore.get(
    authCookieNames.refreshToken,
  )?.value;

  if (!accessToken) {
    if (refreshToken) {
      redirect(
        `/api/auth/refresh?returnTo=${encodeURIComponent(
          pathname,
        )}`,
      );
    }

    redirect(loginRedirect(pathname));
  }

  const me = await backendMe(accessToken);

  if (!me.ok) {
    if (me.status === 401 && refreshToken) {
      redirect(
        `/api/auth/refresh?returnTo=${encodeURIComponent(
          pathname,
        )}`,
      );
    }

    redirect(loginRedirect(pathname));
  }

  return {
    user: me.data,
    workspace: resolveWorkspace(me.data),
  };
}

export async function requireCustomerSession() {
  const session = await requireAnySession();

  if (session.workspace !== "CUSTOMER") {
    redirect(workspaceRedirect(session.workspace));
  }

  return session;
}