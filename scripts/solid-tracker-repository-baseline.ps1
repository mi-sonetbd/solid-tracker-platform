[CmdletBinding()]
param(
    [string]$RepositoryPath = "D:\GitHub\gps-tracker-platform"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param(
        [int]$Number,
        [int]$Total,
        [string]$Message
    )

    Write-Host ("[{0}/{1}] {2}" -f $Number, $Total, $Message) -ForegroundColor Yellow
}

function Write-Utf8FileIfMissingOrEmpty {
    param(
        [string]$RelativePath,
        $Lines
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $parentPath = Split-Path -Parent $fullPath

    if (
        -not [string]::IsNullOrWhiteSpace($parentPath) -and
        -not (Test-Path -LiteralPath $parentPath)
    ) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    $shouldWrite = $false

    if (-not (Test-Path -LiteralPath $fullPath)) {
        $shouldWrite = $true
    }
    elseif ((Get-Item -LiteralPath $fullPath).Length -eq 0) {
        $shouldWrite = $true
    }

    if ($shouldWrite) {
        $textLines = @($Lines | ForEach-Object { [string]$_ })

        [System.IO.File]::WriteAllLines(
            $fullPath,
            $textLines,
            $script:Utf8NoBom
        )

        Write-Host "[CREATED]   $RelativePath" -ForegroundColor Green
    }
    else {
        Write-Host "[PRESERVED] $RelativePath" -ForegroundColor DarkYellow
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Repository Baseline Setup" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath
    $script:RootPath = (Get-Location).Path
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found in $script:RootPath"
    }

    Write-Step 1 7 "Creating repository directories"

    $directories = @(
        ".github\ISSUE_TEMPLATE",
        ".github\workflows",
        "apps\admin-web",
        "apps\android-app",
        "services\backend-api",
        "services\notification-service",
        "services\traccar-integration",
        "packages\shared-config",
        "packages\shared-types",
        "infrastructure\deployment",
        "infrastructure\docker",
        "infrastructure\nginx",
        "infrastructure\traccar\conf",
        "infrastructure\traccar\scripts",
        "scripts"
    )

    foreach ($directory in $directories) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Write-Step 2 7 "Writing repository configuration"

    Write-Utf8FileIfMissingOrEmpty ".editorconfig" @(
        "root = true",
        "",
        "[*]",
        "charset = utf-8",
        "end_of_line = lf",
        "insert_final_newline = true",
        "trim_trailing_whitespace = true",
        "indent_style = space",
        "indent_size = 2",
        "",
        "[*.md]",
        "trim_trailing_whitespace = false",
        "",
        "[*.ps1]",
        "end_of_line = crlf",
        "indent_size = 4"
    )

    Write-Utf8FileIfMissingOrEmpty ".gitignore" @(
        "# Dependencies",
        "node_modules/",
        ".pnpm-store/",
        "",
        "# Build output",
        "dist/",
        "build/",
        "coverage/",
        "*.tsbuildinfo",
        "",
        "# Environment and secrets",
        ".env",
        ".env.*",
        "!.env.example",
        "",
        "# Logs",
        "logs/",
        "*.log",
        "npm-debug.log*",
        "pnpm-debug.log*",
        "",
        "# IDE files",
        ".vscode/*",
        "!.vscode/extensions.json",
        "!.vscode/settings.json",
        ".idea/",
        "",
        "# Operating-system files",
        ".DS_Store",
        "Thumbs.db",
        "Desktop.ini",
        "",
        "# Temporary files",
        "tmp/",
        "temp/",
        ".cache/",
        "",
        "# Local databases",
        "*.db",
        "*.db-journal",
        "",
        "# Android generated files",
        "apps/android-app/.gradle/",
        "apps/android-app/local.properties",
        "apps/android-app/**/build/",
        "",
        "# Generated backend files",
        "services/backend-api/src/generated/"
    )

    Write-Step 3 7 "Writing repository documentation"

    Write-Utf8FileIfMissingOrEmpty "README.md" @(
        "# Solid Tracker Platform",
        "",
        "Solid Tracker is a professional GPS tracking and fleet-management platform.",
        "",
        "## Platform capabilities",
        "",
        "- Live GPS device tracking",
        "- Customer and dealer management",
        "- Dealer-manager operations",
        "- Device installation and assignment",
        "- Subscription and billing management",
        "- Online payment processing",
        "- Automated dealer commissions",
        "- Notifications and reporting",
        "- Traccar integration",
        "",
        "## Repository structure",
        "",
        "- apps: admin and mobile applications",
        "- services: backend and integration services",
        "- packages: reusable shared packages",
        "- infrastructure: Docker, deployment, Nginx and Traccar",
        "- docs: business and technical documentation",
        "- scripts: development and operations scripts",
        "",
        "## Backend technology",
        "",
        "- NestJS",
        "- TypeScript",
        "- PostgreSQL",
        "- Prisma ORM",
        "- Redis",
        "- Docker Compose",
        "- Traccar",
        "",
        "## Development workflow",
        "",
        "Production-ready code remains on the main branch.",
        "Development work is performed on short-lived feature branches."
    )

    Write-Utf8FileIfMissingOrEmpty "CONTRIBUTING.md" @(
        "# Contributing to Solid Tracker",
        "",
        "## Branch naming",
        "",
        "- feat/feature-name",
        "- fix/issue-name",
        "- docs/document-name",
        "- chore/task-name",
        "",
        "Direct feature development on main is not permitted.",
        "",
        "## Commit convention",
        "",
        "- feat: new functionality",
        "- fix: bug correction",
        "- docs: documentation changes",
        "- test: test changes",
        "- refactor: internal restructuring",
        "- chore: tooling and maintenance",
        "",
        "## Required checks",
        "",
        "- Formatting",
        "- Linting",
        "- Type checking",
        "- Unit tests",
        "- Integration tests",
        "- Successful production build",
        "",
        "Secrets and production credentials must never be committed."
    )

    Write-Utf8FileIfMissingOrEmpty "CHANGELOG.md" @(
        "# Changelog",
        "",
        "All notable changes to Solid Tracker will be documented here.",
        "",
        "## Unreleased",
        "",
        "### Added",
        "",
        "- Initial professional repository structure",
        "- Project documentation structure",
        "- Application and service boundaries",
        "- Infrastructure directories"
    )

    Write-Utf8FileIfMissingOrEmpty "SECURITY.md" @(
        "# Security Policy",
        "",
        "## Vulnerability reporting",
        "",
        "Do not publish suspected security vulnerabilities in public issues.",
        "",
        "Report vulnerabilities privately to the project maintainers.",
        "",
        "Include:",
        "",
        "- Affected component",
        "- Reproduction procedure",
        "- Expected and actual behavior",
        "- Potential security impact",
        "- Suggested remediation",
        "",
        "## Secret management",
        "",
        "Never commit:",
        "",
        "- Environment files containing real credentials",
        "- Database passwords",
        "- JWT secrets",
        "- Encryption keys",
        "- Payment gateway credentials",
        "- Traccar administrator credentials",
        "- API keys",
        "- Private certificates"
    )

    Write-Step 4 7 "Checking Git identity"

    $gitName = (git config --get user.name 2>$null)
    $gitEmail = (git config --get user.email 2>$null)

    if ([string]::IsNullOrWhiteSpace($gitName)) {
        $gitName = Read-Host "Enter your Git name"

        if ([string]::IsNullOrWhiteSpace($gitName)) {
            throw "Git name cannot be empty."
        }

        git config user.name "$gitName"
    }

    if ([string]::IsNullOrWhiteSpace($gitEmail)) {
        $gitEmail = Read-Host "Enter your Git email"

        if ([string]::IsNullOrWhiteSpace($gitEmail)) {
            throw "Git email cannot be empty."
        }

        git config user.email "$gitEmail"
    }

    Write-Host "Git author: $gitName <$gitEmail>" -ForegroundColor Green

    Write-Step 5 7 "Creating repository baseline commit"

    git add --all

    cmd.exe /c "git rev-parse --verify HEAD >nul 2>&1"
    $hasCommit = ($LASTEXITCODE -eq 0)

    if (-not $hasCommit) {
        git commit -m "chore(repo): initialize Solid Tracker repository"

        if ($LASTEXITCODE -ne 0) {
            throw "Initial Git commit failed."
        }
    }
    else {
        $pendingChanges = @(git status --porcelain)

        if ($pendingChanges.Count -gt 0) {
            git commit -m "chore(repo): complete Solid Tracker repository baseline"

            if ($LASTEXITCODE -ne 0) {
                throw "Repository baseline commit failed."
            }
        }
        else {
            Write-Host "No new repository changes require a commit." -ForegroundColor Green
        }
    }

    Write-Step 6 7 "Creating or selecting backend development branch"

    $currentBranch = (git branch --show-current).Trim()
    $branchExists = @(git branch --list "feat/backend-foundation")

    if ($currentBranch -eq "feat/backend-foundation") {
        Write-Host "Already on feat/backend-foundation." -ForegroundColor Green
    }
    elseif ($branchExists.Count -gt 0) {
        git switch "feat/backend-foundation"
    }
    else {
        git switch -c "feat/backend-foundation"
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Could not switch to feat/backend-foundation."
    }

    Write-Step 7 7 "Verifying repository"

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Repository Baseline Completed" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current

    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate

    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status

    Write-Host ""
    Write-Host "Solid Tracker backend foundation branch is ready." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "SETUP FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
