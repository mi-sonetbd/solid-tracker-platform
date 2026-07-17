# Solid Tracker Web Panel

The professional operations web application for the Solid Tracker GPS tracking platform.

## Foundation

- Next.js App Router
- TypeScript
- Tailwind CSS
- ESLint
- Turbopack development server
- Role-aware navigation model
- Shared API client foundation
- Responsive administration shell
- Initial routes for tracking, vehicles, customers, dealers, billing, reports, and settings

## Local ports

- Backend API: `http://localhost:3000`
- Web panel: `http://localhost:3001`

Copy `.env.example` to `.env.local` before backend integration.

## Commands

From the repository root:

```powershell
pnpm.cmd --filter "@solid-tracker/web-panel" dev
pnpm.cmd --filter "@solid-tracker/web-panel" lint
pnpm.cmd --filter "@solid-tracker/web-panel" typecheck
pnpm.cmd --filter "@solid-tracker/web-panel" build
```

## Next stage

Implement secure authentication, token lifecycle, logout, session recovery, protected route groups, and role-based authorization.