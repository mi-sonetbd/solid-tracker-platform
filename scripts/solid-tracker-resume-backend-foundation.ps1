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

function Invoke-Pnpm {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host ("pnpm {0}" -f ($Arguments -join " ")) -ForegroundColor DarkCyan
    & pnpm.cmd @Arguments

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Pending blocked build scripts:" -ForegroundColor Yellow
        & pnpm.cmd ignored-builds 2>$null

        throw "pnpm command failed: pnpm $($Arguments -join ' ')"
    }
}

function Get-EnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $pattern = "^{0}=(.*)$" -f [regex]::Escape($Name)
    $line = Get-Content -LiteralPath $FilePath |
        Where-Object { $_ -match $pattern } |
        Select-Object -First 1

    if ($null -eq $line) {
        return $null
    }

    return ([regex]::Match($line, $pattern)).Groups[1].Value
}

function Test-ContainerHealth {
    param([string]$ContainerName)

    $health = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        $ContainerName 2>$null

    if ($LASTEXITCODE -ne 0) {
        return "missing"
    }

    return $health.Trim()
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Resume Backend Foundation" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath
    $rootPath = (Get-Location).Path
    $backendPath = Join-Path $rootPath "services\backend-api"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found in $rootPath"
    }

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -ne "feat/backend-foundation") {
        throw "Expected branch feat/backend-foundation, but current branch is $currentBranch"
    }

    Write-Step 1 8 "Validating the interrupted setup"

    foreach ($requiredFile in @(
        "package.json",
        "pnpm-workspace.yaml",
        ".env",
        ".env.example",
        "compose.yaml",
        "services\backend-api\package.json",
        "services\backend-api\src\main.ts",
        "scripts\solid-tracker-backend-foundation.ps1"
    )) {
        if (-not (Test-Path -LiteralPath $requiredFile)) {
            throw "Required interrupted-setup file is missing: $requiredFile"
        }
    }

    $postgresHealth = Test-ContainerHealth "solid-tracker-postgres"
    $redisHealth = Test-ContainerHealth "solid-tracker-redis"

    if ($postgresHealth -ne "healthy" -or $redisHealth -ne "healthy") {
        throw "PostgreSQL and Redis must both be healthy. PostgreSQL=$postgresHealth Redis=$redisHealth"
    }

    Write-Host "PostgreSQL: $postgresHealth" -ForegroundColor Green
    Write-Host "Redis:      $redisHealth" -ForegroundColor Green

    Write-Step 2 8 "Recording the dependency build-security decision"

    # @scarf/scarf runs installation analytics. It is not required to compile
    # or run the Solid Tracker API, so its postinstall script is explicitly denied.
    & pnpm.cmd approve-builds '!@scarf/scarf'

    if ($LASTEXITCODE -ne 0) {
        throw "Could not record the @scarf/scarf build-script decision."
    }

    # Also record the analytics opt-out in the root package manifest.
    $rootPackagePath = Join-Path $rootPath "package.json"
    $rootPackage = Get-Content -LiteralPath $rootPackagePath -Raw | ConvertFrom-Json

    if ($null -eq $rootPackage.scarfSettings) {
        $rootPackage |
            Add-Member `
                -MemberType NoteProperty `
                -Name "scarfSettings" `
                -Value ([pscustomobject]@{ enabled = $false })
    }
    else {
        $rootPackage.scarfSettings.enabled = $false
    }

    [System.IO.File]::WriteAllText(
        $rootPackagePath,
        (($rootPackage | ConvertTo-Json -Depth 30) + "`n"),
        $utf8NoBom
    )

    Write-Host "@scarf/scarf postinstall: denied" -ForegroundColor Green
    Write-Host "Scarf analytics: disabled" -ForegroundColor Green

    Write-Step 3 8 "Completing production dependency installation"

    Invoke-Pnpm @(
        "--filter",
        "@solid-tracker/backend-api",
        "add",
        "@nestjs/common",
        "@nestjs/config",
        "@nestjs/core",
        "@nestjs/platform-express",
        "@nestjs/swagger",
        "@nestjs/terminus",
        "class-transformer",
        "class-validator",
        "helmet",
        "ioredis",
        "joi",
        "pg",
        "reflect-metadata",
        "rxjs"
    )

    Write-Step 4 8 "Installing development and test dependencies"

    Invoke-Pnpm @(
        "--filter",
        "@solid-tracker/backend-api",
        "add",
        "--save-dev",
        "@nestjs/cli",
        "@nestjs/schematics",
        "@nestjs/testing",
        "@eslint/js",
        "@types/express",
        "@types/jest",
        "@types/node",
        "@types/pg",
        "@types/supertest",
        "eslint",
        "eslint-config-prettier",
        "eslint-plugin-prettier",
        "globals",
        "jest",
        "prettier",
        "source-map-support",
        "supertest",
        "ts-jest",
        "ts-loader",
        "ts-node",
        "tsconfig-paths",
        "typescript@5.9.3",
        "typescript-eslint"
    )

    Invoke-Pnpm @("install")

    Write-Step 5 8 "Running code-quality checks"

    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "format")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "lint")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "typecheck")

    Write-Step 6 8 "Running automated tests and production build"

    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "test", "--runInBand")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "test:e2e", "--runInBand")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "build")

    Write-Step 7 8 "Running live API smoke test"

    $envPath = Join-Path $rootPath ".env"
    $appPort = Get-EnvValue -FilePath $envPath -Name "APP_PORT"

    if ([string]::IsNullOrWhiteSpace($appPort)) {
        $appPort = "3000"
    }

    $candidateMainFiles = @(
        (Join-Path $backendPath "dist\main.js"),
        (Join-Path $backendPath "dist\src\main.js")
    )

    $compiledMain = $candidateMainFiles |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($compiledMain)) {
        throw "Compiled NestJS entry point was not found."
    }

    $logDirectory = Join-Path $rootPath "temp\backend-smoke-test"
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

    $stdoutPath = Join-Path $logDirectory "stdout.log"
    $stderrPath = Join-Path $logDirectory "stderr.log"

    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue

    $apiProcess = Start-Process `
        -FilePath "node.exe" `
        -ArgumentList "`"$compiledMain`"" `
        -WorkingDirectory $backendPath `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru

    try {
        $deadline = (Get-Date).AddSeconds(60)
        $ready = $false

        do {
            Start-Sleep -Seconds 2

            if ($apiProcess.HasExited) {
                $stdout = if (Test-Path $stdoutPath) {
                    Get-Content -LiteralPath $stdoutPath -Raw
                }
                else {
                    ""
                }

                $stderr = if (Test-Path $stderrPath) {
                    Get-Content -LiteralPath $stderrPath -Raw
                }
                else {
                    ""
                }

                throw "API process exited during smoke test.`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
            }

            try {
                $readiness = Invoke-RestMethod `
                    -Uri ("http://127.0.0.1:{0}/api/v1/health/ready" -f $appPort) `
                    -Method Get `
                    -TimeoutSec 5

                if ($readiness.status -eq "ok") {
                    $ready = $true
                }
            }
            catch {
                # Keep waiting while NestJS initializes.
            }
        }
        while (-not $ready -and (Get-Date) -lt $deadline)

        if (-not $ready) {
            $stdout = if (Test-Path $stdoutPath) {
                Get-Content -LiteralPath $stdoutPath -Raw
            }
            else {
                ""
            }

            $stderr = if (Test-Path $stderrPath) {
                Get-Content -LiteralPath $stderrPath -Raw
            }
            else {
                ""
            }

            throw "API readiness timed out.`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
        }

        $serviceInfo = Invoke-RestMethod `
            -Uri ("http://127.0.0.1:{0}/api/v1" -f $appPort) `
            -Method Get `
            -TimeoutSec 5

        if ($serviceInfo.name -ne "Solid Tracker Backend API") {
            throw "The API root endpoint returned an unexpected response."
        }

        Write-Host "API root:   healthy" -ForegroundColor Green
        Write-Host "PostgreSQL: healthy" -ForegroundColor Green
        Write-Host "Redis:      healthy" -ForegroundColor Green
    }
    finally {
        if ($null -ne $apiProcess -and -not $apiProcess.HasExited) {
            Stop-Process -Id $apiProcess.Id -Force
            $apiProcess.WaitForExit()
        }
    }

    Write-Step 8 8 "Committing the completed backend foundation"

    git add -- `
        ".env.example" `
        "package.json" `
        "pnpm-lock.yaml" `
        "pnpm-workspace.yaml" `
        "services/backend-api" `
        "scripts/solid-tracker-backend-foundation.ps1" `
        "scripts/solid-tracker-resume-backend-foundation.ps1"

    $stagedFiles = @(git diff --cached --name-only)

    if ($stagedFiles.Count -eq 0) {
        Write-Host "No new backend changes require a commit." -ForegroundColor Green
    }
    else {
        git commit -m "feat(api): establish NestJS backend foundation"

        if ($LASTEXITCODE -ne 0) {
            throw "Git commit failed."
        }
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " NestJS Backend Foundation Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

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
    Write-Host "Start development server:" -ForegroundColor Yellow
    Write-Host "pnpm api:start:dev"

    Write-Host ""
    Write-Host "Endpoints:" -ForegroundColor Yellow
    Write-Host "http://localhost:$appPort/api/v1"
    Write-Host "http://localhost:$appPort/api/v1/health/live"
    Write-Host "http://localhost:$appPort/api/v1/health/ready"
    Write-Host "http://localhost:$appPort/docs"

    Write-Host ""
    Write-Host "Solid Tracker NestJS backend foundation is ready." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "RESUME FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null

    exit 1
}
