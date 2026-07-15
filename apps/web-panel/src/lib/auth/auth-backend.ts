import "server-only";

import { authConfig } from "@/lib/auth/auth-config";
import type {
  BackendAuthContext,
  BackendTokenResponse,
} from "@/lib/auth/auth-types";

type BackendResult<T> =
  | {
      ok: true;
      status: number;
      data: T;
    }
  | {
      ok: false;
      status: number;
      message: string;
      details?: unknown;
    };

async function parseResponse(response: Response): Promise<unknown> {
  const contentType = response.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    return response.json();
  }

  const text = await response.text();
  return text || null;
}

function errorMessage(payload: unknown, fallback: string) {
  if (
    payload &&
    typeof payload === "object" &&
    "message" in payload
  ) {
    const value = (payload as { message?: unknown }).message;

    if (Array.isArray(value)) {
      return value.filter((item) => typeof item === "string").join(" ");
    }

    if (typeof value === "string") {
      return value;
    }
  }

  return fallback;
}

async function backendRequest<T>(
  path: string,
  init: RequestInit,
): Promise<BackendResult<T>> {
  try {
    const response = await fetch(
      `${authConfig.apiBaseUrl}${path}`,
      {
        ...init,
        cache: "no-store",
        headers: {
          Accept: "application/json",
          ...init.headers,
        },
      },
    );

    const payload = await parseResponse(response);

    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        message: errorMessage(
          payload,
          "The Solid Tracker API rejected the request.",
        ),
        details: payload,
      };
    }

    return {
      ok: true,
      status: response.status,
      data: payload as T,
    };
  } catch (error) {
    return {
      ok: false,
      status: 503,
      message:
        error instanceof Error
          ? error.message
          : "The Solid Tracker API is unavailable.",
    };
  }
}

export function backendLogin(input: {
  mobileNumber: string;
  password: string;
  deviceName?: string;
}) {
  return backendRequest<BackendTokenResponse>("/auth/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      mobileNumber: input.mobileNumber,
      password: input.password,
      platform: "WEB",
      deviceName: input.deviceName,
      appVersion: authConfig.appVersion,
    }),
  });
}

export function backendRefresh(refreshToken: string) {
  return backendRequest<BackendTokenResponse>("/auth/refresh", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ refreshToken }),
  });
}

export function backendMe(accessToken: string) {
  return backendRequest<BackendAuthContext>("/auth/me", {
    method: "GET",
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });
}

export function backendLogout(accessToken: string) {
  return backendRequest<null>("/auth/logout", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });
}