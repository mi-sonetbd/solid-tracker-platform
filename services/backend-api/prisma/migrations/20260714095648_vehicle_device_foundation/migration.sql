-- CreateEnum
CREATE TYPE "VehicleType" AS ENUM ('CAR', 'MOTORCYCLE', 'BUS', 'TRUCK', 'CNG', 'PICKUP', 'MICROBUS', 'AMBULANCE', 'CONSTRUCTION_EQUIPMENT', 'OTHER');

-- CreateEnum
CREATE TYPE "VehicleStatus" AS ENUM ('PENDING', 'ACTIVE', 'INACTIVE', 'SUSPENDED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "DeviceNetworkType" AS ENUM ('GSM_2G', 'UMTS_3G', 'LTE_4G', 'LTE_5G', 'LORA', 'SATELLITE', 'OTHER');

-- CreateEnum
CREATE TYPE "DeviceModelStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "DeviceLifecycleStatus" AS ENUM ('RECEIVED', 'IN_STOCK', 'RESERVED', 'ALLOCATED', 'INSTALLED', 'UNDER_REPAIR', 'LOST', 'DAMAGED', 'RETIRED');

-- CreateEnum
CREATE TYPE "DeviceOwnerType" AS ENUM ('PLATFORM', 'DEALER', 'CUSTOMER');

-- CreateEnum
CREATE TYPE "DeviceCustodianType" AS ENUM ('PLATFORM', 'DEALER', 'CUSTOMER', 'USER');

-- CreateEnum
CREATE TYPE "DeviceOwnershipReason" AS ENUM ('INITIAL_STOCK', 'PURCHASE', 'SALE', 'TRANSFER', 'RETURN', 'ADJUSTMENT', 'OTHER');

-- CreateEnum
CREATE TYPE "DeviceCustodyReason" AS ENUM ('RECEIVED', 'ALLOCATION', 'INSTALLATION', 'REMOVAL', 'REPAIR', 'RETURN', 'TRANSFER', 'ADJUSTMENT', 'OTHER');

-- CreateEnum
CREATE TYPE "DeviceAllocationStatus" AS ENUM ('ALLOCATED', 'AVAILABLE', 'INSTALLED', 'RETURNED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "InstallationStatus" AS ENUM ('SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'CANCELLED', 'REMOVED');

-- CreateEnum
CREATE TYPE "AssignmentType" AS ENUM ('PRIMARY', 'SECONDARY', 'BACKUP');

-- CreateEnum
CREATE TYPE "AssignmentStatus" AS ENUM ('ACTIVE', 'ENDED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "AssignmentEndReason" AS ENUM ('DEVICE_FAILURE', 'DEVICE_REPLACEMENT', 'VEHICLE_TRANSFER', 'VEHICLE_SOLD', 'CUSTOMER_REQUEST', 'SUBSCRIPTION_CANCELLED', 'TRANSFER_TO_ANOTHER_VEHICLE', 'LOST', 'OTHER');

-- CreateEnum
CREATE TYPE "InstallationRemovalReason" AS ENUM ('CUSTOMER_REQUEST', 'VEHICLE_SOLD', 'DEVICE_FAILURE', 'WARRANTY_REPLACEMENT', 'SUBSCRIPTION_CANCELLED', 'TRANSFER_TO_ANOTHER_VEHICLE', 'LOST', 'OTHER');

-- CreateTable
CREATE TABLE "vehicles" (
    "id" UUID NOT NULL,
    "vehicleCode" VARCHAR(40) NOT NULL,
    "customerId" UUID NOT NULL,
    "registrationNumber" VARCHAR(100),
    "normalizedRegistrationNumber" VARCHAR(100),
    "vehicleType" "VehicleType" NOT NULL,
    "manufacturer" VARCHAR(120),
    "modelName" VARCHAR(120),
    "manufacturingYear" INTEGER,
    "color" VARCHAR(60),
    "chassisNumber" VARCHAR(120),
    "engineNumber" VARCHAR(120),
    "status" "VehicleStatus" NOT NULL DEFAULT 'PENDING',
    "createdByUserId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "vehicles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device_models" (
    "id" UUID NOT NULL,
    "modelCode" VARCHAR(60) NOT NULL,
    "manufacturer" VARCHAR(120) NOT NULL,
    "modelName" VARCHAR(160) NOT NULL,
    "protocol" VARCHAR(100) NOT NULL,
    "networkType" "DeviceNetworkType" NOT NULL,
    "capabilities" JSONB,
    "status" "DeviceModelStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "device_models_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" UUID NOT NULL,
    "deviceCode" VARCHAR(40) NOT NULL,
    "deviceModelId" UUID NOT NULL,
    "imei" VARCHAR(32),
    "serialNumber" VARCHAR(100),
    "hardwareVersion" VARCHAR(60),
    "firmwareVersion" VARCHAR(60),
    "lifecycleStatus" "DeviceLifecycleStatus" NOT NULL DEFAULT 'RECEIVED',
    "receivedAt" TIMESTAMPTZ(3),
    "retiredAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device_ownership_history" (
    "id" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "ownerType" "DeviceOwnerType" NOT NULL,
    "ownerOrganizationId" UUID,
    "ownerCustomerId" UUID,
    "startedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMPTZ(3),
    "reason" "DeviceOwnershipReason" NOT NULL,
    "changedByUserId" UUID,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "device_ownership_history_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device_custody_history" (
    "id" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "custodianType" "DeviceCustodianType" NOT NULL,
    "custodianOrganizationId" UUID,
    "custodianCustomerId" UUID,
    "custodianUserId" UUID,
    "startedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMPTZ(3),
    "reason" "DeviceCustodyReason" NOT NULL,
    "changedByUserId" UUID,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "device_custody_history_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dealer_device_allocations" (
    "id" UUID NOT NULL,
    "allocationCode" VARCHAR(40) NOT NULL,
    "dealerOrganizationId" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "status" "DeviceAllocationStatus" NOT NULL DEFAULT 'ALLOCATED',
    "allocatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "availableAt" TIMESTAMPTZ(3),
    "installedAt" TIMESTAMPTZ(3),
    "returnedAt" TIMESTAMPTZ(3),
    "allocatedByUserId" UUID,
    "returnedByUserId" UUID,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "dealer_device_allocations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device_installations" (
    "id" UUID NOT NULL,
    "installationCode" VARCHAR(40) NOT NULL,
    "deviceId" UUID NOT NULL,
    "vehicleId" UUID NOT NULL,
    "dealerOrganizationId" UUID,
    "installedByUserId" UUID,
    "installedAt" TIMESTAMPTZ(3),
    "installationLocation" JSONB,
    "odometerReading" DECIMAL(12,2),
    "powerConnectionType" VARCHAR(80),
    "ignitionConnected" BOOLEAN NOT NULL DEFAULT false,
    "relayConnected" BOOLEAN NOT NULL DEFAULT false,
    "sosConnected" BOOLEAN NOT NULL DEFAULT false,
    "installationNotes" TEXT,
    "status" "InstallationStatus" NOT NULL DEFAULT 'SCHEDULED',
    "verifiedByUserId" UUID,
    "verifiedAt" TIMESTAMPTZ(3),
    "removedAt" TIMESTAMPTZ(3),
    "removalReason" "InstallationRemovalReason",
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "device_installations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "vehicle_device_assignments" (
    "id" UUID NOT NULL,
    "vehicleId" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "installationId" UUID,
    "assignmentType" "AssignmentType" NOT NULL DEFAULT 'PRIMARY',
    "startedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMPTZ(3),
    "status" "AssignmentStatus" NOT NULL DEFAULT 'ACTIVE',
    "assignedByUserId" UUID,
    "endedByUserId" UUID,
    "endReason" "AssignmentEndReason",
    "endNotes" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "vehicle_device_assignments_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "vehicles_vehicleCode_key" ON "vehicles"("vehicleCode");

-- CreateIndex
CREATE UNIQUE INDEX "vehicles_normalizedRegistrationNumber_key" ON "vehicles"("normalizedRegistrationNumber");

-- CreateIndex
CREATE UNIQUE INDEX "vehicles_chassisNumber_key" ON "vehicles"("chassisNumber");

-- CreateIndex
CREATE UNIQUE INDEX "vehicles_engineNumber_key" ON "vehicles"("engineNumber");

-- CreateIndex
CREATE INDEX "vehicles_customerId_status_idx" ON "vehicles"("customerId", "status");

-- CreateIndex
CREATE INDEX "vehicles_vehicleType_status_idx" ON "vehicles"("vehicleType", "status");

-- CreateIndex
CREATE UNIQUE INDEX "device_models_modelCode_key" ON "device_models"("modelCode");

-- CreateIndex
CREATE INDEX "device_models_status_idx" ON "device_models"("status");

-- CreateIndex
CREATE UNIQUE INDEX "devices_deviceCode_key" ON "devices"("deviceCode");

-- CreateIndex
CREATE UNIQUE INDEX "devices_imei_key" ON "devices"("imei");

-- CreateIndex
CREATE UNIQUE INDEX "devices_serialNumber_key" ON "devices"("serialNumber");

-- CreateIndex
CREATE INDEX "devices_deviceModelId_lifecycleStatus_idx" ON "devices"("deviceModelId", "lifecycleStatus");

-- CreateIndex
CREATE INDEX "devices_lifecycleStatus_idx" ON "devices"("lifecycleStatus");

-- CreateIndex
CREATE INDEX "device_ownership_history_deviceId_startedAt_idx" ON "device_ownership_history"("deviceId", "startedAt");

-- CreateIndex
CREATE INDEX "device_ownership_history_ownerOrganizationId_endedAt_idx" ON "device_ownership_history"("ownerOrganizationId", "endedAt");

-- CreateIndex
CREATE INDEX "device_ownership_history_ownerCustomerId_endedAt_idx" ON "device_ownership_history"("ownerCustomerId", "endedAt");

-- CreateIndex
CREATE INDEX "device_custody_history_deviceId_startedAt_idx" ON "device_custody_history"("deviceId", "startedAt");

-- CreateIndex
CREATE INDEX "device_custody_history_custodianOrganizationId_endedAt_idx" ON "device_custody_history"("custodianOrganizationId", "endedAt");

-- CreateIndex
CREATE INDEX "device_custody_history_custodianCustomerId_endedAt_idx" ON "device_custody_history"("custodianCustomerId", "endedAt");

-- CreateIndex
CREATE INDEX "device_custody_history_custodianUserId_endedAt_idx" ON "device_custody_history"("custodianUserId", "endedAt");

-- CreateIndex
CREATE UNIQUE INDEX "dealer_device_allocations_allocationCode_key" ON "dealer_device_allocations"("allocationCode");

-- CreateIndex
CREATE INDEX "dealer_device_allocations_dealerOrganizationId_status_idx" ON "dealer_device_allocations"("dealerOrganizationId", "status");

-- CreateIndex
CREATE INDEX "dealer_device_allocations_deviceId_status_idx" ON "dealer_device_allocations"("deviceId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "device_installations_installationCode_key" ON "device_installations"("installationCode");

-- CreateIndex
CREATE INDEX "device_installations_deviceId_status_idx" ON "device_installations"("deviceId", "status");

-- CreateIndex
CREATE INDEX "device_installations_vehicleId_status_idx" ON "device_installations"("vehicleId", "status");

-- CreateIndex
CREATE INDEX "device_installations_dealerOrganizationId_status_idx" ON "device_installations"("dealerOrganizationId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "vehicle_device_assignments_installationId_key" ON "vehicle_device_assignments"("installationId");

-- CreateIndex
CREATE INDEX "vehicle_device_assignments_vehicleId_status_idx" ON "vehicle_device_assignments"("vehicleId", "status");

-- CreateIndex
CREATE INDEX "vehicle_device_assignments_deviceId_status_idx" ON "vehicle_device_assignments"("deviceId", "status");

-- CreateIndex
CREATE INDEX "vehicle_device_assignments_assignmentType_status_idx" ON "vehicle_device_assignments"("assignmentType", "status");

-- AddForeignKey
ALTER TABLE "vehicles" ADD CONSTRAINT "vehicles_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicles" ADD CONSTRAINT "vehicles_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_deviceModelId_fkey" FOREIGN KEY ("deviceModelId") REFERENCES "device_models"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_ownership_history" ADD CONSTRAINT "device_ownership_history_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_ownership_history" ADD CONSTRAINT "device_ownership_history_ownerOrganizationId_fkey" FOREIGN KEY ("ownerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_ownership_history" ADD CONSTRAINT "device_ownership_history_ownerCustomerId_fkey" FOREIGN KEY ("ownerCustomerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_ownership_history" ADD CONSTRAINT "device_ownership_history_changedByUserId_fkey" FOREIGN KEY ("changedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_custody_history" ADD CONSTRAINT "device_custody_history_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_custody_history" ADD CONSTRAINT "device_custody_history_custodianOrganizationId_fkey" FOREIGN KEY ("custodianOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_custody_history" ADD CONSTRAINT "device_custody_history_custodianCustomerId_fkey" FOREIGN KEY ("custodianCustomerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_custody_history" ADD CONSTRAINT "device_custody_history_custodianUserId_fkey" FOREIGN KEY ("custodianUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_custody_history" ADD CONSTRAINT "device_custody_history_changedByUserId_fkey" FOREIGN KEY ("changedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_device_allocations" ADD CONSTRAINT "dealer_device_allocations_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_device_allocations" ADD CONSTRAINT "dealer_device_allocations_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_device_allocations" ADD CONSTRAINT "dealer_device_allocations_allocatedByUserId_fkey" FOREIGN KEY ("allocatedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_device_allocations" ADD CONSTRAINT "dealer_device_allocations_returnedByUserId_fkey" FOREIGN KEY ("returnedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_installations" ADD CONSTRAINT "device_installations_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_installations" ADD CONSTRAINT "device_installations_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_installations" ADD CONSTRAINT "device_installations_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_installations" ADD CONSTRAINT "device_installations_installedByUserId_fkey" FOREIGN KEY ("installedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_installations" ADD CONSTRAINT "device_installations_verifiedByUserId_fkey" FOREIGN KEY ("verifiedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicle_device_assignments" ADD CONSTRAINT "vehicle_device_assignments_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicle_device_assignments" ADD CONSTRAINT "vehicle_device_assignments_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicle_device_assignments" ADD CONSTRAINT "vehicle_device_assignments_installationId_fkey" FOREIGN KEY ("installationId") REFERENCES "device_installations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicle_device_assignments" ADD CONSTRAINT "vehicle_device_assignments_assignedByUserId_fkey" FOREIGN KEY ("assignedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicle_device_assignments" ADD CONSTRAINT "vehicle_device_assignments_endedByUserId_fkey" FOREIGN KEY ("endedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Solid Tracker Phase 2 vehicle/device invariants.

ALTER TABLE "vehicles"
ADD CONSTRAINT "vehicles_manufacturing_year_range"
CHECK (
  "manufacturingYear" IS NULL
  OR "manufacturingYear" BETWEEN 1886 AND 2100
);

ALTER TABLE "devices"
ADD CONSTRAINT "devices_retirement_consistency"
CHECK (
  ("lifecycleStatus" = 'RETIRED' AND "retiredAt" IS NOT NULL)
  OR
  ("lifecycleStatus" <> 'RETIRED' AND "retiredAt" IS NULL)
);

ALTER TABLE "device_installations"
ADD CONSTRAINT "device_installations_status_consistency"
CHECK (
  (
    "status" IN ('COMPLETED', 'REMOVED')
    AND "installedAt" IS NOT NULL
  )
  OR
  "status" IN ('SCHEDULED', 'IN_PROGRESS', 'FAILED', 'CANCELLED')
);

ALTER TABLE "device_installations"
ADD CONSTRAINT "device_installations_removal_consistency"
CHECK (
  (
    "status" = 'REMOVED'
    AND "removedAt" IS NOT NULL
    AND "removalReason" IS NOT NULL
  )
  OR
  (
    "status" <> 'REMOVED'
    AND "removedAt" IS NULL
    AND "removalReason" IS NULL
  )
);

ALTER TABLE "vehicle_device_assignments"
ADD CONSTRAINT "vehicle_device_assignments_status_consistency"
CHECK (
  (
    "status" = 'ACTIVE'
    AND "endedAt" IS NULL
    AND "endReason" IS NULL
  )
  OR
  (
    "status" IN ('ENDED', 'CANCELLED')
    AND "endedAt" IS NOT NULL
  )
);

CREATE UNIQUE INDEX
  "device_ownership_history_one_active_per_device"
ON "device_ownership_history" ("deviceId")
WHERE "endedAt" IS NULL;

CREATE UNIQUE INDEX
  "device_custody_history_one_active_per_device"
ON "device_custody_history" ("deviceId")
WHERE "endedAt" IS NULL;

CREATE UNIQUE INDEX
  "dealer_device_allocations_one_active_per_device"
ON "dealer_device_allocations" ("deviceId")
WHERE "status" IN ('ALLOCATED', 'AVAILABLE', 'INSTALLED');

CREATE UNIQUE INDEX
  "vehicle_device_assignments_one_active_per_device"
ON "vehicle_device_assignments" ("deviceId")
WHERE "status" = 'ACTIVE' AND "endedAt" IS NULL;

CREATE UNIQUE INDEX
  "vehicle_device_assignments_one_active_primary_per_vehicle"
ON "vehicle_device_assignments" ("vehicleId")
WHERE
  "assignmentType" = 'PRIMARY'
  AND "status" = 'ACTIVE'
  AND "endedAt" IS NULL;

CREATE OR REPLACE FUNCTION "solid_tracker_assert_organization_type"(
  organization_id UUID,
  expected_type "OrganizationType"
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  actual_type "OrganizationType";
BEGIN
  SELECT "type"
  INTO actual_type
  FROM "organizations"
  WHERE "id" = organization_id;

  IF NOT FOUND OR actual_type <> expected_type THEN
    RAISE EXCEPTION
      'Organization % must exist and have type %',
      organization_id,
      expected_type;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION "solid_tracker_validate_device_owner"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."ownerType" = 'CUSTOMER' THEN
    IF NEW."ownerCustomerId" IS NULL
       OR NEW."ownerOrganizationId" IS NOT NULL THEN
      RAISE EXCEPTION
        'CUSTOMER ownership requires only ownerCustomerId';
    END IF;

  ELSIF NEW."ownerType" = 'PLATFORM' THEN
    IF NEW."ownerOrganizationId" IS NULL
       OR NEW."ownerCustomerId" IS NOT NULL THEN
      RAISE EXCEPTION
        'PLATFORM ownership requires only ownerOrganizationId';
    END IF;

    PERFORM "solid_tracker_assert_organization_type"(
      NEW."ownerOrganizationId",
      'PLATFORM'
    );

  ELSIF NEW."ownerType" = 'DEALER' THEN
    IF NEW."ownerOrganizationId" IS NULL
       OR NEW."ownerCustomerId" IS NOT NULL THEN
      RAISE EXCEPTION
        'DEALER ownership requires only ownerOrganizationId';
    END IF;

    PERFORM "solid_tracker_assert_organization_type"(
      NEW."ownerOrganizationId",
      'DEALER'
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "device_ownership_validate_owner"
BEFORE INSERT OR UPDATE OF
  "ownerType",
  "ownerOrganizationId",
  "ownerCustomerId"
ON "device_ownership_history"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_device_owner"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_device_custodian"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."custodianType" = 'CUSTOMER' THEN
    IF NEW."custodianCustomerId" IS NULL
       OR NEW."custodianOrganizationId" IS NOT NULL
       OR NEW."custodianUserId" IS NOT NULL THEN
      RAISE EXCEPTION
        'CUSTOMER custody requires only custodianCustomerId';
    END IF;

  ELSIF NEW."custodianType" = 'USER' THEN
    IF NEW."custodianUserId" IS NULL
       OR NEW."custodianOrganizationId" IS NOT NULL
       OR NEW."custodianCustomerId" IS NOT NULL THEN
      RAISE EXCEPTION
        'USER custody requires only custodianUserId';
    END IF;

  ELSIF NEW."custodianType" = 'PLATFORM' THEN
    IF NEW."custodianOrganizationId" IS NULL
       OR NEW."custodianCustomerId" IS NOT NULL
       OR NEW."custodianUserId" IS NOT NULL THEN
      RAISE EXCEPTION
        'PLATFORM custody requires only custodianOrganizationId';
    END IF;

    PERFORM "solid_tracker_assert_organization_type"(
      NEW."custodianOrganizationId",
      'PLATFORM'
    );

  ELSIF NEW."custodianType" = 'DEALER' THEN
    IF NEW."custodianOrganizationId" IS NULL
       OR NEW."custodianCustomerId" IS NOT NULL
       OR NEW."custodianUserId" IS NOT NULL THEN
      RAISE EXCEPTION
        'DEALER custody requires only custodianOrganizationId';
    END IF;

    PERFORM "solid_tracker_assert_organization_type"(
      NEW."custodianOrganizationId",
      'DEALER'
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "device_custody_validate_custodian"
BEFORE INSERT OR UPDATE OF
  "custodianType",
  "custodianOrganizationId",
  "custodianCustomerId",
  "custodianUserId"
ON "device_custody_history"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_device_custodian"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_device_allocation"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM "solid_tracker_assert_organization_type"(
    NEW."dealerOrganizationId",
    'DEALER'
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER "dealer_device_allocations_validate_dealer"
BEFORE INSERT OR UPDATE OF "dealerOrganizationId"
ON "dealer_device_allocations"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_device_allocation"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_installation_dealer"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."dealerOrganizationId" IS NOT NULL THEN
    PERFORM "solid_tracker_assert_organization_type"(
      NEW."dealerOrganizationId",
      'DEALER'
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "device_installations_validate_dealer"
BEFORE INSERT OR UPDATE OF "dealerOrganizationId"
ON "device_installations"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_installation_dealer"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_assignment_installation"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  installation_device_id UUID;
  installation_vehicle_id UUID;
BEGIN
  IF NEW."installationId" IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT "deviceId", "vehicleId"
  INTO installation_device_id, installation_vehicle_id
  FROM "device_installations"
  WHERE "id" = NEW."installationId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Installation % does not exist',
      NEW."installationId";
  END IF;

  IF installation_device_id <> NEW."deviceId"
     OR installation_vehicle_id <> NEW."vehicleId" THEN
    RAISE EXCEPTION
      'Assignment device and vehicle must match the linked installation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "vehicle_device_assignments_validate_installation"
BEFORE INSERT OR UPDATE OF
  "installationId",
  "deviceId",
  "vehicleId"
ON "vehicle_device_assignments"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_assignment_installation"();