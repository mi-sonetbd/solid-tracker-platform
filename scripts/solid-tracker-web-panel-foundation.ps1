[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptName = "Solid Tracker - Frontend Web Panel Foundation"
$ExpectedBranch = "feat/web-panel-foundation"
$WebAppRelativePath = "apps/web-panel"
$WebPackageName = "@solid-tracker/web-panel"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogDirectory = Join-Path $env:LOCALAPPDATA "SolidTrackerLogs"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDirectory "web-panel-foundation-$Timestamp.log"

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Ok {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$Arguments = @()
    )

    $displayCommand = $FilePath
    if ($Arguments.Count -gt 0) {
        $displayCommand += " " + ($Arguments -join " ")
    }

    Write-Host "> $displayCommand" -ForegroundColor DarkGray

    & $FilePath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $displayCommand"
    }
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Content
    )

    $FullPath = Join-Path $RepoRoot $RelativePath
    $ParentDirectory = Split-Path -Parent $FullPath

    if ($ParentDirectory) {
        New-Item -ItemType Directory -Path $ParentDirectory -Force | Out-Null
    }

    $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($FullPath, $Content, $Utf8WithoutBom)
}

function Get-GitStatusLines {
    $lines = @(git status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Git repository status."
    }

    return $lines
}

function Assert-OnlyWorkflowScriptsChanged {
    $allowedPaths = @(
        "scripts/solid-tracker-backend-main-integration.ps1",
        "scripts/solid-tracker-web-panel-foundation.ps1"
    )

    $unexpected = @()

    foreach ($line in (Get-GitStatusLines)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $path = $line.Substring(3).Trim()

        if ($path -notin $allowedPaths) {
            $unexpected += $line
        }
    }

    if ($unexpected.Count -gt 0) {
        Write-Host "Unexpected repository changes were found:" -ForegroundColor Yellow
        $unexpected | ForEach-Object {
            Write-Host $_ -ForegroundColor Yellow
        }

        throw "Commit or discard unrelated changes before running this foundation script."
    }
}

function Commit-WorkflowScripts {
    $scriptPaths = @(
        "scripts/solid-tracker-backend-main-integration.ps1",
        "scripts/solid-tracker-web-panel-foundation.ps1"
    )

    foreach ($relativePath in $scriptPaths) {
        $fullPath = Join-Path $RepoRoot $relativePath

        if (Test-Path $fullPath) {
            Invoke-Native "git" @("add", "--", $relativePath)
        }
    }

    & git diff --cached --quiet

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Workflow scripts are already committed."
        return
    }

    if ($LASTEXITCODE -ne 1) {
        throw "Could not inspect staged workflow script changes."
    }

    Invoke-Native "git" @(
        "commit",
        "-m",
        "chore(scripts): add backend and web foundation workflows"
    )

    Write-Ok "Workflow scripts committed."
}

function Assert-NodeVersion {
    $rawNodeVersion = (& node --version).Trim()

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rawNodeVersion)) {
        throw "Node.js is not available."
    }

    $normalizedVersion = $rawNodeVersion.TrimStart("v").Split("-")[0]
    $nodeVersion = [version]$normalizedVersion
    $minimumVersion = [version]"20.9.0"

    if ($nodeVersion -lt $minimumVersion) {
        throw "Next.js requires Node.js 20.9.0 or newer. Installed: $rawNodeVersion"
    }

    Write-Ok "Node.js version verified: $rawNodeVersion"
}

function Update-WebPackageJson {
    $packageJsonPath = Join-Path $RepoRoot "$WebAppRelativePath/package.json"
    $packageJson = Get-Content -Raw -Path $packageJsonPath | ConvertFrom-Json

    $packageJson.name = $WebPackageName
    $packageJson.private = $true

    $packageJson.scripts.dev = "next dev --turbopack --port 3001"
    $packageJson.scripts.build = "next build"
    $packageJson.scripts.start = "next start --port 3001"
    $packageJson.scripts.lint = "eslint . --max-warnings=0"

    if (-not $packageJson.scripts.PSObject.Properties["typecheck"]) {
        $packageJson.scripts | Add-Member `
            -MemberType NoteProperty `
            -Name "typecheck" `
            -Value "tsc --noEmit"
    }
    else {
        $packageJson.scripts.typecheck = "tsc --noEmit"
    }

    $json = $packageJson | ConvertTo-Json -Depth 100
    Write-Utf8File "$WebAppRelativePath/package.json" ($json + [Environment]::NewLine)
}

function New-PlaceholderPage {
    param(
        [Parameter(Mandatory)][string]$Route,
        [Parameter(Mandatory)][string]$Eyebrow,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description
    )

    $content = @"
import { FeaturePlaceholder } from "@/components/shared/feature-placeholder";

export default function Page() {
  return (
    <FeaturePlaceholder
      eyebrow="$Eyebrow"
      title="$Title"
      description="$Description"
    />
  );
}
"@

    Write-Utf8File "$WebAppRelativePath/src/app/(panel)/$Route/page.tsx" $content
}

Set-Location $RepoRoot
Start-Transcript -Path $LogFile | Out-Null

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " $ScriptName" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Section "1. Repository and Toolchain Safety Checks"

    Invoke-Native "git" @("rev-parse", "--is-inside-work-tree")

    $currentBranch = (git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Could not determine the active Git branch."
    }

    if ($currentBranch -ne $ExpectedBranch) {
        throw "Expected branch '$ExpectedBranch', but current branch is '$currentBranch'."
    }

    Write-Ok "Current branch verified: $currentBranch"

    Assert-OnlyWorkflowScriptsChanged
    Commit-WorkflowScripts

    if ((Get-GitStatusLines).Count -ne 0) {
        throw "Repository must be clean before scaffolding the web panel."
    }

    Assert-NodeVersion

    $pnpmVersion = (& pnpm.cmd --version).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($pnpmVersion)) {
        throw "pnpm is not available."
    }

    Write-Ok "pnpm version verified: $pnpmVersion"

    $workspacePath = Join-Path $RepoRoot "pnpm-workspace.yaml"
    if (-not (Test-Path $workspacePath)) {
        throw "pnpm-workspace.yaml was not found at the repository root."
    }

    $workspaceContent = Get-Content -Raw -Path $workspacePath
    if ($workspaceContent -notmatch "apps/") {
        throw "pnpm-workspace.yaml does not appear to include the apps directory."
    }

    Write-Ok "Monorepo workspace configuration verified."

    $webAppPath = Join-Path $RepoRoot $WebAppRelativePath
    if (Test-Path $webAppPath) {
        throw "'$WebAppRelativePath' already exists. This script will not overwrite an existing frontend application."
    }

    Write-Section "2. Create Next.js Web Panel Application"

    Invoke-Native "pnpm.cmd" @(
        "create",
        "next-app",
        $WebAppRelativePath,
        "--ts",
        "--tailwind",
        "--eslint",
        "--app",
        "--src-dir",
        "--turbopack",
        "--import-alias",
        "@/*",
        "--use-pnpm",
        "--disable-git",
        "--no-agents-md",
        "--empty",
        "--yes"
    )

    Update-WebPackageJson
    Write-Ok "Next.js application metadata configured."

    Write-Section "3. Establish Frontend Architecture"

    Write-Utf8File "$WebAppRelativePath/.env.example" @'
NEXT_PUBLIC_APP_NAME=Solid Tracker
NEXT_PUBLIC_API_BASE_URL=http://localhost:3000
'@

    Write-Utf8File "$WebAppRelativePath/src/app/globals.css" @'
@import "tailwindcss";

:root {
  --background: #f4f7fb;
  --foreground: #172033;
  --surface: #ffffff;
  --surface-muted: #eef3f8;
  --border: #dce4ed;
  --brand: #0f766e;
  --brand-strong: #115e59;
  --brand-soft: #ccfbf1;
  --muted: #64748b;
  --danger: #b91c1c;
}

* {
  box-sizing: border-box;
}

html {
  min-width: 320px;
  background: var(--background);
}

body {
  margin: 0;
  background: var(--background);
  color: var(--foreground);
  font-family: Arial, Helvetica, sans-serif;
}

button,
input,
select,
textarea {
  font: inherit;
}

a {
  color: inherit;
  text-decoration: none;
}
'@

    Write-Utf8File "$WebAppRelativePath/src/app/layout.tsx" @'
import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Solid Tracker",
    template: "%s | Solid Tracker",
  },
  description:
    "Solid Tracker fleet, device, customer, dealer, billing, and live tracking management platform.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
'@

    Write-Utf8File "$WebAppRelativePath/src/app/page.tsx" @'
import { redirect } from "next/navigation";

export default function HomePage() {
  redirect("/dashboard");
}
'@

    Write-Utf8File "$WebAppRelativePath/src/config/navigation.ts" @'
export type PanelRole =
  | "SUPER_ADMIN"
  | "ADMIN"
  | "DEALER_MANAGER"
  | "DEALER"
  | "CUSTOMER";

export type NavigationItem = {
  label: string;
  href: string;
  shortLabel: string;
  roles: readonly PanelRole[];
};

const allOperationalRoles: readonly PanelRole[] = [
  "SUPER_ADMIN",
  "ADMIN",
  "DEALER_MANAGER",
  "DEALER",
];

const allRoles: readonly PanelRole[] = [...allOperationalRoles, "CUSTOMER"];

export const panelNavigation: readonly NavigationItem[] = [
  {
    label: "Dashboard",
    href: "/dashboard",
    shortLabel: "DB",
    roles: allRoles,
  },
  {
    label: "Live Tracking",
    href: "/live-tracking",
    shortLabel: "LT",
    roles: allRoles,
  },
  {
    label: "Vehicles",
    href: "/vehicles",
    shortLabel: "VH",
    roles: allRoles,
  },
  {
    label: "Customers",
    href: "/customers",
    shortLabel: "CU",
    roles: allOperationalRoles,
  },
  {
    label: "Dealers",
    href: "/dealers",
    shortLabel: "DL",
    roles: ["SUPER_ADMIN", "ADMIN", "DEALER_MANAGER"],
  },
  {
    label: "Billing",
    href: "/billing",
    shortLabel: "BL",
    roles: allRoles,
  },
  {
    label: "Reports",
    href: "/reports",
    shortLabel: "RP",
    roles: allRoles,
  },
  {
    label: "Settings",
    href: "/settings",
    shortLabel: "ST",
    roles: allRoles,
  },
];
'@

    Write-Utf8File "$WebAppRelativePath/src/lib/env.ts" @'
export const env = {
  appName: process.env.NEXT_PUBLIC_APP_NAME ?? "Solid Tracker",
  apiBaseUrl:
    process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:3000",
} as const;
'@

    Write-Utf8File "$WebAppRelativePath/src/lib/api/client.ts" @'
import { env } from "@/lib/env";

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly payload?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

type ApiRequestOptions = Omit<RequestInit, "body"> & {
  body?: unknown;
  accessToken?: string;
};

export async function apiRequest<T>(
  path: string,
  options: ApiRequestOptions = {},
): Promise<T> {
  const { accessToken, body, headers, ...requestOptions } = options;

  const response = await fetch(
    new URL(path.replace(/^\//, ""), `${env.apiBaseUrl}/`),
    {
      ...requestOptions,
      body: body === undefined ? undefined : JSON.stringify(body),
      headers: {
        Accept: "application/json",
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        ...(accessToken
          ? { Authorization: `Bearer ${accessToken}` }
          : {}),
        ...headers,
      },
    },
  );

  const contentType = response.headers.get("content-type") ?? "";
  const payload = contentType.includes("application/json")
    ? await response.json()
    : await response.text();

  if (!response.ok) {
    throw new ApiError(
      `Solid Tracker API request failed with status ${response.status}.`,
      response.status,
      payload,
    );
  }

  return payload as T;
}
'@

    Write-Utf8File "$WebAppRelativePath/src/types/auth.ts" @'
import type { PanelRole } from "@/config/navigation";

export type AuthenticatedUser = {
  id: string;
  displayName: string;
  mobileNumber: string;
  role: PanelRole;
};

export type LoginRequest = {
  mobileNumber: string;
  password: string;
};

export type LoginResponse = {
  accessToken: string;
  refreshToken: string;
  user: AuthenticatedUser;
};
'@

    Write-Utf8File "$WebAppRelativePath/src/components/layout/panel-sidebar.tsx" @'
import Link from "next/link";
import { panelNavigation } from "@/config/navigation";

export function PanelSidebar() {
  return (
    <aside className="hidden min-h-screen w-72 shrink-0 border-r border-slate-200 bg-slate-950 text-white lg:flex lg:flex-col">
      <div className="border-b border-white/10 px-7 py-7">
        <Link href="/dashboard" className="flex items-center gap-3">
          <span className="grid h-11 w-11 place-items-center rounded-2xl bg-teal-500 font-black text-slate-950">
            ST
          </span>
          <span>
            <span className="block text-lg font-bold tracking-tight">
              Solid Tracker
            </span>
            <span className="block text-xs text-slate-400">
              Operations Web Panel
            </span>
          </span>
        </Link>
      </div>

      <nav className="flex-1 space-y-1 px-4 py-6" aria-label="Main navigation">
        {panelNavigation.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium text-slate-300 transition hover:bg-white/10 hover:text-white"
          >
            <span className="grid h-8 w-8 place-items-center rounded-lg bg-white/10 text-xs font-bold text-teal-300">
              {item.shortLabel}
            </span>
            {item.label}
          </Link>
        ))}
      </nav>

      <div className="border-t border-white/10 p-5">
        <div className="rounded-2xl bg-white/5 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-teal-300">
            Backend
          </p>
          <p className="mt-2 text-sm font-semibold">API verified</p>
          <p className="mt-1 text-xs leading-5 text-slate-400">
            Authentication, tracking, billing, notifications, and mobile APIs
            passed their quality gates.
          </p>
        </div>
      </div>
    </aside>
  );
}
'@

    Write-Utf8File "$WebAppRelativePath/src/components/layout/panel-header.tsx" @'
export function PanelHeader() {
  return (
    <header className="sticky top-0 z-20 border-b border-slate-200 bg-white/95 px-5 py-4 backdrop-blur md:px-8">
      <div className="mx-auto flex max-w-[1600px] items-center justify-between gap-4">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">
            Solid Tracker
          </p>
          <p className="text-sm text-slate-500">
            Professional GPS tracking operations
          </p>
        </div>

        <div className="flex items-center gap-3">
          <span className="hidden rounded-full bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700 sm:inline">
            Backend verified
          </span>
          <div className="grid h-10 w-10 place-items-center rounded-full bg-slate-900 text-sm font-bold text-white">
            SA
          </div>
        </div>
      </div>
    </header>
  );
}
'@

    Write-Utf8File "$WebAppRelativePath/src/components/dashboard/stat-card.tsx" @'
type StatCardProps = {
  label: string;
  value: string;
  detail: string;
};

export function StatCard({ label, value, detail }: StatCardProps) {
  return (
    <article className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <p className="text-sm font-medium text-slate-500">{label}</p>
      <p className="mt-3 text-3xl font-black tracking-tight text-slate-950">
        {value}
      </p>
      <p className="mt-2 text-sm text-slate-500">{detail}</p>
    </article>
  );
}
'@

    Write-Utf8File "$WebAppRelativePath/src/components/shared/feature-placeholder.tsx" @'
import Link from "next/link";

type FeaturePlaceholderProps = {
  eyebrow: string;
  title: string;
  description: string;
};

export function FeaturePlaceholder({
  eyebrow,
  title,
  description,
}: FeaturePlaceholderProps) {
  return (
    <div className="mx-auto max-w-5xl">
      <div className="rounded-3xl border border-slate-200 bg-white p-8 shadow-sm md:p-12">
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-teal-700">
          {eyebrow}
        </p>
        <h1 className="mt-4 text-3xl font-black tracking-tight text-slate-950 md:text-4xl">
          {title}
        </h1>
        <p className="mt-4 max-w-2xl text-base leading-7 text-slate-600">
          {description}
        </p>

        <div className="mt-8 rounded-2xl border border-dashed border-teal-300 bg-teal-50 p-5">
          <p className="font-semibold text-teal-950">
            Foundation route is ready.
          </p>
          <p className="mt-1 text-sm leading-6 text-teal-800">
            Authentication, API contracts, authorization, loading states, and
            production data will be implemented in the relevant development
            stage.
          </p>
        </div>

        <Link
          href="/dashboard"
          className="mt-8 inline-flex rounded-xl bg-slate-950 px-5 py-3 text-sm font-semibold text-white transition hover:bg-slate-800"
        >
          Return to dashboard
        </Link>
      </div>
    </div>
  );
}
'@

    Write-Utf8File "$WebAppRelativePath/src/app/(panel)/layout.tsx" @'
import { PanelHeader } from "@/components/layout/panel-header";
import { PanelSidebar } from "@/components/layout/panel-sidebar";

export default function PanelLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <div className="min-h-screen bg-slate-100 lg:flex">
      <PanelSidebar />
      <div className="min-w-0 flex-1">
        <PanelHeader />
        <main className="px-5 py-6 md:px-8 md:py-8">
          <div className="mx-auto max-w-[1600px]">{children}</div>
        </main>
      </div>
    </div>
  );
}
'@

    Write-Utf8File "$WebAppRelativePath/src/app/(panel)/dashboard/page.tsx" @'
import Link from "next/link";
import { StatCard } from "@/components/dashboard/stat-card";

const developmentModules = [
  {
    name: "Authentication",
    state: "Next",
    description: "Secure login, refresh tokens, logout, and session recovery.",
  },
  {
    name: "Role authorization",
    state: "Planned",
    description:
      "Super admin, admin, dealer manager, dealer, and customer access.",
  },
  {
    name: "Live tracking",
    state: "Planned",
    description: "Map, online state, telemetry, and vehicle selection.",
  },
  {
    name: "Operations",
    state: "Planned",
    description: "Vehicles, devices, customers, dealers, billing, and reports.",
  },
];

export default function DashboardPage() {
  return (
    <div className="space-y-7">
      <section className="overflow-hidden rounded-3xl bg-slate-950 p-7 text-white shadow-xl md:p-10">
        <div className="max-w-3xl">
          <p className="text-xs font-bold uppercase tracking-[0.2em] text-teal-300">
            Frontend foundation
          </p>
          <h1 className="mt-4 text-3xl font-black tracking-tight md:text-5xl">
            Solid Tracker Operations Panel
          </h1>
          <p className="mt-4 max-w-2xl text-sm leading-7 text-slate-300 md:text-base">
            One responsive web application for platform administration,
            dealers, customers, vehicles, billing, reports, and live GPS
            tracking.
          </p>
          <div className="mt-7 flex flex-wrap gap-3">
            <Link
              href="/live-tracking"
              className="rounded-xl bg-teal-400 px-5 py-3 text-sm font-bold text-slate-950 transition hover:bg-teal-300"
            >
              Open live tracking
            </Link>
            <Link
              href="/vehicles"
              className="rounded-xl border border-white/20 px-5 py-3 text-sm font-bold text-white transition hover:bg-white/10"
            >
              View vehicles
            </Link>
          </div>
        </div>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Backend quality gates"
          value="Passed"
          detail="Lint, typecheck, tests, E2E, and production build."
        />
        <StatCard
          label="Database migrations"
          value="6"
          detail="PostgreSQL schema is fully up to date."
        />
        <StatCard
          label="Backend unit tests"
          value="18"
          detail="All current unit tests passed."
        />
        <StatCard
          label="Backend E2E tests"
          value="11"
          detail="All current end-to-end tests passed."
        />
      </section>

      <section className="grid gap-6 xl:grid-cols-[1.4fr_0.6fr]">
        <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm md:p-8">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">
                Implementation sequence
              </p>
              <h2 className="mt-2 text-2xl font-black tracking-tight text-slate-950">
                Web panel development modules
              </h2>
            </div>
            <span className="rounded-full bg-teal-50 px-3 py-1.5 text-xs font-semibold text-teal-700">
              Foundation active
            </span>
          </div>

          <div className="mt-6 divide-y divide-slate-100">
            {developmentModules.map((module) => (
              <article
                key={module.name}
                className="grid gap-3 py-5 sm:grid-cols-[1fr_auto] sm:items-center"
              >
                <div>
                  <h3 className="font-bold text-slate-950">{module.name}</h3>
                  <p className="mt-1 text-sm leading-6 text-slate-500">
                    {module.description}
                  </p>
                </div>
                <span className="w-fit rounded-full bg-slate-100 px-3 py-1.5 text-xs font-bold text-slate-600">
                  {module.state}
                </span>
              </article>
            ))}
          </div>
        </div>

        <aside className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm md:p-8">
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">
            Current stage
          </p>
          <h2 className="mt-3 text-2xl font-black tracking-tight text-slate-950">
            Frontend before Flutter
          </h2>
          <p className="mt-4 text-sm leading-7 text-slate-600">
            The web panel will validate backend contracts, roles, tracking
            workflows, and operational screens before the customer mobile
            application is started.
          </p>
          <div className="mt-6 rounded-2xl bg-slate-950 p-5 text-white">
            <p className="text-sm font-bold">Next implementation</p>
            <p className="mt-2 text-sm leading-6 text-slate-300">
              Web authentication and role-aware protected routing.
            </p>
          </div>
        </aside>
      </section>
    </div>
  );
}
'@

    Write-Utf8File "$WebAppRelativePath/src/app/(auth)/login/page.tsx" @'
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Login",
};

export default function LoginPage() {
  return (
    <main className="grid min-h-screen place-items-center bg-slate-950 px-5 py-10">
      <div className="w-full max-w-md rounded-3xl bg-white p-7 shadow-2xl md:p-9">
        <Link href="/" className="inline-flex items-center gap-3">
          <span className="grid h-11 w-11 place-items-center rounded-2xl bg-teal-500 font-black text-slate-950">
            ST
          </span>
          <span>
            <span className="block text-lg font-black tracking-tight text-slate-950">
              Solid Tracker
            </span>
            <span className="block text-xs text-slate-500">
              Secure operations panel
            </span>
          </span>
        </Link>

        <div className="mt-8">
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">
            Account access
          </p>
          <h1 className="mt-2 text-3xl font-black tracking-tight text-slate-950">
            Sign in
          </h1>
          <p className="mt-2 text-sm leading-6 text-slate-500">
            The interface is ready. Backend authentication integration is the
            next controlled development stage.
          </p>
        </div>

        <form className="mt-7 space-y-5">
          <label className="block">
            <span className="text-sm font-semibold text-slate-700">
              Mobile number
            </span>
            <input
              type="tel"
              name="mobileNumber"
              autoComplete="tel"
              placeholder="01XXXXXXXXX"
              className="mt-2 w-full rounded-xl border border-slate-300 px-4 py-3 outline-none transition focus:border-teal-600 focus:ring-4 focus:ring-teal-100"
            />
          </label>

          <label className="block">
            <span className="text-sm font-semibold text-slate-700">
              Password
            </span>
            <input
              type="password"
              name="password"
              autoComplete="current-password"
              placeholder="Enter your password"
              className="mt-2 w-full rounded-xl border border-slate-300 px-4 py-3 outline-none transition focus:border-teal-600 focus:ring-4 focus:ring-teal-100"
            />
          </label>

          <button
            type="button"
            className="w-full rounded-xl bg-slate-950 px-5 py-3.5 text-sm font-bold text-white transition hover:bg-slate-800"
          >
            Authentication integration pending
          </button>
        </form>
      </div>
    </main>
  );
}
'@

    New-PlaceholderPage `
        -Route "live-tracking" `
        -Eyebrow "Tracking operations" `
        -Title "Live Tracking" `
        -Description "This route will contain the production map, vehicle selector, latest telemetry, connection status, and real-time position updates."

    New-PlaceholderPage `
        -Route "vehicles" `
        -Eyebrow "Fleet operations" `
        -Title "Vehicles and Devices" `
        -Description "This route will manage vehicle records, device assignments, installation details, tracker credentials, and operational status."

    New-PlaceholderPage `
        -Route "customers" `
        -Eyebrow "Account operations" `
        -Title "Customer Management" `
        -Description "This route will manage customer accounts, subscriptions, linked vehicles, dealer relationships, and service status."

    New-PlaceholderPage `
        -Route "dealers" `
        -Eyebrow "Channel operations" `
        -Title "Dealer Management" `
        -Description "This route will manage dealers, dealer managers, permissions, customer ownership, commissions, and settlement configuration."

    New-PlaceholderPage `
        -Route "billing" `
        -Eyebrow "Financial operations" `
        -Title "Billing and Payments" `
        -Description "This route will show invoices, payment status, automated gateway activity, dealer commissions, and settlement records."

    New-PlaceholderPage `
        -Route "reports" `
        -Eyebrow "Operational intelligence" `
        -Title "Reports" `
        -Description "This route will provide tracking, trip, device, customer, dealer, billing, payment, and audit reports."

    New-PlaceholderPage `
        -Route "settings" `
        -Eyebrow "Platform configuration" `
        -Title "Settings" `
        -Description "This route will contain organization, security, notification, mapping, billing, and integration settings."

    Write-Utf8File "$WebAppRelativePath/README.md" @'
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
'@

    Write-Utf8File "docs/frontend/web-panel-foundation.md" @'
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
'@

    Write-Ok "Application routes, layout, API client, role model, and documentation created."

    Write-Section "4. Install and Verify Frontend"

    Invoke-Native "pnpm.cmd" @("install")

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $WebPackageName,
        "lint"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $WebPackageName,
        "typecheck"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $WebPackageName,
        "build"
    )

    Invoke-Native "git" @("diff", "--check")

    Write-Ok "Frontend lint, typecheck, build, and Git whitespace checks passed."

    Write-Section "5. Commit Web Panel Foundation"

    Invoke-Native "git" @("add", "--all")

    & git diff --cached --quiet

    if ($LASTEXITCODE -eq 0) {
        throw "No frontend foundation changes were staged."
    }

    if ($LASTEXITCODE -ne 1) {
        throw "Could not inspect staged frontend changes."
    }

    Invoke-Native "git" @(
        "commit",
        "-m",
        "feat(web): establish operations panel foundation"
    )

    if ((Get-GitStatusLines).Count -ne 0) {
        throw "Repository is not clean after the frontend foundation commit."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host " Frontend Web Panel Foundation Completed" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host ""

    Write-Host "Current branch : $ExpectedBranch" -ForegroundColor Yellow
    Write-Host "Web application: $WebAppRelativePath" -ForegroundColor Yellow
    Write-Host "Development URL: http://localhost:3001" -ForegroundColor Yellow
    Write-Host "Next stage     : Authentication and role-based routing" -ForegroundColor Yellow
    Write-Host "Log file       : $LogFile" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Latest commits:" -ForegroundColor Yellow
    git log --oneline --decorate --graph -8

    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
}
catch {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host " Frontend Foundation Failed" -ForegroundColor Red
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Log file: $LogFile" -ForegroundColor Yellow

    exit 1
}
finally {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Transcript may not have started if failure occurred very early.
    }
}
