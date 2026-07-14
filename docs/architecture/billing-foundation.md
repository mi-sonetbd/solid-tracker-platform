# Billing, Commission, and Settlement Foundation

## Scope

This migration introduces:

- service plans and plan versions;
- vehicle subscriptions;
- invoices and invoice lines;
- payments and payment allocations;
- payment gateway event idempotency;
- refunds;
- dealer commission rules and commission entries;
- dealer payout accounts;
- dealer settlements and settlement items;
- append-only dealer ledger entries.

## Core financial flow

```text
Service Plan
    â†“
Vehicle Subscription
    â†“
Invoice
    â†“
Payment
    â†“
Payment Allocation
    â†“
Commission Entry
    â†“
Dealer Settlement
    â†“
Dealer Ledger
```

## Plan versioning

A plan family may have multiple immutable versions. Historical subscriptions and invoices retain the plan version and monetary values that applied at the time.

## Subscription invariant

A vehicle may have only one current subscription across these statuses:

- `PENDING`
- `TRIALING`
- `ACTIVE`
- `PAST_DUE`
- `SUSPENDED`

Cancelled and expired subscriptions remain as history.

## Invoice accounting

Invoice totals obey:

```text
total = subtotal - discount + tax
paid + outstanding = total
```

Payment allocation is append-only. A confirmed payment may be allocated across one or more invoices, while an invoice may receive multiple payments.

The database prevents:

- allocation beyond the payment amount;
- allocation beyond the invoice total;
- customer mismatch;
- currency mismatch;
- allocation from an unconfirmed payment.

## Gateway idempotency

`PaymentGatewayEvent` has a unique pair:

```text
gateway + externalEventId
```

Repeated gateway webhooks therefore cannot produce duplicate payment effects.

## Refunds

A refund must reference a confirmed payment, preserve customer and currency, and may not make total requested/pending/succeeded refunds exceed the original payment.

## Dealer commission

Commission rules support:

- percentage;
- fixed amount;
- tiered calculation;
- no commission.

Commission entries retain calculation snapshots. Reversal entries are negative and reference the original commission entry.

Historical commission belongs to the dealer recorded at transaction time, even if the customer later changes dealer.

## Payout and settlement

A dealer may have only one active default payout account. Processing or completing a settlement requires an active, verified payout account belonging to the same dealer.

Settlement items can include only available commission entries for the same dealer and currency.

## Ledger immutability

Dealer ledger entries are append-only. Corrections use new reversal or adjustment entries rather than update or delete operations.

## Data types

All money fields use PostgreSQL `NUMERIC` through Prisma `Decimal`. Currency is stored separately as a three-character code, initially `BDT`.