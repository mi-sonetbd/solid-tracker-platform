# Solid Tracker Backend API

This service provides the REST API for the Solid Tracker platform.

## Current foundation

- NestJS and TypeScript
- Environment validation
- PostgreSQL connection pool
- Redis connection
- Liveness and readiness endpoints
- Swagger/OpenAPI documentation
- Global request validation
- Security headers
- Unit and end-to-end tests

## Local endpoints

- API root: http://localhost:3000/api/v1
- Liveness: http://localhost:3000/api/v1/health/live
- Readiness: http://localhost:3000/api/v1/health/ready
- Swagger: http://localhost:3000/docs

## Commands

From the repository root:

    pnpm api:start:dev
    pnpm api:build
    pnpm api:lint
    pnpm api:typecheck
    pnpm api:test
    pnpm api:test:e2e

Business database models are intentionally not defined in this foundation.
The Prisma schema will be created after the Solid Tracker domain model and ERD are reviewed.
