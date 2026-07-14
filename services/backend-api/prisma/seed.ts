import { PrismaPg } from '@prisma/adapter-pg';
import { config } from 'dotenv';
import { resolve } from 'node:path';
import { PrismaClient } from '../src/generated/prisma/client';

config({
  path: resolve(process.cwd(), '../../.env'),
});

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error('DATABASE_URL is required to seed Solid Tracker.');
}

const adapter = new PrismaPg({ connectionString });
const prisma = new PrismaClient({ adapter });

const permissionDefinitions = [
  ['user.view', 'View users'],
  ['user.create', 'Create users'],
  ['user.disable', 'Disable users'],
  ['dealer.view', 'View dealers'],
  ['dealer.manage', 'Manage dealers'],
  ['dealer.staff.manage', 'Manage dealer staff'],
  ['customer.view', 'View customers'],
  ['customer.create', 'Create customers'],
  ['customer.update', 'Update customers'],
  ['customer.transfer', 'Transfer customers'],
  ['vehicle.view', 'View vehicles'],
  ['vehicle.create', 'Create vehicles'],
  ['vehicle.update', 'Update vehicles'],
  ['vehicle.location.view', 'View live vehicle location'],
  ['vehicle.history.view', 'View vehicle history'],
  ['device.view', 'View devices'],
  ['device.register', 'Register devices'],
  ['device.install', 'Install devices'],
  ['device.replace', 'Replace devices'],
  ['device.remove', 'Remove devices'],
  ['subscription.view', 'View subscriptions'],
  ['subscription.create', 'Create subscriptions'],
  ['subscription.suspend', 'Suspend subscriptions'],
  ['invoice.view', 'View invoices'],
  ['payment.view', 'View payments'],
  ['commission.view', 'View commissions'],
  ['settlement.create', 'Create settlements'],
  ['command.send', 'Send device commands'],
  ['command.engine_cutoff', 'Send engine-cutoff commands'],
  ['notification.template.manage', 'Manage notification templates'],
  ['notification.delivery.manage', 'Manage notification delivery'],
  ['notification.delivery.view', 'View notification delivery'],
] as const;

const roleDefinitions = [
  ['PLATFORM_SUPER_ADMIN', 'Platform Super Administrator'],
  ['PLATFORM_ADMIN', 'Platform Administrator'],
  ['PLATFORM_SUPPORT', 'Platform Support'],
  ['PLATFORM_FINANCE', 'Platform Finance'],
  ['DEALER_OWNER', 'Dealer Owner'],
  ['DEALER_MANAGER', 'Dealer Manager'],
  ['DEALER_INSTALLER', 'Dealer Installer'],
  ['DEALER_ACCOUNTS', 'Dealer Accounts'],
  ['CUSTOMER_OWNER', 'Customer Owner'],
  ['CUSTOMER_ADMIN', 'Customer Administrator'],
  ['CUSTOMER_VIEWER', 'Customer Viewer'],
] as const;

const rolePermissionCodes: Record<string, readonly string[]> = {
  PLATFORM_SUPER_ADMIN: permissionDefinitions.map(([code]) => code),
  PLATFORM_ADMIN: permissionDefinitions
    .map(([code]) => code)
    .filter((code) => code !== 'command.engine_cutoff'),
  PLATFORM_SUPPORT: [
    'user.view',
    'dealer.view',
    'customer.view',
    'vehicle.view',
    'vehicle.location.view',
    'vehicle.history.view',
    'device.view',
    'device.replace',
    'device.remove',
    'subscription.view',
    'invoice.view',
    'command.send',
    'notification.delivery.view',
  ],
  PLATFORM_FINANCE: [
    'dealer.view',
    'customer.view',
    'subscription.view',
    'invoice.view',
    'payment.view',
    'commission.view',
    'settlement.create',
  ],
  DEALER_OWNER: [
    'dealer.view',
    'dealer.staff.manage',
    'customer.view',
    'customer.create',
    'customer.update',
    'vehicle.view',
    'vehicle.create',
    'vehicle.update',
    'vehicle.location.view',
    'vehicle.history.view',
    'device.view',
    'device.install',
    'device.replace',
    'device.remove',
    'subscription.view',
    'subscription.create',
    'invoice.view',
    'payment.view',
    'commission.view',
  ],
  DEALER_MANAGER: [
    'customer.view',
    'customer.create',
    'customer.update',
    'vehicle.view',
    'vehicle.create',
    'vehicle.update',
    'vehicle.location.view',
    'vehicle.history.view',
    'device.view',
    'device.install',
    'device.replace',
    'device.remove',
    'subscription.view',
    'subscription.create',
    'invoice.view',
  ],
  DEALER_INSTALLER: [
    'customer.view',
    'vehicle.view',
    'device.view',
    'device.install',
    'device.replace',
    'device.remove',
  ],
  DEALER_ACCOUNTS: [
    'customer.view',
    'subscription.view',
    'invoice.view',
    'payment.view',
    'commission.view',
  ],
  CUSTOMER_OWNER: [
    'customer.view',
    'customer.update',
    'vehicle.view',
    'vehicle.location.view',
    'vehicle.history.view',
    'subscription.view',
    'invoice.view',
    'payment.view',
  ],
  CUSTOMER_ADMIN: [
    'customer.view',
    'vehicle.view',
    'vehicle.location.view',
    'vehicle.history.view',
    'subscription.view',
    'invoice.view',
  ],
  CUSTOMER_VIEWER: [
    'customer.view',
    'vehicle.view',
    'vehicle.location.view',
    'vehicle.history.view',
  ],
};

async function main(): Promise<void> {
  await prisma.organization.upsert({
    where: { code: 'ORG-PLATFORM' },
    update: {
      name: 'Solid Tracker Platform',
      legalName: 'Solid Tracker',
      type: 'PLATFORM',
      status: 'ACTIVE',
    },
    create: {
      code: 'ORG-PLATFORM',
      name: 'Solid Tracker Platform',
      legalName: 'Solid Tracker',
      type: 'PLATFORM',
      status: 'ACTIVE',
    },
  });

  for (const [code, name] of permissionDefinitions) {
    await prisma.permission.upsert({
      where: { code },
      update: {
        name,
        status: 'ACTIVE',
      },
      create: {
        code,
        name,
        status: 'ACTIVE',
      },
    });
  }

  for (const [code, name] of roleDefinitions) {
    await prisma.role.upsert({
      where: { code },
      update: {
        name,
        status: 'ACTIVE',
        isSystem: true,
      },
      create: {
        code,
        name,
        status: 'ACTIVE',
        isSystem: true,
      },
    });
  }

  const permissions = await prisma.permission.findMany({
    select: {
      id: true,
      code: true,
    },
  });

  const permissionIdByCode = new Map(
    permissions.map((permission) => [permission.code, permission.id]),
  );

  for (const [roleCode] of roleDefinitions) {
    const role = await prisma.role.findUniqueOrThrow({
      where: { code: roleCode },
      select: { id: true },
    });

    const permissionCodes = rolePermissionCodes[roleCode] ?? [];

    for (const permissionCode of permissionCodes) {
      const permissionId = permissionIdByCode.get(permissionCode);

      if (!permissionId) {
        throw new Error(`Missing seeded permission: ${permissionCode}`);
      }

      await prisma.rolePermission.upsert({
        where: {
          roleId_permissionId: {
            roleId: role.id,
            permissionId,
          },
        },
        update: {},
        create: {
          roleId: role.id,
          permissionId,
        },
      });
    }
  }

  const [organizationCount, roleCount, permissionCount] = await Promise.all([
    prisma.organization.count(),
    prisma.role.count(),
    prisma.permission.count(),
  ]);

  console.log('Solid Tracker seed completed.');
  console.log({
    organizationCount,
    roleCount,
    permissionCount,
  });
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });