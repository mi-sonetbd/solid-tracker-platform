-- CreateEnum
CREATE TYPE "RecordStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('PENDING_VERIFICATION', 'ACTIVE', 'LOCKED', 'DISABLED', 'SUSPENDED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "OrganizationType" AS ENUM ('PLATFORM', 'DEALER', 'CUSTOMER_ORGANIZATION');

-- CreateEnum
CREATE TYPE "OrganizationStatus" AS ENUM ('PENDING', 'ACTIVE', 'SUSPENDED', 'INACTIVE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "MembershipType" AS ENUM ('OWNER', 'EMPLOYEE', 'CONTRACTOR', 'MEMBER');

-- CreateEnum
CREATE TYPE "MembershipStatus" AS ENUM ('INVITED', 'ACTIVE', 'SUSPENDED', 'ENDED');

-- CreateEnum
CREATE TYPE "ScopeType" AS ENUM ('PLATFORM', 'ZONE', 'DEALER', 'CUSTOMER_GROUP', 'CUSTOMER', 'VEHICLE', 'SELF');

-- CreateEnum
CREATE TYPE "RoleAssignmentStatus" AS ENUM ('ACTIVE', 'SUSPENDED', 'REVOKED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "SessionPlatform" AS ENUM ('ANDROID', 'WEB', 'IOS', 'API_CLIENT');

-- CreateEnum
CREATE TYPE "SessionStatus" AS ENUM ('ACTIVE', 'REVOKED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "CustomerType" AS ENUM ('INDIVIDUAL', 'ORGANIZATION');

-- CreateEnum
CREATE TYPE "CustomerStatus" AS ENUM ('PENDING', 'ACTIVE', 'SUSPENDED', 'INACTIVE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "AcquisitionSource" AS ENUM ('DIRECT', 'DEALER', 'MIGRATION', 'PARTNER');

-- CreateEnum
CREATE TYPE "CustomerGroupStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "CustomerManagementType" AS ENUM ('PLATFORM', 'DEALER');

-- CreateEnum
CREATE TYPE "AssignmentReason" AS ENUM ('INITIAL_ASSIGNMENT', 'PLATFORM_ASSIGNMENT', 'DEALER_TRANSFER', 'MANUAL_CORRECTION', 'OTHER');

-- CreateTable
CREATE TABLE "zones" (
    "id" UUID NOT NULL,
    "code" VARCHAR(40) NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "description" TEXT,
    "status" "RecordStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "zones_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organizations" (
    "id" UUID NOT NULL,
    "code" VARCHAR(40) NOT NULL,
    "type" "OrganizationType" NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "legalName" VARCHAR(200),
    "zoneId" UUID,
    "status" "OrganizationStatus" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "organizations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "dealer_profiles" (
    "organizationId" UUID NOT NULL,
    "dealerCode" VARCHAR(40) NOT NULL,
    "tradeLicenseNumber" VARCHAR(100),
    "taxIdentificationNumber" VARCHAR(100),
    "contactMobile" VARCHAR(30),
    "contactEmail" VARCHAR(254),
    "commissionEnabled" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "dealer_profiles_pkey" PRIMARY KEY ("organizationId")
);

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "userCode" VARCHAR(40) NOT NULL,
    "fullName" VARCHAR(160) NOT NULL,
    "mobileNumber" VARCHAR(30) NOT NULL,
    "normalizedMobileNumber" VARCHAR(30) NOT NULL,
    "email" VARCHAR(254),
    "normalizedEmail" VARCHAR(254),
    "passwordHash" TEXT,
    "status" "UserStatus" NOT NULL DEFAULT 'PENDING_VERIFICATION',
    "mobileVerifiedAt" TIMESTAMPTZ(3),
    "emailVerifiedAt" TIMESTAMPTZ(3),
    "passwordChangedAt" TIMESTAMPTZ(3),
    "lastLoginAt" TIMESTAMPTZ(3),
    "failedLoginCount" INTEGER NOT NULL DEFAULT 0,
    "lockedUntil" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_memberships" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "membershipType" "MembershipType" NOT NULL,
    "status" "MembershipStatus" NOT NULL DEFAULT 'INVITED',
    "isPrimary" BOOLEAN NOT NULL DEFAULT false,
    "invitedByUserId" UUID,
    "joinedAt" TIMESTAMPTZ(3),
    "endedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "organization_memberships_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "roles" (
    "id" UUID NOT NULL,
    "code" VARCHAR(80) NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "description" TEXT,
    "status" "RecordStatus" NOT NULL DEFAULT 'ACTIVE',
    "isSystem" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "roles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "permissions" (
    "id" UUID NOT NULL,
    "code" VARCHAR(120) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "description" TEXT,
    "status" "RecordStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "permissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "role_permissions" (
    "roleId" UUID NOT NULL,
    "permissionId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("roleId","permissionId")
);

-- CreateTable
CREATE TABLE "role_assignments" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "roleId" UUID NOT NULL,
    "organizationMembershipId" UUID,
    "scopeType" "ScopeType" NOT NULL,
    "scopeId" UUID NOT NULL,
    "status" "RoleAssignmentStatus" NOT NULL DEFAULT 'ACTIVE',
    "effectiveFrom" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "effectiveUntil" TIMESTAMPTZ(3),
    "assignedByUserId" UUID,
    "revokedByUserId" UUID,
    "revokedAt" TIMESTAMPTZ(3),
    "revocationReason" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "role_assignments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_sessions" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tokenFamilyId" UUID NOT NULL,
    "refreshTokenHash" TEXT NOT NULL,
    "deviceName" VARCHAR(160),
    "platform" "SessionPlatform" NOT NULL,
    "appVersion" VARCHAR(50),
    "ipAddress" VARCHAR(45),
    "userAgent" TEXT,
    "status" "SessionStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastUsedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "revokedAt" TIMESTAMPTZ(3),
    "revocationReason" TEXT,

    CONSTRAINT "user_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "customer_groups" (
    "id" UUID NOT NULL,
    "code" VARCHAR(40) NOT NULL,
    "dealerOrganizationId" UUID NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "normalizedName" VARCHAR(120) NOT NULL,
    "description" TEXT,
    "status" "CustomerGroupStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdByUserId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "customer_groups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "customers" (
    "id" UUID NOT NULL,
    "customerCode" VARCHAR(40) NOT NULL,
    "customerType" "CustomerType" NOT NULL,
    "status" "CustomerStatus" NOT NULL DEFAULT 'PENDING',
    "managingDealerId" UUID,
    "customerGroupId" UUID,
    "acquisitionSource" "AcquisitionSource" NOT NULL,
    "primaryMobile" VARCHAR(30),
    "primaryEmail" VARCHAR(254),
    "billingAddress" JSONB,
    "createdByUserId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "customers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "individual_customer_profiles" (
    "customerId" UUID NOT NULL,
    "fullName" VARCHAR(160) NOT NULL,
    "dateOfBirth" DATE,
    "emergencyContactName" VARCHAR(160),
    "emergencyContactMobile" VARCHAR(30),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "individual_customer_profiles_pkey" PRIMARY KEY ("customerId")
);

-- CreateTable
CREATE TABLE "organization_customer_profiles" (
    "customerId" UUID NOT NULL,
    "legalName" VARCHAR(200) NOT NULL,
    "displayName" VARCHAR(160) NOT NULL,
    "registrationNumber" VARCHAR(100),
    "taxReference" VARCHAR(100),
    "contactPersonName" VARCHAR(160),
    "contactMobile" VARCHAR(30),
    "contactEmail" VARCHAR(254),
    "operationalAddress" JSONB,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "organization_customer_profiles_pkey" PRIMARY KEY ("customerId")
);

-- CreateTable
CREATE TABLE "customer_memberships" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "status" "MembershipStatus" NOT NULL DEFAULT 'INVITED',
    "isPrimary" BOOLEAN NOT NULL DEFAULT false,
    "invitedByUserId" UUID,
    "joinedAt" TIMESTAMPTZ(3),
    "endedAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "customer_memberships_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "customer_dealer_assignments" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "managementType" "CustomerManagementType" NOT NULL,
    "dealerOrganizationId" UUID,
    "assignedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMPTZ(3),
    "assignmentReason" "AssignmentReason" NOT NULL,
    "assignedByUserId" UUID,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "customer_dealer_assignments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL,
    "actorUserId" UUID,
    "actorOrganizationId" UUID,
    "action" VARCHAR(160) NOT NULL,
    "resourceType" VARCHAR(100) NOT NULL,
    "resourceId" VARCHAR(100),
    "scopeType" "ScopeType",
    "scopeId" UUID,
    "beforeData" JSONB,
    "afterData" JSONB,
    "metadata" JSONB,
    "ipAddress" VARCHAR(45),
    "userAgent" TEXT,
    "correlationId" VARCHAR(100),
    "occurredAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "zones_code_key" ON "zones"("code");

-- CreateIndex
CREATE INDEX "zones_status_idx" ON "zones"("status");

-- CreateIndex
CREATE UNIQUE INDEX "organizations_code_key" ON "organizations"("code");

-- CreateIndex
CREATE INDEX "organizations_type_status_idx" ON "organizations"("type", "status");

-- CreateIndex
CREATE INDEX "organizations_zoneId_idx" ON "organizations"("zoneId");

-- CreateIndex
CREATE UNIQUE INDEX "dealer_profiles_dealerCode_key" ON "dealer_profiles"("dealerCode");

-- CreateIndex
CREATE UNIQUE INDEX "users_userCode_key" ON "users"("userCode");

-- CreateIndex
CREATE UNIQUE INDEX "users_normalizedMobileNumber_key" ON "users"("normalizedMobileNumber");

-- CreateIndex
CREATE UNIQUE INDEX "users_normalizedEmail_key" ON "users"("normalizedEmail");

-- CreateIndex
CREATE INDEX "users_status_idx" ON "users"("status");

-- CreateIndex
CREATE INDEX "organization_memberships_userId_status_idx" ON "organization_memberships"("userId", "status");

-- CreateIndex
CREATE INDEX "organization_memberships_organizationId_status_idx" ON "organization_memberships"("organizationId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "organization_memberships_organizationId_userId_key" ON "organization_memberships"("organizationId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "roles_code_key" ON "roles"("code");

-- CreateIndex
CREATE INDEX "roles_status_idx" ON "roles"("status");

-- CreateIndex
CREATE UNIQUE INDEX "permissions_code_key" ON "permissions"("code");

-- CreateIndex
CREATE INDEX "permissions_status_idx" ON "permissions"("status");

-- CreateIndex
CREATE INDEX "role_permissions_permissionId_idx" ON "role_permissions"("permissionId");

-- CreateIndex
CREATE INDEX "role_assignments_userId_status_idx" ON "role_assignments"("userId", "status");

-- CreateIndex
CREATE INDEX "role_assignments_scopeType_scopeId_status_idx" ON "role_assignments"("scopeType", "scopeId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "role_assignments_userId_roleId_scopeType_scopeId_key" ON "role_assignments"("userId", "roleId", "scopeType", "scopeId");

-- CreateIndex
CREATE UNIQUE INDEX "user_sessions_refreshTokenHash_key" ON "user_sessions"("refreshTokenHash");

-- CreateIndex
CREATE INDEX "user_sessions_userId_status_idx" ON "user_sessions"("userId", "status");

-- CreateIndex
CREATE INDEX "user_sessions_expiresAt_idx" ON "user_sessions"("expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "customer_groups_code_key" ON "customer_groups"("code");

-- CreateIndex
CREATE INDEX "customer_groups_dealerOrganizationId_status_idx" ON "customer_groups"("dealerOrganizationId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "customer_groups_dealerOrganizationId_normalizedName_key" ON "customer_groups"("dealerOrganizationId", "normalizedName");

-- CreateIndex
CREATE UNIQUE INDEX "customers_customerCode_key" ON "customers"("customerCode");

-- CreateIndex
CREATE INDEX "customers_managingDealerId_status_idx" ON "customers"("managingDealerId", "status");

-- CreateIndex
CREATE INDEX "customers_customerGroupId_idx" ON "customers"("customerGroupId");

-- CreateIndex
CREATE INDEX "customers_customerType_status_idx" ON "customers"("customerType", "status");

-- CreateIndex
CREATE INDEX "customers_primaryMobile_idx" ON "customers"("primaryMobile");

-- CreateIndex
CREATE UNIQUE INDEX "organization_customer_profiles_registrationNumber_key" ON "organization_customer_profiles"("registrationNumber");

-- CreateIndex
CREATE INDEX "customer_memberships_userId_status_idx" ON "customer_memberships"("userId", "status");

-- CreateIndex
CREATE INDEX "customer_memberships_customerId_status_idx" ON "customer_memberships"("customerId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "customer_memberships_customerId_userId_key" ON "customer_memberships"("customerId", "userId");

-- CreateIndex
CREATE INDEX "customer_dealer_assignments_customerId_assignedAt_idx" ON "customer_dealer_assignments"("customerId", "assignedAt");

-- CreateIndex
CREATE INDEX "customer_dealer_assignments_dealerOrganizationId_endedAt_idx" ON "customer_dealer_assignments"("dealerOrganizationId", "endedAt");

-- CreateIndex
CREATE INDEX "audit_logs_actorUserId_occurredAt_idx" ON "audit_logs"("actorUserId", "occurredAt");

-- CreateIndex
CREATE INDEX "audit_logs_resourceType_resourceId_idx" ON "audit_logs"("resourceType", "resourceId");

-- CreateIndex
CREATE INDEX "audit_logs_correlationId_idx" ON "audit_logs"("correlationId");

-- CreateIndex
CREATE INDEX "audit_logs_occurredAt_idx" ON "audit_logs"("occurredAt");

-- AddForeignKey
ALTER TABLE "organizations" ADD CONSTRAINT "organizations_zoneId_fkey" FOREIGN KEY ("zoneId") REFERENCES "zones"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "dealer_profiles" ADD CONSTRAINT "dealer_profiles_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "organization_memberships" ADD CONSTRAINT "organization_memberships_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "organization_memberships" ADD CONSTRAINT "organization_memberships_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "organization_memberships" ADD CONSTRAINT "organization_memberships_invitedByUserId_fkey" FOREIGN KEY ("invitedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "role_permissions" ADD CONSTRAINT "role_permissions_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "roles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "role_permissions" ADD CONSTRAINT "role_permissions_permissionId_fkey" FOREIGN KEY ("permissionId") REFERENCES "permissions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "role_assignments" ADD CONSTRAINT "role_assignments_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "role_assignments" ADD CONSTRAINT "role_assignments_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "roles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "role_assignments" ADD CONSTRAINT "role_assignments_organizationMembershipId_fkey" FOREIGN KEY ("organizationMembershipId") REFERENCES "organization_memberships"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "role_assignments" ADD CONSTRAINT "role_assignments_assignedByUserId_fkey" FOREIGN KEY ("assignedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "role_assignments" ADD CONSTRAINT "role_assignments_revokedByUserId_fkey" FOREIGN KEY ("revokedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_sessions" ADD CONSTRAINT "user_sessions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_groups" ADD CONSTRAINT "customer_groups_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_groups" ADD CONSTRAINT "customer_groups_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customers" ADD CONSTRAINT "customers_managingDealerId_fkey" FOREIGN KEY ("managingDealerId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customers" ADD CONSTRAINT "customers_customerGroupId_fkey" FOREIGN KEY ("customerGroupId") REFERENCES "customer_groups"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customers" ADD CONSTRAINT "customers_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "individual_customer_profiles" ADD CONSTRAINT "individual_customer_profiles_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "organization_customer_profiles" ADD CONSTRAINT "organization_customer_profiles_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_memberships" ADD CONSTRAINT "customer_memberships_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_memberships" ADD CONSTRAINT "customer_memberships_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_memberships" ADD CONSTRAINT "customer_memberships_invitedByUserId_fkey" FOREIGN KEY ("invitedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_dealer_assignments" ADD CONSTRAINT "customer_dealer_assignments_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_dealer_assignments" ADD CONSTRAINT "customer_dealer_assignments_dealerOrganizationId_fkey" FOREIGN KEY ("dealerOrganizationId") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customer_dealer_assignments" ADD CONSTRAINT "customer_dealer_assignments_assignedByUserId_fkey" FOREIGN KEY ("assignedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_actorOrganizationId_fkey" FOREIGN KEY ("actorOrganizationId") REFERENCES "organizations"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Solid Tracker Phase 1 invariants that require PostgreSQL-native constraints.

ALTER TABLE "customers"
ADD CONSTRAINT "customers_direct_group_consistency"
CHECK (
  "managingDealerId" IS NOT NULL
  OR "customerGroupId" IS NULL
);

ALTER TABLE "customer_dealer_assignments"
ADD CONSTRAINT "customer_dealer_assignment_management_consistency"
CHECK (
  (
    "managementType" = 'PLATFORM'
    AND "dealerOrganizationId" IS NULL
  )
  OR
  (
    "managementType" = 'DEALER'
    AND "dealerOrganizationId" IS NOT NULL
  )
);

CREATE UNIQUE INDEX
  "customer_dealer_assignments_one_active_per_customer"
ON "customer_dealer_assignments" ("customerId")
WHERE "endedAt" IS NULL;

CREATE UNIQUE INDEX
  "customer_memberships_one_active_primary_per_customer"
ON "customer_memberships" ("customerId")
WHERE "isPrimary" = TRUE AND "status" = 'ACTIVE';

CREATE UNIQUE INDEX
  "organization_memberships_one_active_primary_per_organization"
ON "organization_memberships" ("organizationId")
WHERE "isPrimary" = TRUE AND "status" = 'ACTIVE';

CREATE OR REPLACE FUNCTION "solid_tracker_assert_dealer_organization"(
  organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  organization_type "OrganizationType";
BEGIN
  SELECT "type"
  INTO organization_type
  FROM "organizations"
  WHERE "id" = organization_id;

  IF NOT FOUND OR organization_type <> 'DEALER' THEN
    RAISE EXCEPTION
      'Organization % must exist and have type DEALER',
      organization_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION "solid_tracker_validate_dealer_profile"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM "solid_tracker_assert_dealer_organization"(NEW."organizationId");
  RETURN NEW;
END;
$$;

CREATE TRIGGER "dealer_profiles_validate_organization"
BEFORE INSERT OR UPDATE OF "organizationId"
ON "dealer_profiles"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_dealer_profile"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_customer_group"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM "solid_tracker_assert_dealer_organization"(
    NEW."dealerOrganizationId"
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER "customer_groups_validate_dealer"
BEFORE INSERT OR UPDATE OF "dealerOrganizationId"
ON "customer_groups"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_customer_group"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_customer"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  group_dealer_id UUID;
BEGIN
  IF NEW."managingDealerId" IS NOT NULL THEN
    PERFORM "solid_tracker_assert_dealer_organization"(
      NEW."managingDealerId"
    );
  END IF;

  IF NEW."customerGroupId" IS NOT NULL THEN
    IF NEW."managingDealerId" IS NULL THEN
      RAISE EXCEPTION
        'A direct customer cannot belong to a dealer customer group';
    END IF;

    SELECT "dealerOrganizationId"
    INTO group_dealer_id
    FROM "customer_groups"
    WHERE "id" = NEW."customerGroupId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Customer group % does not exist',
        NEW."customerGroupId";
    END IF;

    IF group_dealer_id <> NEW."managingDealerId" THEN
      RAISE EXCEPTION
        'Customer group dealer must match the customer managing dealer';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "customers_validate_management"
BEFORE INSERT OR UPDATE OF "managingDealerId", "customerGroupId"
ON "customers"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_customer"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_customer_assignment"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."managementType" = 'DEALER' THEN
    PERFORM "solid_tracker_assert_dealer_organization"(
      NEW."dealerOrganizationId"
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "customer_assignments_validate_dealer"
BEFORE INSERT OR UPDATE OF "managementType", "dealerOrganizationId"
ON "customer_dealer_assignments"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_customer_assignment"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_individual_profile"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM "customers"
    WHERE "id" = NEW."customerId"
      AND "customerType" = 'INDIVIDUAL'
  ) THEN
    RAISE EXCEPTION
      'Individual profile requires an INDIVIDUAL customer';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "individual_profiles_validate_customer_type"
BEFORE INSERT OR UPDATE OF "customerId"
ON "individual_customer_profiles"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_individual_profile"();

CREATE OR REPLACE FUNCTION "solid_tracker_validate_organization_profile"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM "customers"
    WHERE "id" = NEW."customerId"
      AND "customerType" = 'ORGANIZATION'
  ) THEN
    RAISE EXCEPTION
      'Organization profile requires an ORGANIZATION customer';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "organization_profiles_validate_customer_type"
BEFORE INSERT OR UPDATE OF "customerId"
ON "organization_customer_profiles"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_organization_profile"();
