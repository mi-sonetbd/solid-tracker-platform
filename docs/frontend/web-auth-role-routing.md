# Solid Tracker Web Authentication and Role Routing

## Customer interface decision

The currently approved screenshot-based interface is the Customer workspace.

It is implemented as `CustomerShell` and must remain independent from the
future role-specific templates.

## Future role templates

The following authenticated workspaces are intentionally separated:

- Dealer
- Dealer Manager
- Admin
- Super Admin

Until their templates are provided, those users are redirected to
`/role-template-pending` and never shown the Customer workspace.

## Backend contract

The web BFF integrates with:

- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `GET /api/v1/auth/me`
- `POST /api/v1/auth/logout`

Login sends:

- `mobileNumber`
- `password`
- `platform: WEB`
- `deviceName`
- `appVersion`

## Security architecture

- Access and refresh tokens are stored in HttpOnly cookies.
- Production cookies use the Secure attribute.
- Cookies use SameSite=Lax.
- The browser never receives tokens in JavaScript-readable storage.
- Next.js Route Handlers form a backend-for-frontend boundary.
- `proxy.ts` performs an optimistic cookie-presence redirect.
- Protected Server Component layouts validate the token with `/auth/me`.
- Expired access tokens are rotated through `/auth/refresh`.
- Customer routes enforce Customer workspace authorization server-side.

## Routes

- `/login`
- `/api/auth/login`
- `/api/auth/session`
- `/api/auth/refresh`
- `/api/auth/logout`
- `/role-template-pending`

## Next stage

1. create or identify a real Customer login account;
2. execute browser login/logout/session-expiry verification;
3. connect Customer dashboard data;
4. connect Customer vehicles and live tracking;
5. add Dealer/Admin templates when supplied.