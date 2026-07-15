import type {
  DeviceAssignmentSummary,
  VehicleListResponse,
  VehicleSummary,
} from "@/lib/management/asset-types";

export type CustomerAssetView =
  | "monitor"
  | "device"
  | "report"
  | "fleet";

export type CustomerVehicleAsset = VehicleSummary & {
  deviceAssignments: DeviceAssignmentSummary[];
};

export type CustomerAssetListResponse = Omit<
  VehicleListResponse,
  "items"
> & {
  items: CustomerVehicleAsset[];
};

export function normalizeCustomerVehicle(
  vehicle: VehicleSummary,
): CustomerVehicleAsset {
  return {
    ...vehicle,
    deviceAssignments: vehicle.deviceAssignments ?? [],
  };
}

export function activeDeviceAssignment(
  vehicle: CustomerVehicleAsset,
) {
  return vehicle.deviceAssignments.find(
    (assignment) => assignment.status === "ACTIVE",
  ) ?? vehicle.deviceAssignments[0] ?? null;
}

export function vehicleDisplayName(
  vehicle: CustomerVehicleAsset,
) {
  const model = [vehicle.manufacturer, vehicle.modelName]
    .filter(Boolean)
    .join(" ");

  return (
    vehicle.registrationNumber ||
    model ||
    vehicle.vehicleCode
  );
}

export function titleCase(value: string) {
  return value
    .replaceAll("_", " ")
    .toLowerCase()
    .replace(/\b\w/g, (character) =>
      character.toUpperCase(),
    );
}