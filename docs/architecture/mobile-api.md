# Customer Mobile API

## Purpose

The mobile API provides stable, customer-scoped contracts for Android and iOS clients without exposing Traccar directly.

All routes are served beneath:

```text
/api/v1/mobile
```

## Authorization

Mobile access requires:

- a valid access token;
- an active customer membership;
- the existing permission required by the requested operation.

The service derives customer scope from the authenticated access-token context and does not accept customer identifiers from the client.

## Contracts

The stage provides:

- authenticated customer profile;
- cached customer dashboard;
- cursor-paginated vehicle summaries;
- detailed vehicle, tracker, subscription, and geofence context;
- live position;
- bounded position history;
- derived trip feed;
- cursor-paginated tracking event feed;
- subscription and invoice feeds;
- notification feed;
- Redis-backed live tracking sessions.

## Live sessions

Live sessions are short-lived, user-bound Redis records. A session cannot be read or closed by another user.

Latest position responses use a small Redis cache to avoid excessive calls to Traccar while the mobile client polls.

## Caching

The dashboard cache is intentionally short-lived. The cache stores only customer-authorized response data and is keyed by user and customer scope.

## Data ownership

PostgreSQL remains the source of truth for customers, vehicles, subscriptions, invoices, events, and notifications.

Traccar remains the telemetry source. The mobile client communicates only with the NestJS API.

## Database impact

This stage introduces no Prisma migration.

The invariant remains:

```text
Applied migrations: 6
Public tables: 53
```