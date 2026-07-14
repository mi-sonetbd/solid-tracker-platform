-- CreateEnum
CREATE TYPE "TraccarServerStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'DEGRADED', 'MAINTENANCE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "TraccarHealthStatus" AS ENUM ('UNKNOWN', 'UP', 'DEGRADED', 'DOWN');

-- CreateEnum
CREATE TYPE "TraccarSyncStatus" AS ENUM ('PENDING', 'SYNCED', 'FAILED', 'DISABLED', 'DELETED_EXTERNALLY');

-- CreateEnum
CREATE TYPE "TrackingEventSeverity" AS ENUM ('INFO', 'WARNING', 'CRITICAL');

-- CreateEnum
CREATE TYPE "TrackingEventProcessingStatus" AS ENUM ('RECEIVED', 'PROCESSING', 'PROCESSED', 'FAILED', 'IGNORED');

-- CreateEnum
CREATE TYPE "GeofenceGeometryType" AS ENUM ('CIRCLE', 'POLYGON', 'POLYLINE');

-- CreateEnum
CREATE TYPE "GeofenceStatus" AS ENUM ('DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "GeofenceAssignmentStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'ENDED');

-- CreateEnum
CREATE TYPE "NotificationChannel" AS ENUM ('PUSH', 'SMS', 'EMAIL', 'IN_APP', 'WHATSAPP', 'VOICE_CALL');

-- CreateEnum
CREATE TYPE "NotificationRecipientType" AS ENUM ('USER', 'CUSTOMER_OWNER', 'CUSTOMER_ADMIN', 'CUSTOM_ADDRESS');

-- CreateEnum
CREATE TYPE "NotificationStatus" AS ENUM ('QUEUED', 'PROCESSING', 'SENT', 'DELIVERED', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "DeviceCommandType" AS ENUM ('REQUEST_POSITION', 'RESTART_DEVICE', 'SET_REPORTING_INTERVAL', 'ACTIVATE_RELAY', 'DEACTIVATE_RELAY', 'ENGINE_CUTOFF', 'ENGINE_RESTORE', 'CHANGE_SERVER', 'CUSTOM');

-- CreateEnum
CREATE TYPE "DeviceCommandStatus" AS ENUM ('PENDING_APPROVAL', 'QUEUED', 'SENT', 'ACKNOWLEDGED', 'COMPLETED', 'FAILED', 'CANCELLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "IntegrationJobType" AS ENUM ('CREATE_DEVICE', 'UPDATE_DEVICE', 'DISABLE_DEVICE', 'SYNC_DEVICE', 'FETCH_LATEST_POSITION', 'PROCESS_EVENT', 'SYNC_GEOFENCE', 'SEND_COMMAND', 'RETRY_FAILED_SYNC');

-- CreateEnum
CREATE TYPE "IntegrationJobStatus" AS ENUM ('PENDING', 'PROCESSING', 'SUCCEEDED', 'FAILED', 'CANCELLED', 'DEAD_LETTER');

-- CreateTable
CREATE TABLE "traccar_servers" (
    "id" UUID NOT NULL,
    "serverCode" VARCHAR(60) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "baseUrl" VARCHAR(500) NOT NULL,
    "apiUsernameReference" VARCHAR(160),
    "encryptedCredentialReference" TEXT NOT NULL,
    "status" "TraccarServerStatus" NOT NULL DEFAULT 'ACTIVE',
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "lastHealthCheckAt" TIMESTAMPTZ(3),
    "lastHealthStatus" "TraccarHealthStatus" NOT NULL DEFAULT 'UNKNOWN',
    "lastHealthError" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "traccar_servers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "traccar_device_mappings" (
    "id" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "traccarServerId" UUID NOT NULL,
    "traccarDeviceId" BIGINT NOT NULL,
    "traccarUniqueId" VARCHAR(160) NOT NULL,
    "syncStatus" "TraccarSyncStatus" NOT NULL DEFAULT 'PENDING',
    "isPrimary" BOOLEAN NOT NULL DEFAULT true,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "lastSyncAttemptAt" TIMESTAMPTZ(3),
    "lastSyncedAt" TIMESTAMPTZ(3),
    "lastSyncError" TEXT,
    "disabledAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "traccar_device_mappings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tracking_events" (
    "id" UUID NOT NULL,
    "eventCode" VARCHAR(70) NOT NULL,
    "customerId" UUID NOT NULL,
    "vehicleId" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "traccarServerId" UUID,
    "traccarEventId" BIGINT,
    "deduplicationKey" VARCHAR(160) NOT NULL,
    "eventType" VARCHAR(100) NOT NULL,
    "severity" "TrackingEventSeverity" NOT NULL DEFAULT 'INFO',
    "latitude" DECIMAL(10,7),
    "longitude" DECIMAL(10,7),
    "occurredAt" TIMESTAMPTZ(3) NOT NULL,
    "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "attributes" JSONB,
    "processingStatus" "TrackingEventProcessingStatus" NOT NULL DEFAULT 'RECEIVED',
    "processingError" TEXT,
    "acknowledgedAt" TIMESTAMPTZ(3),
    "acknowledgedByUserId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "tracking_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "geofences" (
    "id" UUID NOT NULL,
    "geofenceCode" VARCHAR(60) NOT NULL,
    "customerId" UUID NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "normalizedName" VARCHAR(160) NOT NULL,
    "description" TEXT,
    "geometryType" "GeofenceGeometryType" NOT NULL,
    "geometryData" JSONB NOT NULL,
    "status" "GeofenceStatus" NOT NULL DEFAULT 'DRAFT',
    "traccarServerId" UUID,
    "traccarGeofenceId" BIGINT,
    "syncStatus" "TraccarSyncStatus" NOT NULL DEFAULT 'PENDING',
    "lastSyncAttemptAt" TIMESTAMPTZ(3),
    "lastSyncedAt" TIMESTAMPTZ(3),
    "lastSyncError" TEXT,
    "createdByUserId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "geofences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "vehicle_geofence_assignments" (
    "id" UUID NOT NULL,
    "geofenceId" UUID NOT NULL,
    "vehicleId" UUID NOT NULL,
    "monitorEntry" BOOLEAN NOT NULL DEFAULT true,
    "monitorExit" BOOLEAN NOT NULL DEFAULT true,
    "activeFrom" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "activeUntil" TIMESTAMPTZ(3),
    "status" "GeofenceAssignmentStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "vehicle_geofence_assignments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_rules" (
    "id" UUID NOT NULL,
    "ruleCode" VARCHAR(60) NOT NULL,
    "customerId" UUID NOT NULL,
    "vehicleId" UUID,
    "eventType" VARCHAR(100) NOT NULL,
    "minimumSeverity" "TrackingEventSeverity" NOT NULL DEFAULT 'INFO',
    "channel" "NotificationChannel" NOT NULL,
    "recipientType" "NotificationRecipientType" NOT NULL,
    "recipientUserId" UUID,
    "recipientAddress" VARCHAR(320),
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "quietHoursStartMinute" INTEGER,
    "quietHoursEndMinute" INTEGER,
    "cooldownSeconds" INTEGER NOT NULL DEFAULT 0,
    "dailyLimit" INTEGER,
    "createdByUserId" UUID,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,
    "archivedAt" TIMESTAMPTZ(3),

    CONSTRAINT "notification_rules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL,
    "notificationCode" VARCHAR(70) NOT NULL,
    "customerId" UUID NOT NULL,
    "userId" UUID,
    "trackingEventId" UUID,
    "notificationRuleId" UUID,
    "channel" "NotificationChannel" NOT NULL,
    "recipient" VARCHAR(320) NOT NULL,
    "subject" VARCHAR(240),
    "renderedContent" TEXT NOT NULL,
    "status" "NotificationStatus" NOT NULL DEFAULT 'QUEUED',
    "provider" VARCHAR(120),
    "providerMessageId" VARCHAR(200),
    "queuedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processingAt" TIMESTAMPTZ(3),
    "sentAt" TIMESTAMPTZ(3),
    "deliveredAt" TIMESTAMPTZ(3),
    "failedAt" TIMESTAMPTZ(3),
    "failureReason" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "device_command_requests" (
    "id" UUID NOT NULL,
    "commandCode" VARCHAR(70) NOT NULL,
    "deviceId" UUID NOT NULL,
    "vehicleId" UUID,
    "traccarServerId" UUID,
    "requestedByUserId" UUID NOT NULL,
    "approvedByUserId" UUID,
    "commandType" "DeviceCommandType" NOT NULL,
    "parameters" JSONB,
    "reason" TEXT NOT NULL,
    "status" "DeviceCommandStatus" NOT NULL DEFAULT 'QUEUED',
    "requiresApproval" BOOLEAN NOT NULL DEFAULT false,
    "approvedAt" TIMESTAMPTZ(3),
    "traccarCommandId" BIGINT,
    "requestedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sentAt" TIMESTAMPTZ(3),
    "acknowledgedAt" TIMESTAMPTZ(3),
    "completedAt" TIMESTAMPTZ(3),
    "failedAt" TIMESTAMPTZ(3),
    "failureReason" TEXT,
    "expiresAt" TIMESTAMPTZ(3),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "device_command_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "integration_jobs" (
    "id" UUID NOT NULL,
    "jobCode" VARCHAR(70) NOT NULL,
    "idempotencyKey" VARCHAR(180),
    "jobType" "IntegrationJobType" NOT NULL,
    "traccarServerId" UUID,
    "entityType" VARCHAR(100) NOT NULL,
    "entityId" VARCHAR(100) NOT NULL,
    "status" "IntegrationJobStatus" NOT NULL DEFAULT 'PENDING',
    "priority" INTEGER NOT NULL DEFAULT 100,
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "maximumAttempts" INTEGER NOT NULL DEFAULT 5,
    "nextAttemptAt" TIMESTAMPTZ(3),
    "lockedAt" TIMESTAMPTZ(3),
    "startedAt" TIMESTAMPTZ(3),
    "completedAt" TIMESTAMPTZ(3),
    "failedAt" TIMESTAMPTZ(3),
    "lastError" TEXT,
    "payload" JSONB,
    "result" JSONB,
    "correlationId" VARCHAR(100),
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "integration_jobs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "traccar_servers_serverCode_key" ON "traccar_servers"("serverCode");

-- CreateIndex
CREATE UNIQUE INDEX "traccar_servers_baseUrl_key" ON "traccar_servers"("baseUrl");

-- CreateIndex
CREATE INDEX "traccar_servers_status_idx" ON "traccar_servers"("status");

-- CreateIndex
CREATE INDEX "traccar_device_mappings_syncStatus_isActive_idx" ON "traccar_device_mappings"("syncStatus", "isActive");

-- CreateIndex
CREATE UNIQUE INDEX "traccar_device_mappings_deviceId_traccarServerId_key" ON "traccar_device_mappings"("deviceId", "traccarServerId");

-- CreateIndex
CREATE UNIQUE INDEX "traccar_device_mappings_traccarServerId_traccarDeviceId_key" ON "traccar_device_mappings"("traccarServerId", "traccarDeviceId");

-- CreateIndex
CREATE UNIQUE INDEX "traccar_device_mappings_traccarServerId_traccarUniqueId_key" ON "traccar_device_mappings"("traccarServerId", "traccarUniqueId");

-- CreateIndex
CREATE UNIQUE INDEX "tracking_events_eventCode_key" ON "tracking_events"("eventCode");

-- CreateIndex
CREATE UNIQUE INDEX "tracking_events_deduplicationKey_key" ON "tracking_events"("deduplicationKey");

-- CreateIndex
CREATE INDEX "tracking_events_customerId_occurredAt_idx" ON "tracking_events"("customerId", "occurredAt");

-- CreateIndex
CREATE INDEX "tracking_events_vehicleId_occurredAt_idx" ON "tracking_events"("vehicleId", "occurredAt");

-- CreateIndex
CREATE INDEX "tracking_events_deviceId_occurredAt_idx" ON "tracking_events"("deviceId", "occurredAt");

-- CreateIndex
CREATE INDEX "tracking_events_eventType_severity_occurredAt_idx" ON "tracking_events"("eventType", "severity", "occurredAt");

-- CreateIndex
CREATE INDEX "tracking_events_processingStatus_receivedAt_idx" ON "tracking_events"("processingStatus", "receivedAt");

-- CreateIndex
CREATE UNIQUE INDEX "tracking_events_traccarServerId_traccarEventId_key" ON "tracking_events"("traccarServerId", "traccarEventId");

-- CreateIndex
CREATE UNIQUE INDEX "geofences_geofenceCode_key" ON "geofences"("geofenceCode");

-- CreateIndex
CREATE INDEX "geofences_customerId_status_idx" ON "geofences"("customerId", "status");

-- CreateIndex
CREATE INDEX "geofences_syncStatus_idx" ON "geofences"("syncStatus");

-- CreateIndex
CREATE UNIQUE INDEX "geofences_customerId_normalizedName_key" ON "geofences"("customerId", "normalizedName");

-- CreateIndex
CREATE UNIQUE INDEX "geofences_traccarServerId_traccarGeofenceId_key" ON "geofences"("traccarServerId", "traccarGeofenceId");

-- CreateIndex
CREATE INDEX "vehicle_geofence_assignments_geofenceId_status_idx" ON "vehicle_geofence_assignments"("geofenceId", "status");

-- CreateIndex
CREATE INDEX "vehicle_geofence_assignments_vehicleId_status_idx" ON "vehicle_geofence_assignments"("vehicleId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "notification_rules_ruleCode_key" ON "notification_rules"("ruleCode");

-- CreateIndex
CREATE INDEX "notification_rules_customerId_enabled_idx" ON "notification_rules"("customerId", "enabled");

-- CreateIndex
CREATE INDEX "notification_rules_vehicleId_enabled_idx" ON "notification_rules"("vehicleId", "enabled");

-- CreateIndex
CREATE INDEX "notification_rules_eventType_minimumSeverity_enabled_idx" ON "notification_rules"("eventType", "minimumSeverity", "enabled");

-- CreateIndex
CREATE UNIQUE INDEX "notifications_notificationCode_key" ON "notifications"("notificationCode");

-- CreateIndex
CREATE INDEX "notifications_customerId_status_idx" ON "notifications"("customerId", "status");

-- CreateIndex
CREATE INDEX "notifications_userId_status_idx" ON "notifications"("userId", "status");

-- CreateIndex
CREATE INDEX "notifications_trackingEventId_idx" ON "notifications"("trackingEventId");

-- CreateIndex
CREATE INDEX "notifications_status_queuedAt_idx" ON "notifications"("status", "queuedAt");

-- CreateIndex
CREATE UNIQUE INDEX "notifications_provider_providerMessageId_key" ON "notifications"("provider", "providerMessageId");

-- CreateIndex
CREATE UNIQUE INDEX "device_command_requests_commandCode_key" ON "device_command_requests"("commandCode");

-- CreateIndex
CREATE INDEX "device_command_requests_deviceId_status_idx" ON "device_command_requests"("deviceId", "status");

-- CreateIndex
CREATE INDEX "device_command_requests_vehicleId_status_idx" ON "device_command_requests"("vehicleId", "status");

-- CreateIndex
CREATE INDEX "device_command_requests_requestedByUserId_requestedAt_idx" ON "device_command_requests"("requestedByUserId", "requestedAt");

-- CreateIndex
CREATE INDEX "device_command_requests_status_expiresAt_idx" ON "device_command_requests"("status", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "device_command_requests_traccarServerId_traccarCommandId_key" ON "device_command_requests"("traccarServerId", "traccarCommandId");

-- CreateIndex
CREATE UNIQUE INDEX "integration_jobs_jobCode_key" ON "integration_jobs"("jobCode");

-- CreateIndex
CREATE UNIQUE INDEX "integration_jobs_idempotencyKey_key" ON "integration_jobs"("idempotencyKey");

-- CreateIndex
CREATE INDEX "integration_jobs_status_priority_nextAttemptAt_idx" ON "integration_jobs"("status", "priority", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "integration_jobs_traccarServerId_status_idx" ON "integration_jobs"("traccarServerId", "status");

-- CreateIndex
CREATE INDEX "integration_jobs_entityType_entityId_idx" ON "integration_jobs"("entityType", "entityId");

-- CreateIndex
CREATE INDEX "integration_jobs_correlationId_idx" ON "integration_jobs"("correlationId");

-- AddForeignKey
ALTER TABLE "traccar_device_mappings" ADD CONSTRAINT "traccar_device_mappings_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "traccar_device_mappings" ADD CONSTRAINT "traccar_device_mappings_traccarServerId_fkey" FOREIGN KEY ("traccarServerId") REFERENCES "traccar_servers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tracking_events" ADD CONSTRAINT "tracking_events_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tracking_events" ADD CONSTRAINT "tracking_events_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tracking_events" ADD CONSTRAINT "tracking_events_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tracking_events" ADD CONSTRAINT "tracking_events_traccarServerId_fkey" FOREIGN KEY ("traccarServerId") REFERENCES "traccar_servers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tracking_events" ADD CONSTRAINT "tracking_events_acknowledgedByUserId_fkey" FOREIGN KEY ("acknowledgedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "geofences" ADD CONSTRAINT "geofences_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "geofences" ADD CONSTRAINT "geofences_traccarServerId_fkey" FOREIGN KEY ("traccarServerId") REFERENCES "traccar_servers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "geofences" ADD CONSTRAINT "geofences_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicle_geofence_assignments" ADD CONSTRAINT "vehicle_geofence_assignments_geofenceId_fkey" FOREIGN KEY ("geofenceId") REFERENCES "geofences"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicle_geofence_assignments" ADD CONSTRAINT "vehicle_geofence_assignments_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_rules" ADD CONSTRAINT "notification_rules_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_rules" ADD CONSTRAINT "notification_rules_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_rules" ADD CONSTRAINT "notification_rules_recipientUserId_fkey" FOREIGN KEY ("recipientUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_rules" ADD CONSTRAINT "notification_rules_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_trackingEventId_fkey" FOREIGN KEY ("trackingEventId") REFERENCES "tracking_events"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_notificationRuleId_fkey" FOREIGN KEY ("notificationRuleId") REFERENCES "notification_rules"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_command_requests" ADD CONSTRAINT "device_command_requests_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_command_requests" ADD CONSTRAINT "device_command_requests_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "vehicles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_command_requests" ADD CONSTRAINT "device_command_requests_traccarServerId_fkey" FOREIGN KEY ("traccarServerId") REFERENCES "traccar_servers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_command_requests" ADD CONSTRAINT "device_command_requests_requestedByUserId_fkey" FOREIGN KEY ("requestedByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_command_requests" ADD CONSTRAINT "device_command_requests_approvedByUserId_fkey" FOREIGN KEY ("approvedByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "integration_jobs" ADD CONSTRAINT "integration_jobs_traccarServerId_fkey" FOREIGN KEY ("traccarServerId") REFERENCES "traccar_servers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Solid Tracker Phase 4 tracking-integration invariants.

ALTER TABLE "traccar_servers"
ADD CONSTRAINT "traccar_servers_archive_consistency"
CHECK (
  (
    "status" = 'ARCHIVED'
    AND "archivedAt" IS NOT NULL
  )
  OR
  (
    "status" <> 'ARCHIVED'
  )
);

ALTER TABLE "traccar_device_mappings"
ADD CONSTRAINT "traccar_device_mappings_state_consistency"
CHECK (
  (
    "isActive" = TRUE
    AND "disabledAt" IS NULL
    AND "syncStatus" <> 'DISABLED'
  )
  OR
  (
    "isActive" = FALSE
    AND "disabledAt" IS NOT NULL
  )
);

ALTER TABLE "tracking_events"
ADD CONSTRAINT "tracking_events_coordinates_valid"
CHECK (
  (
    "latitude" IS NULL
    AND "longitude" IS NULL
  )
  OR
  (
    "latitude" BETWEEN -90 AND 90
    AND "longitude" BETWEEN -180 AND 180
  )
);

ALTER TABLE "tracking_events"
ADD CONSTRAINT "tracking_events_acknowledgement_valid"
CHECK (
  (
    "acknowledgedAt" IS NULL
    AND "acknowledgedByUserId" IS NULL
  )
  OR
  (
    "acknowledgedAt" IS NOT NULL
    AND "acknowledgedByUserId" IS NOT NULL
  )
);

ALTER TABLE "geofences"
ADD CONSTRAINT "geofences_external_mapping_valid"
CHECK (
  (
    "traccarGeofenceId" IS NULL
    AND (
      "syncStatus" IN ('PENDING', 'FAILED', 'DISABLED')
      OR "traccarServerId" IS NOT NULL
    )
  )
  OR
  (
    "traccarGeofenceId" IS NOT NULL
    AND "traccarServerId" IS NOT NULL
  )
);

ALTER TABLE "vehicle_geofence_assignments"
ADD CONSTRAINT "vehicle_geofence_assignments_period_valid"
CHECK (
  (
    "activeUntil" IS NULL
    OR "activeUntil" > "activeFrom"
  )
  AND (
    "monitorEntry" = TRUE
    OR "monitorExit" = TRUE
  )
);

ALTER TABLE "notification_rules"
ADD CONSTRAINT "notification_rules_limits_valid"
CHECK (
  "cooldownSeconds" >= 0
  AND (
    "dailyLimit" IS NULL
    OR "dailyLimit" > 0
  )
  AND (
    (
      "quietHoursStartMinute" IS NULL
      AND "quietHoursEndMinute" IS NULL
    )
    OR
    (
      "quietHoursStartMinute" BETWEEN 0 AND 1439
      AND "quietHoursEndMinute" BETWEEN 0 AND 1439
    )
  )
);

ALTER TABLE "notification_rules"
ADD CONSTRAINT "notification_rules_recipient_valid"
CHECK (
  (
    "recipientType" = 'USER'
    AND "recipientUserId" IS NOT NULL
    AND "recipientAddress" IS NULL
  )
  OR
  (
    "recipientType" = 'CUSTOM_ADDRESS'
    AND "recipientUserId" IS NULL
    AND "recipientAddress" IS NOT NULL
  )
  OR
  (
    "recipientType" IN ('CUSTOMER_OWNER', 'CUSTOMER_ADMIN')
    AND "recipientUserId" IS NULL
    AND "recipientAddress" IS NULL
  )
);

ALTER TABLE "notifications"
ADD CONSTRAINT "notifications_status_timestamps_valid"
CHECK (
  (
    "status" = 'QUEUED'
    AND "processingAt" IS NULL
    AND "sentAt" IS NULL
    AND "deliveredAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'PROCESSING'
    AND "processingAt" IS NOT NULL
    AND "deliveredAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'SENT'
    AND "sentAt" IS NOT NULL
    AND "deliveredAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'DELIVERED'
    AND "sentAt" IS NOT NULL
    AND "deliveredAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'FAILED'
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" = 'CANCELLED'
  )
);

ALTER TABLE "device_command_requests"
ADD CONSTRAINT "device_command_requests_expiry_valid"
CHECK (
  "expiresAt" IS NULL
  OR "expiresAt" > "requestedAt"
);

ALTER TABLE "device_command_requests"
ADD CONSTRAINT "device_command_requests_approval_valid"
CHECK (
  (
    "requiresApproval" = FALSE
    AND "approvedByUserId" IS NULL
    AND "approvedAt" IS NULL
    AND "status" <> 'PENDING_APPROVAL'
  )
  OR
  (
    "requiresApproval" = TRUE
    AND (
      (
        "status" = 'PENDING_APPROVAL'
        AND "approvedByUserId" IS NULL
        AND "approvedAt" IS NULL
      )
      OR
      (
        "status" <> 'PENDING_APPROVAL'
        AND "approvedByUserId" IS NOT NULL
        AND "approvedAt" IS NOT NULL
        AND "approvedByUserId" <> "requestedByUserId"
      )
    )
  )
);

ALTER TABLE "device_command_requests"
ADD CONSTRAINT "device_command_requests_status_timestamps_valid"
CHECK (
  (
    "status" IN ('PENDING_APPROVAL', 'QUEUED')
    AND "sentAt" IS NULL
    AND "acknowledgedAt" IS NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'SENT'
    AND "sentAt" IS NOT NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'ACKNOWLEDGED'
    AND "sentAt" IS NOT NULL
    AND "acknowledgedAt" IS NOT NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'COMPLETED'
    AND "sentAt" IS NOT NULL
    AND "completedAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'FAILED'
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" IN ('CANCELLED', 'EXPIRED')
  )
);

ALTER TABLE "integration_jobs"
ADD CONSTRAINT "integration_jobs_attempts_valid"
CHECK (
  "priority" >= 0
  AND "attemptCount" >= 0
  AND "maximumAttempts" > 0
  AND "attemptCount" <= "maximumAttempts"
);

ALTER TABLE "integration_jobs"
ADD CONSTRAINT "integration_jobs_status_timestamps_valid"
CHECK (
  (
    "status" = 'PENDING'
    AND "startedAt" IS NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'PROCESSING'
    AND "startedAt" IS NOT NULL
    AND "completedAt" IS NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" = 'SUCCEEDED'
    AND "startedAt" IS NOT NULL
    AND "completedAt" IS NOT NULL
    AND "failedAt" IS NULL
  )
  OR
  (
    "status" IN ('FAILED', 'DEAD_LETTER')
    AND "failedAt" IS NOT NULL
  )
  OR
  (
    "status" = 'CANCELLED'
  )
);

CREATE UNIQUE INDEX
  "traccar_servers_one_active_default"
ON "traccar_servers" ("isDefault")
WHERE
  "isDefault" = TRUE
  AND "status" = 'ACTIVE';

CREATE UNIQUE INDEX
  "traccar_device_mappings_one_active_primary_per_device"
ON "traccar_device_mappings" ("deviceId")
WHERE
  "isPrimary" = TRUE
  AND "isActive" = TRUE
  AND "syncStatus" <> 'DISABLED';

CREATE UNIQUE INDEX
  "vehicle_geofence_assignments_one_active_pair"
ON "vehicle_geofence_assignments" ("geofenceId", "vehicleId")
WHERE "status" = 'ACTIVE';

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_traccar_mapping"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  server_status "TraccarServerStatus";
BEGIN
  SELECT "status"
  INTO server_status
  FROM "traccar_servers"
  WHERE "id" = NEW."traccarServerId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Traccar server % does not exist',
      NEW."traccarServerId";
  END IF;

  IF NEW."isActive" = TRUE
     AND server_status NOT IN ('ACTIVE', 'DEGRADED') THEN
    RAISE EXCEPTION
      'Active mappings require an active or degraded Traccar server';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "traccar_mappings_validate_server"
BEFORE INSERT OR UPDATE OF
  "traccarServerId",
  "isActive",
  "syncStatus"
ON "traccar_device_mappings"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_traccar_mapping"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_tracking_event"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vehicle_customer_id UUID;
BEGIN
  SELECT "customerId"
  INTO vehicle_customer_id
  FROM "vehicles"
  WHERE "id" = NEW."vehicleId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Vehicle % does not exist',
      NEW."vehicleId";
  END IF;

  IF vehicle_customer_id <> NEW."customerId" THEN
    RAISE EXCEPTION
      'Tracking event customer must own the vehicle';
  END IF;

  IF NEW."traccarServerId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "traccar_device_mappings"
       WHERE "deviceId" = NEW."deviceId"
         AND "traccarServerId" = NEW."traccarServerId"
     ) THEN
    RAISE EXCEPTION
      'Tracking event device is not mapped to the selected Traccar server';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "tracking_events_validate_context"
BEFORE INSERT OR UPDATE OF
  "customerId",
  "vehicleId",
  "deviceId",
  "traccarServerId"
ON "tracking_events"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_tracking_event"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_geofence"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."traccarServerId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "traccar_servers"
       WHERE "id" = NEW."traccarServerId"
         AND "status" IN ('ACTIVE', 'DEGRADED', 'MAINTENANCE')
     ) THEN
    RAISE EXCEPTION
      'Geofence references an unavailable Traccar server';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "geofences_validate_context"
BEFORE INSERT OR UPDATE OF
  "traccarServerId",
  "syncStatus"
ON "geofences"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_geofence"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_geofence_assignment"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  geofence_customer_id UUID;
  vehicle_customer_id UUID;
BEGIN
  SELECT "customerId"
  INTO geofence_customer_id
  FROM "geofences"
  WHERE "id" = NEW."geofenceId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Geofence % does not exist',
      NEW."geofenceId";
  END IF;

  SELECT "customerId"
  INTO vehicle_customer_id
  FROM "vehicles"
  WHERE "id" = NEW."vehicleId";

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Vehicle % does not exist',
      NEW."vehicleId";
  END IF;

  IF geofence_customer_id <> vehicle_customer_id THEN
    RAISE EXCEPTION
      'Geofence and vehicle must belong to the same customer';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "geofence_assignments_validate_context"
BEFORE INSERT OR UPDATE OF
  "geofenceId",
  "vehicleId"
ON "vehicle_geofence_assignments"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_geofence_assignment"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_notification_rule"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  vehicle_customer_id UUID;
BEGIN
  IF NEW."vehicleId" IS NOT NULL THEN
    SELECT "customerId"
    INTO vehicle_customer_id
    FROM "vehicles"
    WHERE "id" = NEW."vehicleId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Vehicle % does not exist',
        NEW."vehicleId";
    END IF;

    IF vehicle_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Notification-rule vehicle must belong to the rule customer';
    END IF;
  END IF;

  IF NEW."recipientUserId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "customer_memberships"
       WHERE "customerId" = NEW."customerId"
         AND "userId" = NEW."recipientUserId"
         AND "status" = 'ACTIVE'
     ) THEN
    RAISE EXCEPTION
      'Notification recipient user must be an active customer member';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "notification_rules_validate_context"
BEFORE INSERT OR UPDATE OF
  "customerId",
  "vehicleId",
  "recipientUserId",
  "recipientType"
ON "notification_rules"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_notification_rule"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_notification"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  event_customer_id UUID;
  rule_customer_id UUID;
BEGIN
  IF NEW."trackingEventId" IS NOT NULL THEN
    SELECT "customerId"
    INTO event_customer_id
    FROM "tracking_events"
    WHERE "id" = NEW."trackingEventId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Tracking event % does not exist',
        NEW."trackingEventId";
    END IF;

    IF event_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Notification customer must match tracking-event customer';
    END IF;
  END IF;

  IF NEW."notificationRuleId" IS NOT NULL THEN
    SELECT "customerId"
    INTO rule_customer_id
    FROM "notification_rules"
    WHERE "id" = NEW."notificationRuleId";

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Notification rule % does not exist',
        NEW."notificationRuleId";
    END IF;

    IF rule_customer_id <> NEW."customerId" THEN
      RAISE EXCEPTION
        'Notification customer must match notification-rule customer';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "notifications_validate_context"
BEFORE INSERT OR UPDATE OF
  "customerId",
  "trackingEventId",
  "notificationRuleId"
ON "notifications"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_notification"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_device_command"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."commandType" IN ('ENGINE_CUTOFF', 'ENGINE_RESTORE') THEN
    IF NEW."requiresApproval" <> TRUE THEN
      RAISE EXCEPTION
        'Engine-control commands require approval';
    END IF;

    IF NEW."vehicleId" IS NULL THEN
      RAISE EXCEPTION
        'Engine-control commands require a vehicle';
    END IF;
  END IF;

  IF NEW."vehicleId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "vehicle_device_assignments"
       WHERE "vehicleId" = NEW."vehicleId"
         AND "deviceId" = NEW."deviceId"
         AND "status" = 'ACTIVE'
         AND "endedAt" IS NULL
     ) THEN
    RAISE EXCEPTION
      'Command device must be actively assigned to the selected vehicle';
  END IF;

  IF NEW."traccarServerId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "traccar_device_mappings"
       WHERE "deviceId" = NEW."deviceId"
         AND "traccarServerId" = NEW."traccarServerId"
         AND "isActive" = TRUE
     ) THEN
    RAISE EXCEPTION
      'Command device must have an active mapping on the selected server';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "device_commands_validate_context"
BEFORE INSERT OR UPDATE OF
  "deviceId",
  "vehicleId",
  "traccarServerId",
  "commandType",
  "requiresApproval",
  "approvedByUserId",
  "approvedAt",
  "status"
ON "device_command_requests"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_device_command"();

CREATE OR REPLACE FUNCTION
  "solid_tracker_validate_integration_job"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."traccarServerId" IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM "traccar_servers"
       WHERE "id" = NEW."traccarServerId"
         AND "status" <> 'ARCHIVED'
     ) THEN
    RAISE EXCEPTION
      'Integration job references an unavailable Traccar server';
  END IF;

  IF NEW."status" IN ('FAILED', 'DEAD_LETTER')
     AND NEW."lastError" IS NULL THEN
    RAISE EXCEPTION
      'Failed integration jobs require an error message';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "integration_jobs_validate_context"
BEFORE INSERT OR UPDATE OF
  "traccarServerId",
  "status",
  "lastError"
ON "integration_jobs"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_validate_integration_job"();