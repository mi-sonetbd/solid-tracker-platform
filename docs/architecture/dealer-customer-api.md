# Dealer and Customer Management API

## Scope

This stage adds REST APIs and application services for:

- dealer organizations;
- dealer staff and scoped roles;
- customer groups;
- individual and organization customer onboarding;
- customer account members;
- customer group assignment;
- dealer-to-dealer and dealer-to-platform transfer;
- immutable management audit records.

The existing database foundation already contains the required entities, so this stage does not add a new migration.

## Authorization

Each protected operation requires both:

1. a matching permission code;
2. access to the specific dealer or customer resource.

Platform-scoped roles can operate across the platform according to their permissions.

Dealer-scoped roles can operate only on the matching dealer and its managed customers.

Customer-scoped roles can access only linked customer accounts.

## Dealer and dealer manager

A dealer is an organization with type `DEALER`.

A dealer manager is a user connected through an organization membership and a dealer-scoped role assignment.

Devices, customers, commissions, and settlements belong to the dealer organization, not to an individual manager.

## Customer groups

A customer group belongs to exactly one dealer.

A customer may belong to a group only when the group belongs to the customer's current managing dealer.

Archived groups remain available for history but cannot be selected for new assignments.

## Customer transfer

A platform-authorized transfer:

1. ends the current assignment-history record;
2. creates the next assignment record;
3. updates the current dealer pointer;
4. validates or clears the customer group;
5. writes an immutable audit record.

Historical invoices, payments, and commission snapshots remain unchanged.

## Provisioned users

Dealer staff and customer members may attach an existing user by normalized mobile number.

A newly provisioned user requires a strong password. The password is hashed and never returned.

## Endpoints

```text
GET    /api/v1/dealers
POST   /api/v1/dealers
GET    /api/v1/dealers/:dealerId
PATCH  /api/v1/dealers/:dealerId

GET    /api/v1/dealers/:dealerId/staff
POST   /api/v1/dealers/:dealerId/staff
PATCH  /api/v1/dealers/:dealerId/staff/:userId

GET    /api/v1/dealers/:dealerId/customer-groups
POST   /api/v1/dealers/:dealerId/customer-groups
PATCH  /api/v1/dealers/:dealerId/customer-groups/:groupId

GET    /api/v1/customers
POST   /api/v1/customers/individual
POST   /api/v1/customers/organization
GET    /api/v1/customers/:customerId
PATCH  /api/v1/customers/:customerId/group
POST   /api/v1/customers/:customerId/transfer

GET    /api/v1/customers/:customerId/members
POST   /api/v1/customers/:customerId/members
```