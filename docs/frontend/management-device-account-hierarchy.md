# Management Device Account Hierarchy, Transfer, and Bulk Intake

## Route

```text
/management/device
```

## Account hierarchy

The Device workspace reuses the operational Management Monitor hierarchy.

- Platform users see the Platform root, Direct Customers, Dealers, and Dealer Customers.
- Dealer Manager users see only Customers and synthesized Dealer nodes within their authenticated scope.
- Dealer users see only their organization scope and managed Customers.
- Hierarchy expansion and hierarchy selection are independent.

The selected node becomes a backend query:

```text
Platform root  -> authenticated Device scope
Direct         -> directCustomers=true
Dealer         -> dealerOrganizationId=<scoped Dealer>
Customer       -> customerId=<scoped Customer>
```

Backend `deviceWhere(auth)` is always applied before these filters. Browser IDs
cannot expand the authenticated scope.

## Pagination

Device pagination is backend-authoritative.

```text
page
pageSize
total
totalPages
```

Search, lifecycle, Device Model, hierarchy selection, and page size reset the
current page and issue a new scoped request.

## Bulk stock intake

Platform operators with `device.register` may:

1. select one active Device Model;
2. enter up to 250 IMEI lines;
3. apply shared hardware, firmware, and received-time metadata;
4. receive per-line `CREATED` or `ERROR` results.

The backend:

- trims every IMEI;
- validates 14â€“17 digits;
- rejects duplicate lines;
- relies on the unique IMEI database constraint for existing stock;
- calls the normal registration transaction for every accepted line;
- creates Platform ownership and custody history;
- records the standard `device.registered` audit event.

## Sell / move

Users with `device.remove` may move only Devices already inside their effective
scope. Destination Dealer and Customer IDs are independently revalidated.

Blocked lifecycle states include:

- installed or actively assigned;
- reserved;
- under repair;
- lost;
- damaged;
- retired.

A successful transfer transaction:

1. closes active Dealer allocation rows;
2. closes current ownership history;
3. closes current custody history;
4. creates destination ownership;
5. creates destination custody;
6. creates available Dealer stock when the destination is a Dealer;
7. keeps Dealer-managed Customer stock linked to its managing Dealer;
8. sets lifecycle state to `ALLOCATED`;
9. records `device.transferred` audit entries.

Installed Devices must use the explicit removal workflow before transfer.

## UI preservation

The approved Account List, search fields, reference action row, Device table,
status presentation, selection controls, and pagination are retained.

Options that belong to future Billing or removal workflows remain visible but
disabled rather than being simulated.