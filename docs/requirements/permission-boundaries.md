# Solid Tracker Permission Boundaries

## Least-privilege principle

Users receive only the permissions required for their responsibilities.

## Platform boundaries

### Platform super administrator

May manage platform-wide configuration, privileged administrators, global integrations, and emergency security operations.

### Platform administrator

May manage platform users, dealers, customers, plans, and operational settings according to assigned permissions.

### Platform support

May investigate devices, installations, Traccar synchronization, and customer issues. Support access does not automatically include finance operations or high-risk remote commands.

### Platform finance

May manage invoices, payments, commissions, payout accounts, settlements, and financial reports. Finance access does not automatically include live tracking or device-control commands.

## Dealer boundaries

### Dealer owner

May manage the dealer organization, dealer staff, dealer customers, inventory, and permitted financial records.

### Dealer manager

May manage dealer customers and operational resources within the assigned dealer or customer-group scope.

### Dealer installer

May view relevant customers and vehicles and perform installations, replacements, and removals for devices allocated to the dealer.

### Dealer accounts

May view invoices, payments, commissions, and settlements for the dealer. This role does not automatically permit device reassignment or installation.

## Customer boundaries

### Customer owner

May manage the customer profile, customer users, vehicles, subscriptions, invoices, and notification preferences.

### Customer admin

May manage operational data and customer users within assigned permissions.

### Customer viewer

May view permitted vehicles, live location, route history, and selected reports.

## Scope enforcement examples

- A dealer manager with `customer.create` may create customers only under the assigned dealer.
- A manager scoped to one customer group may not view customers in another group.
- A customer user may view only vehicles belonging to the customer membership scope.
- A dealer installer may install only devices allocated to the installerâ€™s dealer.
- A platform finance user may view settlements but may not send engine-control commands.

## High-risk actions

The following actions require dedicated permission, reason capture, audit logging, and step-up authentication where implemented:

- changing dealer payout accounts;
- issuing manual refunds;
- transferring customers between dealers;
- modifying device IMEI;
- changing commission rules;
- creating privileged administrators;
- sending engine-cutoff commands.