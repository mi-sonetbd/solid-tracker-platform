param(
    [ValidateSet("Start", "Restart", "Status", "Stop")]
    [string]$Action = "Start",

    [string]$RepoRoot = "D:\GitHub\gps-tracker-platform",

    [string]$Route = "/management/monitor",

    [switch]$OpenBrowser,

    [switch]$StopInfrastructure,

    [ValidateRange(60, 600)]
    [int]$DockerStartupTimeoutSeconds = 240,

    [ValidateRange(60, 600)]
    [int]$ServiceStartupTimeoutSeconds = 300
)

& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    # Some older Solid Tracker development scripts read $LASTEXITCODE before
    # any native command has assigned it. Initializing it keeps them compatible
    # with PowerShell 5.1 and StrictMode.
    $global:LASTEXITCODE = 0

    $BackendUrl = "http://localhost:3000"
    $BackendHealthUrl = "$BackendUrl/api/v1/auth/me"
    $WebUrl = "http://localhost:3001"
    $TraccarUrl = "http://localhost:8082"
    $TraccarHealthUrl = "$TraccarUrl/api/health"

    $TraccarImage = "traccar/traccar:6.14.5-alpine"
    $TraccarDbName = "traccar_local"
    $TraccarDbUser = "traccar_local"
    $TraccarContainer = "solid-tracker-traccar-local"

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    function Write-Section {
        param([Parameter(Mandatory = $true)][string]$Title)

        Write-Host ""
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host " $Title" -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan
    }

    function Write-Ok {
        param([Parameter(Mandatory = $true)][string]$Message)

        Write-Host "[OK] $Message" -ForegroundColor Green
    }

    function Invoke-NativeChecked {
        param(
            [Parameter(Mandatory = $true)][string]$FilePath,
            [Parameter(Mandatory = $true)][string[]]$Arguments,
            [Parameter(Mandatory = $true)][string]$FailureMessage
        )

        & $FilePath @Arguments

        if ($LASTEXITCODE -ne 0) {
            throw "$FailureMessage Exit code: $LASTEXITCODE"
        }
    }

    function Get-DotEnvValues {
        param([Parameter(Mandatory = $true)][string]$Path)

        $Values = @{}

        foreach ($RawLine in [System.IO.File]::ReadAllLines($Path)) {
            $Line = $RawLine.Trim()

            if ($Line.Length -eq 0 -or $Line.StartsWith("#")) {
                continue
            }

            $Separator = $Line.IndexOf("=")

            if ($Separator -le 0) {
                continue
            }

            $Key = $Line.Substring(0, $Separator).Trim()
            $Value = $Line.Substring($Separator + 1).Trim()

            if (
                $Value.Length -ge 2 -and
                (
                    ($Value.StartsWith('"') -and $Value.EndsWith('"')) -or
                    ($Value.StartsWith("'") -and $Value.EndsWith("'"))
                )
            ) {
                $Value = $Value.Substring(1, $Value.Length - 2)
            }

            $Values[$Key] = $Value
        }

        return $Values
    }

    function Get-RequiredDotEnvValue {
        param(
            [Parameter(Mandatory = $true)][hashtable]$Values,
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$SourcePath
        )

        if (
            -not $Values.ContainsKey($Name) -or
            [string]::IsNullOrWhiteSpace([string]$Values[$Name])
        ) {
            throw "Required value '$Name' is missing from $SourcePath"
        }

        return [string]$Values[$Name]
    }

    function New-RandomHexSecret {
        param([ValidateRange(16, 128)][int]$ByteCount = 32)

        $Bytes = New-Object byte[] $ByteCount
        $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()

        try {
            $Generator.GetBytes($Bytes)
        }
        finally {
            $Generator.Dispose()
        }

        return (($Bytes | ForEach-Object { $_.ToString("x2") }) -join "")
    }

    function Write-Utf8File {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Content
        )

        $Parent = Split-Path -Parent $Path

        if (-not [string]::IsNullOrWhiteSpace($Parent)) {
            [System.IO.Directory]::CreateDirectory($Parent) | Out-Null
        }

        $Normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
        $Normalized = $Normalized.TrimEnd([char[]]"`r`n") + "`n"
        [System.IO.File]::WriteAllText($Path, $Normalized, $Utf8NoBom)
    }

    function Protect-LocalSecretFile {
        param([Parameter(Mandatory = $true)][string]$Path)

        try {
            $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            & icacls.exe $Path "/inheritance:r" "/grant:r" "${Identity}:(F)" | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Write-Host "[WARN] Could not restrict ACL for $Path" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "[WARN] Could not restrict ACL for $Path" -ForegroundColor Yellow
        }
    }

    function Test-DockerEngine {
        & docker info --format "{{.ServerVersion}}" *> $null
        return ($LASTEXITCODE -eq 0)
    }

    function Start-DockerEngine {
        if (Test-DockerEngine) {
            Write-Ok "Docker Engine is already running."
            return
        }

        Write-Host "Docker Engine is not reachable. Starting Docker Desktop..." -ForegroundColor Yellow

        $Candidates = @(
            (Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"),
            (Join-Path $env:LOCALAPPDATA "Docker\Docker Desktop.exe")
        )

        $DockerDesktopPath = $null

        foreach ($Candidate in $Candidates) {
            if (Test-Path -LiteralPath $Candidate) {
                $DockerDesktopPath = $Candidate
                break
            }
        }

        if ($null -eq $DockerDesktopPath) {
            throw "Docker Desktop executable was not found. Start Docker Desktop manually and rerun this script."
        }

        Start-Process -FilePath $DockerDesktopPath | Out-Null

        $Deadline = [DateTime]::UtcNow.AddSeconds($DockerStartupTimeoutSeconds)

        while ([DateTime]::UtcNow -lt $Deadline) {
            Start-Sleep -Seconds 3

            if (Test-DockerEngine) {
                Write-Ok "Docker Engine is ready."
                return
            }

            Write-Host "." -NoNewline -ForegroundColor DarkGray
        }

        Write-Host ""
        throw "Docker Engine did not become ready within $DockerStartupTimeoutSeconds seconds."
    }

    function Get-ContainerState {
        param([Parameter(Mandatory = $true)][string]$ContainerName)

        $State = [string](& docker inspect `
            --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
            $ContainerName 2>$null)

        if ($LASTEXITCODE -ne 0) {
            return "missing"
        }

        return $State.Trim()
    }

    function Wait-ForContainerReady {
        param(
            [Parameter(Mandatory = $true)][string]$ContainerName,
            [ValidateRange(30, 600)][int]$TimeoutSeconds = 180
        )

        $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $LastState = "unknown"

        while ([DateTime]::UtcNow -lt $Deadline) {
            $LastState = Get-ContainerState -ContainerName $ContainerName

            if ($LastState -eq "healthy" -or $LastState -eq "running") {
                return
            }

            Start-Sleep -Seconds 2
        }

        throw "Container '$ContainerName' did not become ready. Last state: $LastState"
    }

    function Test-HttpReachable {
        param([Parameter(Mandatory = $true)][string]$Url)

        try {
            $Response = Invoke-WebRequest `
                -Uri $Url `
                -Method Get `
                -UseBasicParsing `
                -TimeoutSec 5

            return ($Response.StatusCode -lt 500)
        }
        catch [System.Net.WebException] {
            if ($null -ne $_.Exception.Response) {
                try {
                    $StatusCode = [int]$_.Exception.Response.StatusCode
                    return ($StatusCode -lt 500)
                }
                catch {
                    return $false
                }
            }

            return $false
        }
        catch {
            return $false
        }
    }

    function Wait-ForHttpReachable {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Url,
            [ValidateRange(30, 600)][int]$TimeoutSeconds = 300
        )

        $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

        Write-Host "Waiting for $Name at $Url"

        while ([DateTime]::UtcNow -lt $Deadline) {
            if (Test-HttpReachable -Url $Url) {
                Write-Host ""
                Write-Ok "$Name is reachable."
                return
            }

            Write-Host "." -NoNewline -ForegroundColor DarkGray
            Start-Sleep -Seconds 2
        }

        Write-Host ""
        throw "$Name did not become reachable within $TimeoutSeconds seconds."
    }

    function Initialize-TraccarRuntime {
        param(
            [Parameter(Mandatory = $true)][string]$RepoEnvPath,
            [Parameter(Mandatory = $true)][string]$BaseComposePath
        )

        $LocalAppData = [Environment]::GetFolderPath("LocalApplicationData")

        if ([string]::IsNullOrWhiteSpace($LocalAppData)) {
            throw "Windows LocalApplicationData path could not be resolved."
        }

        $StateRoot = Join-Path $LocalAppData "SolidTracker\traccar-local"
        $LocalEnvPath = Join-Path $StateRoot "traccar.local.env"
        $LocalComposePath = Join-Path $StateRoot "compose.traccar.local.yaml"

        [System.IO.Directory]::CreateDirectory($StateRoot) | Out-Null

        $ExistingLocalEnv = @{}

        if (Test-Path -LiteralPath $LocalEnvPath) {
            $ExistingLocalEnv = Get-DotEnvValues -Path $LocalEnvPath
        }

        if (
            $ExistingLocalEnv.ContainsKey("TRACCAR_LOCAL_DB_PASSWORD") -and
            -not [string]::IsNullOrWhiteSpace(
                [string]$ExistingLocalEnv["TRACCAR_LOCAL_DB_PASSWORD"]
            )
        ) {
            $TraccarDbPassword = [string]$ExistingLocalEnv["TRACCAR_LOCAL_DB_PASSWORD"]
        }
        else {
            $TraccarDbPassword = New-RandomHexSecret -ByteCount 32
        }

        if ($TraccarDbPassword -notmatch "^[a-f0-9]{64}$") {
            throw (
                "The stored Traccar database password is invalid. " +
                "Rename or remove '$LocalEnvPath' and rerun this script."
            )
        }

        $LocalEnvironment = @"
TRACCAR_LOCAL_IMAGE=$TraccarImage
TRACCAR_LOCAL_DB_NAME=$TraccarDbName
TRACCAR_LOCAL_DB_USER=$TraccarDbUser
TRACCAR_LOCAL_DB_PASSWORD=$TraccarDbPassword
TRACCAR_LOCAL_ADMIN_PORT=8082
TRACCAR_LOCAL_OSMAND_PORT=5055
"@

        $LocalCompose = @'
services:
  traccar:
    image: ${TRACCAR_LOCAL_IMAGE:?TRACCAR_LOCAL_IMAGE is required}
    container_name: solid-tracker-traccar-local
    restart: unless-stopped
    environment:
      CONFIG_USE_ENVIRONMENT_VARIABLES: "true"
      DATABASE_DRIVER: org.postgresql.Driver
      DATABASE_URL: jdbc:postgresql://postgres:5432/${TRACCAR_LOCAL_DB_NAME}
      DATABASE_USER: ${TRACCAR_LOCAL_DB_USER}
      DATABASE_PASSWORD: ${TRACCAR_LOCAL_DB_PASSWORD}
      DATABASE_MAX_POOL_SIZE: "10"
      OSMAND_PORT: "5055"
      EVENT_STATUS_ENABLE: "true"
      MEDIA_PATH: /opt/traccar/media
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "127.0.0.1:${TRACCAR_LOCAL_ADMIN_PORT}:8082/tcp"
      - "127.0.0.1:${TRACCAR_LOCAL_OSMAND_PORT}:5055/tcp"
    volumes:
      - solid_tracker_traccar_local_logs:/opt/traccar/logs
      - solid_tracker_traccar_local_media:/opt/traccar/media
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:8082/api/health"]
      interval: 15s
      timeout: 5s
      retries: 20
      start_period: 3m
    stop_grace_period: 45s
    networks:
      - solid_tracker_network

volumes:
  solid_tracker_traccar_local_logs:
  solid_tracker_traccar_local_media:
'@

        Write-Utf8File -Path $LocalEnvPath -Content $LocalEnvironment
        Protect-LocalSecretFile -Path $LocalEnvPath
        Write-Utf8File -Path $LocalComposePath -Content $LocalCompose

        return @{
            StateRoot = $StateRoot
            EnvPath = $LocalEnvPath
            ComposePath = $LocalComposePath
            DbPassword = $TraccarDbPassword
        }
    }

    function Get-ComposeArguments {
        param(
            [Parameter(Mandatory = $true)][string]$RepoEnvPath,
            [Parameter(Mandatory = $true)][string]$BaseComposePath,
            [Parameter(Mandatory = $true)][string]$LocalEnvPath,
            [Parameter(Mandatory = $true)][string]$LocalComposePath
        )

        return @(
            "compose",
            "--env-file", $RepoEnvPath,
            "--env-file", $LocalEnvPath,
            "-f", $BaseComposePath,
            "-f", $LocalComposePath
        )
    }

    function Start-InfrastructureAndTraccar {
        param(
            [Parameter(Mandatory = $true)][string[]]$ComposeArguments,
            [Parameter(Mandatory = $true)][string]$PostgresUser,
            [Parameter(Mandatory = $true)][string]$PostgresDb,
            [Parameter(Mandatory = $true)][string]$TraccarDbPassword,
            [switch]$ForceTraccarRestart
        )

        Write-Section "START POSTGRESQL AND REDIS"

        Invoke-NativeChecked `
            -FilePath "docker" `
            -Arguments ($ComposeArguments + @("up", "-d", "postgres", "redis")) `
            -FailureMessage "PostgreSQL or Redis startup failed."

        Wait-ForContainerReady `
            -ContainerName "solid-tracker-postgres" `
            -TimeoutSeconds 180

        Wait-ForContainerReady `
            -ContainerName "solid-tracker-redis" `
            -TimeoutSeconds 120

        Write-Ok "PostgreSQL and Redis are ready."

        Write-Section "VERIFY TRACCAR DATABASE"

        $DatabaseSql = @"
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', '$TraccarDbUser', '$TraccarDbPassword')
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = '$TraccarDbUser'
)
\gexec
ALTER ROLE "$TraccarDbUser" WITH LOGIN PASSWORD '$TraccarDbPassword';
SELECT format('CREATE DATABASE %I OWNER %I', '$TraccarDbName', '$TraccarDbUser')
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_database
    WHERE datname = '$TraccarDbName'
)
\gexec
ALTER DATABASE "$TraccarDbName" OWNER TO "$TraccarDbUser";
"@

        $DatabaseSql | & docker @ComposeArguments exec `
            -T `
            postgres `
            psql `
            --set=ON_ERROR_STOP=1 `
            --username $PostgresUser `
            --dbname $PostgresDb

        if ($LASTEXITCODE -ne 0) {
            throw "Traccar database initialization failed."
        }

        Write-Ok "Separate database '$TraccarDbName' is ready."

        Write-Section "START TRACCAR"

        Invoke-NativeChecked `
            -FilePath "docker" `
            -Arguments ($ComposeArguments + @("up", "-d", "traccar")) `
            -FailureMessage "Traccar startup failed."

        if ($ForceTraccarRestart) {
            Invoke-NativeChecked `
                -FilePath "docker" `
                -Arguments ($ComposeArguments + @("restart", "traccar")) `
                -FailureMessage "Traccar restart failed."
        }

        Wait-ForContainerReady `
            -ContainerName $TraccarContainer `
            -TimeoutSeconds $ServiceStartupTimeoutSeconds

        Wait-ForHttpReachable `
            -Name "Traccar API" `
            -Url $TraccarHealthUrl `
            -TimeoutSeconds $ServiceStartupTimeoutSeconds
    }

    function Start-SolidTrackerApplications {
        param([switch]$RestartApplications)

        $DevScript = Join-Path $RepoRoot "scripts\dev.ps1"

        if (-not (Test-Path -LiteralPath $DevScript)) {
            throw "Existing Solid Tracker launcher is missing: $DevScript"
        }

        Write-Section "START SOLID TRACKER BACKEND AND WEB PANEL"

        # Reset before invoking the existing script for compatibility with its
        # StrictMode and PowerShell 5.1 behavior.
        $global:LASTEXITCODE = 0

        if ($RestartApplications) {
            & $DevScript -Restart -Route $Route
        }
        else {
            & $DevScript -Route $Route
        }

        if (-not $?) {
            throw "The existing Solid Tracker live-development launcher failed."
        }

        Wait-ForHttpReachable `
            -Name "Backend API" `
            -Url $BackendHealthUrl `
            -TimeoutSeconds $ServiceStartupTimeoutSeconds

        Wait-ForHttpReachable `
            -Name "Web panel" `
            -Url "$WebUrl/login" `
            -TimeoutSeconds $ServiceStartupTimeoutSeconds
    }

    function Show-Status {
        param(
            [Parameter(Mandatory = $true)][string[]]$ComposeArguments
        )

        Write-Section "SOLID TRACKER SERVICE STATUS"

        $BackendReady = Test-HttpReachable -Url $BackendHealthUrl
        $WebReady = Test-HttpReachable -Url "$WebUrl/login"
        $TraccarReady = Test-HttpReachable -Url $TraccarHealthUrl

        Write-Host ("Backend API : " + $(if ($BackendReady) { "READY" } else { "STOPPED/UNREACHABLE" })) `
            -ForegroundColor $(if ($BackendReady) { "Green" } else { "Red" })

        Write-Host ("Web panel   : " + $(if ($WebReady) { "READY" } else { "STOPPED/UNREACHABLE" })) `
            -ForegroundColor $(if ($WebReady) { "Green" } else { "Red" })

        Write-Host ("Traccar     : " + $(if ($TraccarReady) { "READY" } else { "STOPPED/UNREACHABLE" })) `
            -ForegroundColor $(if ($TraccarReady) { "Green" } else { "Red" })

        Write-Host ""
        & docker @ComposeArguments ps postgres redis traccar

        $StatusScript = Join-Path $RepoRoot "scripts\dev-status.ps1"

        if (Test-Path -LiteralPath $StatusScript) {
            Write-Host ""
            $global:LASTEXITCODE = 0
            & $StatusScript
        }
    }

    function Stop-AllServices {
        param(
            [Parameter(Mandatory = $true)][string[]]$ComposeArguments
        )

        Write-Section "STOP SOLID TRACKER SERVICES"

        $StopScript = Join-Path $RepoRoot "scripts\dev-stop.ps1"

        if (Test-Path -LiteralPath $StopScript) {
            $global:LASTEXITCODE = 0
            & $StopScript
        }
        else {
            Write-Host "[WARN] Existing backend/web stop script was not found." -ForegroundColor Yellow
        }

        Invoke-NativeChecked `
            -FilePath "docker" `
            -Arguments ($ComposeArguments + @("stop", "traccar")) `
            -FailureMessage "Traccar stop failed."

        if ($StopInfrastructure) {
            Invoke-NativeChecked `
                -FilePath "docker" `
                -Arguments ($ComposeArguments + @("stop", "postgres", "redis")) `
                -FailureMessage "PostgreSQL or Redis stop failed."

            Write-Ok "Backend, web panel, Traccar, PostgreSQL, and Redis are stopped."
        }
        else {
            Write-Ok "Backend, web panel, and Traccar are stopped. PostgreSQL and Redis remain running."
        }
    }

    try {
        Write-Section "SOLID TRACKER - ALL SERVICES"

        if ($PSVersionTable.PSVersion.Major -lt 5) {
            throw "PowerShell 5.1 or newer is required."
        }

        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) {
            throw "Solid Tracker repository was not found: $RepoRoot"
        }

        $RepoEnvPath = Join-Path $RepoRoot ".env"
        $BaseComposePath = Join-Path $RepoRoot "compose.yaml"

        foreach ($RequiredPath in @($RepoEnvPath, $BaseComposePath)) {
            if (-not (Test-Path -LiteralPath $RequiredPath)) {
                throw "Required file is missing: $RequiredPath"
            }
        }

        Set-Location -LiteralPath $RepoRoot

        Start-DockerEngine

        $RepoEnv = Get-DotEnvValues -Path $RepoEnvPath
        $PostgresUser = Get-RequiredDotEnvValue `
            -Values $RepoEnv `
            -Name "POSTGRES_USER" `
            -SourcePath $RepoEnvPath
        $PostgresDb = Get-RequiredDotEnvValue `
            -Values $RepoEnv `
            -Name "POSTGRES_DB" `
            -SourcePath $RepoEnvPath

        $TraccarRuntime = Initialize-TraccarRuntime `
            -RepoEnvPath $RepoEnvPath `
            -BaseComposePath $BaseComposePath

        $ComposeArguments = Get-ComposeArguments `
            -RepoEnvPath $RepoEnvPath `
            -BaseComposePath $BaseComposePath `
            -LocalEnvPath $TraccarRuntime.EnvPath `
            -LocalComposePath $TraccarRuntime.ComposePath

        Invoke-NativeChecked `
            -FilePath "docker" `
            -Arguments ($ComposeArguments + @("config", "--quiet")) `
            -FailureMessage "Combined Docker Compose configuration is invalid."

        switch ($Action) {
            "Status" {
                Show-Status -ComposeArguments $ComposeArguments
                return
            }

            "Stop" {
                Stop-AllServices -ComposeArguments $ComposeArguments
                return
            }

            "Restart" {
                Start-InfrastructureAndTraccar `
                    -ComposeArguments $ComposeArguments `
                    -PostgresUser $PostgresUser `
                    -PostgresDb $PostgresDb `
                    -TraccarDbPassword $TraccarRuntime.DbPassword `
                    -ForceTraccarRestart

                Start-SolidTrackerApplications -RestartApplications
            }

            default {
                Start-InfrastructureAndTraccar `
                    -ComposeArguments $ComposeArguments `
                    -PostgresUser $PostgresUser `
                    -PostgresDb $PostgresDb `
                    -TraccarDbPassword $TraccarRuntime.DbPassword

                $AppsAlreadyReady = (
                    (Test-HttpReachable -Url $BackendHealthUrl) -and
                    (Test-HttpReachable -Url "$WebUrl/login")
                )

                if ($AppsAlreadyReady) {
                    Write-Ok "Backend API and web panel are already running."
                }
                else {
                    Start-SolidTrackerApplications
                }
            }
        }

        Write-Section "ALL SERVICES ARE READY"

        Write-Host "Solid Tracker : $WebUrl$Route" -ForegroundColor Green
        Write-Host "Backend API   : $BackendUrl" -ForegroundColor Green
        Write-Host "Traccar UI    : $TraccarUrl" -ForegroundColor Green
        Write-Host "OsmAnd port   : http://localhost:5055" -ForegroundColor Green
        Write-Host "Backend log   : $RepoRoot\.runtime\logs\backend.log" -ForegroundColor DarkGray
        Write-Host "Web log       : $RepoRoot\.runtime\logs\web.log" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Status:" -ForegroundColor Yellow
        Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action Status"
        Write-Host "Restart:" -ForegroundColor Yellow
        Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action Restart -OpenBrowser"
        Write-Host "Stop apps + Traccar:" -ForegroundColor Yellow
        Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action Stop"
        Write-Host "Stop everything:" -ForegroundColor Yellow
        Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action Stop -StopInfrastructure"

        if ($OpenBrowser) {
            Start-Process "$WebUrl$Route" | Out-Null
            Start-Process $TraccarUrl | Out-Null
        }
    }
    catch {
        Write-Host ""
        Write-Host "==================================================" -ForegroundColor Red
        Write-Host " ALL-SERVICES STARTUP FAILED" -ForegroundColor Red
        Write-Host "==================================================" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        try {
            Write-Host ""
            Write-Host "Current Docker containers:" -ForegroundColor Yellow
            & docker ps -a `
                --filter "name=solid-tracker-" `
                --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
        }
        catch {
            # Preserve the original error.
        }

        exit 1
    }
}
