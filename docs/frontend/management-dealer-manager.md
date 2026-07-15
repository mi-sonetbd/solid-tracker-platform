# Dealer Manager Provisioning

## Backend contract

The web panel uses the existing Dealer staff API:

- `GET /api/v1/dealers/:dealerId/staff`
- `POST /api/v1/dealers/:dealerId/staff`

Both operations require `dealer.staff.manage`.

The backend additionally validates that the selected Dealer is within the
authenticated Platform or Dealer scope.

## Dealer Manager identity

A Dealer Manager is not a Dealer organization.

The provisioned login is represented by:

```text
User
+
OrganizationMembership
+
RoleAssignment(
  role = DEALER_MANAGER,
  scopeType = DEALER,
  scopeId = selected Dealer
)
```

## New versus existing user

### New login

Required fields:

- full name;
- mobile number;
- temporary password of at least 12 characters.

The password is hashed by the backend and is never returned.

### Existing user

The existing Solid Tracker user is located by normalized mobile number.

The existing user is attached to the Dealer through a membership and
Dealer-scoped role assignment. No password is accepted or changed in this mode.

## BFF routes

Browser requests use:

- `GET /api/management/dealers/:dealerId/staff`
- `POST /api/management/dealers/:dealerId/staff`

The BFF keeps access and refresh tokens in HttpOnly cookies, refreshes expired
access tokens, forwards validation and permission errors, and never exposes
backend credentials to browser JavaScript.

## Audit

Successful provisioning records:

```text
dealer.staff.provisioned
```

The audit metadata records whether a new user was administratively provisioned.

## UI behavior

Account Management now provides:

- Add Dealer Manager card;
- Dealer selection;
- new-versus-existing user mode;
- password confirmation for new users;
- fixed `DEALER_MANAGER` role;
- Dealer Staff directory;
- staff count refresh after provisioning;
- Dealer-specific Add Manager actions.

## Next operation stage

After login and scope verification:

1. add Customer under Platform or Dealer;
2. create Customer login membership;
3. connect the account hierarchy to real Dealer and Customer records.