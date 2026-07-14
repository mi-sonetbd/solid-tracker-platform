import { PrismaPg } from '@prisma/adapter-pg';
import { config } from 'dotenv';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { PrismaClient } from '../../generated/prisma/client';
import { normalizeMobileNumber } from '../common/mobile-number.util';
import { PasswordService } from '../common/password.service';

config({
  path: resolve(process.cwd(), '../../.env'),
});

function readArgument(name: string): string {
  const index = process.argv.indexOf(name);
  const value = index >= 0 ? process.argv[index + 1] : undefined;

  if (!value) {
    throw new Error(`Required argument is missing: ${name}`);
  }

  return value;
}

async function main(): Promise<void> {
  const connectionString = process.env.DATABASE_URL;
  const password = process.env.SOLID_TRACKER_BOOTSTRAP_PASSWORD;

  if (!connectionString) {
    throw new Error('DATABASE_URL is required.');
  }

  if (!password) {
    throw new Error('SOLID_TRACKER_BOOTSTRAP_PASSWORD is required.');
  }

  const mobileNumber = readArgument('--mobile');
  const fullName = readArgument('--name');
  const normalizedMobileNumber = normalizeMobileNumber(mobileNumber);
  const passwordService = new PasswordService();
  const passwordHash = await passwordService.hash(password);

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString }),
  });

  try {
    const platformOrganization = await prisma.organization.findUniqueOrThrow({
      where: { code: 'ORG-PLATFORM' },
    });

    const superAdminRole = await prisma.role.findUniqueOrThrow({
      where: { code: 'PLATFORM_SUPER_ADMIN' },
    });

    const user = await prisma.$transaction(async (transaction) => {
      const createdOrUpdatedUser = await transaction.user.upsert({
        where: { normalizedMobileNumber },
        update: {
          fullName,
          mobileNumber,
          passwordHash,
          passwordChangedAt: new Date(),
          mobileVerifiedAt: new Date(),
          status: 'ACTIVE',
          failedLoginCount: 0,
          lockedUntil: null,
        },
        create: {
          userCode: `USR-${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`,
          fullName,
          mobileNumber,
          normalizedMobileNumber,
          passwordHash,
          passwordChangedAt: new Date(),
          mobileVerifiedAt: new Date(),
          status: 'ACTIVE',
        },
      });

      const membership = await transaction.organizationMembership.upsert({
        where: {
          organizationId_userId: {
            organizationId: platformOrganization.id,
            userId: createdOrUpdatedUser.id,
          },
        },
        update: {
          membershipType: 'OWNER',
          status: 'ACTIVE',
          joinedAt: new Date(),
          endedAt: null,
        },
        create: {
          organizationId: platformOrganization.id,
          userId: createdOrUpdatedUser.id,
          membershipType: 'OWNER',
          status: 'ACTIVE',
          joinedAt: new Date(),
          isPrimary: false,
        },
      });

      await transaction.roleAssignment.upsert({
        where: {
          userId_roleId_scopeType_scopeId: {
            userId: createdOrUpdatedUser.id,
            roleId: superAdminRole.id,
            scopeType: 'PLATFORM',
            scopeId: platformOrganization.id,
          },
        },
        update: {
          organizationMembershipId: membership.id,
          status: 'ACTIVE',
          effectiveFrom: new Date(),
          effectiveUntil: null,
          revokedAt: null,
          revokedByUserId: null,
          revocationReason: null,
        },
        create: {
          userId: createdOrUpdatedUser.id,
          roleId: superAdminRole.id,
          organizationMembershipId: membership.id,
          scopeType: 'PLATFORM',
          scopeId: platformOrganization.id,
          status: 'ACTIVE',
        },
      });

      await transaction.auditLog.create({
        data: {
          actorUserId: createdOrUpdatedUser.id,
          actorOrganizationId: platformOrganization.id,
          action: 'identity.platform_admin.bootstrapped',
          resourceType: 'User',
          resourceId: createdOrUpdatedUser.id,
        },
      });

      return createdOrUpdatedUser;
    });

    console.log('Solid Tracker platform administrator is ready.');
    console.log({
      userId: user.id,
      userCode: user.userCode,
      mobileNumber: user.mobileNumber,
    });
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
