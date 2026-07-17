# Solid Tracker Web Panel Foundation

## Decision

The frontend web panel is implemented before the Flutter customer application.

This order allows the team to validate:

- backend API contracts;
- user and role permissions;
- dealer and customer operational flows;
- device and vehicle management;
- billing, payment, commission, and settlement flows;
- live tracking and historical tracking workflows;
- reusable frontend domain models.

## Application location

`apps/web-panel`

## Technology baseline

- Next.js App Router
- React
- TypeScript
- Tailwind CSS
- ESLint
- pnpm workspace
- Turbopack for local development

## Initial role model

- Super Admin
- Admin
- Dealer Manager
- Dealer
- Customer

The navigation configuration contains role metadata, but route enforcement will be introduced with authentication.

## Initial routes

- `/login`
- `/dashboard`
- `/live-tracking`
- `/vehicles`
- `/customers`
- `/dealers`
- `/billing`
- `/reports`
- `/settings`

## Development sequence

1. Authentication and session lifecycle
2. Role-based route protection
3. Backend API integration layer
4. Dashboard data
5. Vehicles and devices
6. Customers and dealers
7. Live tracking
8. Trips, playback, geofences, and alerts
9. Billing, payments, commissions, and settlements
10. Reports, audit views, responsive testing, and deployment readiness
11. Flutter mobile application