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

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $hash = $sha256.ComputeHash($Bytes)

        return (
            [System.BitConverter]::ToString($hash)
        ).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-NewlineSequences {
    param(
        [int]$MinimumLength,
        [int]$MaximumLength
    )

    $results = New-Object System.Collections.Generic.List[string]
    $tokens = @("`n", "`r`n")

    function Expand-NewlineSequence {
        param(
            [string]$Current,
            [int]$Depth,
            [int]$TargetDepth
        )

        if ($Depth -eq $TargetDepth) {
            $results.Add($Current)
            return
        }

        foreach ($token in $tokens) {
            Expand-NewlineSequence `
                -Current ($Current + $token) `
                -Depth ($Depth + 1) `
                -TargetDepth $TargetDepth
        }
    }

    for ($length = $MinimumLength; $length -le $MaximumLength; $length++) {
        Expand-NewlineSequence `
            -Current "" `
            -Depth 0 `
            -TargetDepth $length
    }

    return $results
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-Host $Description -ForegroundColor DarkCyan
    & $Command

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed."
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Migration Checksum Recovery v3" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath
    $rootPath = (Get-Location).Path

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found."
    }

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -ne "feat/vehicle-device-foundation") {
        throw (
            "Expected branch feat/vehicle-device-foundation, " +
            "but current branch is $currentBranch"
        )
    }

    $phase2ScriptRelativePath =
        "scripts/solid-tracker-vehicle-device-foundation.ps1"

    $recoveryScriptRelativePath =
        "scripts/solid-tracker-phase1-migration-checksum-recovery.ps1"

    foreach ($requiredPath in @(
        ".env",
        $phase2ScriptRelativePath,
        "services/backend-api/prisma.config.ts",
        "services/backend-api/prisma/schema.prisma",
        "services/backend-api/prisma/migrations"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file or directory is missing: $requiredPath"
        }
    }

    $allowedStatusEntries = @(
        "?? $phase2ScriptRelativePath",
        "?? $recoveryScriptRelativePath"
    )

    $unexpectedChanges = @(
        git status --short |
            Where-Object {
                $_ -and
                $allowedStatusEntries -notcontains $_.TrimEnd()
            }
    )

    if ($unexpectedChanges.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        $unexpectedChanges | ForEach-Object {
            Write-Host $_ -ForegroundColor Yellow
        }

        throw (
            "Recovery stopped because unrelated working-tree changes " +
            "were found."
        )
    }

    Write-Step 1 6 `
        "Identifying the applied Phase 1 migration and stored checksum"

    $phase1Migration = Get-ChildItem `
        -LiteralPath "services/backend-api/prisma/migrations" `
        -Directory |
        Where-Object {
            $_.Name -like "*_identity_customer_foundation"
        } |
        Select-Object -First 1

    if (-not $phase1Migration) {
        throw (
            "The applied identity/customer migration directory " +
            "was not found."
        )
    }

    $migrationName = $phase1Migration.Name
    $migrationSqlPath = Join-Path `
        $phase1Migration.FullName `
        "migration.sql"

    if (-not (Test-Path -LiteralPath $migrationSqlPath)) {
        throw "The Phase 1 migration.sql file was not found."
    }

    $checksumSql = @"
SELECT checksum
FROM "_prisma_migrations"
WHERE migration_name = '$migrationName';
"@

    $checksumOutput = $checksumSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw (
            "Could not read the applied migration checksum " +
            "from PostgreSQL."
        )
    }

    $databaseChecksum = (
        $checksumOutput |
            Out-String
    ).Trim().ToLowerInvariant()

    if ($databaseChecksum -notmatch "^[0-9a-f]{64}$") {
        throw (
            "Unexpected migration checksum returned by PostgreSQL: " +
            $databaseChecksum
        )
    }

    $currentBytes = [System.IO.File]::ReadAllBytes($migrationSqlPath)
    $currentChecksum = Get-Sha256Hex -Bytes $currentBytes

    Write-Host "Migration:         $migrationName" -ForegroundColor Green
    Write-Host "Database checksum: $databaseChecksum" -ForegroundColor Green
    Write-Host "Current checksum:  $currentChecksum" -ForegroundColor Yellow

    Write-Step 2 6 `
        "Reconstructing the exact migration bytes originally applied"

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $textOffset = 0

    if (
        $currentBytes.Length -ge 3 -and
        $currentBytes[0] -eq 0xEF -and
        $currentBytes[1] -eq 0xBB -and
        $currentBytes[2] -eq 0xBF
    ) {
        $textOffset = 3
    }

    $migrationText = $strictUtf8.GetString(
        $currentBytes,
        $textOffset,
        $currentBytes.Length - $textOffset
    )

    $normalized = $migrationText.
        Replace("`r`n", "`n").
        Replace("`r", "`n")

    $marker = (
        "-- Solid Tracker Phase 1 invariants that require " +
        "PostgreSQL-native constraints."
    )

    $markerIndex = $normalized.IndexOf(
        $marker,
        [System.StringComparison]::Ordinal
    )

    if ($markerIndex -lt 0) {
        throw "Could not find the Phase 1 custom SQL marker."
    }

    $baseCore = $normalized.
        Substring(0, $markerIndex).
        TrimEnd("`n")

    $customCore = $normalized.
        Substring($markerIndex).
        Trim("`n")

    $newlineStyles = @(
        [pscustomobject]@{
            Name  = "LF"
            Value = "`n"
        },
        [pscustomobject]@{
            Name  = "CRLF"
            Value = "`r`n"
        }
    )

    $separators = Get-NewlineSequences `
        -MinimumLength 1 `
        -MaximumLength 5

    $trailers = @("") + @(
        Get-NewlineSequences `
            -MinimumLength 1 `
            -MaximumLength 4
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $bomCharacter = [string][char]0xFEFF

    $matchingBytes = $null
    $matchingName = $null
    $candidateCount = 0

    if ($currentChecksum -eq $databaseChecksum) {
        $matchingBytes = $currentBytes
        $matchingName = "current bytes"
    }
    else {
        :SearchCandidates foreach ($baseStyle in $newlineStyles) {
            $baseText = $baseCore.Replace(
                "`n",
                $baseStyle.Value
            )

            foreach ($customStyle in $newlineStyles) {
                $customText = $customCore.Replace(
                    "`n",
                    $customStyle.Value
                )

                foreach ($separator in $separators) {
                    foreach ($trailer in $trailers) {
                        foreach ($startBom in @($false, $true)) {
                            foreach (
                                $embeddedBom in @($false, $true)
                            ) {
                                $startPrefix = ""

                                if ($startBom) {
                                    $startPrefix = $bomCharacter
                                }

                                $embeddedPrefix = ""

                                if ($embeddedBom) {
                                    $embeddedPrefix = $bomCharacter
                                }

                                $candidateText = (
                                    $startPrefix +
                                    $baseText +
                                    $separator +
                                    $embeddedPrefix +
                                    $customText +
                                    $trailer
                                )

                                $candidateBytes =
                                    $utf8NoBom.GetBytes($candidateText)

                                $candidateChecksum =
                                    Get-Sha256Hex `
                                        -Bytes $candidateBytes

                                $candidateCount++

                                if (
                                    $candidateChecksum -eq
                                    $databaseChecksum
                                ) {
                                    $matchingBytes =
                                        $candidateBytes

                                    $matchingName = (
                                        "base={0}; custom={1}; " +
                                        "separatorBytes={2}; " +
                                        "trailerBytes={3}; " +
                                        "startBom={4}; " +
                                        "embeddedBom={5}"
                                    ) -f
                                        $baseStyle.Name,
                                        $customStyle.Name,
                                        $utf8NoBom.
                                            GetByteCount($separator),
                                        $utf8NoBom.
                                            GetByteCount($trailer),
                                        $startBom,
                                        $embeddedBom

                                    break SearchCandidates
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if ($null -eq $matchingBytes) {
        throw (
            "No line-ending/BOM reconstruction matched the applied " +
            "checksum. Database was not changed. Candidate count: " +
            $candidateCount
        )
    }

    [System.IO.File]::WriteAllBytes(
        $migrationSqlPath,
        $matchingBytes
    )

    $restoredBytes = [System.IO.File]::ReadAllBytes(
        $migrationSqlPath
    )

    $restoredChecksum = Get-Sha256Hex `
        -Bytes $restoredBytes

    if ($restoredChecksum -ne $databaseChecksum) {
        throw (
            "The restored migration checksum does not match " +
            "PostgreSQL."
        )
    }

    Write-Host "Matched representation:" -ForegroundColor Green
    Write-Host $matchingName -ForegroundColor DarkGreen
    Write-Host (
        "Applied migration bytes restored exactly."
    ) -ForegroundColor Green

    Write-Step 3 6 `
        "Protecting migration SQL from future line-ending conversion"

    $attributesPath = Join-Path $rootPath ".gitattributes"

    $attributeLine = (
        "services/backend-api/prisma/migrations/**/" +
        "migration.sql -text"
    )

    if (Test-Path -LiteralPath $attributesPath) {
        $attributesContent = [System.IO.File]::ReadAllText(
            $attributesPath
        )

        $attributeLines = $attributesContent -split "\r?\n"

        if ($attributeLines -notcontains $attributeLine) {
            if (
                $attributesContent.Length -gt 0 -and
                -not $attributesContent.EndsWith("`n")
            ) {
                $attributesContent += "`n"
            }

            $attributesContent += $attributeLine + "`n"

            Write-Utf8NoBomFile `
                -Path $attributesPath `
                -Content $attributesContent
        }
    }
    else {
        Write-Utf8NoBomFile `
            -Path $attributesPath `
            -Content ($attributeLine + "`n")
    }

    Invoke-CheckedCommand "Verify Prisma migration history" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    Write-Step 4 6 `
        "Committing the migration-preservation repair"

    git add -- `
        ".gitattributes" `
        "services/backend-api/prisma/migrations/$migrationName/migration.sql" `
        $recoveryScriptRelativePath

    git commit `
        -m "fix(database): preserve applied migration checksums"

    if ($LASTEXITCODE -ne 0) {
        throw "Migration-preservation commit failed."
    }

    Write-Host (
        "The checksum stored in PostgreSQL was not edited."
    ) -ForegroundColor Green

    Write-Host (
        "The migration file now matches the exact bytes already applied."
    ) -ForegroundColor Green

    Write-Step 5 6 `
        "Resuming the vehicle and device foundation"

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File ".\scripts\solid-tracker-vehicle-device-foundation.ps1"

    if ($LASTEXITCODE -ne 0) {
        throw (
            "The resumed vehicle/device foundation script failed."
        )
    }

    Write-Step 6 6 "Confirming final repository state"

    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current

    Write-Host ""
    Write-Host "Recent commits:" -ForegroundColor Yellow
    git log --oneline --decorate --graph -5

    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Migration Recovery and Phase 2 Completed" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    exit 0
}
catch {
    Write-Host ""
    Write-Host "MIGRATION CHECKSUM RECOVERY FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    Write-Host (
        "No Prisma migration checksum was changed in PostgreSQL."
    ) -ForegroundColor Yellow

    Write-Host "Do not run prisma migrate reset." -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    exit 1
}
