[CmdletBinding()]
param(
    [string]$RepositoryPath = "D:\GitHub\gps-tracker-platform"
)

$ErrorActionPreference = "Stop"

function Get-LfContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.File]::ReadAllText($Path).Replace(
        "`r`n",
        "`n"
    )
}

function Set-LfContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $Path,
        $Content.Replace("`r`n", "`n"),
        $utf8NoBom
    )
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

function Get-AppliedMigrationCount {
    $sql = @'
SELECT COUNT(*)
FROM "_prisma_migrations"
WHERE finished_at IS NOT NULL
  AND rolled_back_at IS NULL;
'@

    $output = $sql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Could not query the applied migration count."
    }

    return [int](($output | Out-String).Trim())
}

function Add-TokenServiceImport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $importLine =
        "import { TokenService } from '../src/identity/common/token.service';"

    if ($Content.Contains($importLine)) {
        Write-Host (
            "[UNCHANGED] $Description already imports TokenService."
        ) -ForegroundColor DarkGreen

        return $Content
    }

    $marker =
        "import { PasswordService } from '../src/identity/common/password.service';"

    $markerCount = (
        [regex]::Matches(
            $Content,
            [regex]::Escape($marker)
        )
    ).Count

    if ($markerCount -ne 1) {
        throw (
            "Expected exactly one PasswordService import in ${Description}, " +
            "but found $markerCount."
        )
    }

    Write-Host (
        "[UPDATED] $Description imports TokenService."
    ) -ForegroundColor Green

    return $Content.Replace(
        $marker,
        $marker + "`n" + $importLine
    )
}

function Add-TokenServiceLookup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $lookupLine =
        "    const tokenService = app.get(TokenService);"

    if ($Content.Contains($lookupLine)) {
        Write-Host (
            "[UNCHANGED] $Description already resolves TokenService."
        ) -ForegroundColor DarkGreen

        return $Content
    }

    $marker =
        "    const passwordService = app.get(PasswordService);"

    $markerCount = (
        [regex]::Matches(
            $Content,
            [regex]::Escape($marker)
        )
    ).Count

    if ($markerCount -ne 1) {
        throw (
            "Expected exactly one PasswordService lookup in ${Description}, " +
            "but found $markerCount."
        )
    }

    Write-Host (
        "[UPDATED] $Description resolves TokenService."
    ) -ForegroundColor Green

    return $Content.Replace(
        $marker,
        $marker + "`n" + $lookupLine
    )
}

function Replace-FormattedLoginBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $directSessionMarker =
        "tokenService.hashRefreshToken(refreshToken)"

    if ($Content.Contains($directSessionMarker)) {
        Write-Host (
            "[UNCHANGED] $Description already uses an audit-safe direct session."
        ) -ForegroundColor DarkGreen

        return $Content
    }

    $pattern = @'
(?ms)^[ \t]{4}const loginResponse\s*=.*?^[ \t]{4}accessToken\s*=\s*.*?;\s*(?=\n)
'@

    $matches = [regex]::Matches(
        $Content,
        $pattern
    )

    if ($matches.Count -ne 1) {
        $startCount = (
            [regex]::Matches(
                $Content,
                '(?m)^[ \t]{4}const loginResponse\s*='
            )
        ).Count
        $accessTokenCount = (
            [regex]::Matches(
                $Content,
                '(?m)^[ \t]{4}accessToken\s*='
            )
        ).Count

        throw (
            "Expected one formatted login/access-token block in ${Description}, " +
            "but matched $($matches.Count). " +
            "loginResponseStarts=$startCount accessTokenAssignments=$accessTokenCount."
        )
    }

    $replacement = @'
    const refreshToken =
      tokenService.createRefreshToken();
    const session = await prisma.userSession.create({
      data: {
        userId,
        tokenFamilyId: randomUUID(),
        refreshTokenHash:
          tokenService.hashRefreshToken(refreshToken),
        platform: 'ANDROID',
        deviceName: 'Mobile API E2E',
        appVersion: 'test',
        expiresAt: tokenService.getRefreshExpiry(),
      },
    });

    accessToken =
      await tokenService.signAccessToken(
        userId,
        session.id,
      );

'@

    Write-Host (
        "[UPDATED] $Description replaces HTTP login with an audit-safe test session."
    ) -ForegroundColor Green

    return [regex]::Replace(
        $Content,
        $pattern,
        $replacement.Replace("`r`n", "`n"),
        1
    )
}

function Patch-MobileE2EContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $Content = Add-TokenServiceImport `
        -Content $Content `
        -Description $Description

    $Content = Add-TokenServiceLookup `
        -Content $Content `
        -Description $Description

    return Replace-FormattedLoginBlock `
        -Content $Content `
        -Description $Description
}

function Ensure-RecoveryGitAddEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $recoveryLine =
        '        "scripts/solid-tracker-mobile-api-recovery.ps1" `'

    if ($Content.Contains($recoveryLine)) {
        return $Content
    }

    $gitAddMarker = "    git add -- ``"
    $foundationLine =
        '        "scripts/solid-tracker-mobile-api.ps1" `'

    $gitAddIndex = $Content.IndexOf(
        $gitAddMarker,
        [System.StringComparison]::Ordinal
    )

    if ($gitAddIndex -lt 0) {
        throw "The final git add block was not found."
    }

    $foundationIndex = $Content.IndexOf(
        $foundationLine,
        $gitAddIndex,
        [System.StringComparison]::Ordinal
    )

    if ($foundationIndex -lt 0) {
        throw "The mobile foundation git-add entry was not found."
    }

    $insertAt =
        $foundationIndex +
        $foundationLine.Length

    return (
        $Content.Substring(0, $insertAt) +
        "`n" +
        $recoveryLine +
        $Content.Substring($insertAt)
    )
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Mobile Formatted Login Recovery" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found."
    }

    $currentBranch = (
        (git branch --show-current) |
            Out-String
    ).Trim()

    if ($currentBranch -ne "feat/mobile-api") {
        throw (
            "Expected branch feat/mobile-api, " +
            "but current branch is $currentBranch."
        )
    }

    Write-Host "[1/6] Confirming immutable migration state" -ForegroundColor Yellow

    $migrationCount = Get-AppliedMigrationCount

    if ($migrationCount -ne 6) {
        throw (
            "Expected exactly 6 applied migrations, " +
            "but found $migrationCount."
        )
    }

    Write-Host "Applied migrations: 6" -ForegroundColor Green
    Write-Host "Migration changes:   none required" -ForegroundColor Green

    $testPath = Join-Path `
        $RepositoryPath `
        "services\backend-api\test\mobile-api.e2e-spec.ts"

    $foundationPath = Join-Path `
        $RepositoryPath `
        "scripts\solid-tracker-mobile-api.ps1"

    foreach ($requiredPath in @(
        $testPath,
        $foundationPath
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file was not found: $requiredPath"
        }
    }

    Write-Host "[2/6] Patching the formatted mobile E2E login block" -ForegroundColor Yellow

    $testContent = Get-LfContent $testPath
    $testContent = Patch-MobileE2EContent `
        -Content $testContent `
        -Description "services/backend-api/test/mobile-api.e2e-spec.ts"

    Set-LfContent `
        -Path $testPath `
        -Content $testContent

    Write-Host "[3/6] Synchronizing the reproducible mobile foundation" -ForegroundColor Yellow

    $foundationContent = Get-LfContent $foundationPath
    $foundationContent = Patch-MobileE2EContent `
        -Content $foundationContent `
        -Description "scripts/solid-tracker-mobile-api.ps1"

    $foundationContent =
        Ensure-RecoveryGitAddEntry $foundationContent

    foreach ($banner in @(
        " Solid Tracker - Customer Mobile API Platform v7",
        " Solid Tracker - Customer Mobile API Platform v6",
        " Solid Tracker - Customer Mobile API Platform v5",
        " Solid Tracker - Customer Mobile API Platform v4",
        " Solid Tracker - Customer Mobile API Platform v3",
        " Solid Tracker - Customer Mobile API Platform v2",
        " Solid Tracker - Customer Mobile API Platform"
    )) {
        if ($foundationContent.Contains($banner)) {
            $foundationContent = $foundationContent.Replace(
                $banner,
                " Solid Tracker - Customer Mobile API Platform v8"
            )
            break
        }
    }

    Set-LfContent `
        -Path $foundationPath `
        -Content $foundationContent

    Write-Host (
        "[UPDATED] scripts/solid-tracker-mobile-api.ps1"
    ) -ForegroundColor Green

    Write-Host "[4/6] Running focused TypeScript verification" -ForegroundColor Yellow

    Invoke-CheckedCommand "Backend format" {
        pnpm.cmd --filter "@solid-tracker/backend-api" format
    }

    Invoke-CheckedCommand "Backend lint" {
        pnpm.cmd --filter "@solid-tracker/backend-api" lint
    }

    Invoke-CheckedCommand "Backend typecheck" {
        pnpm.cmd --filter "@solid-tracker/backend-api" typecheck
    }

    Write-Host "[5/6] Running focused mobile E2E verification" -ForegroundColor Yellow

    Invoke-CheckedCommand "Mobile API E2E test" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec node `
            --experimental-vm-modules `
            ./node_modules/jest/bin/jest.js `
            --config ./test/jest-e2e.json `
            test/mobile-api.e2e-spec.ts `
            --runInBand
    }

    Write-Host "[6/6] Resuming complete mobile API verification" -ForegroundColor Yellow
    Write-Host ""

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $foundationPath `
        -RepositoryPath $RepositoryPath

    if ($LASTEXITCODE -ne 0) {
        throw (
            "The mobile API stage stopped with exit code " +
            "$LASTEXITCODE."
        )
    }

    exit 0
}
catch {
    Write-Host ""
    Write-Host "MOBILE FORMATTED LOGIN RECOVERY FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "Do not reset, delete, rename, or edit any of the six applied migrations."
    ) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    exit 1
}
