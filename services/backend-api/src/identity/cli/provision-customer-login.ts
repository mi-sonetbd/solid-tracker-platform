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

const supportedRoleCodes = ['CUSTOMER_OWNER', 'CUSTOMER_ADMIN', 'CUSTOMER_VIEWER'] as const;

type SupportedRoleCode = (typeof supportedRoleCodes)[number];

function readArgument(name: string): string {
  const index = process.argv.indexOf(name);
  const value = index >= 0 ? process.argv[index + 1] : undefined;

  if (!value) {
    throw new Error(`Required argument is missing: ${name}`);
  }

  return value;
}

function readRole(): SupportedRoleCode {
  const index = process.argv.indexOf('--role');
  const value = index >= 0 ? process.argv[index + 1] : 'CUSTOMER_OWNER';

  if (!supportedRoleCodes.includes(value as SupportedRoleCode)) {
    throw new Error(`Unsupported Customer role: ${value}.`);
  }

  return value as SupportedRoleCode;
}

function code(prefix: string): string {
  return `${prefix}-${randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase()}`;
}

function mobileCandidates(mobileNumber: string, normalizedMobileNumber: string): string[] {
  const values = new Set<string>([mobileNumber.trim(), normalizedMobileNumber]);

  if (normalizedMobileNumber.startsWith('+880')) {
    values.add(`0${normalizedMobileNumber.slice(4)}`);
    values.add(normalizedMobileNumber.slice(1));
  }

  return Array.from(values);
}

async function main(): Promise<void> {
  const connectionString = process.env.DATABASE_URL;
  const password = process.env.SOLID_TRACKER_CUSTOMER_PASSWORD;

  if (!connectionString) {
    throw new Error('DATABASE_URL is required.');
  }

  if (!password) {
    throw new Error('SOLID_TRACKER_CUSTOMER_PASSWORD is required.');
  }

  const mobileNumber = readArgument('--mobile').trim();
  const fullName = readArgument('--name').trim();
  const roleCode = readRole();
  const normalizedMobileNumber = normalizeMobileNumber(mobileNumber);
  const passwordHash = await new PasswordService().hash(password);
  const now = new Date();

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString }),
  });

  try {
    const platformOrganization = await prisma.organization.findUniqueOrThrow({
      where: {
        code: 'ORG-PLATFORM',
      },
    });

    const platformAdministratorAssignment = await prisma.roleAssignment.findFirst({
      where: {
        scopeType: 'PLATFORM',
        status: 'ACTIVE',
        role: {
          code: 'PLATFORM_SUPER_ADMIN',
          status: 'ACTIVE',
        },
        user: {
          status: 'ACTIVE',
        },
      },
      orderBy: {
        createdAt: 'asc',
      },
      select: {
        userId: true,
      },
    });

    if (!platformAdministratorAssignment) {
      throw new Error('An active PLATFORM_SUPER_ADMIN is required.');
    }

    const actorUserId = platformAdministratorAssignment.userId;

    const customerRole = await prisma.role.findUniqueOrThrow({
      where: {
        code: roleCode,
      },
    });

    if (customerRole.status !== 'ACTIVE') {
      throw new Error(`Customer role ${roleCode} is not active.`);
    }

    const existingUser = await prisma.user.findUnique({
      where: {
        normalizedMobileNumber,
      },
      include: {
        customerMemberships: {
          where: {
            status: 'ACTIVE',
          },
          include: {
            customer: true,
          },
          orderBy: {
            createdAt: 'asc',
          },
        },
      },
    });

    let customer = existingUser?.customerMemberships[0]?.customer ?? null;

    if (!customer) {
      const matchingCustomers = await prisma.customer.findMany({
        where: {
          primaryMobile: {
            in: mobileCandidates(mobileNumber, normalizedMobileNumber),
          },
          status: {
            not: 'ARCHIVED',
          },
        },
        include: {
          individualProfile: true,
        },
        orderBy: {
          createdAt: 'asc',
        },
      });

      if (matchingCustomers.length > 1) {
        throw new Error(
          'Multiple active Customer records use this mobile number. Resolve the duplicate before provisioning login.',
        );
      }

      customer = matchingCustomers[0] ?? null;
    }

    const result = await prisma.$transaction(async (transaction) => {
      let activeCustomer = customer;

      if (!activeCustomer) {
        activeCustomer = await transaction.customer.create({
          data: {
            customerCode: code('CUS'),
            customerType: 'INDIVIDUAL',
            status: 'ACTIVE',
            acquisitionSource: 'DIRECT',
            primaryMobile: mobileNumber,
            createdByUserId: actorUserId,
            individualProfile: {
              create: {
                fullName,
              },
            },
            dealerAssignments: {
              create: {
                managementType: 'PLATFORM',
                assignmentReason: 'INITIAL_ASSIGNMENT',
                assignedByUserId: actorUserId,
              },
            },
          },
          include: {
            individualProfile: true,
          },
        });
      }

      if (activeCustomer.status !== 'ACTIVE') {
        activeCustomer = await transaction.customer.update({
          where: {
            id: activeCustomer.id,
          },
          data: {
            status: 'ACTIVE',
            archivedAt: null,
          },
          include: {
            individualProfile: true,
          },
        });
      }

      const user = await transaction.user.upsert({
        where: {
          normalizedMobileNumber,
        },
        update: {
          fullName,
          mobileNumber,
          passwordHash,
          passwordChangedAt: now,
          mobileVerifiedAt: now,
          status: 'ACTIVE',
          failedLoginCount: 0,
          lockedUntil: null,
          archivedAt: null,
        },
        create: {
          userCode: code('USR'),
          fullName,
          mobileNumber,
          normalizedMobileNumber,
          passwordHash,
          passwordChangedAt: now,
          mobileVerifiedAt: now,
          status: 'ACTIVE',
        },
      });

      await transaction.userSession.updateMany({
        where: {
          userId: user.id,
          status: 'ACTIVE',
        },
        data: {
          status: 'REVOKED',
          revokedAt: now,
          revocationReason: 'CUSTOMER_LOGIN_REPROVISIONED',
        },
      });

      if (roleCode === 'CUSTOMER_OWNER') {
        await transaction.customerMembership.updateMany({
          where: {
            customerId: activeCustomer.id,
            isPrimary: true,
            userId: {
              not: user.id,
            },
          },
          data: {
            isPrimary: false,
          },
        });
      }

      const membership = await transaction.customerMembership.upsert({
        where: {
          customerId_userId: {
            customerId: activeCustomer.id,
            userId: user.id,
          },
        },
        update: {
          status: 'ACTIVE',
          isPrimary: roleCode === 'CUSTOMER_OWNER',
          invitedByUserId: actorUserId,
          joinedAt: now,
          endedAt: null,
        },
        create: {
          customerId: activeCustomer.id,
          userId: user.id,
          status: 'ACTIVE',
          isPrimary: roleCode === 'CUSTOMER_OWNER',
          invitedByUserId: actorUserId,
          joinedAt: now,
        },
      });

      const roleAssignment = await transaction.roleAssignment.upsert({
        where: {
          userId_roleId_scopeType_scopeId: {
            userId: user.id,
            roleId: customerRole.id,
            scopeType: 'CUSTOMER',
            scopeId: activeCustomer.id,
          },
        },
        update: {
          status: 'ACTIVE',
          effectiveFrom: now,
          effectiveUntil: null,
          assignedByUserId: actorUserId,
          revokedByUserId: null,
          revokedAt: null,
          revocationReason: null,
        },
        create: {
          userId: user.id,
          roleId: customerRole.id,
          scopeType: 'CUSTOMER',
          scopeId: activeCustomer.id,
          status: 'ACTIVE',
          assignedByUserId: actorUserId,
        },
      });

      await transaction.auditLog.create({
        data: {
          actorUserId,
          actorOrganizationId: platformOrganization.id,
          action: 'identity.customer_login.provisioned',
          resourceType: 'User',
          resourceId: user.id,
          scopeType: 'CUSTOMER',
          scopeId: activeCustomer.id,
          afterData: {
            customerId: activeCustomer.id,
            membershipId: membership.id,
            roleAssignmentId: roleAssignment.id,
            roleCode,
            normalizedMobileNumber,
          },
        },
      });

      return {
        user,
        customer: activeCustomer,
        membership,
        roleAssignment,
      };
    });

    console.log('Solid Tracker Customer login is ready.');
    console.log({
      userId: result.user.id,
      userCode: result.user.userCode,
      customerId: result.customer.id,
      customerCode: result.customer.customerCode,
      mobileNumber: result.user.mobileNumber,
      normalizedMobileNumber: result.user.normalizedMobileNumber,
      roleCode,
      isPrimary: result.membership.isPrimary,
      status: result.user.status,
    });
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
