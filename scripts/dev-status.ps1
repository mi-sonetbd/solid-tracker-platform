[CmdletBinding()]
param(
    [int]$BackendPort = 3000,
    [int]$WebPort = 3001
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "dev-common.ps1")

$RepoRoot = Get-SolidTrackerRepoRoot
$Runtime = Get-SolidTrackerRuntimePaths -RepoRoot $RepoRoot
$State = Read-SolidTrackerDevState -StatePath $Runtime.State
$BackendUrl = "http://localhost:$BackendPort/api/v1/auth/me"
$WebUrl = "http://localhost:$WebPort/login"

Set-Location $RepoRoot

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Solid Tracker - Development Status" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$branch = (& git branch --show-current).Trim()
$statusText = ((& git status --porcelain) -join [Environment]::NewLine)

Write-Host "Branch       : $branch" -ForegroundColor Yellow
Write-Host "Repository   : $(if ([string]::IsNullOrWhiteSpace($statusText)) { 'clean' } else { 'modified' })" -ForegroundColor Yellow
Write-Host ""

$backendReady = Test-SolidTrackerEndpoint -Url $BackendUrl
$webReady = Test-SolidTrackerEndpoint -Url $WebUrl

Write-Host "Backend API  : $(if ($backendReady) { 'READY' } else { 'STOPPED/UNREACHABLE' })" `
    -ForegroundColor $(if ($backendReady) { "Green" } else { "Red" })

Write-Host "Web panel    : $(if ($webReady) { 'READY' } else { 'STOPPED/UNREACHABLE' })" `
    -ForegroundColor $(if ($webReady) { "Green" } else { "Red" })

if ($null -ne $State) {
    Write-Host ""
    Write-Host "Tracked session:" -ForegroundColor Cyan
    Write-Host "Started      : $($State.startedAt)" -ForegroundColor DarkGray
    Write-Host "Branch       : $($State.branch)" -ForegroundColor DarkGray
    Write-Host "Backend PID  : $($State.backend.processId)" -ForegroundColor DarkGray
    Write-Host "Web PID      : $($State.web.processId)" -ForegroundColor DarkGray
    Write-Host "Backend log  : $($State.backend.log)" -ForegroundColor DarkGray
    Write-Host "Web log      : $($State.web.log)" -ForegroundColor DarkGray
}
else {
    Write-Host ""
    Write-Host "No tracked development state file exists." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Docker services:" -ForegroundColor Cyan
& docker compose --env-file .env ps postgres redis