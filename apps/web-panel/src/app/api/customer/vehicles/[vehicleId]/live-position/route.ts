import { NextRequest } from "next/server";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

type RouteContext = {
  params: Promise<{ vehicleId: string }>;
};

export async function GET(
  request: NextRequest,
  context: RouteContext,
) {
  const { vehicleId } = await context.params;

  if (!vehicleId || vehicleId.length > 100) {
    return managementJsonError("A valid vehicle is required.", 400);
  }

  const apiBaseUrl = process.env.SOLID_TRACKER_API_BASE_URL?.replace(/\/$/, "");

  if (!apiBaseUrl) {
    return managementJsonError("The backend API is not configured.", 500);
  }

  return withManagementSession(request, async (accessToken) => {
    const response = await fetch(
      `${apiBaseUrl}/tracking/vehicles/${encodeURIComponent(vehicleId)}/live-position`,
      {
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        cache: "no-store",
      },
    );
    const payload = (await response.json()) as {
      message?: string;
      [key: string]: unknown;
    };

    if (!response.ok) {
      return {
        ok: false as const,
        status: response.status,
        message: payload.message || "Live position could not be loaded.",
      };
    }

    return {
      ok: true as const,
      status: response.status,
      data: payload,
    };
  });
}