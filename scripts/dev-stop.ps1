[CmdletBinding()]
param(
    [switch]$StopInfrastructure
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "dev-common.ps1")

$RepoRoot = Get-SolidTrackerRepoRoot
$Runtime = Get-SolidTrackerRuntimePaths -RepoRoot $RepoRoot
$State = Read-SolidTrackerDevState -StatePath $Runtime.State

Set-Location $RepoRoot

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Solid Tracker - Stop Live Development" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

if ($null -eq $State) {
    Write-Host "No tracked live-development session was found." -ForegroundColor Yellow
}
else {
    $processEntries = @(
        [PSCustomObject]@{
            Name = "Backend API"
            ProcessId = $State.backend.processId
        },
        [PSCustomObject]@{
            Name = "Web panel"
            ProcessId = $State.web.processId
        }
    )

    foreach ($entry in $processEntries) {
        if ($null -eq $entry.ProcessId) {
            Write-Host "$($entry.Name) was not started by the tracked session." -ForegroundColor DarkGray
            continue
        }

        $processId = [int]$entry.ProcessId

        if (Test-SolidTrackerProcess -ProcessId $processId) {
            Write-Host "Stopping $($entry.Name) process tree: $processId" -ForegroundColor Yellow
            & taskkill.exe /PID $processId /T /F | Out-Host

            if ($LASTEXITCODE -ne 0) {
                throw "Could not stop $($entry.Name) process tree."
            }

            Write-Host "[OK] $($entry.Name) stopped." -ForegroundColor Green
        }
        else {
            Write-Host "$($entry.Name) process is already stopped." -ForegroundColor DarkGray
        }
    }

    Remove-Item -LiteralPath $Runtime.State -Force -ErrorAction SilentlyContinue
}

if ($StopInfrastructure) {
    Write-Host "Stopping PostgreSQL and Redis..." -ForegroundColor Yellow
    & docker compose --env-file .env stop postgres redis

    if ($LASTEXITCODE -ne 0) {
        throw "Docker infrastructure could not be stopped."
    }

    Write-Host "[OK] PostgreSQL and Redis stopped." -ForegroundColor Green
}
else {
    Write-Host "PostgreSQL and Redis remain running for fast restart." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Live-development stop completed." -ForegroundColor Green