# Local Docker Infrastructure

The local Solid Tracker development stack contains:

- PostgreSQL for application data
- Redis for caching, sessions, queues and distributed coordination

## Commands

Start services:

    pnpm infra:up

Show service status:

    pnpm infra:status

Follow logs:

    pnpm infra:logs

Stop services without deleting data:

    pnpm infra:stop

Delete containers and local data volumes:

    pnpm infra:reset

The .env file contains local secrets and must not be committed.
