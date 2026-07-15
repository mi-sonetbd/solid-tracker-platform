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

export type DeviceNetworkType =
  | "GSM_2G"
  | "UMTS_3G"
  | "LTE_4G"
  | "LTE_5G"
  | "LORA"
  | "SATELLITE"
  | "OTHER";

export type DeviceModelSummary = {
  id: string;
  modelCode: string;
  manufacturer: string;
  modelName: string;
  protocol: string;
  networkType: DeviceNetworkType | null;
  capabilities?: Record<string, unknown> | null;
  status?: "ACTIVE" | "INACTIVE" | "ARCHIVED";
  createdAt?: string;
  updatedAt?: string;
  _count?: {
    devices: number;
  };
};

export type DeviceModelListResponse = {
  items: DeviceModelSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type CreateDeviceModelInput = {
  manufacturer: string;
  modelName: string;
  protocol: string;
  networkType: DeviceNetworkType;
  capabilities?: Record<string, unknown>;
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
  allocationCode?: string;
  status: string;
  allocatedAt?: string;
  availableAt?: string | null;
  dealerOrganizationId: string;
  dealerOrganization: {
    id: string;
    code: string;
    name: string;
  };
};

export type DeviceOwnershipSummary = {
  id: string;
  ownerType: string;
  ownerOrganizationId: string | null;
  ownerCustomerId: string | null;
  startedAt?: string;
  endedAt?: string | null;
};

export type DeviceCustodySummary = {
  id: string;
  custodianType: string;
  custodianOrganizationId: string | null;
  custodianCustomerId: string | null;
  startedAt?: string;
  endedAt?: string | null;
};

export type DeviceVehicleAssignmentSummary = {
  id: string;
  status: string;
  vehicleId: string;
  vehicle?: {
    id: string;
    customerId: string;
    vehicleCode: string;
    registrationNumber: string | null;
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
  receivedAt?: string | null;
  retiredAt?: string | null;
  createdAt: string;
  updatedAt?: string;
  deviceModel: DeviceModelSummary;
  dealerAllocations?: DealerDeviceAllocationSummary[];
  vehicleAssignments?: DeviceVehicleAssignmentSummary[];
  ownershipHistory?: DeviceOwnershipSummary[];
  custodyHistory?: DeviceCustodySummary[];
};

export type DeviceListResponse = {
  items: DeviceSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type RegisterDeviceInput = {
  deviceModelId: string;
  imei?: string;
  serialNumber?: string;
  hardwareVersion?: string;
  firmwareVersion?: string;
  receivedAt?: string;
};

export type BulkRegisterDevicesInput = {
  deviceModelId: string;
  imeis: string[];
  hardwareVersion?: string;
  firmwareVersion?: string;
  receivedAt?: string;
};

export type BulkDeviceRegistrationLineResult = {
  imei: string;
  status: "CREATED" | "ERROR";
  device?: DeviceSummary;
  message?: string;
};

export type BulkDeviceRegistrationResult = {
  total: number;
  created: number;
  failed: number;
  results: BulkDeviceRegistrationLineResult[];
};

export type TransferDevicesInput = {
  deviceIds: string[];
  targetType: "DEALER" | "CUSTOMER";
  targetId: string;
  notes?: string;
};

export type TransferDevicesResult = {
  items: DeviceSummary[];
  total: number;
  targetType: "DEALER" | "CUSTOMER";
  targetId: string;
};

export type AllocateDeviceInput = {
  dealerOrganizationId: string;
  notes?: string;
};

export type DealerDeviceAllocationResult = {
  id: string;
  allocationCode: string;
  dealerOrganizationId: string;
  deviceId: string;
  status: string;
  allocatedAt: string;
  availableAt: string | null;
  dealerOrganization: {
    id: string;
    code: string;
    name: string;
  };
  device: DeviceSummary;
};

export type InstallDeviceInput = {
  vehicleId: string;
  installedAt?: string;
  latitude?: number;
  longitude?: number;
  odometerReading?: number;
  powerConnectionType?: string;
  ignitionConnected?: boolean;
  relayConnected?: boolean;
  sosConnected?: boolean;
  installationNotes?: string;
};

export type DeviceInstallationResult = {
  id: string;
  installationCode: string;
  deviceId: string;
  vehicleId: string;
  status: string;
};