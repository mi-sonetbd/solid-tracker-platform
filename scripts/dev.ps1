[CmdletBinding()]
param(
    [switch]$OpenBrowser,
    [string]$Route = "/management/accounts",
    [switch]$Restart,
    [switch]$SkipInfrastructure,
    [int]$BackendPort = 3000,
    [int]$WebPort = 3001
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "dev-common.ps1")

$RepoRoot = Get-SolidTrackerRepoRoot
$Runtime = Get-SolidTrackerRuntimePaths -RepoRoot $RepoRoot
$BackendPackageName = "@solid-tracker/backend-api"
$WebPackageName = "@solid-tracker/web-panel"
$BackendPackagePath = Join-Path $RepoRoot "services\backend-api\package.json"
$WebPackagePath = Join-Path $RepoRoot "apps\web-panel\package.json"
$BackendUrl = "http://localhost:$BackendPort/api/v1/auth/me"
$WebBaseUrl = "http://localhost:$WebPort"
$WebHealthUrl = "$WebBaseUrl/login"

Set-Location $RepoRoot

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Solid Tracker - Live Development" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

if ($Restart) {
    & (Join-Path $PSScriptRoot "dev-stop.ps1")

    if ($LASTEXITCODE -ne 0) {
        throw "The existing development session could not be stopped."
    }
}

if (-not $SkipInfrastructure) {
    Write-Host "Starting PostgreSQL and Redis..." -ForegroundColor Yellow
    & docker compose --env-file .env up -d postgres redis

    if ($LASTEXITCODE -ne 0) {
        throw "Docker infrastructure failed to start."
    }

    Write-Host "[OK] PostgreSQL and Redis are running." -ForegroundColor Green
}

$backendScript = Resolve-SolidTrackerPackageScript `
    -PackageJsonPath $BackendPackagePath `
    -Candidates @("start:dev", "dev", "start")

$webScript = Resolve-SolidTrackerPackageScript `
    -PackageJsonPath $WebPackagePath `
    -Candidates @("dev", "start")

$backendProcessId = $null
$webProcessId = $null

if (Test-SolidTrackerEndpoint -Url $BackendUrl) {
    Write-Host "[OK] Backend API is already running." -ForegroundColor Green
}
else {
    $backendProcess = Start-SolidTrackerWorkspaceProcess `
        -RepoRoot $RepoRoot `
        -WindowTitle "Solid Tracker Backend API - Live" `
        -PackageName $BackendPackageName `
        -ScriptName $backendScript `
        -LogPath $Runtime.BackendLog

    $backendProcessId = $backendProcess.Id

    Wait-SolidTrackerEndpoint `
        -Url $BackendUrl `
        -Name "Backend API"
}

if (Test-SolidTrackerEndpoint -Url $WebHealthUrl) {
    Write-Host "[OK] Web panel is already running." -ForegroundColor Green
}
else {
    $webProcess = Start-SolidTrackerWorkspaceProcess `
        -RepoRoot $RepoRoot `
        -WindowTitle "Solid Tracker Web Panel - Live" `
        -PackageName $WebPackageName `
        -ScriptName $webScript `
        -LogPath $Runtime.WebLog

    $webProcessId = $webProcess.Id

    Wait-SolidTrackerEndpoint `
        -Url $WebHealthUrl `
        -Name "Web panel"
}

$branch = (& git branch --show-current).Trim()

$state = [PSCustomObject]@{
    startedAt = (Get-Date).ToString("o")
    branch = $branch
    backend = [PSCustomObject]@{
        processId = $backendProcessId
        url = $BackendUrl
        log = $Runtime.BackendLog
    }
    web = [PSCustomObject]@{
        processId = $webProcessId
        url = $WebBaseUrl
        log = $Runtime.WebLog
    }
}

Write-SolidTrackerDevState `
    -StatePath $Runtime.State `
    -State $state

$routePath = $Route

if ([string]::IsNullOrWhiteSpace($routePath)) {
    $routePath = "/"
}
elseif (-not $routePath.StartsWith("/")) {
    $routePath = "/$routePath"
}

$reviewUrl = "$WebBaseUrl$routePath"

if ($OpenBrowser) {
    Start-Process $reviewUrl
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host " Live Development Ready" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Web panel     : $WebBaseUrl" -ForegroundColor Yellow
Write-Host "Backend API   : http://localhost:$BackendPort" -ForegroundColor Yellow
Write-Host "Review route  : $reviewUrl" -ForegroundColor Yellow
Write-Host "Backend log   : $($Runtime.BackendLog)" -ForegroundColor DarkGray
Write-Host "Web log       : $($Runtime.WebLog)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Hot reload is active for backend and web changes." -ForegroundColor Green
Write-Host "Check status  : .\scripts\dev-status.ps1" -ForegroundColor Cyan
Write-Host "Restart all   : .\scripts\dev.ps1 -Restart -OpenBrowser" -ForegroundColor Cyan
Write-Host "Stop services : .\scripts\dev-stop.ps1" -ForegroundColor Cyan