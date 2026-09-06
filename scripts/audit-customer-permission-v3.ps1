param(
    [string]$RepoRoot = "D:\GitHub\gps-tracker-platform",
    [string]$CustomerName = "Habiba Sultana",
    [string]$MobileNumber = "",
    [string]$AccessToken = "",
    [switch]$PromptForLogin,
    [switch]$OpenReport
)

& {
    # Solid Tracker customer permission audit
    # Version marker is intentionally printed so an old copied script is obvious.
    $AuditScriptVersion = "3.0.1"
    $ErrorActionPreference = "Stop"
    $global:LASTEXITCODE = 0

    $Backend = "http://localhost:3000/api/v1"
    $Web = "http://localhost:3001"
    $Traccar = "http://localhost:8082"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportDir = Join-Path $RepoRoot ".runtime\audits"
    $report = Join-Path $reportDir "customer-permission-audit-$stamp.txt"
    [System.IO.Directory]::CreateDirectory($reportDir) | Out-Null

    function Log {
        param(
            [string]$Text = "",
            [ValidateSet("INFO","PASS","WARN","FAIL","DATA")]
            [string]$Level = "INFO"
        )

        $line = if ($Text) { "[$Level] $Text" } else { "" }

        switch ($Level) {
            "PASS" { Write-Host $line -ForegroundColor Green }
            "WARN" { Write-Host $line -ForegroundColor Yellow }
            "FAIL" { Write-Host $line -ForegroundColor Red }
            "DATA" { Write-Host $line -ForegroundColor Gray }
            default { Write-Host $line -ForegroundColor Cyan }
        }

        Add-Content -LiteralPath $report -Value $line -Encoding UTF8
    }

    function Section {
        param([string]$Title)
        Log
        Log ("=" * 68)
        Log $Title
        Log ("=" * 68)
    }

    function Read-Env {
        param([string]$Path)

        $values = @{}

        foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
            $line = $raw.Trim()

            if (-not $line -or $line.StartsWith("#")) {
                continue
            }

            $index = $line.IndexOf("=")

            if ($index -le 0) {
                continue
            }

            $key = $line.Substring(0, $index).Trim()
            $value = $line.Substring($index + 1).Trim().Trim('"').Trim("'")
            $values[$key] = $value
        }

        return $values
    }

    function Sql-Literal {
        param([string]$Value)
        return "'" + $Value.Replace("'", "''") + "'"
    }

    function Psql {
        param(
            [string]$Sql,
            [switch]$Machine
        )

        $args = @(
            "compose",
            "--env-file", $script:envPath,
            "-f", $script:composePath,
            "exec", "-T",
            "postgres",
            "psql",
            "-X",
            "-v", "ON_ERROR_STOP=1",
            "-U", $script:pgUser,
            "-d", $script:pgDb
        )

        if ($Machine) {
            $args += @("-A", "-t", "-F", "|")
        }

        $global:LASTEXITCODE = 0
        $output = @($Sql | & docker @args 2>&1)
        $code = $LASTEXITCODE

        if ($code -ne 0) {
            foreach ($item in $output) {
                Log ([string]$item) "FAIL"
            }

            throw "PostgreSQL query failed with exit code $code."
        }

        return @(
            $output |
            ForEach-Object { ([string]$_).TrimEnd() } |
            Where-Object { $_ -ne "" }
        )
    }

    function Http-Status {
        param([string]$Url)

        try {
            $response = Invoke-WebRequest `
                -Uri $Url `
                -UseBasicParsing `
                -TimeoutSec 5

            return [int]$response.StatusCode
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                return [int]$_.Exception.Response.StatusCode
            }

            return 0
        }
        catch {
            return 0
        }
    }

    function Show-Matches {
        param(
            [string]$RelativePath,
            [string[]]$Patterns
        )

        $path = Join-Path $RepoRoot $RelativePath

        if (-not (Test-Path -LiteralPath $path)) {
            Log "Missing code file: $RelativePath" "WARN"
            return
        }

        Log "File: $RelativePath" "DATA"
        $number = 0

        foreach ($line in Get-Content -LiteralPath $path) {
            $number++

            foreach ($pattern in $Patterns) {
                if ($line -match $pattern) {
                    Log ("{0,5}: {1}" -f $number, $line.TrimEnd()) "DATA"
                    break
                }
            }
        }
    }

    function Secure-PasswordText {
        $secure = Read-Host "Customer password (hidden)" -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }

    try {
        [System.IO.File]::WriteAllText(
            $report,
            "Solid Tracker Customer Permission / Workspace Audit`r`n" +
            "Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")`r`n" +
            "Customer: $CustomerName`r`n" +
            "Mode: read-only by default. -PromptForLogin creates temporary " +
            "authentication sessions and revokes them after testing.`r`n",
            (New-Object System.Text.UTF8Encoding($false))
        )

        Section "1. PREFLIGHT"
        Log "Audit script version: $AuditScriptVersion" "PASS"

        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) {
            throw "Repository not found: $RepoRoot"
        }

        Set-Location -LiteralPath $RepoRoot
        $script:envPath = Join-Path $RepoRoot ".env"
        $script:composePath = Join-Path $RepoRoot "compose.yaml"

        foreach ($path in @($script:envPath, $script:composePath)) {
            if (-not (Test-Path -LiteralPath $path)) {
                throw "Required file missing: $path"
            }
        }

        & docker info --format "{{.ServerVersion}}" *> $null

        if ($LASTEXITCODE -ne 0) {
            throw "Docker Engine is not running."
        }

        Log "Repository and Docker are ready." "PASS"

        $env = Read-Env $script:envPath
        $script:pgUser = [string]$env["POSTGRES_USER"]
        $script:pgDb = [string]$env["POSTGRES_DB"]

        if (-not $script:pgUser -or -not $script:pgDb) {
            throw "POSTGRES_USER or POSTGRES_DB is missing from .env."
        }

        Log "Database: $script:pgDb; user: $script:pgUser" "DATA"

        Section "2. SERVICE STATUS"

        $composeOutput = @(
            & docker compose `
                --env-file $script:envPath `
                -f $script:composePath `
                ps 2>&1
        )

        foreach ($line in $composeOutput) {
            Log ([string]$line) "DATA"
        }

        foreach ($item in @(
            @("Backend", "$Backend/auth/me"),
            @("Web", "$Web/login"),
            @("Traccar", "$Traccar/api/health")
        )) {
            $status = Http-Status $item[1]

            if ($status -gt 0 -and $status -lt 500) {
                Log "$($item[0]) reachable: HTTP $status" "PASS"
            }
            else {
                Log "$($item[0]) unreachable: $($item[1])" "WARN"
            }
        }

        Section "3. GIT STATUS"

        foreach ($command in @(
            @("branch", "--show-current"),
            @("log", "-1", "--oneline"),
            @("status", "--short"),
            @("diff", "--check")
        )) {
            $output = @(& git @command 2>&1)
            $code = $LASTEXITCODE

            foreach ($line in $output) {
                Log ([string]$line) "DATA"
            }

            if ($command[0] -eq "diff" -and $code -eq 0) {
                Log "git diff --check passed." "PASS"
            }
        }

        Section "4. WORKSPACE / SESSION CODE"

        Show-Matches `
            "apps\web-panel\src\app\(panel)\monitor\page.tsx" `
            @("requireCustomerSession","session\.user\.permissions","vehicle\.view")

        Show-Matches `
            "apps\web-panel\src\lib\customer\use-customer-assets.ts" `
            @("canViewVehicles","/api/customer/assets","vehicle\.view permission")

        Show-Matches `
            "apps\web-panel\src\lib\auth\server-session.ts" `
            @("permissions","workspace","auth/me","requireCustomerSession","CUSTOMER")

        Show-Matches `
            "services\backend-api\src\identity\access-control\access-control.service.ts" `
            @("buildContext","roleAssignment","effectiveFrom","effectiveUntil","permission\.code","customerMembership")

        Show-Matches `
            "services\backend-api\src\identity\access-control\access-token.guard.ts" `
            @("buildContext","request\.auth","session")

        Section "5. DATABASE AUDIT"

        $name = Sql-Literal $CustomerName
        $predicate = "LOWER(u.""fullName"") = LOWER($name)"

        if ($MobileNumber) {
            $mobile = Sql-Literal $MobileNumber
            $predicate = "($predicate OR u.""mobileNumber"" = $mobile)"
        }

        $cte = @"
WITH matched_users AS (
    SELECT
        u.id,
        u."userCode",
        u."fullName",
        u."mobileNumber",
        u.status
    FROM users u
    WHERE $predicate
)
"@

        Log "Matched user(s):" "DATA"
        $usersSql = @"
$cte
SELECT id, "userCode", "fullName", "mobileNumber", status
FROM matched_users
ORDER BY id;
"@
        [string[]]$users = @(Psql -Sql $usersSql -Machine)

        foreach ($row in $users) {
            Log $row "DATA"
        }

        Log "Customer membership(s):" "DATA"
        $membershipsSql = @"
$cte
SELECT
    cm.id,
    cm."customerId",
    cm.status,
    cm."isPrimary",
    cm."joinedAt",
    cm."endedAt"
FROM customer_memberships cm
JOIN matched_users u ON u.id = cm."userId"
ORDER BY cm.status, cm."isPrimary" DESC;
"@
        [string[]]$memberships = @(Psql -Sql $membershipsSql -Machine)

        foreach ($row in $memberships) {
            Log $row "DATA"
        }

        Log "Role assignment(s):" "DATA"
        $rolesSql = @"
$cte
SELECT
    ra.id,
    r.code,
    r.status,
    ra.status,
    ra."scopeType",
    ra."scopeId",
    ra."effectiveFrom",
    ra."effectiveUntil",
    EXISTS (
        SELECT 1
        FROM role_permissions rp
        JOIN permissions p ON p.id = rp."permissionId"
        WHERE rp."roleId" = r.id
          AND p.code = 'vehicle.view'
          AND p.status = 'ACTIVE'
    ) AS has_vehicle_view
FROM role_assignments ra
JOIN matched_users u ON u.id = ra."userId"
JOIN roles r ON r.id = ra."roleId"
ORDER BY ra.status, r.code;
"@
        [string[]]$roles = @(Psql -Sql $rolesSql -Machine)

        foreach ($row in $roles) {
            Log $row "DATA"
        }

        if (@($roles).Length -eq 0) {
            Log (
                "No role assignment exists for the matched user. " +
                "Customer membership alone does not grant permissions."
            ) "FAIL"
        }

        Log "Candidate ACTIVE roles that grant vehicle.view:" "DATA"
        $candidateRoleSql = @"
SELECT
    r.code,
    r.name,
    r.status,
    COUNT(DISTINCT rp."permissionId") AS permission_count
FROM roles r
JOIN role_permissions rp ON rp."roleId" = r.id
JOIN permissions p ON p.id = rp."permissionId"
WHERE r.status = 'ACTIVE'
  AND p.status = 'ACTIVE'
  AND p.code = 'vehicle.view'
GROUP BY r.id, r.code, r.name, r.status
ORDER BY r.code;
"@
        [string[]]$candidateRoles = @(
            Psql -Sql $candidateRoleSql -Machine
        )

        if (@($candidateRoles).Length -eq 0) {
            Log (
                "No ACTIVE role currently grants vehicle.view. " +
                "The role-permission configuration must be repaired first."
            ) "FAIL"
        }
        else {
            foreach ($candidateRole in $candidateRoles) {
                Log $candidateRole "DATA"
            }
        }

        $countsSql = @"
$cte,
effective_assignments AS (
    SELECT ra.*
    FROM role_assignments ra
    JOIN matched_users u ON u.id = ra."userId"
    JOIN roles r ON r.id = ra."roleId"
    WHERE ra.status = 'ACTIVE'
      AND r.status = 'ACTIVE'
      AND ra."effectiveFrom" <= NOW()
      AND (
          ra."effectiveUntil" IS NULL
          OR ra."effectiveUntil" > NOW()
      )
),
vehicle_view AS (
    SELECT DISTINCT
        ea.id,
        ea."userId",
        ea."scopeType",
        ea."scopeId"
    FROM effective_assignments ea
    JOIN role_permissions rp ON rp."roleId" = ea."roleId"
    JOIN permissions p ON p.id = rp."permissionId"
    WHERE p.code = 'vehicle.view'
      AND p.status = 'ACTIVE'
)
SELECT
    (SELECT COUNT(*) FROM matched_users),
    (
        SELECT COUNT(*)
        FROM customer_memberships cm
        JOIN matched_users u ON u.id = cm."userId"
        WHERE cm.status = 'ACTIVE'
    ),
    (SELECT COUNT(*) FROM effective_assignments),
    (SELECT COUNT(*) FROM vehicle_view),
    (
        SELECT COUNT(*)
        FROM vehicle_view vv
        WHERE vv."scopeType" = 'CUSTOMER'
          AND EXISTS (
              SELECT 1
              FROM customer_memberships cm
              WHERE cm."userId" = vv."userId"
                AND cm.status = 'ACTIVE'
                AND cm."customerId" = vv."scopeId"
          )
    ),
    (
        SELECT COUNT(*)
        FROM vehicle_view vv
        WHERE vv."scopeType" = 'CUSTOMER'
          AND NOT EXISTS (
              SELECT 1
              FROM customer_memberships cm
              WHERE cm."userId" = vv."userId"
                AND cm.status = 'ACTIVE'
                AND cm."customerId" = vv."scopeId"
          )
    );
"@
        # PowerShell 5.1 unwraps a single pipeline result into a scalar.
        # Force array semantics so .Count and [0] work reliably.
        [string[]]$counts = @(Psql -Sql $countsSql -Machine)

        $values = @(0,0,0,0,0,0)

        if (@($counts).Length -gt 0) {
            $parts = @($counts[0].Split("|"))

            for ($i = 0; $i -lt $values.Length; $i++) {
                if ($i -lt $parts.Length) {
                    $parsed = 0
                    [void][int]::TryParse($parts[$i], [ref]$parsed)
                    $values[$i] = $parsed
                }
            }
        }

        Log "Matched users: $($values[0])" "DATA"
        Log "ACTIVE customer memberships: $($values[1])" "DATA"
        Log "Effective role assignments: $($values[2])" "DATA"
        Log "Effective vehicle.view grants: $($values[3])" "DATA"
        Log "Matching CUSTOMER scope grants: $($values[4])" "DATA"
        Log "Mismatching CUSTOMER scope grants: $($values[5])" "DATA"

        if ($values[0] -eq 1) {
            Log "Exactly one user matched." "PASS"
        }
        elseif ($values[0] -eq 0) {
            Log "No user matched. Check spelling or add -MobileNumber." "FAIL"
        }
        else {
            Log "Multiple users matched. Add -MobileNumber." "WARN"
        }

        if ($values[1] -gt 0) {
            Log "ACTIVE customer membership exists." "PASS"
        }
        else {
            Log "No ACTIVE customer membership exists." "FAIL"
        }

        if ($values[3] -gt 0) {
            Log "Database grants effective vehicle.view." "PASS"
        }
        else {
            Log "Database does not grant effective vehicle.view." "FAIL"
        }

        if ($values[5] -gt 0) {
            Log "CUSTOMER role scope does not match ACTIVE membership." "WARN"
        }
        elseif ($values[4] -gt 0) {
            Log "CUSTOMER role scope matches ACTIVE membership." "PASS"
        }

        Log "Permission catalog:" "DATA"
        $permissionSql = @"
SELECT id, code, name, status
FROM permissions
WHERE code = 'vehicle.view';
"@
        [string[]]$permission = @(Psql -Sql $permissionSql -Machine)

        foreach ($row in $permission) {
            Log $row "DATA"
        }

        Section "6. OPTIONAL END-TO-END AUTH / BFF / ASSET AUDIT"

        $token = $AccessToken
        $password = $null
        $createdBackendSession = $false
        $apiAudited = $false
        $apiHasVehicleView = $false
        $bffAudited = $false
        $bffSessionHasVehicleView = $false
        $bffAssetsStatus = 0
        $CustomerWebSession = $null

        if ($PromptForLogin) {
            if (-not $MobileNumber) {
                throw "-PromptForLogin requires -MobileNumber."
            }

            $password = Secure-PasswordText
        }

        if (-not $token -and $password) {
            $body = @{
                mobileNumber = $MobileNumber
                password = $password
                platform = "WEB"
                deviceName = "Permission Audit"
                appVersion = "local-audit"
            } | ConvertTo-Json

            $login = Invoke-RestMethod `
                -Uri "$Backend/auth/login" `
                -Method Post `
                -ContentType "application/json" `
                -Body $body `
                -TimeoutSec 15

            $token = [string]$login.accessToken
            $createdBackendSession = $true
            Log "Direct backend login succeeded." "PASS"
        }

        if ($token) {
            $headers = @{
                Authorization = "Bearer $token"
                Accept = "application/json"
            }

            $me = Invoke-RestMethod `
                -Uri "$Backend/auth/me" `
                -Headers $headers `
                -TimeoutSec 12

            $mine = Invoke-RestMethod `
                -Uri "$Backend/permissions/me" `
                -Headers $headers `
                -TimeoutSec 12

            $apiAudited = $true
            $apiPermissions = @(
                $mine.permissions |
                ForEach-Object { [string]$_ }
            )
            $apiHasVehicleView = $apiPermissions -contains "vehicle.view"

            Log "Backend userId: $($me.userId)" "DATA"
            Log "Backend customerIds: $(@($me.customerIds) -join ', ')" "DATA"
            Log "Backend permissions: $($apiPermissions -join ', ')" "DATA"

            if ($apiHasVehicleView) {
                Log "Backend authenticated context contains vehicle.view." "PASS"
            }
            else {
                Log "Backend authenticated context is missing vehicle.view." "FAIL"
            }
        }
        else {
            Log "Direct backend auth audit skipped." "WARN"
        }

        if ($password) {
            try {
                $bffBody = @{
                    mobileNumber = $MobileNumber
                    password = $password
                    rememberMe = $true
                } | ConvertTo-Json

                $bffLogin = Invoke-RestMethod `
                    -Uri "$Web/api/auth/login" `
                    -Method Post `
                    -ContentType "application/json" `
                    -Body $bffBody `
                    -SessionVariable CustomerWebSession `
                    -TimeoutSec 20

                Log "BFF authenticated: $($bffLogin.authenticated)" "DATA"
                Log "BFF workspace: $($bffLogin.workspace)" "DATA"
                Log "BFF redirect: $($bffLogin.redirectTo)" "DATA"

                $bffSession = Invoke-RestMethod `
                    -Uri "$Web/api/auth/session" `
                    -Method Get `
                    -WebSession $CustomerWebSession `
                    -TimeoutSec 20

                $bffAudited = $true
                $sessionPermissions = @()

                if (
                    $null -ne $bffSession.PSObject.Properties["user"] -and
                    $null -ne $bffSession.user -and
                    $null -ne $bffSession.user.PSObject.Properties["permissions"]
                ) {
                    $sessionPermissions = @(
                        $bffSession.user.permissions |
                        ForEach-Object { [string]$_ }
                    )
                }
                elseif (
                    $null -ne $bffSession.PSObject.Properties["permissions"]
                ) {
                    $sessionPermissions = @(
                        $bffSession.permissions |
                        ForEach-Object { [string]$_ }
                    )
                }

                $bffSessionHasVehicleView = (
                    $sessionPermissions -contains "vehicle.view"
                )

                Log "BFF session authenticated: $($bffSession.authenticated)" "DATA"
                Log "BFF session workspace: $($bffSession.workspace)" "DATA"
                Log "BFF session permissions: $($sessionPermissions -join ', ')" "DATA"

                if ($bffSessionHasVehicleView) {
                    Log "Web BFF session contains vehicle.view." "PASS"
                }
                else {
                    Log "Web BFF session is missing vehicle.view." "FAIL"
                }

                try {
                    $assetsResponse = Invoke-WebRequest `
                        -Uri "$Web/api/customer/assets?page=1&pageSize=100" `
                        -Method Get `
                        -WebSession $CustomerWebSession `
                        -UseBasicParsing `
                        -TimeoutSec 20

                    $bffAssetsStatus = [int]$assetsResponse.StatusCode
                    $assetCount = "unknown"

                    try {
                        $assetPayload = $assetsResponse.Content |
                            ConvertFrom-Json

                        if (
                            $null -ne $assetPayload.PSObject.Properties["items"]
                        ) {
                            $assetCount = @($assetPayload.items).Length
                        }
                    }
                    catch {
                        # Status is still useful even if response parsing fails.
                    }

                    Log "Customer assets HTTP: $bffAssetsStatus" "DATA"
                    Log "Customer assets item count: $assetCount" "DATA"

                    if ($bffAssetsStatus -eq 200) {
                        Log "Authenticated BFF customer-assets request passed." "PASS"
                    }
                    else {
                        Log "Authenticated BFF customer-assets request returned HTTP $bffAssetsStatus." "FAIL"
                    }
                }
                catch {
                    if ($null -ne $_.Exception.Response) {
                        try {
                            $bffAssetsStatus = [int]$_.Exception.Response.StatusCode
                        }
                        catch {
                            $bffAssetsStatus = 0
                        }
                    }

                    Log (
                        "Authenticated BFF customer-assets request failed. " +
                        "HTTP $bffAssetsStatus - $($_.Exception.Message)"
                    ) "FAIL"
                }
            }
            finally {
                try {
                    if ($null -ne $CustomerWebSession) {
                        Invoke-RestMethod `
                            -Uri "$Web/api/auth/logout" `
                            -Method Post `
                            -WebSession $CustomerWebSession `
                            -TimeoutSec 10 |
                            Out-Null
                    }
                }
                catch {
                    Log "Could not revoke the temporary BFF audit session." "WARN"
                }

                $password = $null
            }
        }
        else {
            Log (
                "Web BFF/session/assets audit skipped. Use -MobileNumber " +
                "and -PromptForLogin."
            ) "WARN"
        }

        if ($createdBackendSession -and $token) {
            try {
                Invoke-RestMethod `
                    -Uri "$Backend/auth/logout" `
                    -Method Post `
                    -Headers @{
                        Authorization = "Bearer $token"
                    } `
                    -TimeoutSec 10 |
                    Out-Null

                Log "Temporary backend audit session revoked." "PASS"
            }
            catch {
                Log "Could not revoke the temporary backend audit session." "WARN"
            }
        }

        Section "7. DIAGNOSIS"

        $dbHasVehicleView = $values[3] -gt 0

        if (-not $dbHasVehicleView) {
            Log (
                "ROOT CAUSE: database role/permission assignment is not " +
                "currently effective."
            ) "FAIL"
        }
        elseif ($apiAudited -and -not $apiHasVehicleView) {
            Log (
                "ROOT CAUSE AREA: backend AccessControl context or backend " +
                "database/config mismatch."
            ) "FAIL"
        }
        elseif (
            $apiHasVehicleView -and
            $bffAudited -and
            -not $bffSessionHasVehicleView
        ) {
            Log (
                "ROOT CAUSE: web BFF server-session mapping drops " +
                "vehicle.view even though backend /auth/me returns it."
            ) "FAIL"
        }
        elseif (
            $bffSessionHasVehicleView -and
            $bffAssetsStatus -ne 200
        ) {
            Log (
                "ROOT CAUSE AREA: customer-assets BFF proxy, cookie forwarding, " +
                "or upstream tracking authorization."
            ) "FAIL"
        }
        elseif (
            $apiHasVehicleView -and
            $bffSessionHasVehicleView -and
            $bffAssetsStatus -eq 200
        ) {
            Log (
                "Fresh backend and BFF sessions work correctly. The browser " +
                "is likely using an older cookie/session or an older web " +
                "development process. Sign out, clear localhost:3001 site " +
                "data, restart the web process, and log in again."
            ) "WARN"
        }
        elseif ($apiAudited -and $apiHasVehicleView) {
            Log (
                "Backend context is correct. Run with -PromptForLogin to test " +
                "the web BFF session and customer-assets proxy."
            ) "WARN"
        }
        else {
            Log (
                "Database is correct. Run the deep authenticated audit command " +
                "to isolate backend, BFF session, and asset proxy."
            ) "WARN"
        }

        Section "AUDIT COMPLETE"
        Log "Report: $report" "PASS"

        if ($PromptForLogin) {
            Log (
                "No role, permission, membership, asset, configuration, or " +
                "source-code data was changed. Temporary authentication " +
                "sessions and normal auth-audit records may have been created."
            ) "WARN"
        }
        else {
            Log "No database or source-code changes were made." "PASS"
        }

        Log "Deep audit command:" "INFO"

        if ($MobileNumber) {
            Log (
                "powershell.exe -NoProfile -ExecutionPolicy Bypass " +
                "-File `"$PSCommandPath`" -CustomerName `"$CustomerName`" " +
                "-MobileNumber `"$MobileNumber`" -PromptForLogin -OpenReport"
            ) "DATA"
        }
        else {
            Log (
                "powershell.exe -NoProfile -ExecutionPolicy Bypass " +
                "-File `"$PSCommandPath`" -CustomerName `"$CustomerName`" " +
                "-MobileNumber `"<CUSTOMER_MOBILE>`" -PromptForLogin -OpenReport"
            ) "DATA"
        }

        if ($OpenReport) {
            Start-Process notepad.exe $report | Out-Null
        }
    }
    catch {
        try {
            Section "AUDIT FAILED"
            Log $_.Exception.Message "FAIL"

            if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
                Log (
                    "Script line: $($_.InvocationInfo.ScriptLineNumber); " +
                    "statement: $($_.InvocationInfo.Line.Trim())"
                ) "FAIL"
            }

            Log "Audit script version: $AuditScriptVersion" "DATA"
            Log "Partial report: $report" "WARN"
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
        }

        exit 1
    }
}
