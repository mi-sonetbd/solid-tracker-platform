# Payment Gateway and Recurring Billing Automation

## Scope

This stage adds a provider-neutral payment gateway boundary and recurring billing operations without introducing a Prisma migration.

It implements:

- gateway checkout initialization;
- signed and idempotent callback processing;
- payment amount and currency validation;
- automatic invoice allocation and dealer commission;
- callback retry and reconciliation operations;
- recurring invoice generation;
- billing-period advancement;
- overdue invoice and past-due subscription transitions;
- durable automation-run claims;
- bounded manual and scheduled processing;
- sandbox gateway E2E coverage.

## Gateway adapters

The deterministic `OTHER` gateway supports local development and automated tests.

The SSLCOMMERZ adapter initializes hosted checkout and validates provider callback data before financial state changes.

The bKash and Nagad boundaries use signed merchant-proxy adapters so provider credentials remain isolated from the core billing domain.

## Idempotency

`payment_gateway_events` has a database-enforced unique key over:

```text
gateway
externalEventId
```

The verification uses PostgreSQL catalog metadata rather than matching rendered index SQL. This avoids false negatives caused by PostgreSQL omitting quotation marks around identifiers that do not require quoting.

## Recurring automation

The worker is disabled by default in local development. The same bounded operation can be triggered through the authenticated billing-automation endpoint.

Durable run claims prevent concurrent workers from processing the same automation interval.

## Accounting safety

Callbacks do not confirm payments until gateway identity, amount, currency, customer, payment, and invoice context are validated.

Successful allocations use the existing append-only payment allocation and dealer commission services.