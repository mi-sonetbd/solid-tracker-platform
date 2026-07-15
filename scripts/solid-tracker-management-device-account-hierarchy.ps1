[CmdletBinding()]
param(
    [string]$RepoRoot = "D:\GitHub\gps-tracker-platform"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptName = "Solid Tracker - Management Device Account Hierarchy, Transfer, and Bulk Intake"
$SourceBranch = "feat/management-monitor-account-hierarchy"
$TargetBranch = "feat/management-device-account-hierarchy"
$ExpectedSourceCommit = "ee21629"
$BackendPackageName = "@solid-tracker/backend-api"
$WebPackageName = "@solid-tracker/web-panel"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$WebRoot = Join-Path $RepoRoot "apps\web-panel"
$StopScriptPath = Join-Path $RepoRoot "scripts\dev-stop.ps1"
$DevScriptPath = Join-Path $RepoRoot "scripts\dev.ps1"
$RepoScriptPath = Join-Path $RepoRoot "scripts\solid-tracker-management-device-account-hierarchy.ps1"

$LogDirectory = Join-Path $env:LOCALAPPDATA "SolidTrackerLogs"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDirectory "management-device-account-hierarchy-$Timestamp.log"

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

$AllowedPaths = @(
    "services/backend-api/src/assets/common/asset-query.dto.ts",
    "services/backend-api/src/assets/devices/devices.controller.ts",
    "services/backend-api/src/assets/devices/devices.service.ts",
    "services/backend-api/src/assets/devices/dto/bulk-register-devices.dto.ts",
    "services/backend-api/src/assets/devices/dto/transfer-devices.dto.ts",
    "apps/web-panel/src/app/(management)/management/device/page.tsx",
    "apps/web-panel/src/app/api/management/devices/route.ts",
    "apps/web-panel/src/app/api/management/devices/bulk/route.ts",
    "apps/web-panel/src/app/api/management/devices/transfer/route.ts",
    "apps/web-panel/src/components/management/bulk-device-stock-intake-modal.tsx",
    "apps/web-panel/src/components/management/device-management-workspace.tsx",
    "apps/web-panel/src/components/management/device-sell-move-modal.tsx",
    "apps/web-panel/src/lib/management/asset-types.ts",
    "apps/web-panel/src/lib/management/assets-backend.ts",
    "docs/frontend/management-device-account-hierarchy.md",
    "scripts/solid-tracker-management-device-account-hierarchy.ps1"
)

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Ok {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $display = $FilePath

    if ($Arguments.Length -gt 0) {
        $display += " " + ($Arguments -join " ")
    }

    Write-Host "> $display" -ForegroundColor DarkGray
    & $FilePath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $display"
    }
}

function Get-ChangedPaths {
    $lines = @(
        & git status `
            --porcelain `
            --untracked-files=all
    )

    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect Git repository status."
    }

    $paths = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line.Length -lt 4) {
            throw "Unexpected Git status entry: $line"
        }

        $path = $line.Substring(3).Trim()

        if ($path.Contains(" -> ")) {
            $path = ($path -split " -> ", 2)[1]
        }

        $paths.Add($path.Replace("\", "/")) | Out-Null
    }

    return $paths.ToArray()
}

function Assert-RepositoryState {
    param([Parameter(Mandatory = $true)][string]$Branch)

    $changedPaths = @(Get-ChangedPaths)

    if ($Branch -eq $SourceBranch) {
        if ($changedPaths.Length -gt 0) {
            Write-Host "Repository changes:" -ForegroundColor Yellow

            foreach ($path in $changedPaths) {
                Write-Host " - $path" -ForegroundColor Yellow
            }

            throw "The source branch must be clean before this feature starts."
        }

        return
    }

    $unexpected = @(
        $changedPaths |
        Where-Object { $AllowedPaths -notcontains $_ }
    )

    if ($unexpected.Length -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        foreach ($path in $unexpected) {
            Write-Host " - $path" -ForegroundColor Yellow
        }

        throw "Only interrupted Management Device feature files may be modified."
    }

    if ($changedPaths.Length -gt 0) {
        Write-Warn "Expected interrupted feature changes were found and will be preserved."
    }
}

function Assert-CleanRepository {
    $changedPaths = @(Get-ChangedPaths)

    if ($changedPaths.Length -gt 0) {
        Write-Host "Remaining repository changes:" -ForegroundColor Yellow

        foreach ($path in $changedPaths) {
            Write-Host " - $path" -ForegroundColor Yellow
        }

        throw "Repository is not clean after the feature commit."
    }
}

function Read-LfFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $fullPath = Join-Path $RepoRoot $RelativePath

    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Required file is missing: $RelativePath"
    }

    return [System.IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $fullPath = Join-Path $RepoRoot $RelativePath
    $parent = Split-Path -Parent $fullPath

    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $fullPath,
        $Content.Replace("`r`n", "`n"),
        $encoding
    )
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$ExpectedText
    )

    $content = Read-LfFile -RelativePath $RelativePath

    if (-not $content.Contains($ExpectedText)) {
        throw "Required implementation marker was not found in $RelativePath"
    }
}

function Replace-Required {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $count = (
        [regex]::Matches(
            $Content,
            [regex]::Escape($OldText)
        )
    ).Count

    if ($count -ne 1) {
        throw (
            "Expected exactly one patch target for $Description, " +
            "but found $count."
        )
    }

    return $Content.Replace($OldText, $NewText)
}

function Replace-RegexOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $matches = $regex.Matches($Content)

    if ($matches.Count -ne 1) {
        throw (
            "Expected exactly one regex patch target for $Description, " +
            "but found $($matches.Count)."
        )
    }

    return $regex.Replace($Content, $Replacement, 1)
}

function Insert-Before {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Marker,
        [Parameter(Mandatory = $true)][string]$Insertion,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $index = $Content.IndexOf(
        $Marker,
        [System.StringComparison]::Ordinal
    )

    if ($index -lt 0) {
        throw "Could not find insertion marker for $Description"
    }

    return (
        $Content.Substring(0, $index) +
        $Insertion +
        $Content.Substring($index)
    )
}

function Remove-StaleNextState {
    foreach ($lockPath in @(
        (Join-Path $WebRoot ".next\dev\lock"),
        (Join-Path $WebRoot ".next\lock")
    )) {
        if (Test-Path -LiteralPath $lockPath) {
            & attrib.exe -R -H -S $lockPath 2>$null
            Remove-Item -LiteralPath $lockPath -Force
            Write-Ok "Removed stale Next.js lock: $lockPath"
        }
    }

    $nextPath = Join-Path $WebRoot ".next"

    if (Test-Path -LiteralPath $nextPath) {
        Remove-Item -LiteralPath $nextPath -Recurse -Force
    }
}

function Test-DockerEngine {
    & docker info --format "{{.ServerVersion}}" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Stage-ExpectedFiles {
    foreach ($path in $AllowedPaths) {
        if (Test-Path -LiteralPath (Join-Path $RepoRoot $path)) {
            Invoke-Native "git" @("add", "--", $path)
        }
    }

    $unexpected = @(
        Get-ChangedPaths |
        Where-Object { $AllowedPaths -notcontains $_ }
    )

    if ($unexpected.Length -gt 0) {
        Write-Host "Unexpected changes after verification:" -ForegroundColor Yellow

        foreach ($path in $unexpected) {
            Write-Host " - $path" -ForegroundColor Yellow
        }

        throw "Unexpected files changed during verification."
    }
}

Set-Location $RepoRoot
Start-Transcript -Path $LogFile | Out-Null

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " $ScriptName" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Section "1. Repository and Contract Safety"

    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) {
        throw "Solid Tracker Git repository was not found: $RepoRoot"
    }

    foreach ($requiredPath in @(
        $StopScriptPath,
        $DevScriptPath,
        (Join-Path $RepoRoot "services\backend-api\prisma\schema.prisma"),
        (Join-Path $RepoRoot "services\backend-api\src\assets\common\asset-query.dto.ts"),
        (Join-Path $RepoRoot "services\backend-api\src\assets\devices\devices.controller.ts"),
        (Join-Path $RepoRoot "services\backend-api\src\assets\devices\devices.service.ts"),
        (Join-Path $RepoRoot "services\backend-api\test\vehicle-device.e2e-spec.ts"),
        (Join-Path $RepoRoot "apps\web-panel\src\components\management\management-monitor-account-tree.tsx"),
        (Join-Path $RepoRoot "apps\web-panel\src\lib\management\use-management-monitor-hierarchy.ts"),
        (Join-Path $RepoRoot "apps\web-panel\src\lib\management\monitor-types.ts"),
        (Join-Path $RepoRoot "apps\web-panel\src\lib\management\management-bff-session.ts"),
        (Join-Path $RepoRoot "apps\web-panel\src\lib\management\asset-types.ts"),
        (Join-Path $RepoRoot "apps\web-panel\src\lib\management\assets-backend.ts"),
        (Join-Path $RepoRoot "apps\web-panel\src\components\management\add-device-model-modal.tsx"),
        (Join-Path $RepoRoot "apps\web-panel\src\components\management\device-stock-intake-modal.tsx")
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required project file is missing: $requiredPath"
        }
    }

    Invoke-Native "git" @("rev-parse", "--is-inside-work-tree")

    $currentBranch = (& git branch --show-current).Trim()

    if ($LASTEXITCODE -ne 0) {
        throw "Could not determine the active Git branch."
    }

    if (
        $currentBranch -ne $SourceBranch -and
        $currentBranch -ne $TargetBranch
    ) {
        throw (
            "Expected branch '$SourceBranch' or '$TargetBranch', " +
            "but current branch is '$currentBranch'."
        )
    }

    Assert-RepositoryState -Branch $currentBranch

    if ($currentBranch -eq $SourceBranch) {
        $headShort = (& git rev-parse --short=7 HEAD).Trim()

        if (-not $headShort.StartsWith($ExpectedSourceCommit)) {
            throw (
                "Expected source commit '$ExpectedSourceCommit', " +
                "but HEAD is '$headShort'."
            )
        }
    }

    Assert-Contains `
        -RelativePath "apps/web-panel/src/components/management/management-monitor-account-tree.tsx" `
        -ExpectedText "export function ManagementMonitorAccountTree"

    Assert-Contains `
        -RelativePath "apps/web-panel/src/lib/management/use-management-monitor-hierarchy.ts" `
        -ExpectedText "export function useManagementMonitorHierarchy"

    Assert-Contains `
        -RelativePath "services/backend-api/src/assets/devices/devices.service.ts" `
        -ExpectedText "async allocate("

    Assert-Contains `
        -RelativePath "services/backend-api/src/assets/devices/devices.service.ts" `
        -ExpectedText "action: 'device.registered'"

    Assert-Contains `
        -RelativePath "services/backend-api/src/assets/devices/devices.controller.ts" `
        -ExpectedText "@Post(':deviceId/allocate')"

    Assert-Contains `
        -RelativePath "services/backend-api/prisma/schema.prisma" `
        -ExpectedText "ownerCustomerId"

    Assert-Contains `
        -RelativePath "services/backend-api/prisma/schema.prisma" `
        -ExpectedText "custodianCustomerId"

    Write-Ok "Clean source, account hierarchy, and lifecycle contracts verified."

    Write-Section "2. Stop Live Development and Clean Next.js State"

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $StopScriptPath

    if ($LASTEXITCODE -ne 0) {
        throw "The tracked live-development session could not be stopped."
    }

    Remove-StaleNextState
    Write-Ok "Development processes and Next.js state are clean."

    Write-Section "3. Activate Feature Branch"

    if ($currentBranch -eq $TargetBranch) {
        Write-Ok "Feature branch is already active."
    }
    else {
        & git show-ref --verify --quiet "refs/heads/$TargetBranch"

        if ($LASTEXITCODE -eq 0) {
            Invoke-Native "git" @("switch", $TargetBranch)
        }
        elseif ($LASTEXITCODE -eq 1) {
            Invoke-Native "git" @("switch", "-c", $TargetBranch)
        }
        else {
            throw "Could not inspect the target feature branch."
        }
    }

    $activeBranch = (& git branch --show-current).Trim()

    if ($activeBranch -ne $TargetBranch) {
        throw "Could not activate branch '$TargetBranch'."
    }

    if ($PSCommandPath -and $PSCommandPath -ne $RepoScriptPath) {
        Copy-Item `
            -LiteralPath $PSCommandPath `
            -Destination $RepoScriptPath `
            -Force
    }

    Write-Ok "Feature branch active: $TargetBranch"

    Write-Section "4. Add Backend Bulk and Transfer DTOs"

    Write-Utf8File "services/backend-api/src/assets/devices/dto/bulk-register-devices.dto.ts" @'
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class BulkRegisterDevicesDto {
  @ApiProperty()
  @IsUUID()
  deviceModelId!: string;

  @ApiProperty({
    type: String,
    isArray: true,
    description: 'One IMEI per item. Each line is validated independently.',
  })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(250)
  @IsString({ each: true })
  @MaxLength(32, { each: true })
  imeis!: string[];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  hardwareVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  firmwareVersion?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  receivedAt?: string;
}
'@

    Write-Utf8File "services/backend-api/src/assets/devices/dto/transfer-devices.dto.ts" @'
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

const transferTargetTypes = ['DEALER', 'CUSTOMER'] as const;

export class TransferDevicesDto {
  @ApiProperty({
    type: String,
    isArray: true,
  })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @IsUUID('4', { each: true })
  deviceIds!: string[];

  @ApiProperty({ enum: transferTargetTypes })
  @IsIn(transferTargetTypes)
  targetType!: (typeof transferTargetTypes)[number];

  @ApiProperty()
  @IsUUID()
  targetId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}
'@

    Write-Ok "Bulk intake and lifecycle-safe transfer DTOs created."

    Write-Section "5. Extend Device Query Scope"

    $queryPath = "services/backend-api/src/assets/common/asset-query.dto.ts"
    $queryContent = Read-LfFile -RelativePath $queryPath

    if (-not $queryContent.Contains("directCustomers?: boolean;")) {
        $queryContent = Replace-Required `
            -Content $queryContent `
            -OldText @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
'@ `
            -NewText @'
import { Transform } from 'class-transformer';
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsUUID,
} from 'class-validator';
'@ `
            -Description "Device query validation imports"

        $queryContent = Replace-Required `
            -Content $queryContent `
            -OldText @'
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dealerOrganizationId?: string;

  @ApiPropertyOptional({ enum: deviceStatuses })
'@ `
            -NewText @'
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dealerOrganizationId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  directCustomers?: boolean;

  @ApiPropertyOptional({ enum: deviceStatuses })
'@ `
            -Description "Customer and Direct Customer Device filters"

        Write-Utf8File -RelativePath $queryPath -Content $queryContent
    }

    Write-Ok "Device listing accepts Dealer, Customer, and Direct Customer scope filters."

    Write-Section "6. Add Backend Bulk Registration and Sell/Move Operations"

    $controllerPath =
        "services/backend-api/src/assets/devices/devices.controller.ts"
    $controller = Read-LfFile -RelativePath $controllerPath

    if (-not $controller.Contains("@Post('bulk')")) {
        $controller = Replace-Required `
            -Content $controller `
            -OldText @'
import { AllocateDeviceDto } from './dto/allocate-device.dto';
'@ `
            -NewText @'
import { AllocateDeviceDto } from './dto/allocate-device.dto';
import { BulkRegisterDevicesDto } from './dto/bulk-register-devices.dto';
'@ `
            -Description "Bulk Device DTO import"

        $controller = Replace-Required `
            -Content $controller `
            -OldText @'
import { ReturnDeviceDto } from './dto/return-device.dto';
'@ `
            -NewText @'
import { ReturnDeviceDto } from './dto/return-device.dto';
import { TransferDevicesDto } from './dto/transfer-devices.dto';
'@ `
            -Description "Transfer Device DTO import"

        $controller = Insert-Before `
            -Content $controller `
            -Marker @'
  @Get(':deviceId')
'@ `
            -Insertion @'
  @Post('bulk')
  @RequirePermissions('device.register')
  @ApiOperation({
    summary: 'Register multiple platform stock devices with per-IMEI results',
  })
  bulkRegister(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: BulkRegisterDevicesDto,
  ) {
    return this.devicesService.bulkRegister(auth, dto);
  }

  @Post('transfer')
  @RequirePermissions('device.remove')
  @ApiOperation({
    summary: 'Sell or move eligible devices to a scoped Dealer or Customer',
  })
  transfer(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: TransferDevicesDto,
  ) {
    return this.devicesService.transfer(auth, dto);
  }

'@ `
            -Description "Static bulk and transfer routes"

        Write-Utf8File -RelativePath $controllerPath -Content $controller
    }

    $servicePath =
        "services/backend-api/src/assets/devices/devices.service.ts"
    $service = Read-LfFile -RelativePath $servicePath

    if (-not $service.Contains("BulkRegisterDevicesDto")) {
        $service = Replace-Required `
            -Content $service `
            -OldText @'
import type { AllocateDeviceDto } from './dto/allocate-device.dto';
'@ `
            -NewText @'
import type { AllocateDeviceDto } from './dto/allocate-device.dto';
import type { BulkRegisterDevicesDto } from './dto/bulk-register-devices.dto';
'@ `
            -Description "Bulk DTO service import"

        $service = Replace-Required `
            -Content $service `
            -OldText @'
import type { ReturnDeviceDto } from './dto/return-device.dto';
'@ `
            -NewText @'
import type { ReturnDeviceDto } from './dto/return-device.dto';
import type { TransferDevicesDto } from './dto/transfer-devices.dto';
'@ `
            -Description "Transfer DTO service import"
    }

    if (-not $service.Contains("this.listScopeWhere(query),")) {
        $service = Replace-RegexOnce `
            -Content $service `
            -Pattern "(?s)        query\.dealerOrganizationId\s*\?.*?          : \{\}," `
            -Replacement "        this.listScopeWhere(query)," `
            -Description "Scoped Device list predicate"
    }

    if (-not $service.Contains("async bulkRegister(")) {
        $service = Insert-Before `
            -Content $service `
            -Marker @'
  async allocate(
'@ `
            -Insertion @'
  async bulkRegister(
    auth: AuthContext,
    dto: BulkRegisterDevicesDto,
  ) {
    this.access.assertPlatform(auth);

    const seen = new Set<string>();
    const results: Array<{
      imei: string;
      status: 'CREATED' | 'ERROR';
      device?: unknown;
      message?: string;
    }> = [];

    for (const rawImei of dto.imeis) {
      const imei = rawImei.trim();

      if (!/^\d{14,17}$/.test(imei)) {
        results.push({
          imei,
          status: 'ERROR',
          message: 'IMEI must contain 14 to 17 digits.',
        });
        continue;
      }

      if (seen.has(imei)) {
        results.push({
          imei,
          status: 'ERROR',
          message: 'Duplicate IMEI exists in this request.',
        });
        continue;
      }

      seen.add(imei);

      try {
        const device = await this.register(auth, {
          deviceModelId: dto.deviceModelId,
          imei,
          hardwareVersion: dto.hardwareVersion,
          firmwareVersion: dto.firmwareVersion,
          receivedAt: dto.receivedAt,
        });

        results.push({
          imei,
          status: 'CREATED',
          device,
        });
      } catch (error) {
        results.push({
          imei,
          status: 'ERROR',
          message:
            error instanceof Error
              ? error.message
              : 'Device registration failed.',
        });
      }
    }

    const created = results.filter(
      (result) => result.status === 'CREATED',
    ).length;

    return {
      total: results.length,
      created,
      failed: results.length - created,
      results,
    };
  }

  async transfer(
    auth: AuthContext,
    dto: TransferDevicesDto,
  ) {
    const deviceIds = Array.from(new Set(dto.deviceIds));

    if (deviceIds.length !== dto.deviceIds.length) {
      throw new BadRequestException(
        'The transfer request contains duplicate Device identifiers.',
      );
    }

    let targetCustomer: {
      id: string;
      status: string;
      managingDealerId: string | null;
    } | null = null;

    if (dto.targetType === 'DEALER') {
      this.access.assertDealer(auth, dto.targetId);

      const dealer = await this.prisma.organization.findFirst({
        where: {
          id: dto.targetId,
          type: 'DEALER',
          status: 'ACTIVE',
        },
        select: {
          id: true,
        },
      });

      if (!dealer) {
        throw new BadRequestException(
          'An active destination Dealer is required.',
        );
      }
    } else {
      const customer =
        await this.access.assertCustomerMutation(
          auth,
          dto.targetId,
        );

      if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
        throw new BadRequestException(
          'The destination Customer must be active or pending.',
        );
      }

      targetCustomer = {
        id: customer.id,
        status: customer.status,
        managingDealerId:
          customer.managingDealerId,
      };
    }

    const devices = await this.prisma.device.findMany({
      where: {
        AND: [
          {
            id: {
              in: deviceIds,
            },
          },
          this.access.deviceWhere(auth),
        ],
      },
      include: {
        vehicleAssignments: {
          where: {
            status: 'ACTIVE',
          },
        },
      },
    });

    if (devices.length !== deviceIds.length) {
      throw new NotFoundException(
        'One or more Devices were not found within the authenticated scope.',
      );
    }

    const blocked = devices.filter(
      (device) =>
        device.vehicleAssignments.length > 0 ||
        !['RECEIVED', 'IN_STOCK', 'ALLOCATED'].includes(
          device.lifecycleStatus,
        ),
    );

    if (blocked.length > 0) {
      throw new ConflictException(
        'Installed, assigned, damaged, lost, repaired, or retired Devices cannot be moved.',
      );
    }

    const now = new Date();
    const notes = this.optional(dto.notes);

    await this.prisma.$transaction(
      async (transaction) => {
        for (const device of devices) {
          await transaction.dealerDeviceAllocation.updateMany({
            where: {
              deviceId: device.id,
              status: {
                in: [...activeAllocationStatuses],
              },
            },
            data: {
              status: 'RETURNED',
              returnedAt: now,
              returnedByUserId: auth.userId,
            },
          });

          await this.endCurrentOwnership(
            transaction,
            device.id,
            now,
          );

          await this.endCurrentCustody(
            transaction,
            device.id,
            now,
          );

          if (dto.targetType === 'DEALER') {
            await transaction.deviceOwnershipHistory.create({
              data: {
                deviceId: device.id,
                ownerType: 'DEALER',
                ownerOrganizationId: dto.targetId,
                reason: 'TRANSFER',
                changedByUserId: auth.userId,
                notes,
                startedAt: now,
              },
            });

            await transaction.deviceCustodyHistory.create({
              data: {
                deviceId: device.id,
                custodianType: 'DEALER',
                custodianOrganizationId: dto.targetId,
                reason: 'TRANSFER',
                changedByUserId: auth.userId,
                notes,
                startedAt: now,
              },
            });

            await transaction.dealerDeviceAllocation.create({
              data: {
                allocationCode: this.codes.allocation(),
                dealerOrganizationId: dto.targetId,
                deviceId: device.id,
                status: 'AVAILABLE',
                allocatedAt: now,
                availableAt: now,
                allocatedByUserId: auth.userId,
                notes,
              },
            });
          } else {
            await transaction.deviceOwnershipHistory.create({
              data: {
                deviceId: device.id,
                ownerType: 'CUSTOMER',
                ownerCustomerId: dto.targetId,
                reason: 'TRANSFER',
                changedByUserId: auth.userId,
                notes,
                startedAt: now,
              },
            });

            await transaction.deviceCustodyHistory.create({
              data: {
                deviceId: device.id,
                custodianType: 'CUSTOMER',
                custodianCustomerId: dto.targetId,
                reason: 'TRANSFER',
                changedByUserId: auth.userId,
                notes,
                startedAt: now,
              },
            });

            if (targetCustomer?.managingDealerId) {
              await transaction.dealerDeviceAllocation.create({
                data: {
                  allocationCode: this.codes.allocation(),
                  dealerOrganizationId:
                    targetCustomer.managingDealerId,
                  deviceId: device.id,
                  status: 'AVAILABLE',
                  allocatedAt: now,
                  availableAt: now,
                  allocatedByUserId: auth.userId,
                  notes,
                },
              });
            }
          }

          await transaction.device.update({
            where: {
              id: device.id,
            },
            data: {
              lifecycleStatus: 'ALLOCATED',
            },
          });
        }
      },
    );

    const moved = await this.prisma.device.findMany({
      where: {
        id: {
          in: deviceIds,
        },
      },
      include: {
        deviceModel: true,
        ownershipHistory: {
          where: {
            endedAt: null,
          },
        },
        custodyHistory: {
          where: {
            endedAt: null,
          },
        },
        dealerAllocations: {
          where: {
            status: {
              in: [...activeAllocationStatuses],
            },
          },
          include: {
            dealerOrganization: {
              select: {
                id: true,
                code: true,
                name: true,
              },
            },
          },
        },
        vehicleAssignments: {
          where: {
            status: 'ACTIVE',
          },
          include: {
            vehicle: true,
          },
        },
      },
    });

    for (const device of moved) {
      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId:
          this.access.actorOrganizationId(auth),
        action: 'device.transferred',
        resourceType: 'Device',
        resourceId: device.id,
        scopeType: dto.targetType,
        scopeId: dto.targetId,
        afterData: device,
      });
    }

    return {
      items: moved,
      total: moved.length,
      targetType: dto.targetType,
      targetId: dto.targetId,
    };
  }

'@ `
            -Description "Bulk registration and sell/move services"
    }

    if (-not $service.Contains("private listScopeWhere(")) {
        $service = Insert-Before `
            -Content $service `
            -Marker @'
  private async endCurrentCustody(
'@ `
            -Insertion @'
  private listScopeWhere(
    query: DeviceQueryDto,
  ): Prisma.DeviceWhereInput {
    if (query.customerId) {
      return {
        OR: [
          {
            ownershipHistory: {
              some: {
                endedAt: null,
                ownerCustomerId: query.customerId,
              },
            },
          },
          {
            custodyHistory: {
              some: {
                endedAt: null,
                custodianCustomerId: query.customerId,
              },
            },
          },
          {
            vehicleAssignments: {
              some: {
                status: 'ACTIVE',
                vehicle: {
                  customerId: query.customerId,
                },
              },
            },
          },
        ],
      };
    }

    if (query.directCustomers) {
      return {
        OR: [
          {
            ownershipHistory: {
              some: {
                endedAt: null,
                ownerCustomer: {
                  is: {
                    managingDealerId: null,
                  },
                },
              },
            },
          },
          {
            custodyHistory: {
              some: {
                endedAt: null,
                custodianCustomer: {
                  is: {
                    managingDealerId: null,
                  },
                },
              },
            },
          },
          {
            vehicleAssignments: {
              some: {
                status: 'ACTIVE',
                vehicle: {
                  customer: {
                    managingDealerId: null,
                  },
                },
              },
            },
          },
        ],
      };
    }

    if (query.dealerOrganizationId) {
      return {
        dealerAllocations: {
          some: {
            dealerOrganizationId:
              query.dealerOrganizationId,
            status: {
              in: [...activeAllocationStatuses],
            },
          },
        },
      };
    }

    return {};
  }

  private async endCurrentOwnership(
    transaction: TransactionClient,
    deviceId: string,
    endedAt: Date,
  ): Promise<void> {
    await transaction.deviceOwnershipHistory.updateMany({
      where: {
        deviceId,
        endedAt: null,
      },
      data: {
        endedAt,
      },
    });
  }

'@ `
            -Description "Selected hierarchy list scope and ownership history helper"
    }

    Write-Utf8File -RelativePath $servicePath -Content $service
    Write-Ok "Backend Device list, bulk intake, transfer, ownership, custody, and audit operations added."

    Write-Section "7. Expand Frontend Asset Contracts and Backend Adapter"

    Write-Utf8File "apps/web-panel/src/lib/management/asset-types.ts" @'
export type VehicleType =
  | "CAR"
  | "MOTORCYCLE"
  | "BUS"
  | "TRUCK"
  | "CNG"
  | "PICKUP"
  | "MICROBUS"
  | "AMBULANCE"
  | "CONSTRUCTION_EQUIPMENT"
  | "OTHER";

export type DeviceNetworkType =
  | "GSM_2G"
  | "UMTS_3G"
  | "LTE_4G"
  | "LTE_5G"
  | "LORA"
  | "SATELLITE"
  | "OTHER";

export type DeviceModelSummary = {
  id: string;
  modelCode: string;
  manufacturer: string;
  modelName: string;
  protocol: string;
  networkType: DeviceNetworkType | null;
  capabilities?: Record<string, unknown> | null;
  status?: "ACTIVE" | "INACTIVE" | "ARCHIVED";
  createdAt?: string;
  updatedAt?: string;
  _count?: {
    devices: number;
  };
};

export type DeviceModelListResponse = {
  items: DeviceModelSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type CreateDeviceModelInput = {
  manufacturer: string;
  modelName: string;
  protocol: string;
  networkType: DeviceNetworkType;
  capabilities?: Record<string, unknown>;
};

export type DeviceAssignmentSummary = {
  id: string;
  status: string;
  assignmentType: string;
  startedAt: string;
  device: {
    id: string;
    deviceCode: string;
    imei: string | null;
    serialNumber: string | null;
    lifecycleStatus: string;
    firmwareVersion: string | null;
    deviceModel: DeviceModelSummary;
  };
};

export type VehicleSummary = {
  id: string;
  customerId: string;
  vehicleCode: string;
  vehicleType: VehicleType;
  registrationNumber: string | null;
  manufacturer: string | null;
  modelName: string | null;
  manufacturingYear: number | null;
  color: string | null;
  chassisNumber: string | null;
  engineNumber: string | null;
  status: string;
  createdAt: string;
  updatedAt: string;
  deviceAssignments: DeviceAssignmentSummary[];
};

export type VehicleListResponse = {
  items: VehicleSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type CreateVehicleInput = {
  customerId: string;
  vehicleType: VehicleType;
  registrationNumber?: string;
  manufacturer?: string;
  modelName?: string;
  manufacturingYear?: number;
  color?: string;
  chassisNumber?: string;
  engineNumber?: string;
};

export type DealerDeviceAllocationSummary = {
  id: string;
  allocationCode?: string;
  status: string;
  allocatedAt?: string;
  availableAt?: string | null;
  dealerOrganizationId: string;
  dealerOrganization: {
    id: string;
    code: string;
    name: string;
  };
};

export type DeviceOwnershipSummary = {
  id: string;
  ownerType: string;
  ownerOrganizationId: string | null;
  ownerCustomerId: string | null;
  startedAt?: string;
  endedAt?: string | null;
};

export type DeviceCustodySummary = {
  id: string;
  custodianType: string;
  custodianOrganizationId: string | null;
  custodianCustomerId: string | null;
  startedAt?: string;
  endedAt?: string | null;
};

export type DeviceVehicleAssignmentSummary = {
  id: string;
  status: string;
  vehicleId: string;
  vehicle?: {
    id: string;
    customerId: string;
    vehicleCode: string;
    registrationNumber: string | null;
  };
};

export type DeviceSummary = {
  id: string;
  deviceCode: string;
  deviceModelId: string;
  imei: string | null;
  serialNumber: string | null;
  hardwareVersion: string | null;
  firmwareVersion: string | null;
  lifecycleStatus: string;
  receivedAt?: string | null;
  retiredAt?: string | null;
  createdAt: string;
  updatedAt?: string;
  deviceModel: DeviceModelSummary;
  dealerAllocations?: DealerDeviceAllocationSummary[];
  vehicleAssignments?: DeviceVehicleAssignmentSummary[];
  ownershipHistory?: DeviceOwnershipSummary[];
  custodyHistory?: DeviceCustodySummary[];
};

export type DeviceListResponse = {
  items: DeviceSummary[];
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
};

export type RegisterDeviceInput = {
  deviceModelId: string;
  imei?: string;
  serialNumber?: string;
  hardwareVersion?: string;
  firmwareVersion?: string;
  receivedAt?: string;
};

export type BulkRegisterDevicesInput = {
  deviceModelId: string;
  imeis: string[];
  hardwareVersion?: string;
  firmwareVersion?: string;
  receivedAt?: string;
};

export type BulkDeviceRegistrationLineResult = {
  imei: string;
  status: "CREATED" | "ERROR";
  device?: DeviceSummary;
  message?: string;
};

export type BulkDeviceRegistrationResult = {
  total: number;
  created: number;
  failed: number;
  results: BulkDeviceRegistrationLineResult[];
};

export type TransferDevicesInput = {
  deviceIds: string[];
  targetType: "DEALER" | "CUSTOMER";
  targetId: string;
  notes?: string;
};

export type TransferDevicesResult = {
  items: DeviceSummary[];
  total: number;
  targetType: "DEALER" | "CUSTOMER";
  targetId: string;
};

export type AllocateDeviceInput = {
  dealerOrganizationId: string;
  notes?: string;
};

export type DealerDeviceAllocationResult = {
  id: string;
  allocationCode: string;
  dealerOrganizationId: string;
  deviceId: string;
  status: string;
  allocatedAt: string;
  availableAt: string | null;
  dealerOrganization: {
    id: string;
    code: string;
    name: string;
  };
  device: DeviceSummary;
};

export type InstallDeviceInput = {
  vehicleId: string;
  installedAt?: string;
  latitude?: number;
  longitude?: number;
  odometerReading?: number;
  powerConnectionType?: string;
  ignitionConnected?: boolean;
  relayConnected?: boolean;
  sosConnected?: boolean;
  installationNotes?: string;
};

export type DeviceInstallationResult = {
  id: string;
  installationCode: string;
  deviceId: string;
  vehicleId: string;
  status: string;
};
'@

    Write-Utf8File "apps/web-panel/src/lib/management/assets-backend.ts" @'
import "server-only";

import { authConfig } from "@/lib/auth/auth-config";
import type {
  AllocateDeviceInput,
  BulkDeviceRegistrationResult,
  BulkRegisterDevicesInput,
  CreateDeviceModelInput,
  CreateVehicleInput,
  DealerDeviceAllocationResult,
  DeviceInstallationResult,
  DeviceListResponse,
  DeviceModelListResponse,
  DeviceModelSummary,
  DeviceSummary,
  InstallDeviceInput,
  RegisterDeviceInput,
  TransferDevicesInput,
  TransferDevicesResult,
  VehicleListResponse,
  VehicleSummary,
} from "@/lib/management/asset-types";
import type { ManagementBackendResult } from "@/lib/management/dealer-types";

async function parseResponse(response: Response): Promise<unknown> {
  const text = await response.text();

  if (!text) return null;

  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text;
  }
}

function errorMessage(payload: unknown, fallback: string) {
  if (payload && typeof payload === "object" && "message" in payload) {
    const value = (payload as { message?: unknown }).message;

    if (Array.isArray(value)) {
      return value.filter((item) => typeof item === "string").join(" ");
    }

    if (typeof value === "string") {
      return value;
    }
  }

  return fallback;
}

async function assetRequest<T>(
  accessToken: string,
  path: string,
  init: RequestInit,
): Promise<ManagementBackendResult<T>> {
  try {
    const response = await fetch(`${authConfig.apiBaseUrl}${path}`, {
      ...init,
      cache: "no-store",
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${accessToken}`,
        ...init.headers,
      },
    });

    const payload = await parseResponse(response);

    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        message: errorMessage(
          payload,
          "The Solid Tracker Asset API rejected the request.",
        ),
        details: payload,
      };
    }

    return {
      ok: true,
      status: response.status,
      data: payload as T,
    };
  } catch (error) {
    return {
      ok: false,
      status: 503,
      message:
        error instanceof Error
          ? error.message
          : "The Solid Tracker Asset API is unavailable.",
    };
  }
}

export function backendListDeviceModels(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    search?: string;
  },
) {
  const parameters = new URLSearchParams({
    page: String(query.page),
    pageSize: String(query.pageSize),
  });

  if (query.search) parameters.set("search", query.search);

  return assetRequest<DeviceModelListResponse>(
    accessToken,
    `/device-models?${parameters.toString()}`,
    { method: "GET" },
  );
}

export function backendCreateDeviceModel(
  accessToken: string,
  input: CreateDeviceModelInput,
) {
  return assetRequest<DeviceModelSummary>(
    accessToken,
    "/device-models",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendListVehicles(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    customerId?: string;
    search?: string;
  },
) {
  const parameters = new URLSearchParams({
    page: String(query.page),
    pageSize: String(query.pageSize),
  });

  if (query.customerId) {
    parameters.set("customerId", query.customerId);
  }
  if (query.search) parameters.set("search", query.search);

  return assetRequest<VehicleListResponse>(
    accessToken,
    `/vehicles?${parameters.toString()}`,
    { method: "GET" },
  );
}

export function backendCreateVehicle(
  accessToken: string,
  input: CreateVehicleInput,
) {
  return assetRequest<VehicleSummary>(
    accessToken,
    "/vehicles",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendListDevices(
  accessToken: string,
  query: {
    page: number;
    pageSize: number;
    search?: string;
    lifecycleStatus?: string;
    deviceModelId?: string;
    dealerOrganizationId?: string;
    customerId?: string;
    directCustomers?: boolean;
  },
) {
  const parameters = new URLSearchParams({
    page: String(query.page),
    pageSize: String(query.pageSize),
  });

  if (query.search) parameters.set("search", query.search);
  if (query.lifecycleStatus) {
    parameters.set("lifecycleStatus", query.lifecycleStatus);
  }
  if (query.deviceModelId) {
    parameters.set("deviceModelId", query.deviceModelId);
  }
  if (query.dealerOrganizationId) {
    parameters.set(
      "dealerOrganizationId",
      query.dealerOrganizationId,
    );
  }
  if (query.customerId) {
    parameters.set("customerId", query.customerId);
  }
  if (query.directCustomers) {
    parameters.set("directCustomers", "true");
  }

  return assetRequest<DeviceListResponse>(
    accessToken,
    `/devices?${parameters.toString()}`,
    { method: "GET" },
  );
}

export function backendRegisterDevice(
  accessToken: string,
  input: RegisterDeviceInput,
) {
  return assetRequest<DeviceSummary>(
    accessToken,
    "/devices",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendBulkRegisterDevices(
  accessToken: string,
  input: BulkRegisterDevicesInput,
) {
  return assetRequest<BulkDeviceRegistrationResult>(
    accessToken,
    "/devices/bulk",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendTransferDevices(
  accessToken: string,
  input: TransferDevicesInput,
) {
  return assetRequest<TransferDevicesResult>(
    accessToken,
    "/devices/transfer",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendAllocateDevice(
  accessToken: string,
  deviceId: string,
  input: AllocateDeviceInput,
) {
  return assetRequest<DealerDeviceAllocationResult>(
    accessToken,
    `/devices/${deviceId}/allocate`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}

export function backendInstallDevice(
  accessToken: string,
  deviceId: string,
  input: InstallDeviceInput,
) {
  return assetRequest<DeviceInstallationResult>(
    accessToken,
    `/devices/${deviceId}/install`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    },
  );
}
'@

    Write-Ok "Frontend asset contracts preserve existing consumers and add bulk/transfer operations."

    Write-Section "8. Create Scoped Device BFF Routes"

    Write-Utf8File "apps/web-panel/src/app/api/management/devices/route.ts" @'
import { NextRequest } from "next/server";
import type { RegisterDeviceInput } from "@/lib/management/asset-types";
import {
  backendListDevices,
  backendRegisterDevice,
} from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const lifecycleStatuses = [
  "RECEIVED",
  "IN_STOCK",
  "RESERVED",
  "ALLOCATED",
  "INSTALLED",
  "UNDER_REPAIR",
  "LOST",
  "DAMAGED",
  "RETIRED",
] as const;

function positiveInteger(
  value: string | null,
  fallback: number,
  maximum: number,
) {
  const parsed = Number(value ?? fallback);

  if (!Number.isInteger(parsed) || parsed < 1 || parsed > maximum) {
    return fallback;
  }

  return parsed;
}

function optionalText(value: unknown, maximumLength: number) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("An inventory text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `An inventory field exceeds ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseDevice(payload: unknown): RegisterDeviceInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The stock intake request is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const deviceModelId = optionalText(value.deviceModelId, 36);
  const imei = optionalText(value.imei, 17);
  const serialNumber = optionalText(value.serialNumber, 100);
  const receivedAt = optionalText(value.receivedAt, 50);

  if (!deviceModelId || !uuidPattern.test(deviceModelId)) {
    throw new Error("Select a valid active Device Model.");
  }

  if (imei && !/^\d{14,17}$/.test(imei)) {
    throw new Error("IMEI must contain 14 to 17 digits.");
  }

  if (!imei && !serialNumber) {
    throw new Error(
      "Enter at least one device identity: IMEI or serial number.",
    );
  }

  if (receivedAt && Number.isNaN(new Date(receivedAt).getTime())) {
    throw new Error("Enter a valid received date and time.");
  }

  return {
    deviceModelId,
    imei,
    serialNumber,
    hardwareVersion: optionalText(value.hardwareVersion, 60),
    firmwareVersion: optionalText(value.firmwareVersion, 60),
    receivedAt: receivedAt
      ? new Date(receivedAt).toISOString()
      : undefined,
  };
}

function optionalUuid(
  request: NextRequest,
  name: string,
) {
  const value =
    request.nextUrl.searchParams.get(name)?.trim() || undefined;

  if (value && !uuidPattern.test(value)) {
    return null;
  }

  return value;
}

export async function GET(request: NextRequest) {
  const page = positiveInteger(
    request.nextUrl.searchParams.get("page"),
    1,
    100_000,
  );
  const pageSize = positiveInteger(
    request.nextUrl.searchParams.get("pageSize"),
    25,
    100,
  );
  const search =
    request.nextUrl.searchParams.get("search")?.trim().slice(0, 160) ||
    undefined;
  const lifecycleStatus =
    request.nextUrl.searchParams.get("lifecycleStatus")?.trim() ||
    undefined;
  const deviceModelId = optionalUuid(request, "deviceModelId");
  const dealerOrganizationId = optionalUuid(
    request,
    "dealerOrganizationId",
  );
  const customerId = optionalUuid(request, "customerId");

  if (
    deviceModelId === null ||
    dealerOrganizationId === null ||
    customerId === null
  ) {
    return managementJsonError(
      "A selected hierarchy or Device Model identifier is invalid.",
      400,
    );
  }

  if (
    lifecycleStatus &&
    !lifecycleStatuses.includes(
      lifecycleStatus as (typeof lifecycleStatuses)[number],
    )
  ) {
    return managementJsonError(
      "The selected lifecycle status is invalid.",
      400,
    );
  }

  const directCustomers =
    request.nextUrl.searchParams.get("directCustomers") === "true";

  return withManagementSession(request, (accessToken) =>
    backendListDevices(accessToken, {
      page,
      pageSize,
      search,
      lifecycleStatus,
      deviceModelId,
      dealerOrganizationId,
      customerId,
      directCustomers,
    }),
  );
}

export async function POST(request: NextRequest) {
  let input: RegisterDeviceInput;

  try {
    input = parseDevice(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The stock intake request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendRegisterDevice(accessToken, input),
  );
}
'@

    Write-Utf8File "apps/web-panel/src/app/api/management/devices/bulk/route.ts" @'
import { NextRequest } from "next/server";
import type { BulkRegisterDevicesInput } from "@/lib/management/asset-types";
import { backendBulkRegisterDevices } from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function optionalText(value: unknown, maximumLength: number) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error("A bulk intake text field is invalid.");
  }

  const normalized = value.trim();

  if (!normalized) return undefined;

  if (normalized.length > maximumLength) {
    throw new Error(
      `A bulk intake field exceeds ${maximumLength} characters.`,
    );
  }

  return normalized;
}

function parseInput(payload: unknown): BulkRegisterDevicesInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The bulk stock intake request is invalid.");
  }

  const value = payload as Record<string, unknown>;
  const deviceModelId = optionalText(value.deviceModelId, 36);

  if (!deviceModelId || !uuidPattern.test(deviceModelId)) {
    throw new Error("Select a valid active Device Model.");
  }

  if (
    !Array.isArray(value.imeis) ||
    value.imeis.length < 1 ||
    value.imeis.length > 250 ||
    value.imeis.some(
      (item) =>
        typeof item !== "string" ||
        item.length > 32,
    )
  ) {
    throw new Error(
      "Enter between 1 and 250 IMEI lines.",
    );
  }

  const receivedAt = optionalText(value.receivedAt, 50);

  if (receivedAt && Number.isNaN(new Date(receivedAt).getTime())) {
    throw new Error("Enter a valid received date and time.");
  }

  return {
    deviceModelId,
    imeis: value.imeis as string[],
    hardwareVersion: optionalText(value.hardwareVersion, 60),
    firmwareVersion: optionalText(value.firmwareVersion, 60),
    receivedAt: receivedAt
      ? new Date(receivedAt).toISOString()
      : undefined,
  };
}

export async function POST(request: NextRequest) {
  let input: BulkRegisterDevicesInput;

  try {
    input = parseInput(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The bulk stock intake request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendBulkRegisterDevices(accessToken, input),
  );
}
'@

    Write-Utf8File "apps/web-panel/src/app/api/management/devices/transfer/route.ts" @'
import { NextRequest } from "next/server";
import type { TransferDevicesInput } from "@/lib/management/asset-types";
import { backendTransferDevices } from "@/lib/management/assets-backend";
import {
  managementJsonError,
  withManagementSession,
} from "@/lib/management/management-bff-session";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function parseInput(payload: unknown): TransferDevicesInput {
  if (!payload || typeof payload !== "object") {
    throw new Error("The Device transfer request is invalid.");
  }

  const value = payload as Record<string, unknown>;

  if (
    !Array.isArray(value.deviceIds) ||
    value.deviceIds.length < 1 ||
    value.deviceIds.length > 100 ||
    value.deviceIds.some(
      (item) =>
        typeof item !== "string" ||
        !uuidPattern.test(item),
    )
  ) {
    throw new Error(
      "Select between 1 and 100 valid Devices.",
    );
  }

  if (
    value.targetType !== "DEALER" &&
    value.targetType !== "CUSTOMER"
  ) {
    throw new Error("Select a valid transfer target type.");
  }

  if (
    typeof value.targetId !== "string" ||
    !uuidPattern.test(value.targetId)
  ) {
    throw new Error("Select a valid transfer destination.");
  }

  const notes =
    typeof value.notes === "string"
      ? value.notes.trim().slice(0, 1000) || undefined
      : undefined;

  return {
    deviceIds: value.deviceIds as string[],
    targetType: value.targetType,
    targetId: value.targetId,
    notes,
  };
}

export async function POST(request: NextRequest) {
  let input: TransferDevicesInput;

  try {
    input = parseInput(await request.json());
  } catch (error) {
    return managementJsonError(
      error instanceof Error
        ? error.message
        : "The Device transfer request is invalid.",
      400,
    );
  }

  return withManagementSession(request, (accessToken) =>
    backendTransferDevices(accessToken, input),
  );
}
'@

    Write-Ok "Authenticated BFF routes expose authoritative pagination, bulk intake, and transfers."

    Write-Section "9. Create Bulk Stock Intake Modal"

    Write-Utf8File "apps/web-panel/src/components/management/bulk-device-stock-intake-modal.tsx" @'
"use client";

import {
  CheckCircle2,
  CircleAlert,
  LoaderCircle,
  PackagePlus,
  ShieldCheck,
  X,
} from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";
import type {
  BulkDeviceRegistrationResult,
  BulkRegisterDevicesInput,
  DeviceModelSummary,
} from "@/lib/management/asset-types";
import type { ManagementApiError } from "@/lib/management/dealer-types";

type BulkDeviceStockIntakeModalProps = {
  models: DeviceModelSummary[];
  onClose: () => void;
  onCompleted: (
    result: BulkDeviceRegistrationResult,
  ) => void;
};

function currentLocalDateTime() {
  const date = new Date();
  const offset = date.getTimezoneOffset() * 60_000;

  return new Date(date.getTime() - offset)
    .toISOString()
    .slice(0, 16);
}

export function BulkDeviceStockIntakeModal({
  models,
  onClose,
  onCompleted,
}: BulkDeviceStockIntakeModalProps) {
  const activeModels = useMemo(
    () =>
      models.filter(
        (model) =>
          !model.status || model.status === "ACTIVE",
      ),
    [models],
  );
  const [deviceModelId, setDeviceModelId] = useState(
    activeModels[0]?.id ?? "",
  );
  const [imeiText, setImeiText] = useState("");
  const [hardwareVersion, setHardwareVersion] =
    useState("");
  const [firmwareVersion, setFirmwareVersion] =
    useState("");
  const [receivedAt, setReceivedAt] = useState(
    currentLocalDateTime(),
  );
  const [result, setResult] =
    useState<BulkDeviceRegistrationResult | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const enteredLines = imeiText.split(/\r?\n/);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setResult(null);

    if (!deviceModelId) {
      setError("Create or select an active Device Model first.");
      return;
    }

    if (!enteredLines.some((line) => line.trim())) {
      setError("Enter at least one IMEI.");
      return;
    }

    if (enteredLines.length > 250) {
      setError("A maximum of 250 IMEI lines is allowed per batch.");
      return;
    }

    const input: BulkRegisterDevicesInput = {
      deviceModelId,
      imeis: enteredLines,
      hardwareVersion: hardwareVersion.trim() || undefined,
      firmwareVersion: firmwareVersion.trim() || undefined,
      receivedAt: receivedAt || undefined,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        "/api/management/devices/bulk",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const payload = (await response.json()) as
        | BulkDeviceRegistrationResult
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in payload
            ? payload.message
            : "Bulk Device intake failed.",
        );
        return;
      }

      const completed =
        payload as BulkDeviceRegistrationResult;

      setResult(completed);
      onCompleted(completed);
    } catch {
      setError(
        "The web panel could not reach the bulk Device intake service.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2700] grid place-items-center bg-[#17345f]/50 p-5"
      role="presentation"
      onMouseDown={(event) => {
        if (
          event.target === event.currentTarget &&
          !submitting
        ) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="bulk-device-intake-title"
        className="flex max-h-[94vh] w-full max-w-[880px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <PackagePlus className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.12em]">
                Platform Stock
              </span>
            </div>
            <h2
              id="bulk-device-intake-title"
              className="mt-2 text-[18px] font-semibold text-[#2b4065]"
            >
              Bulk Import Devices
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              Select one model and enter one IMEI per line.
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close bulk Device intake"
            className="text-[#71819c]"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form
          onSubmit={submit}
          className="st-scrollbar overflow-y-auto p-6"
        >
          <div className="grid gap-4 md:grid-cols-2">
            <label className="text-[10px] font-semibold text-[#52698e]">
              Device Model
              <select
                value={deviceModelId}
                onChange={(event) =>
                  setDeviceModelId(event.target.value)
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[11px] outline-none"
              >
                <option value="">Select Device Model</option>
                {activeModels.map((model) => (
                  <option key={model.id} value={model.id}>
                    {model.manufacturer} {model.modelName} · {model.protocol}
                  </option>
                ))}
              </select>
            </label>

            <label className="text-[10px] font-semibold text-[#52698e]">
              Received date and time
              <input
                type="datetime-local"
                value={receivedAt}
                onChange={(event) =>
                  setReceivedAt(event.target.value)
                }
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[11px] outline-none"
              />
            </label>

            <label className="text-[10px] font-semibold text-[#52698e]">
              Hardware version
              <input
                value={hardwareVersion}
                onChange={(event) =>
                  setHardwareVersion(event.target.value)
                }
                maxLength={60}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[11px] outline-none"
                placeholder="Optional shared hardware version"
              />
            </label>

            <label className="text-[10px] font-semibold text-[#52698e]">
              Firmware version
              <input
                value={firmwareVersion}
                onChange={(event) =>
                  setFirmwareVersion(event.target.value)
                }
                maxLength={60}
                className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] px-3 text-[11px] outline-none"
                placeholder="Optional shared firmware version"
              />
            </label>
          </div>

          <label className="mt-5 block text-[10px] font-semibold text-[#52698e]">
            IMEI list
            <textarea
              value={imeiText}
              onChange={(event) =>
                setImeiText(event.target.value)
              }
              rows={11}
              className="mt-2 w-full rounded-[4px] border border-[#cfd8e7] px-3 py-3 font-mono text-[11px] leading-6 outline-none"
              placeholder={"867123456789012\n867123456789013\n867123456789014"}
            />
          </label>

          <div className="mt-3 flex items-center justify-between text-[10px] text-[#71819c]">
            <span>{enteredLines.length} line(s)</span>
            <span>14–17 digits per valid IMEI · maximum 250</span>
          </div>

          <div className="mt-5 flex items-start gap-2 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
            <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
            The backend normalizes whitespace, reports malformed and duplicate
            lines independently, rejects existing IMEIs through the database
            uniqueness contract, and records an audit entry for every created
            Device.
          </div>

          {error ? (
            <p className="mt-4 rounded-[4px] bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
              {error}
            </p>
          ) : null}

          {result ? (
            <section className="mt-5 rounded-[5px] border border-[#dfe6ef]">
              <header className="flex items-center justify-between border-b border-[#e2e8f1] px-4 py-3 text-[11px] font-semibold text-[#344b72]">
                <span>
                  Created {result.created} · Failed {result.failed}
                </span>
                <span>Total {result.total}</span>
              </header>
              <div className="st-scrollbar max-h-56 overflow-y-auto">
                {result.results.map((line, index) => (
                  <div
                    key={`${line.imei}-${index}`}
                    className="flex items-start gap-3 border-b border-[#eef2f7] px-4 py-2 text-[10px]"
                  >
                    {line.status === "CREATED" ? (
                      <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
                    ) : (
                      <CircleAlert className="mt-0.5 h-4 w-4 shrink-0 text-red-600" />
                    )}
                    <span className="w-36 shrink-0 font-mono text-[#344b72]">
                      {line.imei || "(blank)"}
                    </span>
                    <span className="text-[#71819c]">
                      {line.status === "CREATED"
                        ? line.device?.deviceCode ?? "Created"
                        : line.message ?? "Rejected"}
                    </span>
                  </div>
                ))}
              </div>
            </section>
          ) : null}

          <footer className="mt-6 flex justify-end gap-3 border-t border-[#e2e8f1] pt-5">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-10 rounded-[4px] border border-[#cfd8e7] px-5 text-[11px] font-semibold text-[#52698e]"
            >
              Close
            </button>
            <button
              type="submit"
              disabled={
                submitting ||
                activeModels.length === 0
              }
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <PackagePlus className="h-4 w-4" />
              )}
              Import Devices
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}
'@

    Write-Ok "Reference-style bulk Device import modal created."

    Write-Section "10. Create Sell/Move Modal"

    Write-Utf8File "apps/web-panel/src/components/management/device-sell-move-modal.tsx" @'
"use client";

import {
  Building2,
  Cpu,
  LoaderCircle,
  MoveRight,
  ShieldCheck,
  UserRound,
  X,
} from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";
import type {
  DeviceSummary,
  TransferDevicesInput,
  TransferDevicesResult,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type {
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";
import { customerDisplayName } from "@/lib/management/monitor-types";

type DeviceSellMoveModalProps = {
  selectedDevices: DeviceSummary[];
  availableDevices: DeviceSummary[];
  dealers: DealerSummary[];
  customers: CustomerSummary[];
  onClose: () => void;
  onCompleted: (
    result: TransferDevicesResult,
  ) => void;
};

function deviceLabel(device: DeviceSummary) {
  return [
    device.deviceCode,
    device.imei ? `IMEI ${device.imei}` : null,
    `${device.deviceModel.manufacturer} ${device.deviceModel.modelName}`,
  ]
    .filter(Boolean)
    .join(" · ");
}

export function DeviceSellMoveModal({
  selectedDevices,
  availableDevices,
  dealers,
  customers,
  onClose,
  onCompleted,
}: DeviceSellMoveModalProps) {
  const defaultType =
    customers.length > 0 ? "CUSTOMER" : "DEALER";
  const [targetType, setTargetType] =
    useState<"DEALER" | "CUSTOMER">(defaultType);
  const [targetId, setTargetId] = useState(
    defaultType === "CUSTOMER"
      ? customers[0]?.id ?? ""
      : dealers[0]?.id ?? "",
  );
  const [selectedIds, setSelectedIds] = useState(
    () => new Set(selectedDevices.map((device) => device.id)),
  );
  const [imeiInput, setImeiInput] = useState("");
  const [notes, setNotes] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const devices = useMemo(
    () =>
      availableDevices.filter((device) =>
        selectedIds.has(device.id),
      ),
    [availableDevices, selectedIds],
  );

  const destinations =
    targetType === "CUSTOMER"
      ? customers
      : dealers;

  function removeDevice(deviceId: string) {
    setSelectedIds((current) => {
      const next = new Set(current);
      next.delete(deviceId);
      return next;
    });
  }

  function addByImei() {
    const normalized = imeiInput.trim();

    if (!normalized) return;

    const device = availableDevices.find(
      (item) => item.imei === normalized,
    );

    if (!device) {
      setError(
        "That IMEI is not present in the currently loaded scoped page.",
      );
      return;
    }

    setSelectedIds((current) => {
      const next = new Set(current);
      next.add(device.id);
      return next;
    });
    setImeiInput("");
    setError("");
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (devices.length === 0) {
      setError("Select at least one Device.");
      return;
    }

    const blocked = devices.some(
      (device) =>
        (device.vehicleAssignments?.length ?? 0) > 0 ||
        !["RECEIVED", "IN_STOCK", "ALLOCATED"].includes(
          device.lifecycleStatus,
        ),
    );

    if (blocked) {
      setError(
        "Installed or lifecycle-blocked Devices must be removed or repaired before transfer.",
      );
      return;
    }

    if (!targetId) {
      setError("Select a destination.");
      return;
    }

    const input: TransferDevicesInput = {
      deviceIds: devices.map((device) => device.id),
      targetType,
      targetId,
      notes: notes.trim() || undefined,
    };

    setSubmitting(true);

    try {
      const response = await fetch(
        "/api/management/devices/transfer",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        },
      );

      const payload = (await response.json()) as
        | TransferDevicesResult
        | ManagementApiError;

      if (!response.ok) {
        setError(
          "message" in payload
            ? payload.message
            : "Device transfer failed.",
        );
        return;
      }

      onCompleted(payload as TransferDevicesResult);
    } catch {
      setError(
        "The web panel could not reach the Device transfer service.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[2700] grid place-items-center bg-[#17345f]/50 p-5"
      role="presentation"
      onMouseDown={(event) => {
        if (
          event.target === event.currentTarget &&
          !submitting
        ) {
          onClose();
        }
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="device-sell-move-title"
        className="flex max-h-[94vh] w-full max-w-[980px] flex-col overflow-hidden rounded-[8px] bg-white shadow-[0_28px_80px_rgba(18,44,86,0.3)]"
      >
        <header className="flex items-start justify-between border-b border-[#e2e8f1] px-6 py-5">
          <div>
            <div className="flex items-center gap-2 text-[#357cf4]">
              <MoveRight className="h-5 w-5" />
              <span className="text-[11px] font-semibold uppercase tracking-[0.12em]">
                Lifecycle Transfer
              </span>
            </div>
            <h2
              id="device-sell-move-title"
              className="mt-2 text-[18px] font-semibold text-[#2b4065]"
            >
              Sell / Move Devices
            </h2>
            <p className="mt-1 text-[11px] text-[#71819c]">
              Move selected stock to a permitted Dealer or Customer.
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="Close Device transfer"
            className="text-[#71819c]"
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form
          onSubmit={submit}
          className="st-scrollbar overflow-y-auto p-6"
        >
          <div className="grid gap-6 lg:grid-cols-2">
            <section>
              <h3 className="text-[12px] font-semibold text-[#344b72]">
                Selected Devices ({devices.length})
              </h3>

              <div className="mt-3 flex h-10 overflow-hidden rounded-[4px] border border-[#cfd8e7]">
                <input
                  value={imeiInput}
                  onChange={(event) =>
                    setImeiInput(event.target.value)
                  }
                  className="min-w-0 flex-1 px-3 text-[11px] outline-none"
                  placeholder="Add IMEI from current scoped page"
                />
                <button
                  type="button"
                  onClick={addByImei}
                  className="bg-[#357cf4] px-4 text-[10px] font-semibold text-white"
                >
                  Add
                </button>
              </div>

              <div className="st-scrollbar mt-3 max-h-80 overflow-y-auto rounded-[5px] border border-[#dfe6ef]">
                {devices.map((device) => (
                  <div
                    key={device.id}
                    className="flex items-start gap-3 border-b border-[#eef2f7] px-4 py-3"
                  >
                    <Cpu className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[10px] font-semibold text-[#344b72]">
                        {deviceLabel(device)}
                      </p>
                      <p className="mt-1 text-[9px] text-[#8b9ab4]">
                        {device.lifecycleStatus}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => removeDevice(device.id)}
                      className="text-[10px] font-semibold text-red-600"
                    >
                      Remove
                    </button>
                  </div>
                ))}

                {devices.length === 0 ? (
                  <p className="px-4 py-8 text-center text-[10px] text-[#8b9ab4]">
                    No Device selected.
                  </p>
                ) : null}
              </div>
            </section>

            <section>
              <h3 className="text-[12px] font-semibold text-[#344b72]">
                Destination
              </h3>

              <div className="mt-3 grid gap-4">
                <label className="text-[10px] font-semibold text-[#52698e]">
                  Destination type
                  <select
                    value={targetType}
                    onChange={(event) => {
                      const nextType = event.target.value as
                        | "DEALER"
                        | "CUSTOMER";

                      setTargetType(nextType);
                      setTargetId(
                        nextType === "CUSTOMER"
                          ? customers[0]?.id ?? ""
                          : dealers[0]?.id ?? "",
                      );
                    }}
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[11px] outline-none"
                  >
                    <option
                      value="CUSTOMER"
                      disabled={customers.length === 0}
                    >
                      Customer
                    </option>
                    <option
                      value="DEALER"
                      disabled={dealers.length === 0}
                    >
                      Dealer
                    </option>
                  </select>
                </label>

                <label className="text-[10px] font-semibold text-[#52698e]">
                  Destination account
                  <select
                    value={targetId}
                    onChange={(event) =>
                      setTargetId(event.target.value)
                    }
                    className="mt-2 h-10 w-full rounded-[4px] border border-[#cfd8e7] bg-white px-3 text-[11px] outline-none"
                  >
                    <option value="">Select destination</option>
                    {targetType === "CUSTOMER"
                      ? customers.map((customer) => (
                          <option
                            key={customer.id}
                            value={customer.id}
                          >
                            {customerDisplayName(customer)}
                            {customer.managingDealer?.name
                              ? ` · ${customer.managingDealer.name}`
                              : " · Direct"}
                          </option>
                        ))
                      : dealers.map((dealer) => (
                          <option
                            key={dealer.id}
                            value={dealer.id}
                          >
                            {dealer.name} · {dealer.code}
                          </option>
                        ))}
                  </select>
                </label>

                <label className="text-[10px] font-semibold text-[#52698e]">
                  Transfer notes
                  <textarea
                    value={notes}
                    onChange={(event) =>
                      setNotes(event.target.value)
                    }
                    maxLength={1000}
                    rows={5}
                    className="mt-2 w-full rounded-[4px] border border-[#cfd8e7] px-3 py-3 text-[11px] outline-none"
                    placeholder="Sale reference, delivery note, or operational reason"
                  />
                </label>
              </div>

              <div className="mt-5 flex items-start gap-2 rounded-[5px] border border-[#dbe7f7] bg-[#f5f9ff] p-4 text-[10px] leading-5 text-[#52698e]">
                <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#357cf4]" />
                The backend independently validates source scope and destination
                scope, blocks installed Devices, closes active ownership,
                custody, and Dealer allocation rows, creates new history, and
                records a Device transfer audit event.
              </div>

              <div className="mt-4 grid grid-cols-2 gap-3 text-[10px]">
                <div className="rounded-[4px] border border-[#e2e8f1] p-3">
                  <Building2 className="h-4 w-4 text-[#ff9b24]" />
                  <p className="mt-2 font-semibold text-[#344b72]">
                    Dealer destination
                  </p>
                  <p className="mt-1 leading-5 text-[#71819c]">
                    Creates Dealer ownership, custody, and available stock.
                  </p>
                </div>
                <div className="rounded-[4px] border border-[#e2e8f1] p-3">
                  <UserRound className="h-4 w-4 text-[#29a8ef]" />
                  <p className="mt-2 font-semibold text-[#344b72]">
                    Customer destination
                  </p>
                  <p className="mt-1 leading-5 text-[#71819c]">
                    Creates Customer ownership and custody before installation.
                  </p>
                </div>
              </div>
            </section>
          </div>

          {error ? (
            <p className="mt-5 rounded-[4px] bg-red-50 px-4 py-3 text-[11px] font-medium text-red-700">
              {error}
            </p>
          ) : null}

          <footer className="mt-6 flex justify-end gap-3 border-t border-[#e2e8f1] pt-5">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="h-10 rounded-[4px] border border-[#cfd8e7] px-5 text-[11px] font-semibold text-[#52698e]"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={
                submitting ||
                devices.length === 0 ||
                destinations.length === 0 ||
                !targetId
              }
              className="flex h-10 items-center gap-2 rounded-[4px] bg-[#357cf4] px-5 text-[11px] font-semibold text-white disabled:bg-[#b8c7dc]"
            >
              {submitting ? (
                <LoaderCircle className="h-4 w-4 animate-spin" />
              ) : (
                <MoveRight className="h-4 w-4" />
              )}
              Confirm Sell / Move
            </button>
          </footer>
        </form>
      </section>
    </div>
  );
}
'@

    Write-Ok "Scoped Dealer/Customer sell and move modal created."

    Write-Section "11. Replace Management Device Workspace"

    Write-Utf8File "apps/web-panel/src/components/management/device-management-workspace.tsx" @'
"use client";

import {
  CirclePlus,
  Cpu,
  FilePenLine,
  FileSpreadsheet,
  LoaderCircle,
  MoveRight,
  PackagePlus,
  RefreshCw,
  Search,
  ShieldCheck,
  Trash2,
  Unlink,
} from "lucide-react";
import {
  useEffect,
  useMemo,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { AddDeviceModelModal } from "@/components/management/add-device-model-modal";
import { BulkDeviceStockIntakeModal } from "@/components/management/bulk-device-stock-intake-modal";
import { DeviceSellMoveModal } from "@/components/management/device-sell-move-modal";
import { DeviceStockIntakeModal } from "@/components/management/device-stock-intake-modal";
import { ManagementMonitorAccountTree } from "@/components/management/management-monitor-account-tree";
import type {
  BulkDeviceRegistrationResult,
  DeviceListResponse,
  DeviceModelListResponse,
  DeviceModelSummary,
  DeviceSummary,
  TransferDevicesResult,
} from "@/lib/management/asset-types";
import type { CustomerSummary } from "@/lib/management/customer-types";
import type {
  DealerSummary,
  ManagementApiError,
} from "@/lib/management/dealer-types";
import {
  customerDisplayName,
  type ManagementMonitorScope,
} from "@/lib/management/monitor-types";
import { useManagementMonitorHierarchy } from "@/lib/management/use-management-monitor-hierarchy";

type DeviceManagementWorkspaceProps = {
  workspace: string;
  canViewDevices: boolean;
  canViewDealers: boolean;
  canViewCustomers: boolean;
  canRegisterDevices: boolean;
  canTransferDevices: boolean;
};

const lifecycleOptions = [
  "",
  "RECEIVED",
  "IN_STOCK",
  "RESERVED",
  "ALLOCATED",
  "INSTALLED",
  "UNDER_REPAIR",
  "LOST",
  "DAMAGED",
  "RETIRED",
];

function normalizeDevice(device: DeviceSummary): DeviceSummary {
  return {
    ...device,
    dealerAllocations: device.dealerAllocations ?? [],
    vehicleAssignments: device.vehicleAssignments ?? [],
    ownershipHistory: device.ownershipHistory ?? [],
    custodyHistory: device.custodyHistory ?? [],
  };
}

function formatDate(value?: string | null) {
  if (!value) return "-";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return "-";

  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function statusClass(status: string) {
  if (status === "IN_STOCK" || status === "RECEIVED") {
    return "bg-emerald-50 text-emerald-700";
  }

  if (status === "ALLOCATED") {
    return "bg-indigo-50 text-indigo-700";
  }

  if (status === "INSTALLED") {
    return "bg-sky-50 text-sky-700";
  }

  if (
    status === "DAMAGED" ||
    status === "LOST" ||
    status === "RETIRED"
  ) {
    return "bg-red-50 text-red-700";
  }

  return "bg-amber-50 text-amber-700";
}

function accountLabel(
  device: DeviceSummary,
  dealers: DealerSummary[],
  customers: CustomerSummary[],
) {
  const customerId =
    device.vehicleAssignments?.[0]?.vehicle?.customerId ??
    device.ownershipHistory?.[0]?.ownerCustomerId ??
    device.custodyHistory?.[0]?.custodianCustomerId ??
    null;

  if (customerId) {
    const customer = customers.find(
      (item) => item.id === customerId,
    );

    if (customer) {
      return customerDisplayName(customer);
    }
  }

  const dealerId =
    device.dealerAllocations?.[0]?.dealerOrganizationId ??
    device.ownershipHistory?.[0]?.ownerOrganizationId ??
    device.custodyHistory?.[0]?.custodianOrganizationId ??
    null;

  if (dealerId) {
    const dealer = dealers.find(
      (item) => item.id === dealerId,
    );

    if (dealer) return dealer.name;
  }

  return "Solid Tracker Platform";
}

function ActionButton({
  icon,
  label,
  onClick,
  disabled = false,
  title,
}: {
  icon: ReactNode;
  label: string;
  onClick?: () => void;
  disabled?: boolean;
  title?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={title}
      className="flex h-8 items-center gap-1.5 rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] font-semibold text-[#52698e] shadow-sm hover:border-[#9fb7dc] disabled:cursor-not-allowed disabled:bg-[#f2f5f9] disabled:text-[#a4afc0]"
    >
      {icon}
      {label}
    </button>
  );
}

export function DeviceManagementWorkspace({
  workspace,
  canViewDevices,
  canViewDealers,
  canViewCustomers,
  canRegisterDevices,
  canTransferDevices,
}: DeviceManagementWorkspaceProps) {
  const [selectedScope, setSelectedScope] =
    useState<ManagementMonitorScope>({
      key: "platform",
      type: "PLATFORM",
      id: null,
      label: "Visible Inventory",
    });
  const [devices, setDevices] = useState<DeviceSummary[]>([]);
  const [models, setModels] = useState<DeviceModelSummary[]>([]);
  const [loading, setLoading] = useState(canViewDevices);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [imeiInput, setImeiInput] = useState("");
  const [nameInput, setNameInput] = useState("");
  const [activeSearch, setActiveSearch] = useState("");
  const [lifecycleStatus, setLifecycleStatus] = useState("");
  const [deviceModelId, setDeviceModelId] = useState("");
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const [total, setTotal] = useState(0);
  const [totalPages, setTotalPages] = useState(1);
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [modelRefreshVersion, setModelRefreshVersion] =
    useState(0);
  const [selectedIds, setSelectedIds] =
    useState<Set<string>>(new Set());
  const [modelModalOpen, setModelModalOpen] = useState(false);
  const [stockModalOpen, setStockModalOpen] = useState(false);
  const [bulkModalOpen, setBulkModalOpen] = useState(false);
  const [transferModalOpen, setTransferModalOpen] =
    useState(false);

  const hierarchy = useManagementMonitorHierarchy({
    canViewDealers,
    canViewCustomers,
  });

  useEffect(() => {
    const controller = new AbortController();

    fetch("/api/management/device-models?page=1&pageSize=100", {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | DeviceModelListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Device Model loading failed.",
          );
        }

        setModels(
          (payload as DeviceModelListResponse).items,
        );
      })
      .catch((requestError: unknown) => {
        if (
          controller.signal.aborted ||
          (requestError instanceof DOMException &&
            requestError.name === "AbortError")
        ) {
          return;
        }

        setError(
          requestError instanceof Error
            ? requestError.message
            : "Device Model loading failed.",
        );
      });

    return () => controller.abort();
  }, [modelRefreshVersion]);

  useEffect(() => {
    if (!canViewDevices) return;

    const controller = new AbortController();
    const parameters = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    });

    if (activeSearch) {
      parameters.set("search", activeSearch);
    }
    if (lifecycleStatus) {
      parameters.set("lifecycleStatus", lifecycleStatus);
    }
    if (deviceModelId) {
      parameters.set("deviceModelId", deviceModelId);
    }

    if (
      selectedScope.type === "DEALER" &&
      selectedScope.id
    ) {
      parameters.set(
        "dealerOrganizationId",
        selectedScope.id,
      );
    } else if (
      selectedScope.type === "CUSTOMER" &&
      selectedScope.id
    ) {
      parameters.set("customerId", selectedScope.id);
    } else if (selectedScope.type === "DIRECT") {
      parameters.set("directCustomers", "true");
    }

    fetch(`/api/management/devices?${parameters.toString()}`, {
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        const payload = (await response.json()) as
          | DeviceListResponse
          | ManagementApiError;

        if (!response.ok) {
          throw new Error(
            "message" in payload
              ? payload.message
              : "Scoped Device loading failed.",
          );
        }

        const result = payload as DeviceListResponse;

        setDevices(result.items.map(normalizeDevice));
        setTotal(result.total);
        setTotalPages(Math.max(result.totalPages, 1));
        setSelectedIds(new Set());
        setError("");
      })
      .catch((requestError: unknown) => {
        if (
          controller.signal.aborted ||
          (requestError instanceof DOMException &&
            requestError.name === "AbortError")
        ) {
          return;
        }

        setDevices([]);
        setTotal(0);
        setTotalPages(1);
        setError(
          requestError instanceof Error
            ? requestError.message
            : "Scoped Device loading failed.",
        );
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      });

    return () => controller.abort();
  }, [
    activeSearch,
    canViewDevices,
    deviceModelId,
    lifecycleStatus,
    page,
    pageSize,
    refreshVersion,
    selectedScope,
  ]);

  const selectedDevices = useMemo(
    () =>
      devices.filter((device) =>
        selectedIds.has(device.id),
      ),
    [devices, selectedIds],
  );

  const transferBlocked = selectedDevices.some(
    (device) =>
      (device.vehicleAssignments?.length ?? 0) > 0 ||
      !["RECEIVED", "IN_STOCK", "ALLOCATED"].includes(
        device.lifecycleStatus,
      ),
  );

  const allSelected =
    devices.length > 0 &&
    devices.every((device) => selectedIds.has(device.id));

  function prepareReload() {
    setLoading(true);
    setError("");
    setSuccess("");
  }

  function reloadDevices() {
    prepareReload();
    setRefreshVersion((current) => current + 1);
  }

  function selectScope(scope: ManagementMonitorScope) {
    prepareReload();
    setSelectedScope(scope);
    setPage(1);
  }

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    prepareReload();
    setActiveSearch(
      imeiInput.trim() || nameInput.trim(),
    );
    setPage(1);
  }

  function resetFilters() {
    prepareReload();
    setImeiInput("");
    setNameInput("");
    setActiveSearch("");
    setLifecycleStatus("");
    setDeviceModelId("");
    setPage(1);
  }

  function toggleAll() {
    setSelectedIds((current) => {
      if (allSelected) return new Set();

      return new Set(devices.map((device) => device.id));
    });
  }

  function toggleDevice(deviceId: string) {
    setSelectedIds((current) => {
      const next = new Set(current);

      if (next.has(deviceId)) {
        next.delete(deviceId);
      } else {
        next.add(deviceId);
      }

      return next;
    });
  }

  function modelCreated(model: DeviceModelSummary) {
    setModels((current) => [model, ...current]);
    setModelModalOpen(false);
    setSuccess(
      `Device Model ${model.manufacturer} ${model.modelName} created.`,
    );
  }

  function deviceCreated(device: DeviceSummary) {
    setStockModalOpen(false);
    setSuccess(
      `Device ${device.deviceCode} received into Platform stock.`,
    );
    setModelRefreshVersion((current) => current + 1);
    reloadDevices();
  }

  function bulkCompleted(
    result: BulkDeviceRegistrationResult,
  ) {
    setSuccess(
      `Bulk intake completed: ${result.created} created, ${result.failed} rejected.`,
    );
    setModelRefreshVersion((current) => current + 1);
    reloadDevices();
  }

  function transferCompleted(
    result: TransferDevicesResult,
  ) {
    setTransferModalOpen(false);
    setSuccess(
      `${result.total} Device(s) moved to the selected ${result.targetType.toLowerCase()}.`,
    );
    hierarchy.refresh();
    reloadDevices();
  }

  if (!canViewDevices) {
    return (
      <div className="grid min-h-[calc(100vh-var(--st-topbar-height))] place-items-center bg-[#f1f4f8] p-6">
        <section className="max-w-lg rounded-[6px] border border-[#dfe6ef] bg-white p-8 text-center">
          <ShieldCheck className="mx-auto h-10 w-10 text-[#357cf4]" />
          <h1 className="mt-4 text-[18px] font-semibold text-[#2b4065]">
            Device access is restricted
          </h1>
          <p className="mt-2 text-[11px] leading-6 text-[#71819c]">
            This authenticated account does not have device.view permission.
          </p>
        </section>
      </div>
    );
  }

  return (
    <>
      <div className="flex h-[calc(100vh-var(--st-topbar-height))] min-h-[640px] overflow-hidden bg-[#f1f4f8]">
        <ManagementMonitorAccountTree
          workspace={workspace}
          dealers={hierarchy.dealers}
          customers={hierarchy.customers}
          loading={hierarchy.loading}
          error={hierarchy.error}
          selectedScope={selectedScope}
          onSelectScope={selectScope}
          onRefresh={() => {
            hierarchy.refresh();
            reloadDevices();
          }}
        />

        <main className="st-scrollbar min-w-0 flex-1 overflow-auto p-3">
          <section className="min-h-full rounded-[4px] border border-[#dfe6ef] bg-white">
            <header className="flex flex-wrap items-center gap-2 border-b border-[#e2e8f1] px-4 py-3">
              <div className="mr-auto">
                <p className="text-[9px] font-semibold uppercase tracking-[0.12em] text-[#8b9ab4]">
                  {selectedScope.label}
                </p>
                <h1 className="mt-1 text-[14px] font-semibold text-[#344b72]">
                  Device Management
                </h1>
              </div>

              <ActionButton
                icon={<PackagePlus className="h-3.5 w-3.5" />}
                label="Import device"
                onClick={() => setBulkModalOpen(true)}
                disabled={!canRegisterDevices}
                title={
                  canRegisterDevices
                    ? "Bulk import one Device Model with multiple IMEIs"
                    : "Platform device.register permission is required"
                }
              />
              <ActionButton
                icon={<FilePenLine className="h-3.5 w-3.5" />}
                label="Edit device"
                disabled
                title="Controlled metadata editing will be connected in a later workflow"
              />
              <ActionButton
                icon={<MoveRight className="h-3.5 w-3.5" />}
                label="Sell/move"
                onClick={() => setTransferModalOpen(true)}
                disabled={
                  !canTransferDevices ||
                  selectedDevices.length === 0 ||
                  transferBlocked
                }
                title={
                  transferBlocked
                    ? "Installed or lifecycle-blocked Devices cannot be moved"
                    : "Move selected Devices to a scoped Dealer or Customer"
                }
              />
              <ActionButton
                icon={<FileSpreadsheet className="h-3.5 w-3.5" />}
                label="Expire/Edit due"
                disabled
                title="Subscription due-date editing is not part of this asset stage"
              />
              <ActionButton
                icon={<FileSpreadsheet className="h-3.5 w-3.5" />}
                label="Create/Edit invoice"
                disabled
                title="Invoice workflow remains in Billing"
              />
              <ActionButton
                icon={<Trash2 className="h-3.5 w-3.5" />}
                label="Delete device"
                disabled
                title="Physical Device history is retained; destructive delete is disabled"
              />
              <ActionButton
                icon={<Unlink className="h-3.5 w-3.5" />}
                label="Unbind"
                disabled
                title="Installed trackers must use the explicit removal workflow"
              />

              {canRegisterDevices ? (
                <>
                  <ActionButton
                    icon={<Cpu className="h-3.5 w-3.5" />}
                    label="Add Device Model"
                    onClick={() => setModelModalOpen(true)}
                  />
                  <ActionButton
                    icon={<CirclePlus className="h-3.5 w-3.5" />}
                    label="Add Device / Stock Intake"
                    onClick={() => setStockModalOpen(true)}
                  />
                </>
              ) : null}
            </header>

            <form
              onSubmit={search}
              className="grid gap-3 border-b border-[#e2e8f1] bg-[#fbfcfe] p-4 md:grid-cols-2 xl:grid-cols-6"
            >
              <label className="text-[9px] font-semibold text-[#71819c]">
                IMEI
                <input
                  value={imeiInput}
                  onChange={(event) =>
                    setImeiInput(event.target.value)
                  }
                  className="mt-1 h-9 w-full rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] outline-none"
                  placeholder="Search IMEI"
                />
              </label>

              <label className="text-[9px] font-semibold text-[#71819c]">
                Device name / code
                <input
                  value={nameInput}
                  onChange={(event) =>
                    setNameInput(event.target.value)
                  }
                  className="mt-1 h-9 w-full rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] outline-none"
                  placeholder="Search Device"
                />
              </label>

              <label className="text-[9px] font-semibold text-[#71819c]">
                Device Model
                <select
                  value={deviceModelId}
                  onChange={(event) => {
                    prepareReload();
                    setDeviceModelId(event.target.value);
                    setPage(1);
                  }}
                  className="mt-1 h-9 w-full rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] outline-none"
                >
                  <option value="">All models</option>
                  {models.map((model) => (
                    <option key={model.id} value={model.id}>
                      {model.manufacturer} {model.modelName}
                    </option>
                  ))}
                </select>
              </label>

              <label className="text-[9px] font-semibold text-[#71819c]">
                Lifecycle
                <select
                  value={lifecycleStatus}
                  onChange={(event) => {
                    prepareReload();
                    setLifecycleStatus(event.target.value);
                    setPage(1);
                  }}
                  className="mt-1 h-9 w-full rounded-[3px] border border-[#cfd8e7] bg-white px-3 text-[10px] outline-none"
                >
                  {lifecycleOptions.map((status) => (
                    <option key={status || "ALL"} value={status}>
                      {status
                        ? status.replaceAll("_", " ")
                        : "All statuses"}
                    </option>
                  ))}
                </select>
              </label>

              <button
                type="submit"
                className="mt-4 flex h-9 items-center justify-center gap-2 rounded-[3px] bg-[#357cf4] px-4 text-[10px] font-semibold text-white"
              >
                <Search className="h-3.5 w-3.5" />
                Search
              </button>

              <button
                type="button"
                onClick={resetFilters}
                className="mt-4 flex h-9 items-center justify-center gap-2 rounded-[3px] border border-[#cfd8e7] bg-white px-4 text-[10px] font-semibold text-[#52698e]"
              >
                <RefreshCw className="h-3.5 w-3.5" />
                Reset
              </button>
            </form>

            {success ? (
              <p className="mx-4 mt-4 rounded-[4px] bg-emerald-50 px-4 py-3 text-[10px] font-medium text-emerald-700">
                {success}
              </p>
            ) : null}

            {error ? (
              <p className="mx-4 mt-4 rounded-[4px] bg-red-50 px-4 py-3 text-[10px] font-medium text-red-700">
                {error}
              </p>
            ) : null}

            <div className="overflow-x-auto">
              <table className="w-full min-w-[1160px] text-left text-[10px]">
                <thead className="bg-[#f7f9fc] text-[9px] font-semibold uppercase tracking-[0.04em] text-[#71819c]">
                  <tr>
                    <th className="w-10 px-3 py-3">
                      <input
                        type="checkbox"
                        checked={allSelected}
                        onChange={toggleAll}
                        aria-label="Select current Device page"
                      />
                    </th>
                    <th className="px-3 py-3">No.</th>
                    <th className="px-3 py-3">Account</th>
                    <th className="px-3 py-3">Device name</th>
                    <th className="px-3 py-3">IMEI</th>
                    <th className="px-3 py-3">Device Model</th>
                    <th className="px-3 py-3">Activated</th>
                    <th className="px-3 py-3">Subscription</th>
                    <th className="px-3 py-3">Expiration</th>
                    <th className="px-3 py-3">Status</th>
                  </tr>
                </thead>

                <tbody>
                  {loading ? (
                    <tr>
                      <td colSpan={10} className="py-20 text-center">
                        <LoaderCircle className="mx-auto h-6 w-6 animate-spin text-[#357cf4]" />
                        <p className="mt-3 text-[#71819c]">
                          Loading scoped Devices
                        </p>
                      </td>
                    </tr>
                  ) : devices.length === 0 ? (
                    <tr>
                      <td colSpan={10} className="py-20 text-center text-[#8b9ab4]">
                        No Device exists in the selected hierarchy scope.
                      </td>
                    </tr>
                  ) : (
                    devices.map((device, index) => (
                      <tr
                        key={device.id}
                        className="border-b border-[#edf1f6] text-[#52698e] hover:bg-[#fbfdff]"
                      >
                        <td className="px-3 py-3">
                          <input
                            type="checkbox"
                            checked={selectedIds.has(device.id)}
                            onChange={() => toggleDevice(device.id)}
                            aria-label={`Select ${device.deviceCode}`}
                          />
                        </td>
                        <td className="px-3 py-3">
                          {(page - 1) * pageSize + index + 1}
                        </td>
                        <td className="max-w-[190px] truncate px-3 py-3 font-medium text-[#344b72]">
                          {accountLabel(
                            device,
                            hierarchy.dealers,
                            hierarchy.customers,
                          )}
                        </td>
                        <td className="px-3 py-3 text-[#357cf4]">
                          {device.deviceCode}
                        </td>
                        <td className="px-3 py-3 font-mono">
                          {device.imei || "-"}
                        </td>
                        <td className="px-3 py-3">
                          {device.deviceModel.manufacturer}{" "}
                          {device.deviceModel.modelName}
                        </td>
                        <td className="px-3 py-3">
                          {formatDate(
                            device.receivedAt ?? device.createdAt,
                          )}
                        </td>
                        <td className="px-3 py-3">-</td>
                        <td className="px-3 py-3">-</td>
                        <td className="px-3 py-3">
                          <span
                            className={[
                              "rounded-full px-2 py-1 text-[8px] font-semibold",
                              statusClass(device.lifecycleStatus),
                            ].join(" ")}
                          >
                            {device.lifecycleStatus.replaceAll("_", " ")}
                          </span>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>

            <footer className="flex flex-wrap items-center justify-between gap-3 border-t border-[#e2e8f1] px-4 py-3 text-[10px] text-[#71819c]">
              <span>
                Selected {selectedDevices.length} · Showing{" "}
                {devices.length} of {total} Device(s)
              </span>

              <div className="flex items-center gap-2">
                <label>
                  Page size{" "}
                  <select
                    value={pageSize}
                    onChange={(event) => {
                      prepareReload();
                      setPageSize(Number(event.target.value));
                      setPage(1);
                    }}
                    className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-2"
                  >
                    <option value={25}>25</option>
                    <option value={50}>50</option>
                    <option value={100}>100</option>
                  </select>
                </label>

                <button
                  type="button"
                  disabled={page <= 1 || loading}
                  onClick={() => {
                    prepareReload();
                    setPage((current) => Math.max(1, current - 1));
                  }}
                  className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 font-semibold disabled:opacity-40"
                >
                  Previous
                </button>

                <span>
                  Page {page} / {totalPages}
                </span>

                <button
                  type="button"
                  disabled={page >= totalPages || loading}
                  onClick={() => {
                    prepareReload();
                    setPage((current) =>
                      Math.min(totalPages, current + 1),
                    );
                  }}
                  className="h-8 rounded-[3px] border border-[#cfd8e7] bg-white px-3 font-semibold disabled:opacity-40"
                >
                  Next
                </button>
              </div>
            </footer>
          </section>
        </main>
      </div>

      {modelModalOpen ? (
        <AddDeviceModelModal
          onClose={() => setModelModalOpen(false)}
          onCreated={modelCreated}
        />
      ) : null}

      {stockModalOpen ? (
        <DeviceStockIntakeModal
          models={models}
          onClose={() => setStockModalOpen(false)}
          onCreated={deviceCreated}
          onCreateModel={() => {
            setStockModalOpen(false);
            setModelModalOpen(true);
          }}
        />
      ) : null}

      {bulkModalOpen ? (
        <BulkDeviceStockIntakeModal
          models={models}
          onClose={() => setBulkModalOpen(false)}
          onCompleted={bulkCompleted}
        />
      ) : null}

      {transferModalOpen ? (
        <DeviceSellMoveModal
          selectedDevices={selectedDevices}
          availableDevices={devices}
          dealers={hierarchy.dealers}
          customers={hierarchy.customers}
          onClose={() => setTransferModalOpen(false)}
          onCompleted={transferCompleted}
        />
      ) : null}
    </>
  );
}
'@

    Write-Ok "Management Device page now uses operational hierarchy, scoped data, selection, and pagination."

    Write-Section "12. Update Server-Side Permission Gating"

    Write-Utf8File "apps/web-panel/src/app/(management)/management/device/page.tsx" @'
import { DeviceManagementWorkspace } from "@/components/management/device-management-workspace";
import { canManageDealers } from "@/lib/auth/management-access";
import { requireManagementSession } from "@/lib/auth/server-session";

export default async function ManagementDevicePage() {
  const session = await requireManagementSession();
  const permissions = new Set(session.user.permissions);
  const platformWorkspace = canManageDealers(
    session.workspace,
  );

  return (
    <DeviceManagementWorkspace
      workspace={session.workspace}
      canViewDevices={permissions.has("device.view")}
      canViewDealers={permissions.has("dealer.view")}
      canViewCustomers={permissions.has("customer.view")}
      canRegisterDevices={
        platformWorkspace &&
        permissions.has("device.register")
      }
      canTransferDevices={permissions.has("device.remove")}
    />
  );
}
'@

    Write-Ok "Bulk registration stays Platform-only; scoped transfer uses device.remove permission."

    Write-Section "13. Document Device Hierarchy and Transfer Architecture"

    Write-Utf8File "docs/frontend/management-device-account-hierarchy.md" @'
# Management Device Account Hierarchy, Transfer, and Bulk Intake

## Route

```text
/management/device
```

## Account hierarchy

The Device workspace reuses the operational Management Monitor hierarchy.

- Platform users see the Platform root, Direct Customers, Dealers, and Dealer Customers.
- Dealer Manager users see only Customers and synthesized Dealer nodes within their authenticated scope.
- Dealer users see only their organization scope and managed Customers.
- Hierarchy expansion and hierarchy selection are independent.

The selected node becomes a backend query:

```text
Platform root  -> authenticated Device scope
Direct         -> directCustomers=true
Dealer         -> dealerOrganizationId=<scoped Dealer>
Customer       -> customerId=<scoped Customer>
```

Backend `deviceWhere(auth)` is always applied before these filters. Browser IDs
cannot expand the authenticated scope.

## Pagination

Device pagination is backend-authoritative.

```text
page
pageSize
total
totalPages
```

Search, lifecycle, Device Model, hierarchy selection, and page size reset the
current page and issue a new scoped request.

## Bulk stock intake

Platform operators with `device.register` may:

1. select one active Device Model;
2. enter up to 250 IMEI lines;
3. apply shared hardware, firmware, and received-time metadata;
4. receive per-line `CREATED` or `ERROR` results.

The backend:

- trims every IMEI;
- validates 14–17 digits;
- rejects duplicate lines;
- relies on the unique IMEI database constraint for existing stock;
- calls the normal registration transaction for every accepted line;
- creates Platform ownership and custody history;
- records the standard `device.registered` audit event.

## Sell / move

Users with `device.remove` may move only Devices already inside their effective
scope. Destination Dealer and Customer IDs are independently revalidated.

Blocked lifecycle states include:

- installed or actively assigned;
- reserved;
- under repair;
- lost;
- damaged;
- retired.

A successful transfer transaction:

1. closes active Dealer allocation rows;
2. closes current ownership history;
3. closes current custody history;
4. creates destination ownership;
5. creates destination custody;
6. creates available Dealer stock when the destination is a Dealer;
7. keeps Dealer-managed Customer stock linked to its managing Dealer;
8. sets lifecycle state to `ALLOCATED`;
9. records `device.transferred` audit entries.

Installed Devices must use the explicit removal workflow before transfer.

## UI preservation

The approved Account List, search fields, reference action row, Device table,
status presentation, selection controls, and pagination are retained.

Options that belong to future Billing or removal workflows remain visible but
disabled rather than being simulated.
'@

    Write-Ok "Hierarchy, authorization, lifecycle, pagination, and audit behavior documented."

    Write-Section "14. Verify Backend and Frontend"

    if (-not (Test-DockerEngine)) {
        throw "Docker Desktop is not running. Start Docker Desktop and rerun the script."
    }

    Invoke-Native "docker" @(
        "compose",
        "--env-file",
        ".env",
        "up",
        "-d",
        "postgres",
        "redis"
    )

    Invoke-Native "pnpm.cmd" @("install")

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $BackendPackageName,
        "exec",
        "prisma",
        "validate",
        "--config",
        "prisma.config.ts"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $BackendPackageName,
        "exec",
        "prisma",
        "migrate",
        "status",
        "--config",
        "prisma.config.ts"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $BackendPackageName,
        "exec",
        "prettier",
        "--write",
        "src/assets/common/asset-query.dto.ts",
        "src/assets/devices/devices.controller.ts",
        "src/assets/devices/devices.service.ts",
        "src/assets/devices/dto/bulk-register-devices.dto.ts",
        "src/assets/devices/dto/transfer-devices.dto.ts"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $BackendPackageName,
        "lint"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $BackendPackageName,
        "typecheck"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $BackendPackageName,
        "test:e2e",
        "--runInBand",
        "vehicle-device.e2e-spec.ts"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $BackendPackageName,
        "test:e2e",
        "--runInBand",
        "dealer-customer.e2e-spec.ts"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $BackendPackageName,
        "build"
    )

    Remove-StaleNextState

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $WebPackageName,
        "lint"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $WebPackageName,
        "typecheck"
    )

    Invoke-Native "pnpm.cmd" @(
        "--filter",
        $WebPackageName,
        "build"
    )

    Invoke-Native "git" @("diff", "--check")

    Write-Ok "Prisma, backend lint/typecheck/E2E/build, frontend lint/typecheck/build, and diff checks passed."

    Write-Section "15. Commit and Restart"

    Stage-ExpectedFiles

    & git diff --cached --quiet
    $cachedStatus = $LASTEXITCODE

    if ($cachedStatus -eq 1) {
        Invoke-Native "git" @(
            "commit",
            "-m",
            "feat(device): add scoped hierarchy transfers and bulk intake"
        )
        Write-Ok "Feature committed."
    }
    elseif ($cachedStatus -eq 0) {
        Write-Warn "No new staged changes were found; the feature may already be committed."
    }
    else {
        throw "Could not inspect staged feature changes."
    }

    Assert-CleanRepository

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $DevScriptPath `
        -OpenBrowser `
        -Route "/management/device"

    if ($LASTEXITCODE -ne 0) {
        throw "Live development could not be restarted."
    }

    Write-Section "Management Device Feature Completed"

    Write-Host "Branch       : $TargetBranch" -ForegroundColor Yellow
    Write-Host "Review route : http://localhost:3001/management/device" -ForegroundColor Yellow
    Write-Host "Hierarchy    : Platform / Direct / Dealer / Customer" -ForegroundColor Yellow
    Write-Host "Pagination   : backend-authoritative" -ForegroundColor Yellow
    Write-Host "Bulk intake  : up to 250 IMEIs with per-line results" -ForegroundColor Yellow
    Write-Host "Sell / move  : scoped Dealer or Customer transfer" -ForegroundColor Yellow
    Write-Host "Migration    : none" -ForegroundColor Yellow
    Write-Host "Log file     : $LogFile" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Latest commits:" -ForegroundColor Cyan
    & git --no-pager log --oneline --decorate -6
}
catch {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host " Management Device Feature Failed" -ForegroundColor Red
    Write-Host "==================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Repository state was preserved for a focused recovery." -ForegroundColor Yellow
    Write-Host "Log file: $LogFile" -ForegroundColor Yellow
    exit 1
}
finally {
    try {
        Stop-Transcript | Out-Null
    } catch {
    }
}
