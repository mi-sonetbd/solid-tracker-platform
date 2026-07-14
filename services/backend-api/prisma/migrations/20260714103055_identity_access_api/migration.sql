-- CreateEnum
CREATE TYPE "OtpPurpose" AS ENUM ('MOBILE_VERIFICATION', 'PASSWORD_RESET', 'HIGH_RISK_ACTION');

-- CreateEnum
CREATE TYPE "OtpChallengeStatus" AS ENUM ('PENDING', 'VERIFIED', 'EXPIRED', 'CANCELLED', 'LOCKED');

-- CreateTable
CREATE TABLE "otp_challenges" (
    "id" UUID NOT NULL,
    "userId" UUID,
    "normalizedMobileNumber" VARCHAR(30) NOT NULL,
    "purpose" "OtpPurpose" NOT NULL,
    "codeHash" TEXT NOT NULL,
    "status" "OtpChallengeStatus" NOT NULL DEFAULT 'PENDING',
    "attemptCount" INTEGER NOT NULL DEFAULT 0,
    "maxAttempts" INTEGER NOT NULL DEFAULT 5,
    "resendCount" INTEGER NOT NULL DEFAULT 0,
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "verifiedAt" TIMESTAMPTZ(3),
    "invalidatedAt" TIMESTAMPTZ(3),
    "requestIp" VARCHAR(45),
    "requestUserAgent" TEXT,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "otp_challenges_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "otp_challenges_normalizedMobileNumber_purpose_status_idx" ON "otp_challenges"("normalizedMobileNumber", "purpose", "status");

-- CreateIndex
CREATE INDEX "otp_challenges_expiresAt_status_idx" ON "otp_challenges"("expiresAt", "status");

-- CreateIndex
CREATE INDEX "otp_challenges_userId_purpose_status_idx" ON "otp_challenges"("userId", "purpose", "status");

-- AddForeignKey
ALTER TABLE "otp_challenges" ADD CONSTRAINT "otp_challenges_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Solid Tracker identity and access invariants.

ALTER TABLE "user_sessions"
ADD CONSTRAINT "user_sessions_expiry_valid"
CHECK ("expiresAt" > "createdAt");

ALTER TABLE "user_sessions"
ADD CONSTRAINT "user_sessions_status_consistency"
CHECK (
  (
    "status" = 'ACTIVE'
    AND "revokedAt" IS NULL
    AND "revocationReason" IS NULL
  )
  OR
  (
    "status" = 'REVOKED'
    AND "revokedAt" IS NOT NULL
  )
  OR
  (
    "status" = 'EXPIRED'
  )
);

ALTER TABLE "otp_challenges"
ADD CONSTRAINT "otp_challenges_attempts_valid"
CHECK (
  "attemptCount" >= 0
  AND "maxAttempts" > 0
  AND "attemptCount" <= "maxAttempts"
  AND "resendCount" >= 0
);

ALTER TABLE "otp_challenges"
ADD CONSTRAINT "otp_challenges_expiry_valid"
CHECK ("expiresAt" > "createdAt");

ALTER TABLE "otp_challenges"
ADD CONSTRAINT "otp_challenges_status_consistency"
CHECK (
  (
    "status" = 'PENDING'
    AND "verifiedAt" IS NULL
    AND "invalidatedAt" IS NULL
  )
  OR
  (
    "status" = 'VERIFIED'
    AND "verifiedAt" IS NOT NULL
  )
  OR
  (
    "status" IN ('EXPIRED', 'CANCELLED', 'LOCKED')
    AND "invalidatedAt" IS NOT NULL
  )
);

CREATE UNIQUE INDEX
  "otp_challenges_one_pending_per_identity"
ON "otp_challenges" (
  "normalizedMobileNumber",
  "purpose"
)
WHERE "status" = 'PENDING';

CREATE OR REPLACE FUNCTION
  "solid_tracker_block_audit_log_mutation"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'audit_logs is append-only and cannot be updated or deleted';
END;
$$;

CREATE TRIGGER "audit_logs_block_update"
BEFORE UPDATE
ON "audit_logs"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_block_audit_log_mutation"();

CREATE TRIGGER "audit_logs_block_delete"
BEFORE DELETE
ON "audit_logs"
FOR EACH ROW
EXECUTE FUNCTION "solid_tracker_block_audit_log_mutation"();