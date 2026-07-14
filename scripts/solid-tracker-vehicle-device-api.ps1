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

function Assert-CleanExceptSelf {
    $allowedEntries = @(
        "?? scripts/solid-tracker-vehicle-device-api.ps1"
    )

    $unexpectedChanges = @(
        git status --short |
            Where-Object {
                $_ -and
                $allowedEntries -notcontains $_.TrimEnd()
            }
    )

    if ($unexpectedChanges.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        $unexpectedChanges | ForEach-Object {
            Write-Host $_ -ForegroundColor Yellow
        }

        throw (
            "Working tree contains changes other than this " +
            "vehicle-device API script."
        )
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Vehicle and Device API" -ForegroundColor Cyan
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

    foreach ($requiredPath in @(
        ".env",
        ".env.example",
        "compose.yaml",
        "services\backend-api\package.json",
        "services\backend-api\prisma.config.ts",
        "services\backend-api\prisma\schema.prisma",
        "services\backend-api\src\app.module.ts",
        "services\backend-api\src\database\prisma.service.ts",
        "services\backend-api\src\identity\access-control\access-control.module.ts",
        "services\backend-api\src\identity\audit\audit.service.ts",
        "services\backend-api\src\management\common\pagination-query.dto.ts",
        "services\backend-api\test\jest-e2e.json"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file is missing: $requiredPath"
        }
    }

    Write-Step 1 9 `
        "Merging dealer-customer APIs and creating the asset API branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/dealer-customer-api") {
        Assert-CleanExceptSelf

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        git merge-base --is-ancestor `
            feat/dealer-customer-api `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge dealer and customer APIs into main" {
                git merge `
                    --no-ff `
                    feat/dealer-customer-api `
                    -m "merge: integrate dealer and customer APIs"
            }
        }
        else {
            Write-Host (
                "Dealer and customer APIs are already contained in main."
            ) -ForegroundColor Green
        }

        $branchExists = git branch --list "feat/vehicle-device-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing vehicle-device API branch" {
                git checkout feat/vehicle-device-api
            }
        }
        else {
            Invoke-CheckedCommand "Create vehicle-device API branch" {
                git checkout -b feat/vehicle-device-api
            }
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-CleanExceptSelf

        git merge-base --is-ancestor `
            feat/dealer-customer-api `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge dealer and customer APIs into main" {
                git merge `
                    --no-ff `
                    feat/dealer-customer-api `
                    -m "merge: integrate dealer and customer APIs"
            }
        }

        $branchExists = git branch --list "feat/vehicle-device-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing vehicle-device API branch" {
                git checkout feat/vehicle-device-api
            }
        }
        else {
            Invoke-CheckedCommand "Create vehicle-device API branch" {
                git checkout -b feat/vehicle-device-api
            }
        }
    }
    elseif ($currentBranch -eq "feat/vehicle-device-api") {
        Assert-CleanExceptSelf
        Write-Host "Already on feat/vehicle-device-api." -ForegroundColor Green
    }
    else {
        throw (
            "Expected feat/dealer-customer-api, main, or " +
            "feat/vehicle-device-api. Current branch: $currentBranch"
        )
    }

    Write-Step 2 9 "Validating infrastructure, migrations, and asset schema"

    $postgresHealth = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        solid-tracker-postgres 2>$null

    $redisHealth = docker inspect `
        --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
        solid-tracker-redis 2>$null

    if (
        $postgresHealth.Trim() -ne "healthy" -or
        $redisHealth.Trim() -ne "healthy"
    ) {
        throw "PostgreSQL and Redis must both be running and healthy."
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $schemaContent = [System.IO.File]::ReadAllText(
        (Join-Path $script:RootPath "services\backend-api\prisma\schema.prisma")
    )

    foreach ($requiredModel in @(
        "model Vehicle {",
        "model DeviceModel {",
        "model Device {",
        "model DeviceOwnershipHistory {",
        "model DeviceCustodyHistory {",
        "model DealerDeviceAllocation {",
        "model DeviceInstallation {",
        "model VehicleDeviceAssignment {"
    )) {
        if (-not $schemaContent.Contains($requiredModel)) {
            throw "Required Prisma asset model is missing: $requiredModel"
        }
    }

    Write-Host "PostgreSQL: healthy" -ForegroundColor Green
    Write-Host "Redis:      healthy" -ForegroundColor Green
    Write-Host "Asset schema: present" -ForegroundColor Green

    Write-Step 3 9 "Writing asset access, identifiers, and query DTOs"

    Write-Utf8File `
        "services\backend-api\src\assets\common\asset-code.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Injectable()
export class AssetCodeService {
  vehicle(): string {
    return this.create('VEH');
  }

  deviceModel(): string {
    return this.create('DVM');
  }

  device(): string {
    return this.create('DEV');
  }

  allocation(): string {
    return this.create('ALC');
  }

  installation(): string {
    return this.create('INS');
  }

  private create(prefix: string): string {
    return `${prefix}-${randomUUID()
      .replace(/-/g, '')
      .slice(0, 12)
      .toUpperCase()}`;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\common\asset-access.service.ts" `
        @'
import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class AssetAccessService {
  constructor(private readonly prisma: PrismaService) {}

  isPlatformScoped(auth: AuthContext): boolean {
    return auth.roles.some((role) => role.scopeType === 'PLATFORM');
  }

  dealerScopeIds(auth: AuthContext): string[] {
    return Array.from(
      new Set(
        auth.roles
          .filter((role) => role.scopeType === 'DEALER')
          .map((role) => role.scopeId),
      ),
    );
  }

  customerScopeIds(auth: AuthContext): string[] {
    return Array.from(
      new Set([
        ...auth.customerIds,
        ...auth.roles
          .filter((role) => role.scopeType === 'CUSTOMER')
          .map((role) => role.scopeId),
      ]),
    );
  }

  assertPlatform(auth: AuthContext): void {
    if (!this.isPlatformScoped(auth)) {
      throw new ForbiddenException(
        'This operation requires platform scope.',
      );
    }
  }

  assertDealer(auth: AuthContext, dealerId: string): void {
    if (this.isPlatformScoped(auth)) {
      return;
    }

    if (!this.dealerScopeIds(auth).includes(dealerId)) {
      throw new ForbiddenException(
        'The selected dealer is outside the authenticated scope.',
      );
    }
  }

  vehicleWhere(auth: AuthContext): Prisma.VehicleWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);
    const scopes: Prisma.VehicleWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push({
        customer: {
          managingDealerId: {
            in: dealerIds,
          },
        },
      });
    }

    if (customerIds.length > 0) {
      scopes.push({
        customerId: {
          in: customerIds,
        },
      });
    }

    return scopes.length > 0
      ? {
          OR: scopes,
        }
      : {
          id: {
            in: [],
          },
        };
  }

  deviceWhere(auth: AuthContext): Prisma.DeviceWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);
    const scopes: Prisma.DeviceWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push(
        {
          dealerAllocations: {
            some: {
              dealerOrganizationId: {
                in: dealerIds,
              },
              status: {
                in: ['ALLOCATED', 'AVAILABLE', 'INSTALLED'],
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
                  managingDealerId: {
                    in: dealerIds,
                  },
                },
              },
            },
          },
        },
      );
    }

    if (customerIds.length > 0) {
      scopes.push({
        vehicleAssignments: {
          some: {
            status: 'ACTIVE',
            vehicle: {
              customerId: {
                in: customerIds,
              },
            },
          },
        },
      });
    }

    return scopes.length > 0
      ? {
          OR: scopes,
        }
      : {
          id: {
            in: [],
          },
        };
  }

  async assertVehicle(
    auth: AuthContext,
    vehicleId: string,
  ): Promise<{
    id: string;
    customerId: string;
    status: string;
    customer: {
      managingDealerId: string | null;
      status: string;
    };
  }> {
    const vehicle = await this.prisma.vehicle.findUnique({
      where: {
        id: vehicleId,
      },
      select: {
        id: true,
        customerId: true,
        status: true,
        customer: {
          select: {
            managingDealerId: true,
            status: true,
          },
        },
      },
    });

    if (!vehicle) {
      throw new NotFoundException('Vehicle was not found.');
    }

    if (this.isPlatformScoped(auth)) {
      return vehicle;
    }

    const dealerAllowed =
      vehicle.customer.managingDealerId !== null &&
      this.dealerScopeIds(auth).includes(
        vehicle.customer.managingDealerId,
      );

    const customerAllowed = this.customerScopeIds(auth).includes(
      vehicle.customerId,
    );

    if (!dealerAllowed && !customerAllowed) {
      throw new ForbiddenException(
        'The selected vehicle is outside the authenticated scope.',
      );
    }

    return vehicle;
  }

  async assertVehicleMutation(
    auth: AuthContext,
    vehicleId: string,
  ): Promise<{
    id: string;
    customerId: string;
    status: string;
    customer: {
      managingDealerId: string | null;
      status: string;
    };
  }> {
    const vehicle = await this.assertVehicle(auth, vehicleId);

    if (this.isPlatformScoped(auth)) {
      return vehicle;
    }

    if (
      !vehicle.customer.managingDealerId ||
      !this.dealerScopeIds(auth).includes(
        vehicle.customer.managingDealerId,
      )
    ) {
      throw new ForbiddenException(
        'Vehicle administration requires matching dealer scope.',
      );
    }

    return vehicle;
  }

  async assertCustomerMutation(
    auth: AuthContext,
    customerId: string,
  ): Promise<{
    id: string;
    managingDealerId: string | null;
    status: string;
  }> {
    const customer = await this.prisma.customer.findUnique({
      where: {
        id: customerId,
      },
      select: {
        id: true,
        managingDealerId: true,
        status: true,
      },
    });

    if (!customer) {
      throw new NotFoundException('Customer was not found.');
    }

    if (this.isPlatformScoped(auth)) {
      return customer;
    }

    if (
      !customer.managingDealerId ||
      !this.dealerScopeIds(auth).includes(
        customer.managingDealerId,
      )
    ) {
      throw new ForbiddenException(
        'Customer administration requires matching dealer scope.',
      );
    }

    return customer;
  }

  async assertDevice(auth: AuthContext, deviceId: string): Promise<void> {
    const count = await this.prisma.device.count({
      where: {
        AND: [
          {
            id: deviceId,
          },
          this.deviceWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException(
        'Device was not found within the authenticated scope.',
      );
    }
  }

  actorOrganizationId(auth: AuthContext): string | undefined {
    return this.dealerScopeIds(auth)[0] ?? auth.organizationIds[0];
  }

  async platformOrganizationId(): Promise<string> {
    const platform = await this.prisma.organization.findUnique({
      where: {
        code: 'ORG-PLATFORM',
      },
      select: {
        id: true,
      },
    });

    if (!platform) {
      throw new NotFoundException(
        'Solid Tracker platform organization was not found.',
      );
    }

    return platform.id;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\common\asset-query.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';

const vehicleStatuses = [
  'PENDING',
  'ACTIVE',
  'INACTIVE',
  'SUSPENDED',
  'ARCHIVED',
] as const;

const vehicleTypes = [
  'CAR',
  'MOTORCYCLE',
  'BUS',
  'TRUCK',
  'CNG',
  'PICKUP',
  'MICROBUS',
  'AMBULANCE',
  'CONSTRUCTION_EQUIPMENT',
  'OTHER',
] as const;

const deviceStatuses = [
  'RECEIVED',
  'IN_STOCK',
  'RESERVED',
  'ALLOCATED',
  'INSTALLED',
  'UNDER_REPAIR',
  'LOST',
  'DAMAGED',
  'RETIRED',
] as const;

export class VehicleQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ enum: vehicleStatuses })
  @IsOptional()
  @IsIn(vehicleStatuses)
  status?: (typeof vehicleStatuses)[number];

  @ApiPropertyOptional({ enum: vehicleTypes })
  @IsOptional()
  @IsIn(vehicleTypes)
  vehicleType?: (typeof vehicleTypes)[number];
}

export class DeviceQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  deviceModelId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dealerOrganizationId?: string;

  @ApiPropertyOptional({ enum: deviceStatuses })
  @IsOptional()
  @IsIn(deviceStatuses)
  lifecycleStatus?: (typeof deviceStatuses)[number];
}
'@

    Write-Step 4 9 "Writing vehicle registration and lifecycle APIs"

    Write-Utf8File `
        "services\backend-api\src\assets\vehicles\dto\create-vehicle.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

const vehicleTypes = [
  'CAR',
  'MOTORCYCLE',
  'BUS',
  'TRUCK',
  'CNG',
  'PICKUP',
  'MICROBUS',
  'AMBULANCE',
  'CONSTRUCTION_EQUIPMENT',
  'OTHER',
] as const;

export class CreateVehicleDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiProperty({ enum: vehicleTypes })
  @IsIn(vehicleTypes)
  vehicleType!: (typeof vehicleTypes)[number];

  @ApiPropertyOptional({ example: 'DHAKA-METRO-GA-12-3456' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  registrationNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  manufacturer?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  modelName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  @Min(1886)
  @Max(2100)
  manufacturingYear?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  color?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  chassisNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  engineNumber?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\vehicles\dto\update-vehicle.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

const vehicleStatuses = [
  'PENDING',
  'ACTIVE',
  'INACTIVE',
  'SUSPENDED',
  'ARCHIVED',
] as const;

const vehicleTypes = [
  'CAR',
  'MOTORCYCLE',
  'BUS',
  'TRUCK',
  'CNG',
  'PICKUP',
  'MICROBUS',
  'AMBULANCE',
  'CONSTRUCTION_EQUIPMENT',
  'OTHER',
] as const;

export class UpdateVehicleDto {
  @ApiPropertyOptional({ enum: vehicleTypes })
  @IsOptional()
  @IsIn(vehicleTypes)
  vehicleType?: (typeof vehicleTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  registrationNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  manufacturer?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  modelName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  @Min(1886)
  @Max(2100)
  manufacturingYear?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  color?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  chassisNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  engineNumber?: string;

  @ApiPropertyOptional({ enum: vehicleStatuses })
  @IsOptional()
  @IsIn(vehicleStatuses)
  status?: (typeof vehicleStatuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\vehicles\vehicles.service.ts" `
        @'
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import type { VehicleQueryDto } from '../common/asset-query.dto';
import type { CreateVehicleDto } from './dto/create-vehicle.dto';
import type { UpdateVehicleDto } from './dto/update-vehicle.dto';

@Injectable()
export class VehiclesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: AssetAccessService,
    private readonly codes: AssetCodeService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: VehicleQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.vehicleWhere(auth);
    const searchWhere: Prisma.VehicleWhereInput = query.search
      ? {
          OR: [
            {
              vehicleCode: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              registrationNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              chassisNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              engineNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
          ],
        }
      : {};

    const where: Prisma.VehicleWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.vehicleType
          ? {
              vehicleType: query.vehicleType,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {
              status: {
                not: 'ARCHIVED',
              },
            },
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.vehicle.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          customer: {
            include: {
              individualProfile: true,
              organizationProfile: true,
              managingDealer: {
                select: {
                  id: true,
                  code: true,
                  name: true,
                },
              },
            },
          },
          deviceAssignments: {
            where: {
              status: 'ACTIVE',
            },
            include: {
              device: {
                include: {
                  deviceModel: true,
                },
              },
            },
          },
        },
      }),
      this.prisma.vehicle.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, vehicleId: string) {
    await this.access.assertVehicle(auth, vehicleId);

    const vehicle = await this.prisma.vehicle.findUnique({
      where: {
        id: vehicleId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
            managingDealer: true,
          },
        },
        installations: {
          orderBy: {
            createdAt: 'desc',
          },
          include: {
            device: {
              include: {
                deviceModel: true,
              },
            },
          },
        },
        deviceAssignments: {
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            device: {
              include: {
                deviceModel: true,
              },
            },
            installation: true,
          },
        },
      },
    });

    if (!vehicle) {
      throw new NotFoundException('Vehicle was not found.');
    }

    return vehicle;
  }

  async create(auth: AuthContext, dto: CreateVehicleDto) {
    const customer = await this.access.assertCustomerMutation(auth, dto.customerId);

    if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
      throw new BadRequestException('Vehicle creation requires an active or pending customer.');
    }

    const normalizedRegistrationNumber = this.normalizeRegistration(dto.registrationNumber);

    await this.assertUniqueIdentity({
      normalizedRegistrationNumber,
      chassisNumber: this.optionalUpper(dto.chassisNumber),
      engineNumber: this.optionalUpper(dto.engineNumber),
    });

    const vehicle = await this.prisma.vehicle.create({
      data: {
        vehicleCode: this.codes.vehicle(),
        customerId: dto.customerId,
        registrationNumber: this.optional(dto.registrationNumber),
        normalizedRegistrationNumber,
        vehicleType: dto.vehicleType,
        manufacturer: this.optional(dto.manufacturer),
        modelName: this.optional(dto.modelName),
        manufacturingYear: dto.manufacturingYear,
        color: this.optional(dto.color),
        chassisNumber: this.optionalUpper(dto.chassisNumber),
        engineNumber: this.optionalUpper(dto.engineNumber),
        status: 'PENDING',
        createdByUserId: auth.userId,
      },
      include: {
        customer: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'vehicle.created',
      resourceType: 'Vehicle',
      resourceId: vehicle.id,
      scopeType: 'VEHICLE',
      scopeId: vehicle.id,
      afterData: vehicle,
    });

    return vehicle;
  }

  async update(auth: AuthContext, vehicleId: string, dto: UpdateVehicleDto) {
    await this.access.assertVehicleMutation(auth, vehicleId);

    const before = await this.prisma.vehicle.findUnique({
      where: {
        id: vehicleId,
      },
    });

    if (!before) {
      throw new NotFoundException('Vehicle was not found.');
    }

    if (dto.status === 'ARCHIVED') {
      const [activeAssignments, activeSubscriptions] = await Promise.all([
        this.prisma.vehicleDeviceAssignment.count({
          where: {
            vehicleId,
            status: 'ACTIVE',
          },
        }),
        this.prisma.subscription.count({
          where: {
            vehicleId,
            status: {
              in: ['PENDING', 'TRIALING', 'ACTIVE', 'PAST_DUE', 'SUSPENDED'],
            },
          },
        }),
      ]);

      if (activeAssignments > 0 || activeSubscriptions > 0) {
        throw new ConflictException(
          'Remove active trackers and close active subscriptions before archiving the vehicle.',
        );
      }
    }

    const normalizedRegistrationNumber =
      dto.registrationNumber !== undefined
        ? this.normalizeRegistration(dto.registrationNumber)
        : undefined;

    await this.assertUniqueIdentity(
      {
        normalizedRegistrationNumber,
        chassisNumber:
          dto.chassisNumber !== undefined ? this.optionalUpper(dto.chassisNumber) : undefined,
        engineNumber:
          dto.engineNumber !== undefined ? this.optionalUpper(dto.engineNumber) : undefined,
      },
      vehicleId,
    );

    const updated = await this.prisma.vehicle.update({
      where: {
        id: vehicleId,
      },
      data: {
        vehicleType: dto.vehicleType,
        registrationNumber:
          dto.registrationNumber !== undefined ? this.optional(dto.registrationNumber) : undefined,
        normalizedRegistrationNumber,
        manufacturer: dto.manufacturer !== undefined ? this.optional(dto.manufacturer) : undefined,
        modelName: dto.modelName !== undefined ? this.optional(dto.modelName) : undefined,
        manufacturingYear: dto.manufacturingYear,
        color: dto.color !== undefined ? this.optional(dto.color) : undefined,
        chassisNumber:
          dto.chassisNumber !== undefined ? this.optionalUpper(dto.chassisNumber) : undefined,
        engineNumber:
          dto.engineNumber !== undefined ? this.optionalUpper(dto.engineNumber) : undefined,
        status: dto.status,
        archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
      },
      include: {
        customer: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'vehicle.updated',
      resourceType: 'Vehicle',
      resourceId: vehicleId,
      scopeType: 'VEHICLE',
      scopeId: vehicleId,
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async history(auth: AuthContext, vehicleId: string) {
    await this.access.assertVehicle(auth, vehicleId);

    return this.prisma.vehicleDeviceAssignment.findMany({
      where: {
        vehicleId,
      },
      orderBy: {
        startedAt: 'desc',
      },
      include: {
        device: {
          include: {
            deviceModel: true,
          },
        },
        installation: true,
        assignedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
        endedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
      },
    });
  }

  private normalizeRegistration(value?: string): string | null {
    const trimmed = value?.trim();

    if (!trimmed) {
      return null;
    }

    return trimmed.toUpperCase().replace(/[\s-]+/g, '');
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }

  private optionalUpper(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed.toUpperCase() : null;
  }

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
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\vehicles\vehicles.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { VehicleQueryDto } from '../common/asset-query.dto';
import { CreateVehicleDto } from './dto/create-vehicle.dto';
import { UpdateVehicleDto } from './dto/update-vehicle.dto';
import { VehiclesService } from './vehicles.service';

@ApiTags('Vehicles')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('vehicles')
export class VehiclesController {
  constructor(private readonly vehiclesService: VehiclesService) {}

  @Get()
  @RequirePermissions('vehicle.view')
  @ApiOperation({ summary: 'List vehicles within effective scope' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: VehicleQueryDto,
  ) {
    return this.vehiclesService.list(auth, query);
  }

  @Post()
  @RequirePermissions('vehicle.create')
  @ApiOperation({ summary: 'Register a vehicle for a customer' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateVehicleDto,
  ) {
    return this.vehiclesService.create(auth, dto);
  }

  @Get(':vehicleId')
  @RequirePermissions('vehicle.view')
  @ApiOperation({ summary: 'Read one scoped vehicle' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
  ) {
    return this.vehiclesService.get(auth, vehicleId);
  }

  @Patch(':vehicleId')
  @RequirePermissions('vehicle.update')
  @ApiOperation({ summary: 'Update a scoped vehicle' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
    @Body() dto: UpdateVehicleDto,
  ) {
    return this.vehiclesService.update(auth, vehicleId, dto);
  }

  @Get(':vehicleId/device-history')
  @RequirePermissions('vehicle.view')
  @ApiOperation({
    summary: 'Read historical tracker assignments for a vehicle',
  })
  history(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
  ) {
    return this.vehiclesService.history(auth, vehicleId);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\vehicles\vehicles.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import { VehiclesController } from './vehicles.controller';
import { VehiclesService } from './vehicles.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [VehiclesController],
  providers: [
    VehiclesService,
    AssetAccessService,
    AssetCodeService,
  ],
  exports: [VehiclesService],
})
export class VehiclesModule {}
'@

    Write-Step 5 9 "Writing device-model and inventory APIs"

    Write-Utf8File `
        "services\backend-api\src\assets\device-models\dto\create-device-model.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

const networkTypes = [
  'GSM_2G',
  'UMTS_3G',
  'LTE_4G',
  'LTE_5G',
  'LORA',
  'SATELLITE',
  'OTHER',
] as const;

export class CreateDeviceModelDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  manufacturer!: string;

  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  modelName!: string;

  @ApiProperty({ example: 'osmand' })
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  protocol!: string;

  @ApiProperty({ enum: networkTypes })
  @IsIn(networkTypes)
  networkType!: (typeof networkTypes)[number];

  @ApiPropertyOptional({
    example: {
      ignition: true,
      relay: true,
      sos: true,
    },
  })
  @IsOptional()
  @IsObject()
  capabilities?: Record<string, unknown>;
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\device-models\dto\update-device-model.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

const networkTypes = [
  'GSM_2G',
  'UMTS_3G',
  'LTE_4G',
  'LTE_5G',
  'LORA',
  'SATELLITE',
  'OTHER',
] as const;

const modelStatuses = [
  'ACTIVE',
  'INACTIVE',
  'ARCHIVED',
] as const;

export class UpdateDeviceModelDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  manufacturer?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  modelName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  protocol?: string;

  @ApiPropertyOptional({ enum: networkTypes })
  @IsOptional()
  @IsIn(networkTypes)
  networkType?: (typeof networkTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  capabilities?: Record<string, unknown>;

  @ApiPropertyOptional({ enum: modelStatuses })
  @IsOptional()
  @IsIn(modelStatuses)
  status?: (typeof modelStatuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\device-models\device-models.service.ts" `
        @'
import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import type { PaginationQueryDto } from '../../management/common/pagination-query.dto';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import type { CreateDeviceModelDto } from './dto/create-device-model.dto';
import type { UpdateDeviceModelDto } from './dto/update-device-model.dto';

@Injectable()
export class DeviceModelsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: AssetAccessService,
    private readonly codes: AssetCodeService,
    private readonly auditService: AuditService,
  ) {}

  async list(query: PaginationQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.DeviceModelWhereInput = {
      status: {
        not: 'ARCHIVED',
      },
      ...(query.search
        ? {
            OR: [
              {
                modelCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                manufacturer: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                modelName: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                protocol: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.deviceModel.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          _count: {
            select: {
              devices: true,
            },
          },
        },
      }),
      this.prisma.deviceModel.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async create(auth: AuthContext, dto: CreateDeviceModelDto) {
    this.access.assertPlatform(auth);

    const duplicate = await this.prisma.deviceModel.findFirst({
      where: {
        manufacturer: {
          equals: dto.manufacturer.trim(),
          mode: 'insensitive',
        },
        modelName: {
          equals: dto.modelName.trim(),
          mode: 'insensitive',
        },
      },
      select: {
        id: true,
      },
    });

    if (duplicate) {
      throw new ConflictException(
        'This manufacturer and device model already exist.',
      );
    }

    const model = await this.prisma.deviceModel.create({
      data: {
        modelCode: this.codes.deviceModel(),
        manufacturer: dto.manufacturer.trim(),
        modelName: dto.modelName.trim(),
        protocol: dto.protocol.trim(),
        networkType: dto.networkType,
        capabilities:
          dto.capabilities as Prisma.InputJsonValue | undefined,
        status: 'ACTIVE',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'device-model.created',
      resourceType: 'DeviceModel',
      resourceId: model.id,
      scopeType: 'PLATFORM',
      afterData: model,
    });

    return model;
  }

  async update(
    auth: AuthContext,
    deviceModelId: string,
    dto: UpdateDeviceModelDto,
  ) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.deviceModel.findUnique({
      where: {
        id: deviceModelId,
      },
    });

    if (!before) {
      throw new NotFoundException('Device model was not found.');
    }

    const updated = await this.prisma.deviceModel.update({
      where: {
        id: deviceModelId,
      },
      data: {
        manufacturer: dto.manufacturer?.trim(),
        modelName: dto.modelName?.trim(),
        protocol: dto.protocol?.trim(),
        networkType: dto.networkType,
        capabilities:
          dto.capabilities as Prisma.InputJsonValue | undefined,
        status: dto.status,
        archivedAt:
          dto.status === 'ARCHIVED'
            ? new Date()
            : dto.status
              ? null
              : undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'device-model.updated',
      resourceType: 'DeviceModel',
      resourceId: deviceModelId,
      scopeType: 'PLATFORM',
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\device-models\device-models.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';
import { DeviceModelsService } from './device-models.service';
import { CreateDeviceModelDto } from './dto/create-device-model.dto';
import { UpdateDeviceModelDto } from './dto/update-device-model.dto';

@ApiTags('Device Models')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('device-models')
export class DeviceModelsController {
  constructor(
    private readonly deviceModelsService: DeviceModelsService,
  ) {}

  @Get()
  @RequirePermissions('device.view')
  @ApiOperation({ summary: 'List active device models' })
  list(@Query() query: PaginationQueryDto) {
    return this.deviceModelsService.list(query);
  }

  @Post()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Create a platform device model' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateDeviceModelDto,
  ) {
    return this.deviceModelsService.create(auth, dto);
  }

  @Patch(':deviceModelId')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Update a platform device model' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceModelId', new ParseUUIDPipe())
    deviceModelId: string,
    @Body() dto: UpdateDeviceModelDto,
  ) {
    return this.deviceModelsService.update(
      auth,
      deviceModelId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\device-models\device-models.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import { DeviceModelsController } from './device-models.controller';
import { DeviceModelsService } from './device-models.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [DeviceModelsController],
  providers: [
    DeviceModelsService,
    AssetAccessService,
    AssetCodeService,
  ],
})
export class DeviceModelsModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\devices\dto\register-device.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsDateString,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
} from 'class-validator';

export class RegisterDeviceDto {
  @ApiProperty()
  @IsUUID()
  deviceModelId!: string;

  @ApiPropertyOptional({
    description: 'IMEI is stored as text and must contain 14 to 17 digits.',
  })
  @IsOptional()
  @IsString()
  @Matches(/^\d{14,17}$/)
  imei?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  serialNumber?: string;

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

    Write-Utf8File `
        "services\backend-api\src\assets\devices\dto\update-device.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

const lifecycleStatuses = [
  'RECEIVED',
  'IN_STOCK',
  'RESERVED',
  'ALLOCATED',
  'INSTALLED',
  'UNDER_REPAIR',
  'LOST',
  'DAMAGED',
  'RETIRED',
] as const;

export class UpdateDeviceDto {
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

  @ApiPropertyOptional({ enum: lifecycleStatuses })
  @IsOptional()
  @IsIn(lifecycleStatuses)
  lifecycleStatus?: (typeof lifecycleStatuses)[number];

  @ApiPropertyOptional({
    description:
      'Required when lifecycleStatus is RETIRED; cleared for all other statuses.',
  })
  @IsOptional()
  @IsDateString()
  retiredAt?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\devices\dto\allocate-device.dto.ts" `
        @'
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class AllocateDeviceDto {
  @ApiProperty()
  @IsUUID()
  dealerOrganizationId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\devices\dto\return-device.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength } from 'class-validator';

export class ReturnDeviceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\devices\dto\install-device.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
} from 'class-validator';

export class InstallDeviceDto {
  @ApiProperty()
  @IsUUID()
  vehicleId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  installedAt?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsLatitude()
  latitude?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsLongitude()
  longitude?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  odometerReading?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  powerConnectionType?: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  ignitionConnected?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  relayConnected?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  sosConnected?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  installationNotes?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\devices\dto\remove-device.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

const assignmentEndReasons = [
  'DEVICE_FAILURE',
  'DEVICE_REPLACEMENT',
  'VEHICLE_TRANSFER',
  'VEHICLE_SOLD',
  'CUSTOMER_REQUEST',
  'SUBSCRIPTION_CANCELLED',
  'TRANSFER_TO_ANOTHER_VEHICLE',
  'LOST',
  'OTHER',
] as const;

const removalReasons = [
  'CUSTOMER_REQUEST',
  'VEHICLE_SOLD',
  'DEVICE_FAILURE',
  'WARRANTY_REPLACEMENT',
  'SUBSCRIPTION_CANCELLED',
  'TRANSFER_TO_ANOTHER_VEHICLE',
  'LOST',
  'OTHER',
] as const;

export class RemoveDeviceDto {
  @ApiProperty({ enum: assignmentEndReasons })
  @IsIn(assignmentEndReasons)
  assignmentEndReason!: (typeof assignmentEndReasons)[number];

  @ApiProperty({ enum: removalReasons })
  @IsIn(removalReasons)
  removalReason!: (typeof removalReasons)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  notes?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\devices\dto\replace-device.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
} from 'class-validator';

const removalReasons = [
  'CUSTOMER_REQUEST',
  'VEHICLE_SOLD',
  'DEVICE_FAILURE',
  'WARRANTY_REPLACEMENT',
  'SUBSCRIPTION_CANCELLED',
  'TRANSFER_TO_ANOTHER_VEHICLE',
  'LOST',
  'OTHER',
] as const;

export class ReplaceDeviceDto {
  @ApiProperty()
  @IsUUID()
  replacementDeviceId!: string;

  @ApiProperty({ enum: removalReasons })
  @IsIn(removalReasons)
  removalReason!: (typeof removalReasons)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  installedAt?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsLatitude()
  latitude?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsLongitude()
  longitude?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  odometerReading?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(80)
  powerConnectionType?: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  ignitionConnected?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  relayConnected?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  sosConnected?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  notes?: string;
}
'@

    Write-Step 6 9 `
        "Writing allocation, installation, replacement, and removal services"

    Write-Utf8File `
        "services\backend-api\src\assets\devices\devices.service.ts" `
        @'
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import type { DeviceQueryDto } from '../common/asset-query.dto';
import type { AllocateDeviceDto } from './dto/allocate-device.dto';
import type { InstallDeviceDto } from './dto/install-device.dto';
import type { RegisterDeviceDto } from './dto/register-device.dto';
import type { RemoveDeviceDto } from './dto/remove-device.dto';
import type { ReplaceDeviceDto } from './dto/replace-device.dto';
import type { ReturnDeviceDto } from './dto/return-device.dto';
import type { UpdateDeviceDto } from './dto/update-device.dto';

type TransactionClient = Prisma.TransactionClient;

const activeAllocationStatuses = ['ALLOCATED', 'AVAILABLE', 'INSTALLED'] as const;

@Injectable()
export class DevicesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: AssetAccessService,
    private readonly codes: AssetCodeService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: DeviceQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.deviceWhere(auth);
    const searchWhere: Prisma.DeviceWhereInput = query.search
      ? {
          OR: [
            {
              deviceCode: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              imei: {
                contains: query.search,
              },
            },
            {
              serialNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
          ],
        }
      : {};

    const where: Prisma.DeviceWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.deviceModelId
          ? {
              deviceModelId: query.deviceModelId,
            }
          : {},
        query.lifecycleStatus
          ? {
              lifecycleStatus: query.lifecycleStatus,
            }
          : {},
        query.dealerOrganizationId
          ? {
              dealerAllocations: {
                some: {
                  dealerOrganizationId: query.dealerOrganizationId,
                  status: {
                    in: [...activeAllocationStatuses],
                  },
                },
              },
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.device.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
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
      }),
      this.prisma.device.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, deviceId: string) {
    await this.access.assertDevice(auth, deviceId);

    const device = await this.prisma.device.findUnique({
      where: {
        id: deviceId,
      },
      include: {
        deviceModel: true,
        ownershipHistory: {
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            ownerOrganization: true,
            ownerCustomer: true,
            changedBy: {
              select: {
                id: true,
                userCode: true,
                fullName: true,
              },
            },
          },
        },
        custodyHistory: {
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            custodianOrganization: true,
            custodianCustomer: true,
            custodianUser: {
              select: {
                id: true,
                userCode: true,
                fullName: true,
              },
            },
            changedBy: {
              select: {
                id: true,
                userCode: true,
                fullName: true,
              },
            },
          },
        },
        dealerAllocations: {
          orderBy: {
            allocatedAt: 'desc',
          },
          include: {
            dealerOrganization: true,
          },
        },
        installations: {
          orderBy: {
            createdAt: 'desc',
          },
          include: {
            vehicle: true,
          },
        },
        vehicleAssignments: {
          orderBy: {
            startedAt: 'desc',
          },
          include: {
            vehicle: true,
            installation: true,
          },
        },
        traccarMappings: {
          orderBy: {
            createdAt: 'desc',
          },
        },
      },
    });

    if (!device) {
      throw new NotFoundException('Device was not found.');
    }

    return device;
  }

  async register(auth: AuthContext, dto: RegisterDeviceDto) {
    this.access.assertPlatform(auth);

    const model = await this.prisma.deviceModel.findFirst({
      where: {
        id: dto.deviceModelId,
        status: 'ACTIVE',
      },
      select: {
        id: true,
      },
    });

    if (!model) {
      throw new BadRequestException('An active device model is required.');
    }

    const imei = this.optional(dto.imei);
    const serialNumber = this.optionalUpper(dto.serialNumber);

    if (!imei && !serialNumber) {
      throw new BadRequestException(
        'At least one device identity, IMEI or serial number, is required.',
      );
    }

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
    if (duplicate) {
      throw new ConflictException('Device IMEI or serial number already exists.');
    }

    const platformOrganizationId = await this.access.platformOrganizationId();
    const receivedAt = dto.receivedAt ? new Date(dto.receivedAt) : new Date();

    const device = await this.prisma.$transaction(async (transaction) => {
      const created = await transaction.device.create({
        data: {
          deviceCode: this.codes.device(),
          deviceModelId: dto.deviceModelId,
          imei,
          serialNumber,
          hardwareVersion: this.optional(dto.hardwareVersion),
          firmwareVersion: this.optional(dto.firmwareVersion),
          lifecycleStatus: 'IN_STOCK',
          receivedAt,
        },
      });

      await transaction.deviceOwnershipHistory.create({
        data: {
          deviceId: created.id,
          ownerType: 'PLATFORM',
          ownerOrganizationId: platformOrganizationId,
          reason: 'INITIAL_STOCK',
          changedByUserId: auth.userId,
        },
      });

      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId: created.id,
          custodianType: 'PLATFORM',
          custodianOrganizationId: platformOrganizationId,
          reason: 'RECEIVED',
          changedByUserId: auth.userId,
        },
      });

      return transaction.device.findUniqueOrThrow({
        where: {
          id: created.id,
        },
        include: {
          deviceModel: true,
          ownershipHistory: true,
          custodyHistory: true,
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.registered',
      resourceType: 'Device',
      resourceId: device.id,
      scopeType: 'PLATFORM',
      afterData: device,
    });

    return device;
  }

  async update(auth: AuthContext, deviceId: string, dto: UpdateDeviceDto) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.device.findUnique({
      where: {
        id: deviceId,
      },
    });

    if (!before) {
      throw new NotFoundException('Device was not found.');
    }

    if (dto.lifecycleStatus === 'RETIRED' && !dto.retiredAt) {
      throw new BadRequestException('retiredAt is required when retiring a device.');
    }

    if (dto.lifecycleStatus && ['INSTALLED', 'ALLOCATED'].includes(dto.lifecycleStatus)) {
      throw new BadRequestException(
        'Installed and allocated states are controlled by lifecycle operations.',
      );
    }

    const activeAssignment = await this.prisma.vehicleDeviceAssignment.count({
      where: {
        deviceId,
        status: 'ACTIVE',
      },
    });

    if (activeAssignment > 0 && dto.lifecycleStatus && dto.lifecycleStatus !== 'INSTALLED') {
      throw new ConflictException(
        'Remove the active vehicle assignment before changing this lifecycle state.',
      );
    }

    const updated = await this.prisma.device.update({
      where: {
        id: deviceId,
      },
      data: {
        hardwareVersion:
          dto.hardwareVersion !== undefined ? this.optional(dto.hardwareVersion) : undefined,
        firmwareVersion:
          dto.firmwareVersion !== undefined ? this.optional(dto.firmwareVersion) : undefined,
        lifecycleStatus: dto.lifecycleStatus,
        retiredAt:
          dto.lifecycleStatus === 'RETIRED'
            ? new Date(dto.retiredAt as string)
            : dto.lifecycleStatus
              ? null
              : undefined,
      },
      include: {
        deviceModel: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.updated',
      resourceType: 'Device',
      resourceId: deviceId,
      scopeType: 'PLATFORM',
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async allocate(auth: AuthContext, deviceId: string, dto: AllocateDeviceDto) {
    this.access.assertPlatform(auth);

    const [device, dealer, activeAllocation, activeAssignment] = await Promise.all([
      this.prisma.device.findUnique({
        where: {
          id: deviceId,
        },
      }),
      this.prisma.organization.findFirst({
        where: {
          id: dto.dealerOrganizationId,
          type: 'DEALER',
          status: 'ACTIVE',
        },
      }),
      this.prisma.dealerDeviceAllocation.findFirst({
        where: {
          deviceId,
          status: {
            in: [...activeAllocationStatuses],
          },
        },
      }),
      this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          deviceId,
          status: 'ACTIVE',
        },
      }),
    ]);

    if (!device) {
      throw new NotFoundException('Device was not found.');
    }

    if (!dealer) {
      throw new BadRequestException('An active dealer organization is required.');
    }

    if (activeAllocation) {
      throw new ConflictException('Device already has an active dealer allocation.');
    }

    if (activeAssignment) {
      throw new ConflictException('An installed device cannot be allocated.');
    }

    if (!['RECEIVED', 'IN_STOCK'].includes(device.lifecycleStatus)) {
      throw new ConflictException('Only received or in-stock devices may be allocated.');
    }

    const now = new Date();

    const allocation = await this.prisma.$transaction(async (transaction) => {
      await this.endCurrentCustody(transaction, deviceId, now);

      const created = await transaction.dealerDeviceAllocation.create({
        data: {
          allocationCode: this.codes.allocation(),
          dealerOrganizationId: dto.dealerOrganizationId,
          deviceId,
          status: 'AVAILABLE',
          allocatedAt: now,
          availableAt: now,
          allocatedByUserId: auth.userId,
          notes: this.optional(dto.notes),
        },
        include: {
          dealerOrganization: true,
          device: {
            include: {
              deviceModel: true,
            },
          },
        },
      });

      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId,
          custodianType: 'DEALER',
          custodianOrganizationId: dto.dealerOrganizationId,
          reason: 'ALLOCATION',
          changedByUserId: auth.userId,
          notes: this.optional(dto.notes),
        },
      });

      await transaction.device.update({
        where: {
          id: deviceId,
        },
        data: {
          lifecycleStatus: 'ALLOCATED',
        },
      });

      return created;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.allocated',
      resourceType: 'DealerDeviceAllocation',
      resourceId: allocation.id,
      scopeType: 'DEALER',
      scopeId: dto.dealerOrganizationId,
      afterData: allocation,
    });

    return allocation;
  }

  async returnToPlatform(auth: AuthContext, deviceId: string, dto: ReturnDeviceDto) {
    const allocation = await this.prisma.dealerDeviceAllocation.findFirst({
      where: {
        deviceId,
        status: {
          in: [...activeAllocationStatuses],
        },
      },
      include: {
        dealerOrganization: true,
      },
    });

    if (!allocation) {
      throw new NotFoundException('Active dealer allocation was not found.');
    }

    this.access.assertDealer(auth, allocation.dealerOrganizationId);

    const activeAssignment = await this.prisma.vehicleDeviceAssignment.count({
      where: {
        deviceId,
        status: 'ACTIVE',
      },
    });

    if (activeAssignment > 0) {
      throw new ConflictException('Remove the device from its vehicle before returning it.');
    }

    const platformOrganizationId = await this.access.platformOrganizationId();
    const now = new Date();

    const returned = await this.prisma.$transaction(async (transaction) => {
      const updated = await transaction.dealerDeviceAllocation.update({
        where: {
          id: allocation.id,
        },
        data: {
          status: 'RETURNED',
          returnedAt: now,
          returnedByUserId: auth.userId,
          notes: this.optional(dto.notes) ?? allocation.notes,
        },
        include: {
          dealerOrganization: true,
          device: true,
        },
      });

      await this.endCurrentCustody(transaction, deviceId, now);

      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId,
          custodianType: 'PLATFORM',
          custodianOrganizationId: platformOrganizationId,
          reason: 'RETURN',
          changedByUserId: auth.userId,
          notes: this.optional(dto.notes),
        },
      });

      await transaction.device.update({
        where: {
          id: deviceId,
        },
        data: {
          lifecycleStatus: 'IN_STOCK',
        },
      });

      return updated;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.returned-to-platform',
      resourceType: 'DealerDeviceAllocation',
      resourceId: allocation.id,
      scopeType: 'DEALER',
      scopeId: allocation.dealerOrganizationId,
      afterData: returned,
    });

    return returned;
  }

  async install(auth: AuthContext, deviceId: string, dto: InstallDeviceDto) {
    const vehicle = await this.access.assertVehicleMutation(auth, dto.vehicleId);

    if (vehicle.status === 'ARCHIVED' || vehicle.customer.status === 'ARCHIVED') {
      throw new BadRequestException('Archived vehicles or customers cannot receive installations.');
    }

    const device = await this.prisma.device.findUnique({
      where: {
        id: deviceId,
      },
    });

    if (!device) {
      throw new NotFoundException('Device was not found.');
    }

    const dealerId = vehicle.customer.managingDealerId;
    const allocation = await this.resolveInstallAllocation(auth, deviceId, dealerId);

    await this.assertInstallationAvailability(deviceId, dto.vehicleId, device.lifecycleStatus);

    const installedAt = dto.installedAt ? new Date(dto.installedAt) : new Date();

    const installation = await this.prisma.$transaction(async (transaction) => {
      return this.installWithinTransaction(transaction, auth, {
        deviceId,
        vehicleId: dto.vehicleId,
        customerId: vehicle.customerId,
        dealerId,
        allocationId: allocation?.id,
        installedAt,
        latitude: dto.latitude,
        longitude: dto.longitude,
        odometerReading: dto.odometerReading,
        powerConnectionType: this.optional(dto.powerConnectionType),
        ignitionConnected: dto.ignitionConnected ?? false,
        relayConnected: dto.relayConnected ?? false,
        sosConnected: dto.sosConnected ?? false,
        notes: this.optional(dto.installationNotes),
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.installed',
      resourceType: 'DeviceInstallation',
      resourceId: installation.id,
      scopeType: 'VEHICLE',
      scopeId: dto.vehicleId,
      afterData: installation,
    });

    return installation;
  }

  async remove(auth: AuthContext, deviceId: string, dto: RemoveDeviceDto) {
    const activeAssignment = await this.prisma.vehicleDeviceAssignment.findFirst({
      where: {
        deviceId,
        status: 'ACTIVE',
      },
      include: {
        vehicle: {
          include: {
            customer: true,
          },
        },
        installation: true,
      },
    });

    if (!activeAssignment) {
      throw new NotFoundException('Active vehicle assignment was not found.');
    }

    await this.access.assertVehicleMutation(auth, activeAssignment.vehicleId);

    const allocation = await this.prisma.dealerDeviceAllocation.findFirst({
      where: {
        deviceId,
        status: {
          in: [...activeAllocationStatuses],
        },
      },
    });

    const now = new Date();
    const result = await this.prisma.$transaction(async (transaction) => {
      return this.removeWithinTransaction(transaction, auth, {
        assignmentId: activeAssignment.id,
        installationId: activeAssignment.installationId,
        deviceId,
        dealerId: activeAssignment.vehicle.customer.managingDealerId,
        allocationId: allocation?.id,
        assignmentEndReason: dto.assignmentEndReason,
        removalReason: dto.removalReason,
        notes: this.optional(dto.notes),
        now,
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.removed',
      resourceType: 'VehicleDeviceAssignment',
      resourceId: activeAssignment.id,
      scopeType: 'VEHICLE',
      scopeId: activeAssignment.vehicleId,
      afterData: result,
    });

    return result;
  }

  async replace(auth: AuthContext, currentDeviceId: string, dto: ReplaceDeviceDto) {
    if (currentDeviceId === dto.replacementDeviceId) {
      throw new BadRequestException(
        'Replacement device must be different from the current device.',
      );
    }

    const activeAssignment = await this.prisma.vehicleDeviceAssignment.findFirst({
      where: {
        deviceId: currentDeviceId,
        status: 'ACTIVE',
        assignmentType: 'PRIMARY',
      },
      include: {
        vehicle: {
          include: {
            customer: true,
          },
        },
        installation: true,
      },
    });

    if (!activeAssignment) {
      throw new NotFoundException('Current active primary assignment was not found.');
    }

    await this.access.assertVehicleMutation(auth, activeAssignment.vehicleId);

    const replacementDevice = await this.prisma.device.findUnique({
      where: {
        id: dto.replacementDeviceId,
      },
    });

    if (!replacementDevice) {
      throw new NotFoundException('Replacement device was not found.');
    }

    const dealerId = activeAssignment.vehicle.customer.managingDealerId;

    const [currentAllocation, replacementAllocation] = await Promise.all([
      this.prisma.dealerDeviceAllocation.findFirst({
        where: {
          deviceId: currentDeviceId,
          status: {
            in: [...activeAllocationStatuses],
          },
        },
      }),
      this.resolveInstallAllocation(auth, dto.replacementDeviceId, dealerId),
    ]);

    await this.assertInstallationAvailability(
      dto.replacementDeviceId,
      activeAssignment.vehicleId,
      replacementDevice.lifecycleStatus,
      activeAssignment.id,
    );

    const now = new Date();
    const installedAt = dto.installedAt ? new Date(dto.installedAt) : now;

    const replacement = await this.prisma.$transaction(async (transaction) => {
      const removed = await this.removeWithinTransaction(transaction, auth, {
        assignmentId: activeAssignment.id,
        installationId: activeAssignment.installationId,
        deviceId: currentDeviceId,
        dealerId,
        allocationId: currentAllocation?.id,
        assignmentEndReason: 'DEVICE_REPLACEMENT',
        removalReason: dto.removalReason,
        notes: this.optional(dto.notes),
        now,
      });

      const installed = await this.installWithinTransaction(transaction, auth, {
        deviceId: dto.replacementDeviceId,
        vehicleId: activeAssignment.vehicleId,
        customerId: activeAssignment.vehicle.customerId,
        dealerId,
        allocationId: replacementAllocation?.id,
        installedAt,
        latitude: dto.latitude,
        longitude: dto.longitude,
        odometerReading: dto.odometerReading,
        powerConnectionType: this.optional(dto.powerConnectionType),
        ignitionConnected: dto.ignitionConnected ?? false,
        relayConnected: dto.relayConnected ?? false,
        sosConnected: dto.sosConnected ?? false,
        notes: this.optional(dto.notes),
      });

      return {
        removed,
        installed,
      };
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'device.replaced',
      resourceType: 'Vehicle',
      resourceId: activeAssignment.vehicleId,
      scopeType: 'VEHICLE',
      scopeId: activeAssignment.vehicleId,
      beforeData: {
        deviceId: currentDeviceId,
        assignmentId: activeAssignment.id,
      },
      afterData: {
        deviceId: dto.replacementDeviceId,
        assignmentId: replacement.installed.assignment.id,
      },
      metadata: {
        removalReason: dto.removalReason,
        notes: dto.notes,
      },
    });

    return replacement;
  }

  async history(auth: AuthContext, deviceId: string) {
    await this.access.assertDevice(auth, deviceId);

    const [ownership, custody, allocations, installations, assignments] = await Promise.all([
      this.prisma.deviceOwnershipHistory.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          startedAt: 'desc',
        },
        include: {
          ownerOrganization: true,
          ownerCustomer: true,
        },
      }),
      this.prisma.deviceCustodyHistory.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          startedAt: 'desc',
        },
        include: {
          custodianOrganization: true,
          custodianCustomer: true,
          custodianUser: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
        },
      }),
      this.prisma.dealerDeviceAllocation.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          allocatedAt: 'desc',
        },
        include: {
          dealerOrganization: true,
        },
      }),
      this.prisma.deviceInstallation.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          vehicle: true,
        },
      }),
      this.prisma.vehicleDeviceAssignment.findMany({
        where: {
          deviceId,
        },
        orderBy: {
          startedAt: 'desc',
        },
        include: {
          vehicle: true,
          installation: true,
        },
      }),
    ]);

    return {
      ownership,
      custody,
      allocations,
      installations,
      assignments,
    };
  }

  private async resolveInstallAllocation(
    auth: AuthContext,
    deviceId: string,
    dealerId: string | null,
  ) {
    const allocation = await this.prisma.dealerDeviceAllocation.findFirst({
      where: {
        deviceId,
        status: {
          in: ['ALLOCATED', 'AVAILABLE'],
        },
      },
    });

    if (dealerId) {
      if (!allocation || allocation.dealerOrganizationId !== dealerId) {
        throw new ForbiddenException(
          'Dealer-managed installation requires an available allocation to that dealer.',
        );
      }

      this.access.assertDealer(auth, dealerId);

      return allocation;
    }

    if (!this.access.isPlatformScoped(auth)) {
      throw new ForbiddenException('Direct-customer installation requires platform scope.');
    }

    if (allocation) {
      throw new ConflictException(
        'Dealer-allocated stock cannot be installed for a direct customer.',
      );
    }

    return null;
  }

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
  private async installWithinTransaction(
    transaction: TransactionClient,
    auth: AuthContext,
    input: {
      deviceId: string;
      vehicleId: string;
      customerId: string;
      dealerId: string | null;
      allocationId?: string;
      installedAt: Date;
      latitude?: number;
      longitude?: number;
      odometerReading?: number;
      powerConnectionType: string | null;
      ignitionConnected: boolean;
      relayConnected: boolean;
      sosConnected: boolean;
      notes: string | null;
    },
  ) {
    const installation = await transaction.deviceInstallation.create({
      data: {
        installationCode: this.codes.installation(),
        deviceId: input.deviceId,
        vehicleId: input.vehicleId,
        dealerOrganizationId: input.dealerId,
        installedByUserId: auth.userId,
        installedAt: input.installedAt,
        installationLocation:
          input.latitude !== undefined && input.longitude !== undefined
            ? {
                latitude: input.latitude,
                longitude: input.longitude,
              }
            : undefined,
        odometerReading: input.odometerReading,
        powerConnectionType: input.powerConnectionType,
        ignitionConnected: input.ignitionConnected,
        relayConnected: input.relayConnected,
        sosConnected: input.sosConnected,
        installationNotes: input.notes,
        status: 'COMPLETED',
      },
    });

    const assignment = await transaction.vehicleDeviceAssignment.create({
      data: {
        vehicleId: input.vehicleId,
        deviceId: input.deviceId,
        installationId: installation.id,
        assignmentType: 'PRIMARY',
        status: 'ACTIVE',
        startedAt: input.installedAt,
        assignedByUserId: auth.userId,
      },
    });

    await this.endCurrentCustody(transaction, input.deviceId, input.installedAt);

    await transaction.deviceCustodyHistory.create({
      data: {
        deviceId: input.deviceId,
        custodianType: 'CUSTOMER',
        custodianCustomerId: input.customerId,
        reason: 'INSTALLATION',
        changedByUserId: auth.userId,
        notes: input.notes,
        startedAt: input.installedAt,
      },
    });

    await transaction.device.update({
      where: {
        id: input.deviceId,
      },
      data: {
        lifecycleStatus: 'INSTALLED',
      },
    });

    await transaction.vehicle.update({
      where: {
        id: input.vehicleId,
      },
      data: {
        status: 'ACTIVE',
      },
    });

    if (input.allocationId) {
      await transaction.dealerDeviceAllocation.update({
        where: {
          id: input.allocationId,
        },
        data: {
          status: 'INSTALLED',
          installedAt: input.installedAt,
        },
      });
    }

    return {
      ...installation,
      assignment,
    };
  }

  private async removeWithinTransaction(
    transaction: TransactionClient,
    auth: AuthContext,
    input: {
      assignmentId: string;
      installationId: string | null;
      deviceId: string;
      dealerId: string | null;
      allocationId?: string;
      assignmentEndReason:
        | 'DEVICE_FAILURE'
        | 'DEVICE_REPLACEMENT'
        | 'VEHICLE_TRANSFER'
        | 'VEHICLE_SOLD'
        | 'CUSTOMER_REQUEST'
        | 'SUBSCRIPTION_CANCELLED'
        | 'TRANSFER_TO_ANOTHER_VEHICLE'
        | 'LOST'
        | 'OTHER';
      removalReason:
        | 'CUSTOMER_REQUEST'
        | 'VEHICLE_SOLD'
        | 'DEVICE_FAILURE'
        | 'WARRANTY_REPLACEMENT'
        | 'SUBSCRIPTION_CANCELLED'
        | 'TRANSFER_TO_ANOTHER_VEHICLE'
        | 'LOST'
        | 'OTHER';
      notes: string | null;
      now: Date;
    },
  ) {
    const assignment = await transaction.vehicleDeviceAssignment.update({
      where: {
        id: input.assignmentId,
      },
      data: {
        status: 'ENDED',
        endedAt: input.now,
        endedByUserId: auth.userId,
        endReason: input.assignmentEndReason,
        endNotes: input.notes,
      },
    });

    let installation = null;

    if (input.installationId) {
      installation = await transaction.deviceInstallation.update({
        where: {
          id: input.installationId,
        },
        data: {
          status: 'REMOVED',
          removedAt: input.now,
          removalReason: input.removalReason,
        },
      });
    }

    await this.endCurrentCustody(transaction, input.deviceId, input.now);

    if (input.dealerId && input.allocationId) {
      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId: input.deviceId,
          custodianType: 'DEALER',
          custodianOrganizationId: input.dealerId,
          reason: 'REMOVAL',
          changedByUserId: auth.userId,
          notes: input.notes,
          startedAt: input.now,
        },
      });

      await transaction.dealerDeviceAllocation.update({
        where: {
          id: input.allocationId,
        },
        data: {
          status: 'AVAILABLE',
          availableAt: input.now,
        },
      });

      await transaction.device.update({
        where: {
          id: input.deviceId,
        },
        data: {
          lifecycleStatus: 'ALLOCATED',
        },
      });
    } else {
      const platformOrganizationId =
        await this.platformOrganizationIdWithinTransaction(transaction);

      await transaction.deviceCustodyHistory.create({
        data: {
          deviceId: input.deviceId,
          custodianType: 'PLATFORM',
          custodianOrganizationId: platformOrganizationId,
          reason: 'REMOVAL',
          changedByUserId: auth.userId,
          notes: input.notes,
          startedAt: input.now,
        },
      });

      await transaction.device.update({
        where: {
          id: input.deviceId,
        },
        data: {
          lifecycleStatus: 'IN_STOCK',
        },
      });
    }

    return {
      assignment,
      installation,
    };
  }

  private async endCurrentCustody(
    transaction: TransactionClient,
    deviceId: string,
    endedAt: Date,
  ): Promise<void> {
    await transaction.deviceCustodyHistory.updateMany({
      where: {
        deviceId,
        endedAt: null,
      },
      data: {
        endedAt,
      },
    });
  }

  private async platformOrganizationIdWithinTransaction(
    transaction: TransactionClient,
  ): Promise<string> {
    const platform = await transaction.organization.findUnique({
      where: {
        code: 'ORG-PLATFORM',
      },
      select: {
        id: true,
      },
    });

    if (!platform) {
      throw new NotFoundException('Solid Tracker platform organization was not found.');
    }

    return platform.id;
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }

  private optionalUpper(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed.toUpperCase() : null;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\devices\devices.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { DeviceQueryDto } from '../common/asset-query.dto';
import { DevicesService } from './devices.service';
import { AllocateDeviceDto } from './dto/allocate-device.dto';
import { InstallDeviceDto } from './dto/install-device.dto';
import { RegisterDeviceDto } from './dto/register-device.dto';
import { RemoveDeviceDto } from './dto/remove-device.dto';
import { ReplaceDeviceDto } from './dto/replace-device.dto';
import { ReturnDeviceDto } from './dto/return-device.dto';
import { UpdateDeviceDto } from './dto/update-device.dto';

@ApiTags('Devices')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('devices')
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Get()
  @RequirePermissions('device.view')
  @ApiOperation({ summary: 'List devices within effective scope' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: DeviceQueryDto,
  ) {
    return this.devicesService.list(auth, query);
  }

  @Post()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Register platform device inventory' })
  register(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: RegisterDeviceDto,
  ) {
    return this.devicesService.register(auth, dto);
  }

  @Get(':deviceId')
  @RequirePermissions('device.view')
  @ApiOperation({ summary: 'Read one device within scope' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
  ) {
    return this.devicesService.get(auth, deviceId);
  }

  @Patch(':deviceId')
  @RequirePermissions('device.register')
  @ApiOperation({
    summary:
      'Update non-identity inventory metadata and controlled lifecycle state',
  })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: UpdateDeviceDto,
  ) {
    return this.devicesService.update(auth, deviceId, dto);
  }

  @Post(':deviceId/allocate')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Allocate platform inventory to a dealer' })
  allocate(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: AllocateDeviceDto,
  ) {
    return this.devicesService.allocate(auth, deviceId, dto);
  }

  @Post(':deviceId/return')
  @RequirePermissions('device.remove')
  @ApiOperation({
    summary: 'Return uninstalled dealer inventory to the platform',
  })
  returnToPlatform(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: ReturnDeviceDto,
  ) {
    return this.devicesService.returnToPlatform(
      auth,
      deviceId,
      dto,
    );
  }

  @Post(':deviceId/install')
  @RequirePermissions('device.install')
  @ApiOperation({
    summary: 'Install an available device as the primary tracker',
  })
  install(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: InstallDeviceDto,
  ) {
    return this.devicesService.install(auth, deviceId, dto);
  }

  @Post(':deviceId/remove')
  @RequirePermissions('device.remove')
  @ApiOperation({
    summary: 'Remove a currently installed device from its vehicle',
  })
  remove(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: RemoveDeviceDto,
  ) {
    return this.devicesService.remove(auth, deviceId, dto);
  }

  @Post(':deviceId/replace')
  @RequirePermissions('device.replace')
  @ApiOperation({
    summary:
      'Transactionally replace the current primary tracker with another device',
  })
  replace(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: ReplaceDeviceDto,
  ) {
    return this.devicesService.replace(auth, deviceId, dto);
  }

  @Get(':deviceId/history')
  @RequirePermissions('device.view')
  @ApiOperation({
    summary:
      'Read ownership, custody, allocation, installation, and assignment history',
  })
  history(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
  ) {
    return this.devicesService.history(auth, deviceId);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\devices\devices.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { AssetAccessService } from '../common/asset-access.service';
import { AssetCodeService } from '../common/asset-code.service';
import { DevicesController } from './devices.controller';
import { DevicesService } from './devices.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [DevicesController],
  providers: [
    DevicesService,
    AssetAccessService,
    AssetCodeService,
  ],
})
export class DevicesModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\assets\asset-management.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { DeviceModelsModule } from './device-models/device-models.module';
import { DevicesModule } from './devices/devices.module';
import { VehiclesModule } from './vehicles/vehicles.module';

@Module({
  imports: [
    VehiclesModule,
    DeviceModelsModule,
    DevicesModule,
  ],
})
export class AssetManagementModule {}
'@

    $appModulePath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\app.module.ts"

    $appModuleContent = [System.IO.File]::ReadAllText($appModulePath)

    $assetImport =
        "import { AssetManagementModule } from './assets/asset-management.module';"

    if (-not $appModuleContent.Contains($assetImport)) {
        $modulePattern = "(?m)^import \{ Module \} from '@nestjs/common';\r?$"
        $moduleMatch = [regex]::Match(
            $appModuleContent,
            $modulePattern
        )

        if (-not $moduleMatch.Success) {
            throw "Could not locate the NestJS Module import."
        }

        $appModuleContent = (
            $appModuleContent.Substring(
                0,
                $moduleMatch.Index + $moduleMatch.Length
            ) +
            [Environment]::NewLine +
            $assetImport +
            $appModuleContent.Substring(
                $moduleMatch.Index + $moduleMatch.Length
            )
        )
    }

    if (-not $appModuleContent.Contains("AssetManagementModule,")) {
        $importsPattern = "(?ms)(imports:\s*\[\s*)"
        $importsMatch = [regex]::Match(
            $appModuleContent,
            $importsPattern
        )

        if (-not $importsMatch.Success) {
            throw "Could not locate AppModule imports."
        }

        $appModuleContent = (
            $appModuleContent.Substring(
                0,
                $importsMatch.Index + $importsMatch.Length
            ) +
            "AssetManagementModule," +
            [Environment]::NewLine +
            "    " +
            $appModuleContent.Substring(
                $importsMatch.Index + $importsMatch.Length
            )
        )
    }

    [System.IO.File]::WriteAllText(
        $appModulePath,
        $appModuleContent,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED] services\backend-api\src\app.module.ts" -ForegroundColor Green

    Write-Step 7 9 "Writing end-to-end asset lifecycle coverage"

    Write-Utf8File `
        "services\backend-api\test\vehicle-device.e2e-spec.ts" `
        @'
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

    Write-Step 8 9 "Running complete quality and invariant verification"

    Invoke-CheckedCommand "Prisma generate" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma generate `
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
    $migrationCount = [int]$verificationParts[1]
    $permissionCount = [int]$verificationParts[2]
    $indexCount = [int]$verificationParts[3]
    $triggerCount = [int]$verificationParts[4]

    if ($publicTableCount -lt 50) {
        throw "Expected at least 50 public tables."
    }

    if ($migrationCount -lt 5) {
        throw "Expected at least 5 applied migrations."
    }

    if ($permissionCount -ne 8) {
        throw "Expected 8 active vehicle/device permissions."
    }

    if ($indexCount -ne 5) {
        throw "Expected 5 vehicle/device invariant indexes."
    }

    if ($triggerCount -ne 5) {
        throw "Expected 5 distinct vehicle/device invariant triggers."
    }

    Write-Host "Public tables:       $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:  $migrationCount" -ForegroundColor Green
    Write-Host "Asset permissions:   $permissionCount" -ForegroundColor Green
    Write-Host "Invariant indexes:   $indexCount" -ForegroundColor Green
    Write-Host "Invariant triggers:  $triggerCount" -ForegroundColor Green

    Write-Step 9 9 "Writing architecture documentation and committing"

    Write-Utf8File `
        "docs\architecture\vehicle-device-api.md" `
        @'
# Vehicle and Device API

## Scope

This stage adds REST APIs and transactional application services for:

- vehicle registration, updates, scoped lists, and assignment history;
- device-model administration;
- physical device inventory registration;
- platform-to-dealer allocation;
- dealer-to-platform return;
- installation as the active primary tracker;
- tracker replacement;
- tracker removal;
- ownership, custody, allocation, installation, and assignment history.

No new database migration is introduced. The existing vehicle/device foundation already defines the asset tables, partial unique indexes, check constraints, and validation triggers.

## API boundaries

### Vehicles

- `GET /api/v1/vehicles`
- `POST /api/v1/vehicles`
- `GET /api/v1/vehicles/:vehicleId`
- `PATCH /api/v1/vehicles/:vehicleId`
- `GET /api/v1/vehicles/:vehicleId/device-history`

### Device models

- `GET /api/v1/device-models`
- `POST /api/v1/device-models`
- `PATCH /api/v1/device-models/:deviceModelId`

### Devices

- `GET /api/v1/devices`
- `POST /api/v1/devices`
- `GET /api/v1/devices/:deviceId`
- `PATCH /api/v1/devices/:deviceId`
- `POST /api/v1/devices/:deviceId/allocate`
- `POST /api/v1/devices/:deviceId/return`
- `POST /api/v1/devices/:deviceId/install`
- `POST /api/v1/devices/:deviceId/replace`
- `POST /api/v1/devices/:deviceId/remove`
- `GET /api/v1/devices/:deviceId/history`

## Authorization

- Platform scope administers device models, registers inventory, and allocates stock.
- A dealer can view devices actively allocated to it or installed for its managed customers.
- Dealer installation, replacement, and removal require the vehicle customer to be managed by the same dealer.
- Customer users can view devices only through active assignments to vehicles under their customer scope.
- Direct-customer installation is a platform operation.
- IMEI and serial number are immutable through normal update endpoints.

## Inventory lifecycle

```text
Platform stock
    ↓ allocate
Dealer available stock
    ↓ install
Customer custody / vehicle assignment
    ↓ remove
Dealer available stock
    ↓ return
Platform stock
```

Ownership is intentionally separate from custody. Registration creates platform ownership and platform custody. Allocation changes custody, not ownership. Installation changes custody to the customer. The ownership history remains available for a later sales or transfer workflow.

## Replacement transaction

Replacement executes in one database transaction:

1. End the current primary assignment.
2. Mark the old installation removed.
3. Return old-device custody to dealer or platform inventory.
4. Create the replacement installation.
5. Create the new primary assignment.
6. Move replacement-device custody to the customer.
7. Update device and allocation lifecycle states.
8. Preserve all historical rows.

The database partial indexes guarantee one active assignment per device and one active primary device per vehicle.

## Verification

The E2E lifecycle test covers:

```text
dealer creation
→ customer creation
→ vehicle registration
→ device-model creation
→ two device registrations
→ both dealer allocations
→ first installation
→ replacement with second device
→ second-device removal
→ historical assignment verification
```
'@

    git add -- `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/assets" `
        "services/backend-api/test/vehicle-device.e2e-spec.ts" `
        "docs/architecture/vehicle-device-api.md" `
        "scripts/solid-tracker-vehicle-device-api.ps1"

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
    Write-Host "VEHICLE AND DEVICE API FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "Do not reset or delete any applied Prisma migration."
    ) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
