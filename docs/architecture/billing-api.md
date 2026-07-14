# Billing, Commission, and Settlement API

## Scope

This stage exposes the existing billing foundation through authenticated REST APIs and transactional application services.

It implements service-plan versioning, vehicle subscriptions, invoices, payment allocations, refunds, dealer commission, encrypted payout accounts, settlements, and immutable dealer-ledger movements.

No Prisma migration is introduced. The existing billing migration already contains the required tables, constraints, indexes, and validation triggers.

## Decimal accounting

Financial arithmetic uses Prisma Decimal rather than JavaScript floating-point arithmetic.

Accepted inputs are Prisma Decimal instances, strings, or numbers. The sum operation uses an explicitly typed `Prisma.Decimal` accumulator and converts each input before addition.

## Accounting invariants

Payment allocations and dealer-ledger entries are append-only. Refunds and corrections produce reversal records rather than deleting financial history.

Only one current subscription may exist for a vehicle. Only one default payout account may exist for a dealer.

Payout account references are encrypted using AES-256-GCM and only masked identifiers are exposed by the API.

## Payment-gateway boundary

The API stores provider-neutral payment state and idempotent gateway events. Provider-specific bKash, Nagad, SSLCommerz, and bank adapters remain isolated for the payment-gateway integration stage.