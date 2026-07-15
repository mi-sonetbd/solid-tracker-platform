# Customer-Owned Device Installation Picker

## Problem

Sell/move to a Customer creates active Customer ownership and custody and sets
the Device lifecycle to `ALLOCATED`.

The previous installation picker used only:

```text
Dealer-managed Customer -> Dealer ALLOCATED stock
Direct Customer         -> Platform IN_STOCK stock
```

A direct Customer's own `ALLOCATED` Device was therefore omitted.

## Corrected loading

The picker now merges two authoritative sources.

### Source 1: Customer-owned or Customer-custodied stock

```text
GET /api/management/devices
  ?customerId=<customer-id>
  &lifecycleStatus=ALLOCATED
```

### Source 2: General installable stock

Dealer-managed Customer:

```text
GET /api/management/devices
  ?dealerOrganizationId=<managing-dealer-id>
  &lifecycleStatus=ALLOCATED
```

Direct Customer:

```text
GET /api/management/devices
  ?lifecycleStatus=IN_STOCK
```

All pages are loaded, results are deduplicated, active assignments are removed,
and only `IN_STOCK` or `ALLOCATED` lifecycle states remain.

Customer-owned Devices are sorted before shared Dealer or Platform stock.

## Backend contract

The existing backend installation service accepts both `IN_STOCK` and
`ALLOCATED`. Direct-customer installation remains Platform-only, and
Dealer-managed installation still requires an active allocation to the
Customer's managing Dealer.

No backend lifecycle rule is weakened.