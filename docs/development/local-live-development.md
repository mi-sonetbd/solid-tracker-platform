# Local Live Development

Solid Tracker uses one persistent development session for daily backend and
frontend work.

## Start

From the repository root:

```powershell
.\scripts\dev.ps1 -OpenBrowser
```

The command:

1. starts PostgreSQL and Redis with Docker Compose;
2. starts the backend API in watch mode;
3. starts the Next.js web panel in development mode;
4. waits for both services to become reachable;
5. stores the tracked PowerShell process IDs locally;
6. optionally opens the requested browser route.

Default endpoints:

```text
Backend API: http://localhost:3000
Web panel:   http://localhost:3001
```

## Open a specific route

```powershell
.\scripts\dev.ps1 `
    -OpenBrowser `
    -Route "/management/accounts"
```

## Daily workflow

Keep both generated service windows open.

Backend and frontend source changes reload automatically. Normal UI review does
not require a new preview script or full production build.

## Status

```powershell
.\scripts\dev-status.ps1
```

This reports:

- current branch;
- repository status;
- backend and web reachability;
- tracked service process IDs;
- log locations;
- PostgreSQL and Redis status.

## Restart

```powershell
.\scripts\dev.ps1 -Restart -OpenBrowser
```

Use restart after:

- dependency changes;
- environment-variable changes;
- Prisma generation;
- framework configuration changes;
- a development server becomes unstable.

## Stop

```powershell
.\scripts\dev-stop.ps1
```

This stops the tracked backend and web PowerShell process trees. PostgreSQL and
Redis remain running for fast restart.

Stop everything:

```powershell
.\scripts\dev-stop.ps1 -StopInfrastructure
```

## Logs

Runtime files are local and ignored by Git:

```text
.runtime/
â”œâ”€â”€ dev-processes.json
â””â”€â”€ logs/
    â”œâ”€â”€ backend.log
    â””â”€â”€ web.log
```

## Verification policy

Use live development for normal implementation review.

Before committing a feature, run its relevant automated tests and quality
gates:

```powershell
pnpm.cmd --filter @solid-tracker/backend-api test
pnpm.cmd --filter @solid-tracker/web-panel lint
pnpm.cmd --filter @solid-tracker/web-panel typecheck
pnpm.cmd --filter @solid-tracker/web-panel build
```

Feature-specific setup, migration, provisioning, recovery, and deployment
scripts remain valid. Routine browser preview scripts are no longer required.

## Next platform stage

After this workflow is approved, direct Customer completion proceeds in this
order:

1. create a Platform-managed direct Customer;
2. provision or attach the Customer Owner login;
3. display the real Customer directory;
4. verify Customer login and scope;
5. assign devices to the Customer;
6. connect real devices to Customer Monitor and Device pages.