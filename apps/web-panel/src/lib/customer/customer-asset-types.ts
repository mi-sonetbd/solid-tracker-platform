import type {
  DeviceAssignmentSummary,
  VehicleListResponse,
  VehicleSummary,
} from "@/lib/management/asset-types";

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
  return (
    vehicle.deviceAssignments.find(
      (assignment) => assignment.status === "ACTIVE",
    ) ??
    vehicle.deviceAssignments[0] ??
    null
  );
}

export function vehicleDisplayName(
  vehicle: CustomerVehicleAsset,
) {
  const vehicleModel = [
    vehicle.manufacturer,
    vehicle.modelName,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    vehicle.registrationNumber ||
    vehicleModel ||
    vehicle.vehicleCode
  );
}

export function deviceDisplayName(
  vehicle: CustomerVehicleAsset,
) {
  const assignment = activeDeviceAssignment(vehicle);

  return (
    vehicle.registrationNumber ||
    assignment?.device.deviceCode ||
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

export function formatAssetDate(
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