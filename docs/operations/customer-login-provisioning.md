# Customer Login Provisioning

## Purpose

A Customer record and a User login identity are separate records.

This operator securely creates or repairs the login identity, links it to the
Customer, assigns a Customer role, clears authentication lockout state, revokes
old sessions, and writes an audit event.

## Run

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\scripts\solid-tracker-provision-customer-login.ps1"
```

The operator securely prompts for:

- Customer mobile number
- Customer full name
- password
- password confirmation

The password is passed to the TypeScript CLI only through a temporary process
environment variable and is removed afterward.

## Default role

`CUSTOMER_OWNER`

Other supported roles:

- `CUSTOMER_ADMIN`
- `CUSTOMER_VIEWER`

## Behavior

- Reuses a matching active Customer record when available.
- Reuses and repairs an existing User identity when available.
- Creates a platform-managed individual Customer when no matching Customer
  exists.
- Marks the Customer owner as the primary Customer member.
- Clears failed-login and temporary-lock state.
- Revokes previous active sessions.
- Creates an immutable audit event.
- Does not create or change any Prisma migration.