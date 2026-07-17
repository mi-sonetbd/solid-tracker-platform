# Management Monitor Account Hierarchy

## Objective

The Management Monitor uses real authenticated scope for:

- Super Admin;
- Admin;
- Dealer Manager;
- Dealer.

The approved three-panel layout remains unchanged:

```text
Account hierarchy | Device list | Map
```

## Hierarchy

### Platform workspaces

```text
Solid Tracker
â”œâ”€ Direct Customers
â”‚  â””â”€ Customer
â””â”€ Dealers
   â””â”€ Dealer
      â””â”€ Customer
```

### Dealer-scoped workspaces

```text
Authenticated Dealer scope
â””â”€ Dealer
   â””â”€ Customer
```

Dealer and Customer records come from:

```text
GET /api/management/dealers
GET /api/management/customers
```

Both BFF routes forward the authenticated access token. The backend applies
`dealerWhere(auth)` and `customerWhere(auth)` before returning records.

## Selection

Expansion and selection are independent.

Selecting:

- the root loads every Customer visible to the authenticated account;
- Direct Customers loads platform-managed Customers;
- a Dealer loads that Dealer's Customers;
- a Customer loads that Customer only.

## Device list

The Device sidebar resolves each selected Customer through:

```text
GET /api/management/vehicles?customerId=<scoped-id>
```

The backend combines the supplied Customer filter with `vehicleWhere(auth)`.
A forged or unauthorized Customer identifier therefore cannot expose another
Customer's vehicles.

Only installed Device assignments appear in the tracking Device sidebar.
Inventory-only Devices remain in Management Device stock workflows.

Each row displays real:

- vehicle registration or code;
- Device code;
- IMEI;
- Customer name;
- installation assignment time.

Tracking-dependent online state, alerts, signal, and coordinates remain
unavailable until Traccar synchronization.

## Device selection

Selecting an installed Device:

1. highlights the Device row;
2. opens the existing right-side Device property drawer;
3. retains the existing map layout;
4. focuses the map only after a real scoped Traccar position exists.

No marker, coordinate, status, signal, or alert is fabricated.