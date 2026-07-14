# Identity and Access API Foundation

## Delivered modules

- `AuthModule`
- `AccessControlModule`
- `UsersModule`
- `OrganizationsModule`
- `MembershipsModule`
- `RolesModule`
- `PermissionsModule`
- `SessionsModule`
- `AuditModule`
- `OtpModule`

## Authentication

Users authenticate with a normalized mobile number and password.

Passwords are hashed using Node.js `scrypt`, a unique random salt, and explicit cost, block-size, parallelization, and memory parameters.

Access tokens are short-lived JWT bearer tokens containing only the user ID, session ID, and token type.

Refresh tokens are opaque random values. PostgreSQL stores only keyed hashes.

## Session security

Refresh-token rotation atomically revokes the old session and creates a replacement in the same token family.

A reused, revoked, or expired refresh token revokes active sessions in that token family.

## Authorization

The access-token guard validates JWT signature, token expiry, token type, active database session, session expiry, and active user status.

`AccessControlModule` imports and re-exports `SecurityModule`. This makes `TokenService` available when Nest resolves the exported access guard in feature-module controller contexts.

The access-control service loads effective roles, permissions, organization memberships, and customer memberships from PostgreSQL.

## Login protection

Redis limits login attempts by IP address and normalized mobile number.

PostgreSQL records failed-login counts and temporary account locking.

## OTP

OTP values are stored only as keyed hashes. Challenges support mobile verification, password reset, high-risk action verification, expiry, attempt limits, replacement, and lockout.

## Audit immutability

PostgreSQL prevents updates and deletes on `audit_logs`.

Automated tests archive test identities instead of deleting immutable audit history.

## Initial administrator

No default administrator or password is committed.

Create the first administrator with:

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\scripts\solid-tracker-create-platform-admin.ps1"
```

## Endpoints

```text
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
GET    /api/v1/auth/me
POST   /api/v1/auth/logout
POST   /api/v1/auth/logout-all

GET    /api/v1/sessions
DELETE /api/v1/sessions/:sessionId

GET    /api/v1/users/me
GET    /api/v1/users/:userId

GET    /api/v1/organizations/me
GET    /api/v1/memberships/me
GET    /api/v1/roles/me
GET    /api/v1/permissions/me
```