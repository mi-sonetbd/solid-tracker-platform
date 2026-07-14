[CmdletBinding()]
param(
    [string]$RepositoryPath = "D:\GitHub\gps-tracker-platform",
    [int]$MaximumAttempts = 5
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

function Invoke-PnpmWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        Write-Host ""
        Write-Host ("pnpm attempt {0}/{1}" -f $attempt, $MaximumAttempts) -ForegroundColor Cyan
        Write-Host ("pnpm {0}" -f ($Arguments -join " ")) -ForegroundColor DarkCyan

        & pnpm.cmd @Arguments

        if ($LASTEXITCODE -eq 0) {
            Write-Host "pnpm command completed successfully." -ForegroundColor Green
            return
        }

        if ($attempt -eq $MaximumAttempts) {
            throw "pnpm failed after $MaximumAttempts attempts."
        }

        $waitSeconds = [Math]::Min(20 * $attempt, 90)

        Write-Host (
            "Command failed. Waiting {0} seconds before retrying..." -f
            $waitSeconds
        ) -ForegroundColor Yellow

        Start-Sleep -Seconds $waitSeconds
    }
}

function Pin-TypeScriptInInstaller {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path $script:RootPath $RelativePath

    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Installer script not found: $RelativePath"
    }

    $content = [System.IO.File]::ReadAllText($fullPath)
    $updated = $content

    $updated = $updated.Replace(
        '        "typescript",',
        '        "typescript@5.9.3",'
    )

    $updated = $updated.Replace(
        '        "typescript@7.0.2",',
        '        "typescript@5.9.3",'
    )

    if ($updated -eq $content) {
        if ($content.Contains('"typescript@5.9.3",')) {
            Write-Host "[PRESERVED] $RelativePath already pins TypeScript 5.9.3" -ForegroundColor DarkYellow
            return
        }

        throw "Could not locate the TypeScript dependency entry in $RelativePath"
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $updated,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED]   $RelativePath" -ForegroundColor Green
}

function Remove-ObsoleteRecoveryScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if (-not (Test-Path -LiteralPath $RelativePath)) {
        return
    }

    & git.exe reset HEAD -- $RelativePath *> $null
    Remove-Item -LiteralPath $RelativePath -Force

    Write-Host "[REMOVED]   $RelativePath" -ForegroundColor Green
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - TypeScript Compatibility Recovery" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath
    $script:RootPath = (Get-Location).Path
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found."
    }

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -ne "feat/backend-foundation") {
        throw "Expected branch feat/backend-foundation, but current branch is $currentBranch"
    }

    foreach ($requiredFile in @(
        "services\backend-api\package.json",
        "services\backend-api\eslint.config.mjs",
        "scripts\solid-tracker-backend-foundation.ps1",
        "scripts\solid-tracker-resume-backend-foundation.ps1"
    )) {
        if (-not (Test-Path -LiteralPath $requiredFile)) {
            throw "Required file is missing: $requiredFile"
        }
    }

    Write-Step 1 7 "Identifying the compatibility failure"

    $installedTypeScript = (
        & pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec tsc --version
    )

    if ($LASTEXITCODE -ne 0) {
        throw "Could not determine the installed TypeScript version."
    }

    Write-Host "Installed TypeScript: $($installedTypeScript.Trim())" -ForegroundColor Red
    Write-Host "Supported target:      TypeScript 5.9.3" -ForegroundColor Green
    Write-Host "typescript-eslint 8.63 supports TypeScript below 6.1." -ForegroundColor Green

    Write-Step 2 7 "Applying resilient pnpm network settings"

    $env:npm_config_fetch_retries = "6"
    $env:npm_config_fetch_retry_factor = "2"
    $env:npm_config_fetch_retry_mintimeout = "10000"
    $env:npm_config_fetch_retry_maxtimeout = "120000"
    $env:npm_config_fetch_timeout = "300000"
    $env:npm_config_network_concurrency = "4"

    Write-Host "Registry retries and extended timeouts enabled." -ForegroundColor Green

    Write-Step 3 7 "Pinning the supported TypeScript version in reusable scripts"

    Pin-TypeScriptInInstaller `
        "scripts\solid-tracker-backend-foundation.ps1"

    Pin-TypeScriptInInstaller `
        "scripts\solid-tracker-resume-backend-foundation.ps1"

    Write-Step 4 7 "Removing obsolete failed recovery scripts"

    Remove-ObsoleteRecoveryScript `
        "scripts\solid-tracker-eslint-version-recovery.ps1"

    Remove-ObsoleteRecoveryScript `
        "scripts\solid-tracker-eslint-recovery.ps1"

    Remove-ObsoleteRecoveryScript `
        "scripts\solid-tracker-pnpm-network-recovery.ps1"

    Write-Step 5 7 "Installing TypeScript 5.9.3 exactly"

    Invoke-PnpmWithRetry @(
        "--filter",
        "@solid-tracker/backend-api",
        "add",
        "--save-dev",
        "typescript@5.9.3"
    )

    Invoke-PnpmWithRetry @("install")

    $verifiedTypeScript = (
        & pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec tsc --version
    )

    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify the corrected TypeScript version."
    }

    if ($verifiedTypeScript.Trim() -ne "Version 5.9.3") {
        throw "Expected TypeScript 5.9.3, but found $($verifiedTypeScript.Trim())"
    }

    Write-Host "Verified TypeScript: Version 5.9.3" -ForegroundColor Green

    Write-Step 6 7 "Staging this compatibility decision"

    $currentScriptPath = $MyInvocation.MyCommand.Path

    if (-not [string]::IsNullOrWhiteSpace($currentScriptPath)) {
        $relativeCurrentScript = $currentScriptPath.Substring(
            $script:RootPath.Length + 1
        )

        git add -- $relativeCurrentScript
    }

    Write-Step 7 7 "Resuming validation, tests, smoke test and commit"

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File ".\scripts\solid-tracker-resume-backend-foundation.ps1"

    if ($LASTEXITCODE -ne 0) {
        throw "The backend resume script reported another validation error."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " TypeScript Compatibility Recovery Completed" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The supported TypeScript toolchain is installed and backend setup completed." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "TYPESCRIPT COMPATIBILITY RECOVERY FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "No rollback is required. The repository remains resumable." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    exit 1
}
