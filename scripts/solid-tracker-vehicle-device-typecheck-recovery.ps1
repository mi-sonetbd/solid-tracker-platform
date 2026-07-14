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

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $parentPath = Split-Path -Parent $fullPath

    if (-not (Test-Path -LiteralPath $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $Content.TrimStart(),
        $script:Utf8NoBom
    )

    Write-Host "[WRITTEN] $RelativePath" -ForegroundColor Green
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

function Replace-RequiredText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$OldText,

        [Parameter(Mandatory = $true)]
        [string]$NewText
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $content = [System.IO.File]::ReadAllText($fullPath)

    if ($content.Contains($NewText)) {
        Write-Host "[PRESERVED] $RelativePath already contains the correction" -ForegroundColor DarkYellow
        return
    }

    if (-not $content.Contains($OldText)) {
        throw "Could not locate the required correction in $RelativePath"
    }

    $content = $content.Replace($OldText, $NewText)

    [System.IO.File]::WriteAllText(
        $fullPath,
        $content,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED] $RelativePath" -ForegroundColor Green
}

function Get-LfContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path $script:RootPath $RelativePath

    return [System.IO.File]::ReadAllText($fullPath).Replace(
        "`r`n",
        "`n"
    )
}

function Set-LfContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $fullPath = Join-Path $script:RootPath $RelativePath

    [System.IO.File]::WriteAllText(
        $fullPath,
        $Content.Replace("`r`n", "`n"),
        $script:Utf8NoBom
    )
}

function Replace-LfBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$StartMarker,

        [Parameter(Mandatory = $true)]
        [string]$EndMarker,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Replacement,

        [switch]$IncludeEndMarker
    )

    $startIndex = $Content.IndexOf(
        $StartMarker,
        [System.StringComparison]::Ordinal
    )

    if ($startIndex -lt 0) {
        throw "Start marker was not found: $StartMarker"
    }

    $searchFrom = $startIndex + $StartMarker.Length
    $endIndex = $Content.IndexOf(
        $EndMarker,
        $searchFrom,
        [System.StringComparison]::Ordinal
    )

    if ($endIndex -lt 0) {
        throw "End marker was not found: $EndMarker"
    }

    if ($IncludeEndMarker) {
        $endIndex += $EndMarker.Length
    }

    return (
        $Content.Substring(0, $startIndex) +
        $Replacement +
        $Content.Substring($endIndex)
    )
}

function Replace-RequiredLfText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$OldText,

        [Parameter(Mandatory = $true)]
        [string]$NewText,

        [string]$AlreadyFixedMarker
    )

    if (
        $AlreadyFixedMarker -and
        $Content.Contains($AlreadyFixedMarker)
    ) {
        return $Content
    }

    $matchCount = (
        [regex]::Matches(
            $Content,
            [regex]::Escape($OldText)
        )
    ).Count

    if ($matchCount -ne 1) {
        throw (
            "Expected exactly one exact-text patch target, " +
            "but found $matchCount."
        )
    }

    return $Content.Replace($OldText, $NewText)
}

function Remove-OptionalLfText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if (-not $Content.Contains($Text)) {
        return $Content
    }

    return $Content.Replace($Text, "")
}

function Sync-FoundationEmbeddedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FoundationContent,

        [Parameter(Mandatory = $true)]
        [string]$EmbeddedPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$SourceContent
    )

    $startMarker = (
        '    Write-Utf8File `' +
        "`n" +
        "        `"$EmbeddedPath`" ``" +
        "`n" +
        "        @'"
    )

    $startIndex = $FoundationContent.IndexOf(
        $startMarker,
        [System.StringComparison]::Ordinal
    )

    if ($startIndex -lt 0) {
        throw "Embedded file start marker was not found: $EmbeddedPath"
    }

    $payloadStart = $startIndex + $startMarker.Length

    if (
        $payloadStart -lt $FoundationContent.Length -and
        $FoundationContent[$payloadStart] -eq "`n"
    ) {
        $payloadStart++
    }

    $endMarker = "`n'@"
    $endIndex = $FoundationContent.IndexOf(
        $endMarker,
        $payloadStart,
        [System.StringComparison]::Ordinal
    )

    if ($endIndex -lt 0) {
        throw "Embedded file terminator was not found: $EmbeddedPath"
    }

    $replacement = (
        $startMarker +
        "`n" +
        $SourceContent.TrimEnd("`n") +
        $endMarker
    )

    return (
        $FoundationContent.Substring(0, $startIndex) +
        $replacement +
        $FoundationContent.Substring(
            $endIndex + $endMarker.Length
        )
    )
}

function Assert-ExpectedRepositoryState {
    $allowedPaths = @(
        "services/backend-api/src/app.module.ts",
        "scripts/solid-tracker-vehicle-device-api.ps1",
        "scripts/solid-tracker-vehicle-device-typecheck-recovery.ps1",
        "services/backend-api/src/assets/",
        "services/backend-api/test/vehicle-device.e2e-spec.ts"
    )

    $unexpected = New-Object System.Collections.Generic.List[string]

    foreach ($line in @(git status --short)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line.Length -lt 4) {
            $unexpected.Add($line)
            continue
        }

        $path = $line.Substring(3).Trim()
        $allowed = $false

        foreach ($allowedPath in $allowedPaths) {
            if (
                $path -eq $allowedPath -or
                $path.StartsWith($allowedPath)
            ) {
                $allowed = $true
                break
            }
        }

        if (-not $allowed) {
            $unexpected.Add($line)
        }
    }

    if ($unexpected.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        foreach ($line in $unexpected) {
            Write-Host $line -ForegroundColor Yellow
        }

        throw (
            "The working tree contains changes outside the " +
            "vehicle-device API recovery scope."
        )
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Vehicle Device API Recovery v6" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath
    $script:RootPath = (Get-Location).Path
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found."
    }

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -ne "feat/vehicle-device-api") {
        throw (
            "Expected branch feat/vehicle-device-api, " +
            "but current branch is $currentBranch"
        )
    }

    Assert-ExpectedRepositoryState

    $devicesService =
        "services/backend-api/src/assets/devices/devices.service.ts"

    $vehiclesService =
        "services/backend-api/src/assets/vehicles/vehicles.service.ts"

    $e2eTest =
        "services/backend-api/test/vehicle-device.e2e-spec.ts"

    $foundationScript =
        "scripts/solid-tracker-vehicle-device-api.ps1"

    foreach ($requiredPath in @(
        ".env",
        $devicesService,
        $vehiclesService,
        $e2eTest,
        $foundationScript,
        "services/backend-api/prisma.config.ts",
        "services/backend-api/prisma/schema.prisma"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file is missing: $requiredPath"
        }
    }

    Write-Step 1 8 "Confirming the existing migration state"

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $migrationCountSql = @'
SELECT COUNT(*)
FROM "_prisma_migrations"
WHERE finished_at IS NOT NULL
  AND rolled_back_at IS NULL;
'@

    $migrationCountOutput = $migrationCountSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify the applied migration count."
    }

    $migrationCount = [int](($migrationCountOutput | Out-String).Trim())

    if ($migrationCount -ne 5) {
        throw (
            "Expected exactly 5 applied migrations for this API-only " +
            "stage, but found $migrationCount."
        )
    }

    Write-Host "Applied migrations: 5" -ForegroundColor Green
    Write-Host "New migration required: no" -ForegroundColor Green

    Write-Step 2 8 "Correcting Prisma identity-condition construction"

    $deviceDuplicateStart = @'
    const duplicate = await this.prisma.device.findFirst({
'@

    $deviceDuplicateEnd = @'
    if (duplicate) {
'@

    $deviceDuplicateReplacement = @'
    const identityConditions: Prisma.DeviceWhereInput[] = [];

    if (imei) {
      identityConditions.push({ imei });
    }

    if (serialNumber) {
      identityConditions.push({ serialNumber });
    }

    const duplicate = await this.prisma.device.findFirst({
      where: {
        OR: identityConditions,
      },
      select: {
        id: true,
      },
    });

'@

    $deviceContent = Get-LfContent $devicesService

    if (-not $deviceContent.Contains(
        "const identityConditions: Prisma.DeviceWhereInput[] = [];"
    )) {
        $deviceContent = Replace-LfBlock `
            -Content $deviceContent `
            -StartMarker $deviceDuplicateStart `
            -EndMarker $deviceDuplicateEnd `
            -Replacement $deviceDuplicateReplacement
    }

    Set-LfContent $devicesService $deviceContent
    Write-Host "[UPDATED] $devicesService" -ForegroundColor Green

    $vehicleMethodReplacement = @'
  private async assertUniqueIdentity(
    identity: {
      normalizedRegistrationNumber?: string | null;
      chassisNumber?: string | null;
      engineNumber?: string | null;
    },
    excludedVehicleId?: string,
  ): Promise<void> {
    const identityConditions: Prisma.VehicleWhereInput[] = [];

    if (identity.normalizedRegistrationNumber) {
      identityConditions.push({
        normalizedRegistrationNumber:
          identity.normalizedRegistrationNumber,
      });
    }

    if (identity.chassisNumber) {
      identityConditions.push({
        chassisNumber: identity.chassisNumber,
      });
    }

    if (identity.engineNumber) {
      identityConditions.push({
        engineNumber: identity.engineNumber,
      });
    }

    if (identityConditions.length === 0) {
      return;
    }

    const duplicate = await this.prisma.vehicle.findFirst({
      where: {
        id: excludedVehicleId
          ? {
              not: excludedVehicleId,
            }
          : undefined,
        OR: identityConditions,
      },
      select: {
        id: true,
      },
    });

    if (duplicate) {
      throw new ConflictException(
        'Vehicle registration, chassis, or engine identity already exists.',
      );
    }
  }
'@

    $vehicleContent = Get-LfContent $vehiclesService

    if (-not $vehicleContent.Contains(
        "const identityConditions: Prisma.VehicleWhereInput[] = [];"
    )) {
        $vehicleMethodStart = $vehicleContent.IndexOf(
            "  private async assertUniqueIdentity(",
            [System.StringComparison]::Ordinal
        )

        if ($vehicleMethodStart -lt 0) {
            throw "Vehicle identity method start was not found."
        }

        $classClosingBrace = $vehicleContent.LastIndexOf(
            "`n}",
            [System.StringComparison]::Ordinal
        )

        if ($classClosingBrace -le $vehicleMethodStart) {
            throw "Vehicle service class closing brace was not found."
        }

        $vehicleContent = (
            $vehicleContent.Substring(0, $vehicleMethodStart) +
            $vehicleMethodReplacement +
            $vehicleContent.Substring($classClosingBrace)
        )
    }

    Set-LfContent $vehiclesService $vehicleContent
    Write-Host "[UPDATED] $vehiclesService" -ForegroundColor Green

    Write-Step 3 8 "Correcting vehicle detail and replacement semantics"

    $vehicleContent = Get-LfContent $vehiclesService
    $billingMarker = "        billingSubscriptions: {"
    $billingStart = $vehicleContent.IndexOf(
        $billingMarker,
        [System.StringComparison]::Ordinal
    )

    if ($billingStart -ge 0) {
        $braceStart = $vehicleContent.IndexOf(
            "{",
            $billingStart,
            [System.StringComparison]::Ordinal
        )

        if ($braceStart -lt 0) {
            throw "Vehicle billing include opening brace was not found."
        }

        $depth = 0
        $billingEnd = -1

        for ($index = $braceStart; $index -lt $vehicleContent.Length; $index++) {
            $character = $vehicleContent[$index]

            if ($character -eq "{") {
                $depth++
            }
            elseif ($character -eq "}") {
                $depth--

                if ($depth -eq 0) {
                    $billingEnd = $index + 1
                    break
                }
            }
        }

        if ($billingEnd -lt 0) {
            throw "Vehicle billing include closing brace was not found."
        }

        if (
            $billingEnd -lt $vehicleContent.Length -and
            $vehicleContent[$billingEnd] -eq ","
        ) {
            $billingEnd++
        }

        if (
            $billingEnd -lt $vehicleContent.Length -and
            $vehicleContent[$billingEnd] -eq "`n"
        ) {
            $billingEnd++
        }

        $vehicleContent = (
            $vehicleContent.Substring(0, $billingStart) +
            $vehicleContent.Substring($billingEnd)
        )
    }

    Set-LfContent $vehiclesService $vehicleContent
    Write-Host "[UPDATED] $vehiclesService relation include" -ForegroundColor Green

    $deviceContent = Get-LfContent $devicesService
    $replaceMethodStart = $deviceContent.IndexOf(
        "  async replace(",
        [System.StringComparison]::Ordinal
    )

    if ($replaceMethodStart -lt 0) {
        throw "Device replacement method was not found."
    }

    $availabilityCallStart = $deviceContent.IndexOf(
        "    await this.assertInstallationAvailability(",
        $replaceMethodStart,
        [System.StringComparison]::Ordinal
    )

    if ($availabilityCallStart -lt 0) {
        throw "Replacement availability call was not found."
    }

    $availabilityCallEnd = $deviceContent.IndexOf(
        "    );",
        $availabilityCallStart,
        [System.StringComparison]::Ordinal
    )

    if ($availabilityCallEnd -lt 0) {
        throw "Replacement availability call terminator was not found."
    }

    $availabilityCallEnd += "    );".Length

    $replacementAvailabilityCall = @'
    await this.assertInstallationAvailability(
      dto.replacementDeviceId,
      activeAssignment.vehicleId,
      replacementDevice.lifecycleStatus,
      activeAssignment.id,
    );
'@

    $deviceContent = (
        $deviceContent.Substring(0, $availabilityCallStart) +
        $replacementAvailabilityCall +
        $deviceContent.Substring($availabilityCallEnd)
    )

    $availabilityMethodStart = $deviceContent.IndexOf(
        "  private async assertInstallationAvailability(",
        [System.StringComparison]::Ordinal
    )

    $nextMethodStart = $deviceContent.IndexOf(
        "  private async installWithinTransaction(",
        [System.StringComparison]::Ordinal
    )

    if (
        $availabilityMethodStart -lt 0 -or
        $nextMethodStart -le $availabilityMethodStart
    ) {
        throw "Installation availability method boundaries were not found."
    }

    $availabilityMethod = @'
  private async assertInstallationAvailability(
    deviceId: string,
    vehicleId: string,
    lifecycleStatus: string,
    ignoredVehicleAssignmentId?: string,
  ): Promise<void> {
    if (!['IN_STOCK', 'ALLOCATED'].includes(lifecycleStatus)) {
      throw new ConflictException(
        'Device lifecycle state is not available for installation.',
      );
    }

    const [deviceAssignment, vehiclePrimary] =
      await Promise.all([
        this.prisma.vehicleDeviceAssignment.findFirst({
          where: {
            deviceId,
            status: 'ACTIVE',
          },
          select: {
            id: true,
          },
        }),
        this.prisma.vehicleDeviceAssignment.findFirst({
          where: {
            id: ignoredVehicleAssignmentId
              ? {
                  not: ignoredVehicleAssignmentId,
                }
              : undefined,
            vehicleId,
            assignmentType: 'PRIMARY',
            status: 'ACTIVE',
          },
          select: {
            id: true,
          },
        }),
      ]);

    if (deviceAssignment) {
      throw new ConflictException(
        'Device already has an active vehicle assignment.',
      );
    }

    if (vehiclePrimary) {
      throw new ConflictException(
        'Vehicle already has an active primary device. Use replacement.',
      );
    }
  }

'@

    $deviceContent = (
        $deviceContent.Substring(0, $availabilityMethodStart) +
        $availabilityMethod +
        $deviceContent.Substring($nextMethodStart)
    )

    Set-LfContent $devicesService $deviceContent
    Write-Host "[UPDATED] $devicesService replacement flow" -ForegroundColor Green

    Write-Step 4 8 "Rewriting the asset lifecycle E2E test"

    $e2eContent = @'
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

describe('Vehicle and device lifecycle (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let accessToken: string;
  let platformUserId: string;
  let platformMembershipId: string;
  let platformRoleAssignmentId: string;
  let dealerId: string;
  let customerId: string;
  let vehicleId: string;
  let deviceModelId: string;
  let firstDeviceId: string;
  let replacementDeviceId: string;

  const numericSuffix = randomInt(
    10_000_000,
    100_000_000,
  ).toString();
  const codeSuffix = randomUUID()
    .replace(/-/g, '')
    .slice(0, 10)
    .toUpperCase();
  const mobileNumber = `+88018${numericSuffix}`;
  const password = 'SolidTrackerTest123';

  beforeAll(async () => {
    const moduleFixture: TestingModule =
      await Test.createTestingModule({
        imports: [AppModule],
      }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    const passwordService = app.get(PasswordService);
    const passwordHash = await passwordService.hash(password);

    const platformOrganization =
      await prisma.organization.findUniqueOrThrow({
        where: {
          code: 'ORG-PLATFORM',
        },
      });

    const superAdminRole = await prisma.role.findUniqueOrThrow({
      where: {
        code: 'PLATFORM_SUPER_ADMIN',
      },
    });

    const user = await prisma.user.create({
      data: {
        userCode: `USR-E2E-${codeSuffix}`,
        fullName: 'Vehicle Device E2E Administrator',
        mobileNumber,
        normalizedMobileNumber: mobileNumber,
        passwordHash,
        passwordChangedAt: new Date(),
        status: 'ACTIVE',
        mobileVerifiedAt: new Date(),
      },
    });

    platformUserId = user.id;

    const membership =
      await prisma.organizationMembership.create({
        data: {
          organizationId: platformOrganization.id,
          userId: user.id,
          membershipType: 'EMPLOYEE',
          status: 'ACTIVE',
          isPrimary: true,
          joinedAt: new Date(),
        },
      });

    platformMembershipId = membership.id;

    const assignment = await prisma.roleAssignment.create({
      data: {
        userId: user.id,
        roleId: superAdminRole.id,
        organizationMembershipId: membership.id,
        scopeType: 'PLATFORM',
        scopeId: platformOrganization.id,
        status: 'ACTIVE',
        assignedByUserId: user.id,
      },
    });

    platformRoleAssignmentId = assignment.id;

    const loginResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        mobileNumber,
        password,
        platform: 'WEB',
        deviceName: 'Vehicle Device E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = loginResponse.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

    if (prisma) {
      if (vehicleId) {
        await prisma.vehicle.update({
          where: {
            id: vehicleId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (customerId) {
        await prisma.customer.update({
          where: {
            id: customerId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (dealerId) {
        await prisma.organization.update({
          where: {
            id: dealerId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      for (const deviceId of [
        firstDeviceId,
        replacementDeviceId,
      ]) {
        if (deviceId) {
          await prisma.device.update({
            where: {
              id: deviceId,
            },
            data: {
              lifecycleStatus: 'RETIRED',
              retiredAt: now,
            },
          });
        }
      }

      if (deviceModelId) {
        await prisma.deviceModel.update({
          where: {
            id: deviceModelId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (platformUserId) {
        await prisma.userSession.deleteMany({
          where: {
            userId: platformUserId,
          },
        });

        await prisma.roleAssignment.deleteMany({
          where: {
            id: platformRoleAssignmentId,
          },
        });

        await prisma.organizationMembership.deleteMany({
          where: {
            id: platformMembershipId,
          },
        });

        await prisma.user.update({
          where: {
            id: platformUserId,
          },
          data: {
            status: 'ARCHIVED',
            passwordHash: null,
            archivedAt: now,
          },
        });
      }
    }

    if (app) {
      await app.close();
    }
  });

  it('registers, allocates, installs, replaces, removes, and returns devices', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Asset E2E Dealer ${codeSuffix}`,
        contactMobile: `017${numericSuffix}`,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        managingDealerId: dealerId,
        fullName: `Asset E2E Customer ${codeSuffix}`,
        primaryMobile: `016${numericSuffix}`,
      })
      .expect(201);

    customerId = customerResponse.body.id as string;

    const vehicleResponse = await request(app.getHttpServer())
      .post('/api/v1/vehicles')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        vehicleType: 'CAR',
        registrationNumber: `DHAKA-E2E-${codeSuffix}`,
        manufacturer: 'Solid Tracker Test',
        modelName: 'Lifecycle Car',
        manufacturingYear: 2026,
      })
      .expect(201);

    vehicleId = vehicleResponse.body.id as string;

    const modelResponse = await request(app.getHttpServer())
      .post('/api/v1/device-models')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        manufacturer: `Solid Tracker E2E ${codeSuffix}`,
        modelName: 'ST-100',
        protocol: 'osmand',
        networkType: 'LTE_4G',
        capabilities: {
          ignition: true,
          relay: true,
          sos: true,
        },
      })
      .expect(201);

    deviceModelId = modelResponse.body.id as string;

    const imeiSuffix = `${Date.now()}`
      .slice(-13)
      .padStart(13, '0');

    const firstDeviceResponse = await request(app.getHttpServer())
      .post('/api/v1/devices')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceModelId,
        imei: `86${imeiSuffix}`,
        serialNumber: `ST-E2E-A-${codeSuffix}`,
        hardwareVersion: '1.0',
        firmwareVersion: '1.0.0',
      })
      .expect(201);

    firstDeviceId = firstDeviceResponse.body.id as string;

    const replacementDeviceResponse = await request(
      app.getHttpServer(),
    )
      .post('/api/v1/devices')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceModelId,
        imei: `87${imeiSuffix}`,
        serialNumber: `ST-E2E-B-${codeSuffix}`,
        hardwareVersion: '1.0',
        firmwareVersion: '1.0.1',
      })
      .expect(201);

    replacementDeviceId =
      replacementDeviceResponse.body.id as string;

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${firstDeviceId}/allocate`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        notes: 'E2E first-device allocation',
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(
        `/api/v1/devices/${replacementDeviceId}/allocate`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        notes: 'E2E replacement-device allocation',
      })
      .expect(201);

    const installationResponse = await request(
      app.getHttpServer(),
    )
      .post(`/api/v1/devices/${firstDeviceId}/install`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        vehicleId,
        latitude: 23.8103,
        longitude: 90.4125,
        ignitionConnected: true,
        relayConnected: true,
        sosConnected: true,
        powerConnectionType: 'BATTERY_DIRECT',
      })
      .expect(201);

    expect(installationResponse.body.status).toBe('COMPLETED');
    expect(
      installationResponse.body.assignment.status,
    ).toBe('ACTIVE');

    const replacementResponse = await request(
      app.getHttpServer(),
    )
      .post(`/api/v1/devices/${firstDeviceId}/replace`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        replacementDeviceId,
        removalReason: 'WARRANTY_REPLACEMENT',
        ignitionConnected: true,
        relayConnected: true,
        sosConnected: true,
        notes: 'E2E replacement',
      })
      .expect(201);

    expect(
      replacementResponse.body.removed.assignment.status,
    ).toBe('ENDED');
    expect(
      replacementResponse.body.installed.assignment.status,
    ).toBe('ACTIVE');

    await request(app.getHttpServer())
      .post(
        `/api/v1/devices/${replacementDeviceId}/remove`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        assignmentEndReason: 'CUSTOMER_REQUEST',
        removalReason: 'CUSTOMER_REQUEST',
        notes: 'E2E final removal',
      })
      .expect(201);

    const historyResponse = await request(app.getHttpServer())
      .get(`/api/v1/vehicles/${vehicleId}/device-history`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(historyResponse.body).toHaveLength(2);
    expect(
      historyResponse.body.every(
        (assignment: { status: string }) =>
          assignment.status === 'ENDED',
      ),
    ).toBe(true);

    const firstAllocated =
      await prisma.device.findUniqueOrThrow({
        where: {
          id: firstDeviceId,
        },
      });

    const replacementAllocated =
      await prisma.device.findUniqueOrThrow({
        where: {
          id: replacementDeviceId,
        },
      });

    expect(firstAllocated.lifecycleStatus).toBe('ALLOCATED');
    expect(replacementAllocated.lifecycleStatus).toBe(
      'ALLOCATED',
    );

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${firstDeviceId}/return`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        notes: 'E2E first-device return',
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(
        `/api/v1/devices/${replacementDeviceId}/return`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        notes: 'E2E replacement-device return',
      })
      .expect(201);

    const firstReturned =
      await prisma.device.findUniqueOrThrow({
        where: {
          id: firstDeviceId,
        },
      });

    const replacementReturned =
      await prisma.device.findUniqueOrThrow({
        where: {
          id: replacementDeviceId,
        },
      });

    expect(firstReturned.lifecycleStatus).toBe('IN_STOCK');
    expect(replacementReturned.lifecycleStatus).toBe(
      'IN_STOCK',
    );
  });
});
'@

    Write-Utf8File $e2eTest $e2eContent

    Write-Step 5 8 "Synchronizing the reproducible foundation script"

    $foundationContent = Get-LfContent $foundationScript

    $foundationContent = Sync-FoundationEmbeddedFile `
        -FoundationContent $foundationContent `
        -EmbeddedPath "services\backend-api\src\assets\devices\devices.service.ts" `
        -SourceContent (Get-LfContent $devicesService)

    $foundationContent = Sync-FoundationEmbeddedFile `
        -FoundationContent $foundationContent `
        -EmbeddedPath "services\backend-api\src\assets\vehicles\vehicles.service.ts" `
        -SourceContent (Get-LfContent $vehiclesService)

    $foundationContent = Sync-FoundationEmbeddedFile `
        -FoundationContent $foundationContent `
        -EmbeddedPath "services\backend-api\test\vehicle-device.e2e-spec.ts" `
        -SourceContent (Get-LfContent $e2eTest)

    Set-LfContent $foundationScript $foundationContent
    Write-Host "[UPDATED] $foundationScript" -ForegroundColor Green

    Write-Step 6 8 "Running complete backend verification"

    Invoke-CheckedCommand "Prisma format" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma format `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma validate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma validate `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma generate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma generate `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    Invoke-CheckedCommand "Backend format" {
        pnpm.cmd --filter "@solid-tracker/backend-api" format
    }

    Invoke-CheckedCommand "Backend lint" {
        pnpm.cmd --filter "@solid-tracker/backend-api" lint
    }

    Invoke-CheckedCommand "Backend typecheck" {
        pnpm.cmd --filter "@solid-tracker/backend-api" typecheck
    }

    Invoke-CheckedCommand "Backend unit tests" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test --runInBand
    }

    Invoke-CheckedCommand "Backend E2E tests" {
        pnpm.cmd --filter "@solid-tracker/backend-api" test:e2e --runInBand
    }

    Invoke-CheckedCommand "Backend production build" {
        pnpm.cmd --filter "@solid-tracker/backend-api" build
    }

    Write-Step 7 8 "Verifying vehicle-device database invariants"

    $databaseVerification = @'
SELECT
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'public'
  ) AS public_table_count,
  (
    SELECT COUNT(*)
    FROM "_prisma_migrations"
    WHERE finished_at IS NOT NULL
      AND rolled_back_at IS NULL
  ) AS applied_migration_count,
  (
    SELECT COUNT(*)
    FROM "permissions"
    WHERE "code" IN (
      'vehicle.view',
      'vehicle.create',
      'vehicle.update',
      'device.view',
      'device.register',
      'device.install',
      'device.replace',
      'device.remove'
    )
      AND "status" = 'ACTIVE'
  ) AS asset_permission_count,
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'device_ownership_history_one_active_per_device',
        'device_custody_history_one_active_per_device',
        'dealer_device_allocations_one_active_per_device',
        'vehicle_device_assignments_one_active_per_device',
        'vehicle_device_assignments_one_active_primary_per_vehicle'
      )
  ) AS invariant_index_count,
  (
    SELECT COUNT(DISTINCT trigger_name)
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'device_ownership_validate_owner',
        'device_custody_validate_custodian',
        'dealer_device_allocations_validate_dealer',
        'device_installations_validate_dealer',
        'vehicle_device_assignments_validate_installation'
      )
  ) AS invariant_trigger_count;
'@

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "Vehicle-device database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $verificationParts = $verificationLine.Split(",")

    if ($verificationParts.Count -ne 5) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTableCount = [int]$verificationParts[0]
    $appliedMigrationCount = [int]$verificationParts[1]
    $permissionCount = [int]$verificationParts[2]
    $indexCount = [int]$verificationParts[3]
    $triggerCount = [int]$verificationParts[4]

    if ($publicTableCount -lt 50) {
        throw "Expected at least 50 public tables."
    }

    if ($appliedMigrationCount -ne 5) {
        throw "Expected exactly 5 applied migrations."
    }

    if ($permissionCount -ne 8) {
        throw "Expected 8 active vehicle-device permissions."
    }

    if ($indexCount -ne 5) {
        throw "Expected 5 vehicle-device invariant indexes."
    }

    if ($triggerCount -ne 5) {
        throw "Expected 5 distinct vehicle-device invariant triggers."
    }

    Write-Host "Public tables:       $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:  $appliedMigrationCount" -ForegroundColor Green
    Write-Host "Asset permissions:   $permissionCount" -ForegroundColor Green
    Write-Host "Invariant indexes:   $indexCount" -ForegroundColor Green
    Write-Host "Invariant triggers:  $triggerCount" -ForegroundColor Green

    Write-Step 8 8 "Writing architecture documentation and committing"

    Write-Utf8File `
        "docs\architecture\vehicle-device-api.md" `
        @'
# Vehicle and Device API

## Scope

This stage provides REST APIs and transactional application services for:

- vehicle registration and updates;
- scoped vehicle lists and tracker-assignment history;
- device-model administration;
- physical device inventory registration;
- platform-to-dealer allocation;
- dealer-to-platform return;
- installation as the active primary tracker;
- transactional tracker replacement;
- tracker removal;
- ownership, custody, allocation, installation, and assignment history.

No new migration is introduced. The existing asset migration already defines the tables, partial unique indexes, constraints, and validation triggers.

## Authorization

Platform scope administers device models, inventory registration, and dealer allocation.

Dealer scope can access devices allocated to that dealer and trackers installed for customers managed by that dealer.

Customer scope can view devices only through active vehicle assignments.

Direct-customer installation requires platform scope.

IMEI and serial-number identity are immutable through the normal update endpoint.

## Lifecycle

```text
Platform stock
    ↓ allocate
Dealer available stock
    ↓ install
Customer custody and active vehicle assignment
    ↓ remove
Dealer available stock
    ↓ return
Platform stock
```

Ownership and custody are separate. Registration creates platform ownership and custody. Allocation and installation change custody without silently changing legal ownership.

## Replacement transaction

Tracker replacement performs the following in one database transaction:

1. ends the current primary assignment;
2. marks the old installation removed;
3. restores the old device to dealer or platform custody;
4. creates the replacement installation;
5. creates the new primary assignment;
6. moves replacement-device custody to the customer;
7. updates allocation and device lifecycle states;
8. preserves every historical row.

The availability check deliberately ignores the current assignment being replaced while still rejecting every other active primary assignment.

## Endpoints

```text
GET    /api/v1/vehicles
POST   /api/v1/vehicles
GET    /api/v1/vehicles/:vehicleId
PATCH  /api/v1/vehicles/:vehicleId
GET    /api/v1/vehicles/:vehicleId/device-history

GET    /api/v1/device-models
POST   /api/v1/device-models
PATCH  /api/v1/device-models/:deviceModelId

GET    /api/v1/devices
POST   /api/v1/devices
GET    /api/v1/devices/:deviceId
PATCH  /api/v1/devices/:deviceId
POST   /api/v1/devices/:deviceId/allocate
POST   /api/v1/devices/:deviceId/return
POST   /api/v1/devices/:deviceId/install
POST   /api/v1/devices/:deviceId/replace
POST   /api/v1/devices/:deviceId/remove
GET    /api/v1/devices/:deviceId/history
```

## Verification

The E2E workflow covers dealer and customer setup, vehicle registration, device-model creation, two inventory registrations, allocations, installation, replacement, removal, assignment history, and inventory return.
'@

    git add -- `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/assets" `
        "services/backend-api/test/vehicle-device.e2e-spec.ts" `
        "docs/architecture/vehicle-device-api.md" `
        "scripts/solid-tracker-vehicle-device-api.ps1" `
        "scripts/solid-tracker-vehicle-device-typecheck-recovery.ps1"

    git commit `
        -m "feat(assets): establish vehicle and device APIs"

    if ($LASTEXITCODE -ne 0) {
        throw "Vehicle-device API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Vehicle and Device API Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current
    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate
    Write-Host ""
    Write-Host "Recent graph:" -ForegroundColor Yellow
    git log --oneline --decorate --graph -8
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    Write-Host "Next implementation stage:" -ForegroundColor Yellow
    Write-Host (
        "Subscription plans, subscriptions, invoices, payments, " +
        "commission, and settlement APIs"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "VEHICLE DEVICE API RECOVERY V6 FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "No migration reset is required. This stage does not add a migration."
    ) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
