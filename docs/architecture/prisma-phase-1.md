# Prisma Phase 1 Database Foundation

## Scope

The first migration establishes:

- users and sessions;
- organizations and zones;
- dealer profiles;
- organization memberships;
- roles, permissions, and scoped role assignments;
- customers and type-specific profiles;
- dealer customer groups;
- customer memberships;
- customer dealer-assignment history;
- audit logs.

Vehicles, devices, subscriptions, payments, commissions, Traccar mappings, and notifications remain outside this migration.

## Runtime architecture

```text
NestJS service
    â†“
PrismaService
    â†“
Prisma Client 7
    â†“
@prisma/adapter-pg
    â†“
node-postgres
    â†“
PostgreSQL
```

## Jest integration

Prisma Client 7 loads parts of its query compiler through dynamic imports.

The E2E test command starts Jest through Node with:

```text
--experimental-vm-modules
```

This enables dynamic imports inside Jest's VM-based test environment. It does not change the production NestJS runtime.

## Dependency build approvals

The repository explicitly allows reviewed build scripts for:

- `@prisma/engines`
- `esbuild`
- `prisma`

Unrelated analytics scripts remain denied. The repository does not enable all dependency build scripts globally.

## Commands

From the repository root:

```powershell
pnpm.cmd db:format
pnpm.cmd db:validate
pnpm.cmd db:generate
pnpm.cmd db:migrate:status
pnpm.cmd db:seed
pnpm.cmd db:studio
```

To create a future development migration after changing the schema:

```powershell
pnpm.cmd db:migrate:dev -- --name descriptive_migration_name
```

## Important rules

- Prisma Client is generated into `src/generated/prisma`.
- Generated code is not committed.
- The PostgreSQL migration contains native constraints and triggers.
- Seed execution is explicit and idempotent.
- The seed creates the platform organization, system roles, permissions, and role-permission mappings.
- No default administrator password or insecure account is created.