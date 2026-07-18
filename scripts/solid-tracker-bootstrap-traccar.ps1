[CmdletBinding()]
param(
    [string]$BackendBaseUrl = "http://127.0.0.1:3000/api/v1",

    [Parameter(Mandatory = $true)]
    [string]$AdminMobileNumber,

    [string]$ServerName = "Local Traccar Development",

    [string]$TraccarBaseUrl = "http://127.0.0.1:8082",

    [Parameter(Mandatory = $true)]
    [string]$TraccarUsername,

    [switch]$BackfillInstalledDevices,

    [switch]$ForceResync,

    [ValidateRange(1, 200)]
    [int]$PageSize = 100
)

$ErrorActionPreference = "Stop"

function Read-PlainSecret {
    param([string]$Prompt)

    $SecureValue = Read-Host $Prompt -AsSecureString
    $Pointer = [IntPtr]::Zero

    try {
        $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
    }
    finally {
        if ($Pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
        }
    }
}

function Normalize-Url {
    param([string]$Value)
    return $Value.Trim().TrimEnd("/").ToLowerInvariant()
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        $Body,
        [int]$TimeoutSec = 30
    )

    $Parameters = @{
        Method = $Method
        Uri = $Uri
        TimeoutSec = $TimeoutSec
    }

    if ($null -ne $Headers) {
        $Parameters["Headers"] = $Headers
    }

    if ($null -ne $Body) {
        $Parameters["ContentType"] = "application/json"
        $Parameters["Body"] = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    try {
        return Invoke-RestMethod @Parameters
    }
    catch {
        Write-Host ""
        Write-Host "[FAIL] $Method $Uri" -ForegroundColor Red

        if ($null -ne $_.Exception.Response) {
            try {
                Write-Host "HTTP $([int]$_.Exception.Response.StatusCode)" -ForegroundColor Red
                $Stream = $_.Exception.Response.GetResponseStream()

                if ($null -ne $Stream) {
                    $Reader = New-Object System.IO.StreamReader($Stream)

                    try {
                        $ErrorBody = $Reader.ReadToEnd()

                        if (-not [string]::IsNullOrWhiteSpace($ErrorBody)) {
                            Write-Host $ErrorBody -ForegroundColor Red
                        }
                    }
                    finally {
                        $Reader.Dispose()
                    }
                }
            }
            catch {
            }
        }

        throw
    }
}

function Get-Items {
    param($Response)

    if ($null -eq $Response) {
        return @()
    }

    if ($Response -is [System.Array]) {
        return @($Response)
    }

    foreach ($Name in @("items", "data", "records", "results")) {
        $Property = $Response.PSObject.Properties[$Name]

        if ($null -ne $Property) {
            return @($Property.Value)
        }
    }

    return @($Response)
}

function Get-InstalledDevices {
    param([hashtable]$Headers)

    $Result = @()
    $Page = 1

    while ($true) {
        $Response = Invoke-Api -Method "GET" -Uri "$BackendBaseUrl/devices?page=$Page&pageSize=$PageSize" -Headers $Headers
        $Items = @(Get-Items -Response $Response)

        if ($Items.Count -eq 0) {
            break
        }

        foreach ($Device in $Items) {
            if ($Device.lifecycleStatus -eq "INSTALLED") {
                $Result += $Device
            }
        }

        $HasNext = $false
        $PaginationProperty = $Response.PSObject.Properties["pagination"]

        if ($null -ne $PaginationProperty -and $null -ne $PaginationProperty.Value) {
            $Pagination = $PaginationProperty.Value
            $TotalPagesProperty = $Pagination.PSObject.Properties["totalPages"]
            $HasNextProperty = $Pagination.PSObject.Properties["hasNextPage"]

            if ($null -ne $TotalPagesProperty) {
                $HasNext = $Page -lt [int]$TotalPagesProperty.Value
            }
            elseif ($null -ne $HasNextProperty) {
                $HasNext = [bool]$HasNextProperty.Value
            }
            else {
                $HasNext = $Items.Count -ge $PageSize
            }
        }
        else {
            $HasNext = $Items.Count -ge $PageSize
        }

        if (-not $HasNext) {
            break
        }

        $Page++

        if ($Page -gt 1000) {
            throw "Pagination safety limit exceeded."
        }
    }

    return @($Result)
}

function Has-ActiveMapping {
    param(
        $Mappings,
        [string]$ServerId
    )

    foreach ($Mapping in @($Mappings)) {
        $MappingServerId = $Mapping.traccarServerId

        if ([string]::IsNullOrWhiteSpace($MappingServerId) -and $null -ne $Mapping.traccarServer) {
            $MappingServerId = $Mapping.traccarServer.id
        }

        if (
            $MappingServerId -eq $ServerId -and
            $Mapping.syncStatus -eq "SYNCED" -and
            $Mapping.isActive -eq $true
        ) {
            return $true
        }
    }

    return $false
}

$AdminPassword = $null
$TraccarPassword = $null

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker Traccar Bootstrap" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "Backend      : $BackendBaseUrl"
    Write-Host "Traccar      : $TraccarBaseUrl"
    Write-Host "Traccar user : $TraccarUsername"
    Write-Host "Backfill     : $($BackfillInstalledDevices.IsPresent)"
    Write-Host "Force resync : $($ForceResync.IsPresent)"

    $AdminPassword = Read-PlainSecret -Prompt "Solid Tracker administrator password"
    $TraccarPassword = Read-PlainSecret -Prompt "Traccar password"

    if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
        throw "Solid Tracker administrator password is required."
    }

    if ([string]::IsNullOrWhiteSpace($TraccarPassword)) {
        throw "Traccar password is required."
    }

    Write-Host ""
    Write-Host "=== LOGIN ===" -ForegroundColor Cyan

    $LoginBody = @{
        mobileNumber = $AdminMobileNumber
        password = $AdminPassword
        platform = "WEB"
        deviceName = "Traccar Bootstrap"
        appVersion = "local-bootstrap"
    }

    $Login = Invoke-Api -Method "POST" -Uri "$BackendBaseUrl/auth/login" -Body $LoginBody

    if ([string]::IsNullOrWhiteSpace($Login.accessToken)) {
        throw "Login response did not contain an access token."
    }

    $Headers = @{
        Authorization = "Bearer $($Login.accessToken)"
    }

    Write-Host "[OK] Solid Tracker login succeeded." -ForegroundColor Green

    Write-Host ""
    Write-Host "=== DEFAULT TRACCAR SERVER ===" -ForegroundColor Cyan

    $ServersResponse = Invoke-Api -Method "GET" -Uri "$BackendBaseUrl/tracking/traccar-servers" -Headers $Headers
    $Servers = @(Get-Items -Response $ServersResponse)
    $TargetUrl = Normalize-Url -Value $TraccarBaseUrl
    $ExistingServer = $null

    foreach ($Candidate in $Servers) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate.baseUrl)) {
            if ((Normalize-Url -Value $Candidate.baseUrl) -eq $TargetUrl) {
                $ExistingServer = $Candidate
                break
            }
        }
    }

    $ServerBody = @{
        name = $ServerName
        baseUrl = $TraccarBaseUrl
        username = $TraccarUsername
        password = $TraccarPassword
        isDefault = $true
    }

    if ($null -eq $ExistingServer) {
        $Server = Invoke-Api -Method "POST" -Uri "$BackendBaseUrl/tracking/traccar-servers" -Headers $Headers -Body $ServerBody
        Write-Host "[OK] Traccar server created." -ForegroundColor Green
    }
    else {
        $ServerBody["status"] = "ACTIVE"
        $Server = Invoke-Api -Method "PATCH" -Uri "$BackendBaseUrl/tracking/traccar-servers/$($ExistingServer.id)" -Headers $Headers -Body $ServerBody
        Write-Host "[OK] Traccar server updated." -ForegroundColor Green
    }

    if ([string]::IsNullOrWhiteSpace($Server.id)) {
        throw "Traccar server response did not contain an ID."
    }

    Write-Host "Server ID : $($Server.id)"
    Write-Host "Status    : $($Server.status)"
    Write-Host "Default   : $($Server.isDefault)"

    Write-Host ""
    Write-Host "=== HEALTH CHECK ===" -ForegroundColor Cyan

    $Health = Invoke-Api -Method "POST" -Uri "$BackendBaseUrl/tracking/traccar-servers/$($Server.id)/health-check" -Headers $Headers -TimeoutSec 30
    Write-Host "[OK] Traccar health check succeeded." -ForegroundColor Green

    if ($null -ne $Health) {
        $Health | ConvertTo-Json -Depth 10
    }

    if ($BackfillInstalledDevices.IsPresent) {
        Write-Host ""
        Write-Host "=== DEVICE BACKFILL ===" -ForegroundColor Cyan

        $Devices = @(Get-InstalledDevices -Headers $Headers)
        Write-Host "Installed devices found: $($Devices.Count)"

        $Synced = 0
        $Skipped = 0
        $Failed = 0

        foreach ($Device in $Devices) {
            $Identity = $Device.imei

            if ([string]::IsNullOrWhiteSpace($Identity)) {
                $Identity = $Device.serialNumber
            }

            if ([string]::IsNullOrWhiteSpace($Identity)) {
                $Identity = $Device.deviceCode
            }

            try {
                $MappingsResponse = Invoke-Api -Method "GET" -Uri "$BackendBaseUrl/tracking/devices/$($Device.id)/mappings" -Headers $Headers
                $Mappings = @(Get-Items -Response $MappingsResponse)

                if ((Has-ActiveMapping -Mappings $Mappings -ServerId $Server.id) -and -not $ForceResync.IsPresent) {
                    Write-Host "[SKIP] $Identity already synchronized."
                    $Skipped++
                    continue
                }

                Write-Host "[SYNC] $Identity"

                $SyncBody = @{
                    serverId = $Server.id
                    forceUpdate = $ForceResync.IsPresent
                }

                $null = Invoke-Api -Method "POST" -Uri "$BackendBaseUrl/tracking/devices/$($Device.id)/sync" -Headers $Headers -Body $SyncBody -TimeoutSec 60
                Write-Host "[OK] $Identity synchronized." -ForegroundColor Green
                $Synced++
            }
            catch {
                Write-Host "[FAIL] $Identity : $($_.Exception.Message)" -ForegroundColor Red
                $Failed++
            }
        }

        Write-Host ""
        Write-Host "Backfill summary" -ForegroundColor Cyan
        Write-Host "Synchronized : $Synced"
        Write-Host "Skipped      : $Skipped"
        Write-Host "Failed       : $Failed"

        if ($Failed -gt 0) {
            throw "$Failed installed device(s) failed synchronization."
        }
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host " Traccar bootstrap completed successfully" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
}
finally {
    $AdminPassword = $null
    $TraccarPassword = $null
    $LoginBody = $null
    $ServerBody = $null
}
