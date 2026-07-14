# Solid Tracker Security Model

## Authentication

- Primary login identity: normalized mobile number.
- Secondary identity: optional verified email.
- Normal login: mobile number and password.
- OTP purposes: verification, activation, password reset, and sensitive actions.
- Password hashing: Argon2id preferred.
- Access tokens: short-lived JWTs.
- Refresh tokens: rotated, session-bound, and stored as hashes.

## Authorization

Authorization requires:

- active user account;
- active organization or customer membership;
- active role assignment;
- required permission;
- matching scope;
- resource ownership validation;
- valid business state.

## Session security

Sessions record device, platform, IP address, user agent, expiry, and revocation state.

Sessions may be revoked after:

- logout;
- password change;
- account disablement;
- security incident;
- refresh-token reuse;
- administrator action.

## OTP controls

- short expiry;
- one-time use;
- maximum attempts;
- purpose binding;
- destination binding;
- request rate limits;
- hashed code storage.

## High-risk operations

High-risk operations require dedicated permissions, reason capture, audit logging, and step-up verification when available.

## Audit

Audit records include actor, organization, action, resource, before/after state, scope, IP address, user agent, correlation ID, and timestamp.