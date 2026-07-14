CREATE TYPE "NotificationTemplateStatus" AS ENUM (
  'DRAFT',
  'ACTIVE',
  'INACTIVE',
  'ARCHIVED'
);

CREATE TYPE "NotificationDeliveryAttemptStatus" AS ENUM (
  'PROCESSING',
  'SENT',
  'DELIVERED',
  'FAILED',
  'DEAD_LETTER',
  'CANCELLED'
);

CREATE TYPE "NotificationProviderEventStatus" AS ENUM (
  'RECEIVED',
  'PROCESSED',
  'IGNORED',
  'FAILED'
);

CREATE TABLE "notification_templates" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "templateCode" VARCHAR(80) NOT NULL,
  "templateKey" VARCHAR(120) NOT NULL,
  "channel" "NotificationChannel" NOT NULL,
  "locale" VARCHAR(20) NOT NULL DEFAULT 'en',
  "version" INTEGER NOT NULL DEFAULT 1,
  "name" VARCHAR(160) NOT NULL,
  "subjectTemplate" VARCHAR(240),
  "bodyTemplate" TEXT NOT NULL,
  "variableSchema" JSONB,
  "status" "NotificationTemplateStatus" NOT NULL DEFAULT 'DRAFT',
  "createdByUserId" UUID,
  "activatedAt" TIMESTAMPTZ(3),
  "archivedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notification_templates_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "notification_templates_version_positive"
    CHECK ("version" > 0)
);

CREATE TABLE "notification_delivery_attempts" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "notificationId" UUID NOT NULL,
  "attemptNumber" INTEGER NOT NULL,
  "provider" VARCHAR(120) NOT NULL,
  "idempotencyKey" VARCHAR(180) NOT NULL,
  "status" "NotificationDeliveryAttemptStatus" NOT NULL DEFAULT 'PROCESSING',
  "requestPayload" JSONB,
  "responsePayload" JSONB,
  "providerMessageId" VARCHAR(200),
  "errorCode" VARCHAR(100),
  "errorMessage" TEXT,
  "nextRetryAt" TIMESTAMPTZ(3),
  "startedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMPTZ(3),
  "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "notification_delivery_attempts_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "notification_delivery_attempts_number_positive"
    CHECK ("attemptNumber" > 0)
);

CREATE TABLE "notification_provider_events" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "provider" VARCHAR(120) NOT NULL,
  "externalEventId" VARCHAR(180) NOT NULL,
  "notificationId" UUID,
  "providerMessageId" VARCHAR(200),
  "eventType" VARCHAR(100) NOT NULL,
  "status" "NotificationProviderEventStatus" NOT NULL DEFAULT 'RECEIVED',
  "signatureValid" BOOLEAN NOT NULL DEFAULT false,
  "payload" JSONB NOT NULL,
  "receivedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "processedAt" TIMESTAMPTZ(3),
  "error" TEXT,
  CONSTRAINT "notification_provider_events_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "notification_templates_templateCode_key"
ON "notification_templates" ("templateCode");

CREATE UNIQUE INDEX "notification_templates_templateKey_channel_locale_version_key"
ON "notification_templates" (
  "templateKey",
  "channel",
  "locale",
  "version"
);

CREATE INDEX "notification_templates_templateKey_channel_locale_status_idx"
ON "notification_templates" (
  "templateKey",
  "channel",
  "locale",
  "status"
);

CREATE INDEX "notification_templates_status_createdAt_idx"
ON "notification_templates" ("status", "createdAt");

CREATE UNIQUE INDEX "notification_templates_one_active_variant"
ON "notification_templates" (
  "templateKey",
  "channel",
  "locale"
)
WHERE "status" = 'ACTIVE';

CREATE UNIQUE INDEX "notification_delivery_attempts_idempotencyKey_key"
ON "notification_delivery_attempts" ("idempotencyKey");

CREATE UNIQUE INDEX "notification_delivery_attempts_notificationId_attemptNumber_key"
ON "notification_delivery_attempts" (
  "notificationId",
  "attemptNumber"
);

CREATE INDEX "notification_delivery_attempts_notificationId_createdAt_idx"
ON "notification_delivery_attempts" (
  "notificationId",
  "createdAt"
);

CREATE INDEX "notification_delivery_attempts_status_nextRetryAt_idx"
ON "notification_delivery_attempts" (
  "status",
  "nextRetryAt"
);

CREATE INDEX "notification_delivery_attempts_provider_providerMessageId_idx"
ON "notification_delivery_attempts" (
  "provider",
  "providerMessageId"
);

CREATE UNIQUE INDEX "notification_provider_events_provider_externalEventId_key"
ON "notification_provider_events" (
  "provider",
  "externalEventId"
);

CREATE INDEX "notification_provider_events_notificationId_receivedAt_idx"
ON "notification_provider_events" (
  "notificationId",
  "receivedAt"
);

CREATE INDEX "notification_provider_events_providerMessageId_idx"
ON "notification_provider_events" ("providerMessageId");

CREATE INDEX "notification_provider_events_status_receivedAt_idx"
ON "notification_provider_events" (
  "status",
  "receivedAt"
);

ALTER TABLE "notification_templates"
ADD CONSTRAINT "notification_templates_createdByUserId_fkey"
FOREIGN KEY ("createdByUserId")
REFERENCES "users" ("id")
ON DELETE SET NULL
ON UPDATE CASCADE;

ALTER TABLE "notification_delivery_attempts"
ADD CONSTRAINT "notification_delivery_attempts_notificationId_fkey"
FOREIGN KEY ("notificationId")
REFERENCES "notifications" ("id")
ON DELETE RESTRICT
ON UPDATE CASCADE;

ALTER TABLE "notification_provider_events"
ADD CONSTRAINT "notification_provider_events_notificationId_fkey"
FOREIGN KEY ("notificationId")
REFERENCES "notifications" ("id")
ON DELETE SET NULL
ON UPDATE CASCADE;

INSERT INTO "permissions" (
  "id",
  "code",
  "name",
  "description",
  "status",
  "createdAt",
  "updatedAt"
)
VALUES
  (
    gen_random_uuid(),
    'notification.template.manage',
    'Manage notification templates',
    'Create, activate, and archive notification template versions.',
    'ACTIVE',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    gen_random_uuid(),
    'notification.delivery.manage',
    'Manage notification delivery',
    'Enqueue, retry, and run notification delivery operations.',
    'ACTIVE',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ),
  (
    gen_random_uuid(),
    'notification.delivery.view',
    'View notification delivery',
    'View notification outbox, attempts, dead letters, and metrics.',
    'ACTIVE',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  )
ON CONFLICT ("code") DO NOTHING;

INSERT INTO "role_permissions" (
  "roleId",
  "permissionId",
  "createdAt"
)
SELECT
  role_record."id",
  permission_record."id",
  CURRENT_TIMESTAMP
FROM "roles" AS role_record
INNER JOIN "permissions" AS permission_record
  ON permission_record."code" IN (
    'notification.template.manage',
    'notification.delivery.manage',
    'notification.delivery.view'
  )
WHERE role_record."code" IN (
  'PLATFORM_SUPER_ADMIN',
  'PLATFORM_ADMIN'
)
ON CONFLICT DO NOTHING;

INSERT INTO "role_permissions" (
  "roleId",
  "permissionId",
  "createdAt"
)
SELECT
  role_record."id",
  permission_record."id",
  CURRENT_TIMESTAMP
FROM "roles" AS role_record
INNER JOIN "permissions" AS permission_record
  ON permission_record."code" =
     'notification.delivery.view'
WHERE role_record."code" = 'PLATFORM_SUPPORT'
ON CONFLICT DO NOTHING;