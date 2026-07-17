import { NextRequest } from "next/server";
import { backendListCustomers } from "@/lib/management/customers-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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

function optionalEnum(value: string | null, allowed: readonly string[]) {
  return value && allowed.includes(value) ? value : undefined;
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
    request.nextUrl.searchParams.get("search")?.trim().slice(0, 160) ||
    undefined;
  const customerType = optionalEnum(
    request.nextUrl.searchParams.get("customerType"),
    ["INDIVIDUAL", "ORGANIZATION"],
  );
  const status = optionalEnum(request.nextUrl.searchParams.get("status"), [
    "PENDING",
    "ACTIVE",
    "SUSPENDED",
    "ARCHIVED",
  ]);
  const rawManagingDealerId =
    request.nextUrl.searchParams.get("managingDealerId")?.trim() || undefined;

  if (rawManagingDealerId && !uuidPattern.test(rawManagingDealerId)) {
    return managementJsonError(
      "The selected Dealer identifier is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendListCustomers(accessToken, {
      page,
      pageSize,
      search,
      customerType,
      status,
      managingDealerId: rawManagingDealerId,
    }),
  );
}