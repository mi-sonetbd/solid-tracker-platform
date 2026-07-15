Set-StrictMode -Version Latest

function Get-SolidTrackerRepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Get-SolidTrackerRuntimePaths {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $runtimeRoot = Join-Path $RepoRoot ".runtime"
    $logRoot = Join-Path $runtimeRoot "logs"

    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

    return [PSCustomObject]@{
        Root = $runtimeRoot
        Logs = $logRoot
        State = Join-Path $runtimeRoot "dev-processes.json"
        BackendLog = Join-Path $logRoot "backend.log"
        WebLog = Join-Path $logRoot "web.log"
    }
}

function Test-SolidTrackerEndpoint {
    param([Parameter(Mandatory = $true)][string]$Url)

    try {
        Invoke-WebRequest `
            -Uri $Url `
            -UseBasicParsing `
            -TimeoutSec 3 |
            Out-Null

        return $true
    }
    catch {
        return ($null -ne $_.Exception.Response)
    }
}

function Wait-SolidTrackerEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$TimeoutSeconds = 90
    )

    Write-Host "Waiting for $Name at $Url" -ForegroundColor Yellow

    for ($attempt = 1; $attempt -le $TimeoutSeconds; $attempt++) {
        if (Test-SolidTrackerEndpoint -Url $Url) {
            Write-Host ""
            Write-Host "[OK] $Name is ready." -ForegroundColor Green
            return
        }

        Write-Host "." -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }

    Write-Host ""
    throw "$Name did not become ready within $TimeoutSeconds seconds."
}

function Resolve-SolidTrackerPackageScript {
    param(
        [Parameter(Mandatory = $true)][string]$PackageJsonPath,
        [Parameter(Mandatory = $true)][string[]]$Candidates
    )

    $packageJson = Get-Content -Raw -LiteralPath $PackageJsonPath |
        ConvertFrom-Json

    foreach ($candidate in $Candidates) {
        if ($null -ne $packageJson.scripts.PSObject.Properties[$candidate]) {
            return $candidate
        }
    }

    throw "No supported development script was found in $PackageJsonPath."
}

function Test-SolidTrackerProcess {
    param([Nullable[int]]$ProcessId)

    if ($null -eq $ProcessId) {
        return $false
    }

    return $null -ne (
        Get-Process -Id $ProcessId.Value -ErrorAction SilentlyContinue
    )
}

function Start-SolidTrackerWorkspaceProcess {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$WindowTitle,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    $escapedRepoRoot = $RepoRoot.Replace("'", "''")
    $escapedWindowTitle = $WindowTitle.Replace("'", "''")
    $escapedPackageName = $PackageName.Replace("'", "''")
    $escapedScriptName = $ScriptName.Replace("'", "''")
    $escapedLogPath = $LogPath.Replace("'", "''")

    $command = @"
`$ErrorActionPreference = 'Continue'
`$Host.UI.RawUI.WindowTitle = '$escapedWindowTitle'
Set-Location '$escapedRepoRoot'
Write-Host ''
Write-Host '$escapedWindowTitle' -ForegroundColor Cyan
Write-Host 'Live reload is active. Keep this window open.' -ForegroundColor Green
Write-Host 'Press Ctrl+C to stop this service.' -ForegroundColor Yellow
Write-Host 'Log: $escapedLogPath' -ForegroundColor DarkGray
Write-Host ''
pnpm.cmd --filter '$escapedPackageName' '$escapedScriptName' 2>&1 |
    Tee-Object -FilePath '$escapedLogPath' -Append
"@

    return Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-NoExit",
            "-Command",
            $command
        ) `
        -PassThru
}

function Read-SolidTrackerDevState {
    param([Parameter(Mandatory = $true)][string]$StatePath)

    if (-not (Test-Path -LiteralPath $StatePath)) {
        return $null
    }

    try {
        return Get-Content -Raw -LiteralPath $StatePath |
            ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-SolidTrackerDevState {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][object]$State
    )

    $json = $State | ConvertTo-Json -Depth 8
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $StatePath,
        $json,
        $utf8WithoutBom
    )
}