import type { VehicleSummary } from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type { DealerSummary } from "@/lib/management/dealer-types";

export type ManagementMonitorScopeType =
  | "PLATFORM"
  | "DIRECT"
  | "DEALER"
  | "CUSTOMER";

export type ManagementMonitorScope = {
  key: string;
  type: ManagementMonitorScopeType;
  id: string | null;
  label: string;
};

export type ManagementMonitorHierarchy = {
  dealers: DealerSummary[];
  customers: CustomerSummary[];
};

export type ManagementMonitorCustomerIdentity = {
  id: string;
  code: string;
  name: string;
  managingDealerId: string | null;
  managingDealerName: string | null;
};

export type ManagementMonitorVehicle = VehicleSummary & {
  monitorCustomer: ManagementMonitorCustomerIdentity;
};

export function customerDisplayName(
  customer: CustomerSummary,
) {
  return (
    customer.individualProfile?.fullName ??
    customer.organizationProfile?.displayName ??
    customer.customerCode
  );
}

export function activeMonitorAssignment(
  vehicle: VehicleSummary,
) {
  return (
    vehicle.deviceAssignments.find(
      (assignment) => assignment.status === "ACTIVE",
    ) ??
    vehicle.deviceAssignments[0] ??
    null
  );
}

export function monitorVehicleDisplayName(
  vehicle: VehicleSummary,
) {
  const assignment = activeMonitorAssignment(vehicle);

  return (
    vehicle.registrationNumber ||
    assignment?.device.deviceCode ||
    vehicle.vehicleCode
  );
}

export function formatMonitorDate(
  value?: string | null,
) {
  if (!value) return "-";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return "-";

  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}