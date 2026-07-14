# Notification Delivery Platform

## Scope

This stage turns the existing `notifications` table into a production-oriented transactional outbox and adds durable delivery metadata.

It implements:

- immutable, versioned notification templates;
- active-template selection by key, channel, and locale;
- deterministic template rendering;
- SMS, email, push, WhatsApp, voice-call, and in-app provider boundaries;
- signed provider-proxy requests;
- HMAC-authenticated provider callbacks;
- durable, numbered delivery attempts;
- exponential retry with jitter;
- dead-letter handling and manual replay;
- Redis-backed worker locking and provider rate limiting;
- callback idempotency;
- delivery metrics and attempt history;
- sandbox provider E2E coverage.

## Data ownership

PostgreSQL owns templates, outbox records, attempts, provider events, callback idempotency, retry schedules, and dead-letter history.

Redis is used only for temporary distributed locks and rate-limit counters.

## Outbox lifecycle

```text
QUEUED
  â†’ PROCESSING
  â†’ SENT
  â†’ DELIVERED
```

Failures create a numbered attempt record and schedule the next retry. After the configured attempt limit, the final attempt is marked `DEAD_LETTER`. Manual retry is explicit and audited.

## Provider isolation

Provider credentials and vendor-specific API shapes remain outside the notification domain.

The core API communicates with signed SMS, email, and push proxy boundaries. When proxies are not configured, the deterministic sandbox adapter supports local development and automated testing.

## Callback security

Callbacks require:

```text
x-solid-timestamp
x-solid-event-id
x-solid-signature
```

The signature covers the timestamp, event ID, and canonical JSON body. Provider events are deduplicated by the database unique key over provider and external event ID.

## Template versioning

Template versions are immutable. Activating one version automatically deactivates the previous active version for the same template key, channel, and locale.

A partial unique index enforces one active version per variant.

## Operations

The worker is disabled by default in local development:

```text
NOTIFICATION_DELIVERY_ENABLED=false
```

A bounded batch can be run through:

```text
POST /api/v1/notification-delivery/run
```