# Unified Customer Account Management

## Route ownership

Dealer and Customer administration share one operational workspace:

```text
/management/accounts
```

No separate Customer management page is required. The Account Management page
contains creation controls, Dealer directory, Customer directory, staff access,
and Customer member access.

## Customer assignment

The same Customer creation workflow supports both ownership models.

### Platform / Direct

```text
managingDealerId = null
acquisitionSource = DIRECT
managementType = PLATFORM
```

### Dealer-managed

```text
managingDealerId = selected Dealer organization ID
acquisitionSource = DEALER
managementType = DEALER
```

The backend remains authoritative and derives acquisition and management values
from the resolved Dealer assignment.

## Workspace behavior

Platform Super Admin and Platform Admin workspaces may choose either Direct or
one accessible Dealer during creation.

Dealer and Dealer Manager workspaces are restricted to their authenticated
Dealer scope. They cannot create Direct Customers or assign Customers to another
Dealer.

## Customer types

The unified modal supports:

- Individual Customer;
- Organization Customer;
- primary mobile and email;
- profile-specific contact information;
- optional immediate Customer Owner provisioning.

## Customer directory

The Account Management workspace provides Dealer and Customer directory tabs.
The Customer directory supports:

- name, code, mobile, or email search;
- Direct versus Dealer-managed filtering;
- Dealer filtering;
- Individual versus Organization filtering;
- status filtering;
- member and vehicle counts;
- Customer member review;
- primary Customer Owner provisioning.

## Authorization

Frontend controls are gated by the authenticated permissions, while the backend
performs final scope and permission enforcement.

```text
customer.view
customer.create
customer.update
```

Customer Owner access is provisioned with:

```text
roleCode = CUSTOMER_OWNER
scopeType = CUSTOMER
scopeId = selected Customer
isPrimary = true
```

New users require a strong temporary password. Existing users may be attached by
normalized mobile number without changing their password.

## Web BFF

Browser requests use:

```text
GET  /api/management/customers
POST /api/management/customers/individual
POST /api/management/customers/organization
GET  /api/management/customers/:customerId/members
POST /api/management/customers/:customerId/members
```

The BFF reads HttpOnly authentication cookies, refreshes expired access tokens,
validates input, and never exposes backend tokens to client JavaScript.

## Live development

After installation, the persistent development environment opens:

```text
http://localhost:3001/management/accounts
```

Backend and web hot reload remain active. Routine review no longer requires a
feature-specific preview script.