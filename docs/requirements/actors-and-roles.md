# Solid Tracker Actors and Roles

## Purpose

This document defines the people, organizations, roles, and authorization scopes used by the Solid Tracker platform.

## Core identity model

Solid Tracker separates five concepts:

1. **Person** â€” the real human being.
2. **User account** â€” the login identity.
3. **Organization** â€” the business or operating entity.
4. **Role** â€” the category of work performed.
5. **Scope** â€” the boundary within which permissions apply.

Authorization is evaluated as:

```text
authenticated user
+ active account
+ active membership
+ role permissions
+ scope
+ resource ownership
+ business status
```

## Organization types

- `PLATFORM`
- `DEALER`
- `CUSTOMER_ORGANIZATION`

A dealer is an organization, not a user account. Dealer owners, managers, installers, and accounts staff are users who act through memberships and role assignments.

## Platform roles

- `PLATFORM_SUPER_ADMIN`
- `PLATFORM_ADMIN`
- `PLATFORM_SUPPORT`
- `PLATFORM_FINANCE`

## Dealer roles

- `DEALER_OWNER`
- `DEALER_MANAGER`
- `DEALER_INSTALLER`
- `DEALER_ACCOUNTS`

## Customer roles

- `CUSTOMER_OWNER`
- `CUSTOMER_ADMIN`
- `CUSTOMER_VIEWER`

Additional customer roles such as fleet manager or driver are intentionally deferred until their permissions are formally required.

## Authorization scopes

- `PLATFORM`
- `ZONE`
- `DEALER`
- `CUSTOMER_GROUP`
- `CUSTOMER`
- `VEHICLE`
- `SELF`

## Permission examples

- `customer.view`
- `customer.create`
- `customer.update`
- `customer.transfer`
- `vehicle.view`
- `vehicle.location.view`
- `vehicle.history.view`
- `device.register`
- `device.install`
- `device.replace`
- `subscription.create`
- `invoice.view`
- `payment.view`
- `commission.view`
- `settlement.create`
- `command.send`
- `command.engine_cutoff`

## Dealer versus dealer manager

| Subject | Dealer | Dealer Manager |
|---|---|---|
| Type | Organization | User role |
| Own business identity | Yes | No |
| Holds commission account | Yes | No by default |
| Holds payout account | Yes | No by default |
| Owns customer relationship | Yes | Acts on dealer behalf |
| Can remain active after employee departure | Yes | No |
| Historical settlement owner | Yes | No |

## Customer access principle

A customer may be either:

- platform-managed, with no managing dealer; or
- dealer-managed, with one current managing dealer.

A customer group belongs to one dealer and may contain only customers managed by that dealer.