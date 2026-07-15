export type VehicleType =
  | "CAR"
  | "MOTORCYCLE"
  | "BUS"
  | "TRUCK"
  | "CNG"
  | "PICKUP"
  | "MICROBUS"
  | "AMBULANCE"
  | "CONSTRUCTION_EQUIPMENT"
  | "OTHER";

export type DeviceModelSummary = {
  id: string;
  modelCode: string;
  manufacturer: string;
  modelName: string;
  protocol: string;
  networkType: string | null;
};

export type DeviceAssignmentSummary = {
  id: string;
  status: string;
  assignmentType: string;
  startedAt: string;
  device: {
    id: string;
    deviceCode: string;
    imei: string | null;
    serialNumber: string | null;
    lifecycleStatus: string;
    firmwareVersion: string | null;
    deviceModel: DeviceModelSummary;
  };
};

export type VehicleSummary = {
  id: string;
  customerId: string;
  vehicleCode: string;
  vehicleType: VehicleType;
  registrationNumber: string | null;
  manufacturer: string | null;
  modelName: string | null;
  manufacturingYear: number | null;
  color: string | null;
  chassisNumber: string | null;
  engineNumber: string | null;
  status: string;
  createdAt: string;
  updatedAt: string;
  deviceAssignments: DeviceAssignmentSummary[];
};

export type VehicleListResponse = {
  items: VehicleSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type CreateVehicleInput = {
  customerId: string;
  vehicleType: VehicleType;
  registrationNumber?: string;
  manufacturer?: string;
  modelName?: string;
  manufacturingYear?: number;
  color?: string;
  chassisNumber?: string;
  engineNumber?: string;
};

export type DealerDeviceAllocationSummary = {
  id: string;
  status: string;
  dealerOrganizationId: string;
  dealerOrganization: {
    id: string;
    code: string;
    name: string;
  };
};

export type DeviceSummary = {
  id: string;
  deviceCode: string;
  deviceModelId: string;
  imei: string | null;
  serialNumber: string | null;
  hardwareVersion: string | null;
  firmwareVersion: string | null;
  lifecycleStatus: string;
  createdAt: string;
  deviceModel: DeviceModelSummary;
  dealerAllocations: DealerDeviceAllocationSummary[];
  vehicleAssignments: Array<{
    id: string;
    status: string;
    vehicleId: string;
  }>;
};

export type DeviceListResponse = {
  items: DeviceSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type InstallDeviceInput = {
  vehicleId: string;
  latitude?: number;
  longitude?: number;
  odometerReading?: number;
  powerConnectionType?: string;
  ignitionConnected?: boolean;
  relayConnected?: boolean;
  sosConnected?: boolean;
  notes?: string;
};

export type DeviceInstallationResult = {
  id: string;
  installationCode: string;
  deviceId: string;
  vehicleId: string;
  status: string;
};