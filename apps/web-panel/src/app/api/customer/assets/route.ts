import { NextRequest } from "next/server";
import { backendListVehicles } from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

function positiveInteger(
  value: string | null,
  fallback: number,
  maximum: number,
) {
  const parsed = Number(value ?? fallback);

  if (!Number.isInteger(parsed) || parsed < 1 || parsed > maximum) {
    return fallback;
  }

  return parsed;
}

export async function GET(request: NextRequest) {
  if (request.nextUrl.searchParams.has("customerId")) {
    return managementJsonError(
      "Customer scope is resolved from the authenticated session.",
      400,
    );
  }

  const page = positiveInteger(
    request.nextUrl.searchParams.get("page"),
    1,
    100_000,
  );
  const pageSize = positiveInteger(
    request.nextUrl.searchParams.get("pageSize"),
    100,
    100,
  );
  const search =
    request.nextUrl.searchParams.get("search")?.trim().slice(0, 160) ||
    undefined;

  return withManagementSession(request, (accessToken) =>
    backendListVehicles(accessToken, {
      page,
      pageSize,
      search,
    }),
  );
}