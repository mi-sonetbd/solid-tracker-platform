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

function Convert-ToText {
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    return (($Lines -join "`n") + "`n")
}

function Write-ManagedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $parentPath = Split-Path -Parent $fullPath
    $expectedText = Convert-ToText -Lines $Lines

    if (
        -not [string]::IsNullOrWhiteSpace($parentPath) -and
        -not (Test-Path -LiteralPath $parentPath)
    ) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    if (Test-Path -LiteralPath $fullPath) {
        $currentText = [System.IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")

        if ($currentText -eq $expectedText) {
            Write-Host "[PRESERVED] $RelativePath" -ForegroundColor DarkYellow
            return
        }

        throw "Refusing to overwrite an existing modified file: $RelativePath"
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $expectedText,
        $script:Utf8NoBom
    )

    Write-Host "[CREATED]   $RelativePath" -ForegroundColor Green
}

function New-RandomSecret {
    param([int]$ByteLength = 32)

    $bytes = New-Object byte[] $ByteLength
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    return [Convert]::ToBase64String($bytes).
        TrimEnd("=").
        Replace("+", "-").
        Replace("/", "_")
}

function Get-ContainerHealth {
    param([string]$ContainerName)

    $result = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        $ContainerName 2>$null

    if ($LASTEXITCODE -ne 0) {
        return "missing"
    }

    return $result.Trim()
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Local Infrastructure Setup" -ForegroundColor Cyan
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

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -ne "feat/backend-foundation") {
        throw "Expected branch feat/backend-foundation, but current branch is $currentBranch"
    }

    Write-Step 1 8 "Validating development tools"

    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
        throw "Node.js is not available."
    }

    if (-not (Get-Command pnpm.cmd -ErrorAction SilentlyContinue)) {
        throw "pnpm is not available."
    }

    if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
        throw "Docker CLI is not available."
    }

    docker info *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "Docker Engine is not running."
    }

    $nodeVersion = (& node.exe --version).Trim()
    $pnpmVersion = (& pnpm.cmd --version).Trim()

    Write-Host "Node.js: $nodeVersion" -ForegroundColor Green
    Write-Host "pnpm:    $pnpmVersion" -ForegroundColor Green
    Write-Host "Docker:  running" -ForegroundColor Green

    Write-Step 2 8 "Creating pnpm workspace files"

    Write-ManagedFile "package.json" @(
        "{",
        '  "name": "solid-tracker-platform",',
        '  "version": "0.1.0",',
        '  "private": true,',
        '  "description": "Solid Tracker GPS tracking platform monorepo",',
        '  "packageManager": "pnpm@11.12.0",',
        '  "engines": {',
        '    "node": ">=24.0.0",',
        '    "pnpm": ">=11.0.0"',
        "  },",
        '  "scripts": {',
        '    "infra:up": "docker compose --env-file .env up -d",',
        '    "infra:stop": "docker compose --env-file .env stop",',
        '    "infra:down": "docker compose --env-file .env down",',
        '    "infra:reset": "docker compose --env-file .env down --volumes --remove-orphans",',
        '    "infra:logs": "docker compose --env-file .env logs -f",',
        '    "infra:status": "docker compose --env-file .env ps"',
        "  }",
        "}"
    )

    Write-ManagedFile "pnpm-workspace.yaml" @(
        "packages:",
        "  - apps/*",
        "  - services/*",
        "  - packages/*"
    )

    Write-ManagedFile ".npmrc" @(
        "engine-strict=true",
        "save-exact=true",
        "prefer-workspace-packages=true",
        "link-workspace-packages=true"
    )

    Write-ManagedFile ".gitattributes" @(
        "* text=auto eol=lf",
        "*.ps1 text eol=crlf",
        "*.cmd text eol=crlf",
        "*.bat text eol=crlf"
    )

    Write-Step 3 8 "Creating environment configuration"

    Write-ManagedFile ".env.example" @(
        "NODE_ENV=development",
        "APP_PORT=3000",
        "",
        "POSTGRES_HOST=localhost",
        "POSTGRES_PORT=5432",
        "POSTGRES_DB=solid_tracker",
        "POSTGRES_USER=solid_tracker",
        "POSTGRES_PASSWORD=replace-with-a-local-password",
        "DATABASE_URL=postgresql://solid_tracker:replace-with-a-local-password@localhost:5432/solid_tracker?schema=public",
        "",
        "REDIS_HOST=localhost",
        "REDIS_PORT=6379",
        "REDIS_PASSWORD=replace-with-a-local-password",
        "REDIS_URL=redis://:replace-with-a-local-password@localhost:6379/0",
        "",
        "TRACCAR_BASE_URL=http://localhost:8082",
        "TRACCAR_USERNAME=",
        "TRACCAR_PASSWORD="
    )

    $envPath = Join-Path $script:RootPath ".env"

    if (-not (Test-Path -LiteralPath $envPath)) {
        $postgresPassword = New-RandomSecret
        $redisPassword = New-RandomSecret

        $envLines = @(
            "NODE_ENV=development",
            "APP_PORT=3000",
            "",
            "POSTGRES_HOST=localhost",
            "POSTGRES_PORT=5432",
            "POSTGRES_DB=solid_tracker",
            "POSTGRES_USER=solid_tracker",
            "POSTGRES_PASSWORD=$postgresPassword",
            "DATABASE_URL=postgresql://solid_tracker:$postgresPassword@localhost:5432/solid_tracker?schema=public",
            "",
            "REDIS_HOST=localhost",
            "REDIS_PORT=6379",
            "REDIS_PASSWORD=$redisPassword",
            "REDIS_URL=redis://:$redisPassword@localhost:6379/0",
            "",
            "TRACCAR_BASE_URL=http://localhost:8082",
            "TRACCAR_USERNAME=",
            "TRACCAR_PASSWORD="
        )

        [System.IO.File]::WriteAllText(
            $envPath,
            (Convert-ToText -Lines $envLines),
            $script:Utf8NoBom
        )

        Write-Host "[CREATED]   .env with generated local secrets" -ForegroundColor Green
    }
    else {
        Write-Host "[PRESERVED] .env" -ForegroundColor DarkYellow
    }

    Write-Step 4 8 "Creating Docker Compose configuration"

    Write-ManagedFile "compose.yaml" @(
        "name: solid-tracker",
        "",
        "services:",
        "  postgres:",
        "    image: postgres:17-alpine",
        "    container_name: solid-tracker-postgres",
        "    restart: unless-stopped",
        "    environment:",
        "      POSTGRES_DB: `${POSTGRES_DB}",
        "      POSTGRES_USER: `${POSTGRES_USER}",
        "      POSTGRES_PASSWORD: `${POSTGRES_PASSWORD}",
        "    ports:",
        '      - "${POSTGRES_PORT}:5432"',
        "    volumes:",
        "      - solid_tracker_postgres_data:/var/lib/postgresql/data",
        "    healthcheck:",
        '      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]',
        "      interval: 5s",
        "      timeout: 5s",
        "      retries: 12",
        "      start_period: 10s",
        "    networks:",
        "      - solid_tracker_network",
        "",
        "  redis:",
        "    image: redis:8-alpine",
        "    container_name: solid-tracker-redis",
        "    restart: unless-stopped",
        "    environment:",
        "      REDIS_PASSWORD: `${REDIS_PASSWORD}",
        "    command:",
        "      - redis-server",
        "      - --appendonly",
        '      - "yes"',
        "      - --requirepass",
        '      - ${REDIS_PASSWORD}',
        "    ports:",
        '      - "${REDIS_PORT}:6379"',
        "    volumes:",
        "      - solid_tracker_redis_data:/data",
        "    healthcheck:",
        '      test: ["CMD-SHELL", "redis-cli -a \"$${REDIS_PASSWORD}\" ping | grep -q PONG"]',
        "      interval: 5s",
        "      timeout: 5s",
        "      retries: 12",
        "      start_period: 5s",
        "    networks:",
        "      - solid_tracker_network",
        "",
        "volumes:",
        "  solid_tracker_postgres_data:",
        "  solid_tracker_redis_data:",
        "",
        "networks:",
        "  solid_tracker_network:",
        "    driver: bridge"
    )

    Write-ManagedFile "infrastructure\docker\README.md" @(
        "# Local Docker Infrastructure",
        "",
        "The local Solid Tracker development stack contains:",
        "",
        "- PostgreSQL for application data",
        "- Redis for caching, sessions, queues and distributed coordination",
        "",
        "## Commands",
        "",
        "Start services:",
        "",
        "    pnpm infra:up",
        "",
        "Show service status:",
        "",
        "    pnpm infra:status",
        "",
        "Follow logs:",
        "",
        "    pnpm infra:logs",
        "",
        "Stop services without deleting data:",
        "",
        "    pnpm infra:stop",
        "",
        "Delete containers and local data volumes:",
        "",
        "    pnpm infra:reset",
        "",
        "The .env file contains local secrets and must not be committed."
    )

    Write-Step 5 8 "Installing the root workspace"

    & pnpm.cmd install

    if ($LASTEXITCODE -ne 0) {
        throw "pnpm workspace installation failed."
    }

    Write-Step 6 8 "Starting PostgreSQL and Redis"

    docker compose --env-file .env config --quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose configuration validation failed."
    }

    docker compose --env-file .env up -d

    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose could not start the local services."
    }

    Write-Host "Waiting for container health checks..." -ForegroundColor Cyan

    $deadline = (Get-Date).AddMinutes(3)
    $postgresHealth = ""
    $redisHealth = ""

    do {
        Start-Sleep -Seconds 3

        $postgresHealth = Get-ContainerHealth "solid-tracker-postgres"
        $redisHealth = Get-ContainerHealth "solid-tracker-redis"

        Write-Host (
            "PostgreSQL: {0} | Redis: {1}" -f
            $postgresHealth,
            $redisHealth
        )

        if (
            $postgresHealth -eq "unhealthy" -or
            $redisHealth -eq "unhealthy"
        ) {
            docker compose --env-file .env logs --tail 100
            throw "One or more infrastructure containers became unhealthy."
        }
    }
    while (
        (Get-Date) -lt $deadline -and
        (
            $postgresHealth -ne "healthy" -or
            $redisHealth -ne "healthy"
        )
    )

    if (
        $postgresHealth -ne "healthy" -or
        $redisHealth -ne "healthy"
    ) {
        docker compose --env-file .env logs --tail 100
        throw "Infrastructure health checks timed out."
    }

    Write-Step 7 8 "Testing database and cache connectivity"

    docker compose --env-file .env exec -T postgres `
        sh `
        -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT current_database(), current_user;"'

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL connectivity test failed."
    }

    docker compose --env-file .env exec -T redis `
        sh `
        -lc 'redis-cli -a "$REDIS_PASSWORD" ping'

    if ($LASTEXITCODE -ne 0) {
        throw "Redis connectivity test failed."
    }

    Write-Step 8 8 "Committing infrastructure foundation"

    $filesToStage = @(
        ".gitattributes",
        ".npmrc",
        ".env.example",
        "compose.yaml",
        "package.json",
        "pnpm-workspace.yaml",
        "pnpm-lock.yaml",
        "infrastructure/docker/README.md",
        "scripts/solid-tracker-local-infrastructure.ps1"
    )

    foreach ($file in $filesToStage) {
        if (Test-Path -LiteralPath $file) {
            git add -- $file
        }
    }

    $stagedChanges = @(git diff --cached --name-only)

    if ($stagedChanges.Count -gt 0) {
        git commit -m "chore(infra): add local PostgreSQL and Redis services"

        if ($LASTEXITCODE -ne 0) {
            throw "Git commit failed."
        }
    }
    else {
        Write-Host "No new infrastructure changes require a commit." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Local Infrastructure Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

    Write-Host ""
    docker compose --env-file .env ps

    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current

    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate

    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short

    Write-Host ""
    Write-Host "PostgreSQL and Redis are healthy and ready." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "SETUP FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    $composePath = Join-Path $RepositoryPath "compose.yaml"
    $envPath = Join-Path $RepositoryPath ".env"

    if (
        (Test-Path -LiteralPath $composePath) -and
        (Test-Path -LiteralPath $envPath)
    ) {
        Write-Host ""
        Write-Host "Current Docker status:" -ForegroundColor Yellow
        docker compose --env-file .env ps 2>$null
    }

    exit 1
}
