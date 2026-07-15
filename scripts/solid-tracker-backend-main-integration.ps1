[CmdletBinding()]
param(
    [string]$RepoPath = "D:\GitHub\gps-tracker-platform",
    [string]$FeatureBranch = "feat/mobile-api",
    [string]$ExpectedFeatureCommit = "af8e58a",
    [string]$NextBranch = "feat/web-panel-foundation"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    Write-Host "> $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code: $LASTEXITCODE)"
    }
}

Write-Section "Solid Tracker - Backend Integration and Web Panel Handoff"

if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    throw "Repository directory was not found: $RepoPath"
}

Set-Location -LiteralPath $RepoPath

if (-not (Test-Path -LiteralPath ".git" -PathType Container)) {
    throw "The selected directory is not a Git repository: $RepoPath"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "SolidTrackerLogs"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logFile = Join-Path $logDirectory "backend-main-integration-$timestamp.log"

$resolvedRepoPath = (Resolve-Path -LiteralPath $RepoPath).Path.TrimEnd("\")
$resolvedScriptPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
$scriptRelativePath = $null

if ($resolvedScriptPath.StartsWith($resolvedRepoPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    $scriptRelativePath = $resolvedScriptPath.Substring($resolvedRepoPath.Length).TrimStart("\").Replace("\", "/")
}

function Get-BlockingGitChanges {
    $statusLines = @(git status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the Git working-tree status."
    }

    $blockingChanges = @()

    foreach ($line in $statusLines) {
        $pathPart = if ($line.Length -gt 3) { $line.Substring(3).Trim().Trim('"') } else { "" }

        if ($scriptRelativePath -and $pathPart -eq $scriptRelativePath) {
            continue
        }

        $blockingChanges += $line
    }

    return $blockingChanges
}

Start-Transcript -Path $logFile -Force | Out-Null

try {
    Write-Section "1. Repository Safety Checks"

    $currentStatus = @(Get-BlockingGitChanges)

    if ($currentStatus.Count -gt 0) {
        Write-Host "Uncommitted repository changes were found:" -ForegroundColor Yellow
        $currentStatus | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        throw "Commit, stash, or remove these changes before running the integration script."
    }

    Invoke-NativeCommand -FilePath "git" -Arguments @(
        "show-ref", "--verify", "--quiet", "refs/heads/$FeatureBranch"
    ) -FailureMessage "Required feature branch '$FeatureBranch' does not exist"

    Invoke-NativeCommand -FilePath "git" -Arguments @(
        "show-ref", "--verify", "--quiet", "refs/heads/main"
    ) -FailureMessage "The main branch does not exist"

    $featureCommit = (git rev-parse --short $FeatureBranch).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Could not resolve the latest commit for '$FeatureBranch'."
    }

    if ($ExpectedFeatureCommit -and $featureCommit -ne $ExpectedFeatureCommit) {
        throw "Expected '$FeatureBranch' at commit '$ExpectedFeatureCommit', but found '$featureCommit'. Review the branch before integration."
    }

    Write-Host "[OK] Working tree is clean." -ForegroundColor Green
    Write-Host "[OK] Feature branch: $FeatureBranch ($featureCommit)" -ForegroundColor Green

    Write-Section "2. Merge Mobile API Into Main"

    Invoke-NativeCommand -FilePath "git" -Arguments @("switch", "main") `
        -FailureMessage "Could not switch to main"

    & git merge-base --is-ancestor $FeatureBranch main
    $alreadyMerged = ($LASTEXITCODE -eq 0)

    if ($alreadyMerged) {
        Write-Host "[OK] '$FeatureBranch' is already contained in main. Merge skipped." -ForegroundColor Green
    }
    else {
        Invoke-NativeCommand -FilePath "git" -Arguments @(
            "merge",
            "--no-ff",
            $FeatureBranch,
            "-m",
            "merge: integrate customer mobile API platform"
        ) -FailureMessage "The mobile API merge failed"

        Write-Host "[OK] Mobile API merged into main." -ForegroundColor Green
    }

    Write-Section "3. Start Backend Infrastructure"

    if (-not (Test-Path -LiteralPath ".env" -PathType Leaf)) {
        throw "The repository root .env file was not found."
    }

    Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "compose", "--env-file", ".env", "up", "-d", "postgres", "redis"
    ) -FailureMessage "Could not start PostgreSQL and Redis"

    Write-Section "4. Verify Prisma and Backend Quality Gates"

    Invoke-NativeCommand -FilePath "pnpm.cmd" -Arguments @(
        "--filter", "@solid-tracker/backend-api",
        "exec", "prisma", "validate",
        "--config", "prisma.config.ts"
    ) -FailureMessage "Prisma validation failed"

    Invoke-NativeCommand -FilePath "pnpm.cmd" -Arguments @(
        "--filter", "@solid-tracker/backend-api",
        "exec", "prisma", "generate",
        "--config", "prisma.config.ts"
    ) -FailureMessage "Prisma client generation failed"

    Invoke-NativeCommand -FilePath "pnpm.cmd" -Arguments @(
        "--filter", "@solid-tracker/backend-api",
        "exec", "prisma", "migrate", "status",
        "--config", "prisma.config.ts"
    ) -FailureMessage "Prisma migration status verification failed"

    Invoke-NativeCommand -FilePath "pnpm.cmd" -Arguments @(
        "--filter", "@solid-tracker/backend-api", "lint"
    ) -FailureMessage "Backend lint failed"

    Invoke-NativeCommand -FilePath "pnpm.cmd" -Arguments @(
        "--filter", "@solid-tracker/backend-api", "typecheck"
    ) -FailureMessage "Backend typecheck failed"

    Invoke-NativeCommand -FilePath "pnpm.cmd" -Arguments @(
        "--filter", "@solid-tracker/backend-api", "test", "--runInBand"
    ) -FailureMessage "Backend unit tests failed"

    Invoke-NativeCommand -FilePath "pnpm.cmd" -Arguments @(
        "--filter", "@solid-tracker/backend-api", "test:e2e", "--runInBand"
    ) -FailureMessage "Backend end-to-end tests failed"

    Invoke-NativeCommand -FilePath "pnpm.cmd" -Arguments @(
        "--filter", "@solid-tracker/backend-api", "build"
    ) -FailureMessage "Backend production build failed"

    Invoke-NativeCommand -FilePath "git" -Arguments @("diff", "--check") `
        -FailureMessage "Git whitespace verification failed"

    $postVerificationStatus = @(Get-BlockingGitChanges)

    if ($postVerificationStatus.Count -gt 0) {
        Write-Host "Verification produced repository changes:" -ForegroundColor Yellow
        $postVerificationStatus | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        throw "Review the generated changes before starting the frontend stage."
    }

    Write-Section "5. Prepare Frontend Web Panel Branch"

    & git show-ref --verify --quiet "refs/heads/$NextBranch"
    $nextBranchExists = ($LASTEXITCODE -eq 0)

    if ($nextBranchExists) {
        Invoke-NativeCommand -FilePath "git" -Arguments @("switch", $NextBranch) `
            -FailureMessage "Could not switch to existing frontend branch '$NextBranch'"
    }
    else {
        Invoke-NativeCommand -FilePath "git" -Arguments @("switch", "-c", $NextBranch) `
            -FailureMessage "Could not create frontend branch '$NextBranch'"
    }

    Write-Section "Integration Completed Successfully"

    Write-Host "Backend status : VERIFIED" -ForegroundColor Green
    Write-Host "Current branch : $((git branch --show-current).Trim())" -ForegroundColor Green
    Write-Host "Next stage     : Frontend Web Panel Foundation" -ForegroundColor Green
    Write-Host "Log file       : $logFile" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Latest commits:" -ForegroundColor Yellow
    git log --oneline --decorate --graph -10

    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
}
catch {
    Write-Host ""
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Log file: $logFile" -ForegroundColor Yellow
    exit 1
}
finally {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Transcript may already be stopped or may not have started fully.
    }
}
