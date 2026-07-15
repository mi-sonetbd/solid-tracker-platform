import { NextRequest } from "next/server";
import { backendListDevices } from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const lifecycleStatuses = [
  "RECEIVED",
  "IN_STOCK",
  "RESERVED",
  "ALLOCATED",
  "INSTALLED",
  "UNDER_REPAIR",
  "LOST",
  "DAMAGED",
  "RETIRED",
] as const;

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
  const lifecycleStatus =
    request.nextUrl.searchParams.get("lifecycleStatus")?.trim() ||
    undefined;
  const dealerOrganizationId =
    request.nextUrl.searchParams.get("dealerOrganizationId")?.trim() ||
    undefined;

  if (
    lifecycleStatus &&
    !lifecycleStatuses.includes(
      lifecycleStatus as (typeof lifecycleStatuses)[number],
    )
  ) {
    return managementJsonError("The device lifecycle filter is invalid.", 400);
  }

  if (dealerOrganizationId && !uuidPattern.test(dealerOrganizationId)) {
    return managementJsonError(
      "The selected Dealer identifier is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendListDevices(accessToken, {
      page,
      pageSize,
      search,
      lifecycleStatus,
      dealerOrganizationId,
    }),
  );
}