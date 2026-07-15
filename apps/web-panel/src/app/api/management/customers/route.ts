import { NextRequest } from "next/server";
import { backendListCustomers } from "@/lib/management/customers-backend";
import { withManagementSession } from "@/lib/management/management-bff-session";

function positiveInteger(
  value: string | null,
  fallback: number,
  maximum: number,
) {
  const parsed = Number(value ?? fallback);

  if (
    !Number.isInteger(parsed) ||
    parsed < 1 ||
    parsed > maximum
  ) {
    return fallback;
  }

  return parsed;
}

export async function GET(request: NextRequest) {
  const page = positiveInteger(
    request.nextUrl.searchParams.get("page"),
    1,
    100_000,
  );
  const pageSize = positiveInteger(
    request.nextUrl.searchParams.get("pageSize"),
    20,
    100,
  );
  const search =
    request.nextUrl.searchParams
      .get("search")
      ?.trim()
      .slice(0, 160) || undefined;
  const customerType =
    request.nextUrl.searchParams.get("customerType") ||
    undefined;
  const status =
    request.nextUrl.searchParams.get("status") || undefined;

  return withManagementSession(request, (accessToken) =>
    backendListCustomers(accessToken, {
      page,
      pageSize,
      search,
      customerType,
      status,
    }),
  );
}