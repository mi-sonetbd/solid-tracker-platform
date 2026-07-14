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
        "?? scripts/solid-tracker-dealer-customer-api.ps1"
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
            "dealer-customer API script."
        )
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Dealer and Customer API" -ForegroundColor Cyan
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
        "services\backend-api\package.json",
        "services\backend-api\prisma.config.ts",
        "services\backend-api\prisma\schema.prisma",
        "services\backend-api\src\app.module.ts",
        "services\backend-api\src\identity\access-control\access-control.module.ts",
        "services\backend-api\src\identity\audit\audit.service.ts",
        "services\backend-api\src\identity\audit\audit.module.ts",
        "services\backend-api\src\identity\common\password.service.ts",
        "services\backend-api\src\identity\common\mobile-number.util.ts",
        "services\backend-api\test\jest-e2e.json"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file is missing: $requiredPath"
        }
    }

    Write-Step 1 9 `
        "Merging identity access and creating the dealer-customer branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/identity-access-api") {
        Assert-CleanExceptSelf

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        git merge-base --is-ancestor `
            feat/identity-access-api `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge identity access API into main" {
                git merge `
                    --no-ff `
                    feat/identity-access-api `
                    -m "merge: integrate identity and access API"
            }
        }
        else {
            Write-Host (
                "Identity and access API is already contained in main."
            ) -ForegroundColor Green
        }

        $branchExists = git branch --list "feat/dealer-customer-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing management branch" {
                git checkout feat/dealer-customer-api
            }
        }
        else {
            Invoke-CheckedCommand "Create management feature branch" {
                git checkout -b feat/dealer-customer-api
            }
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-CleanExceptSelf

        git merge-base --is-ancestor `
            feat/identity-access-api `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge identity access API into main" {
                git merge `
                    --no-ff `
                    feat/identity-access-api `
                    -m "merge: integrate identity and access API"
            }
        }

        $branchExists = git branch --list "feat/dealer-customer-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing management branch" {
                git checkout feat/dealer-customer-api
            }
        }
        else {
            Invoke-CheckedCommand "Create management feature branch" {
                git checkout -b feat/dealer-customer-api
            }
        }
    }
    elseif ($currentBranch -eq "feat/dealer-customer-api") {
        Assert-CleanExceptSelf
        Write-Host "Already on feat/dealer-customer-api." -ForegroundColor Green
    }
    else {
        throw (
            "Expected feat/identity-access-api, main, or " +
            "feat/dealer-customer-api. Current branch: $currentBranch"
        )
    }

    Write-Step 2 9 "Validating infrastructure and Prisma state"

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

    Write-Host "PostgreSQL: healthy" -ForegroundColor Green
    Write-Host "Redis:      healthy" -ForegroundColor Green

    Write-Step 3 9 `
        "Extending audit records and writing scoped management services"

    Write-Utf8File `
        "services\backend-api\src\identity\audit\audit.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';

type AuditScopeType =
  | 'PLATFORM'
  | 'ZONE'
  | 'DEALER'
  | 'CUSTOMER_GROUP'
  | 'CUSTOMER'
  | 'VEHICLE'
  | 'SELF';

export interface AuditRecordInput {
  actorUserId?: string;
  actorOrganizationId?: string;
  action: string;
  resourceType: string;
  resourceId?: string;
  scopeType?: AuditScopeType;
  scopeId?: string;
  beforeData?: unknown;
  afterData?: unknown;
  metadata?: unknown;
  ipAddress?: string;
  userAgent?: string;
  correlationId?: string;
}

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async record(input: AuditRecordInput): Promise<void> {
    await this.prisma.auditLog.create({
      data: {
        actorUserId: input.actorUserId,
        actorOrganizationId: input.actorOrganizationId,
        action: input.action,
        resourceType: input.resourceType,
        resourceId: input.resourceId,
        scopeType: input.scopeType,
        scopeId: input.scopeId,
        beforeData: this.toJson(input.beforeData),
        afterData: this.toJson(input.afterData),
        metadata: this.toJson(input.metadata),
        ipAddress: input.ipAddress,
        userAgent: input.userAgent,
        correlationId: input.correlationId,
      },
    });
  }

  private toJson(value: unknown): Prisma.InputJsonValue | undefined {
    if (value === undefined) {
      return undefined;
    }

    return JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\common\management-context.service.ts" `
        @'
import {
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class ManagementContextService {
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

  async assertDealerExists(dealerId: string): Promise<void> {
    const dealer = await this.prisma.organization.findFirst({
      where: {
        id: dealerId,
        type: 'DEALER',
        status: {
          not: 'ARCHIVED',
        },
      },
      select: {
        id: true,
      },
    });

    if (!dealer) {
      throw new NotFoundException('Dealer was not found.');
    }
  }

  dealerWhere(auth: AuthContext): Prisma.OrganizationWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {
        type: 'DEALER',
      };
    }

    return {
      type: 'DEALER',
      id: {
        in: this.dealerScopeIds(auth),
      },
    };
  }

  customerWhere(auth: AuthContext): Prisma.CustomerWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);
    const scopes: Prisma.CustomerWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push({
        managingDealerId: {
          in: dealerIds,
        },
      });
    }

    if (customerIds.length > 0) {
      scopes.push({
        id: {
          in: customerIds,
        },
      });
    }

    if (scopes.length === 0) {
      return {
        id: {
          in: [],
        },
      };
    }

    return {
      OR: scopes,
    };
  }

  async assertCustomer(
    auth: AuthContext,
    customerId: string,
  ): Promise<{
    id: string;
    managingDealerId: string | null;
    customerGroupId: string | null;
    status: string;
  }> {
    const customer = await this.prisma.customer.findUnique({
      where: {
        id: customerId,
      },
      select: {
        id: true,
        managingDealerId: true,
        customerGroupId: true,
        status: true,
      },
    });

    if (!customer) {
      throw new NotFoundException('Customer was not found.');
    }

    if (this.isPlatformScoped(auth)) {
      return customer;
    }

    const dealerAllowed =
      customer.managingDealerId !== null &&
      this.dealerScopeIds(auth).includes(customer.managingDealerId);

    const customerAllowed = this.customerScopeIds(auth).includes(
      customer.id,
    );

    if (!dealerAllowed && !customerAllowed) {
      throw new ForbiddenException(
        'The selected customer is outside the authenticated scope.',
      );
    }

    return customer;
  }

  async assertCustomerManagedByDealer(
    auth: AuthContext,
    customerId: string,
  ): Promise<{
    id: string;
    managingDealerId: string | null;
    customerGroupId: string | null;
    status: string;
  }> {
    const customer = await this.assertCustomer(auth, customerId);

    if (this.isPlatformScoped(auth)) {
      return customer;
    }

    if (
      !customer.managingDealerId ||
      !this.dealerScopeIds(auth).includes(customer.managingDealerId)
    ) {
      throw new ForbiddenException(
        'Customer administration requires matching dealer scope.',
      );
    }

    return customer;
  }

  actorOrganizationId(auth: AuthContext): string | undefined {
    const dealerId = this.dealerScopeIds(auth)[0];

    return dealerId ?? auth.organizationIds[0];
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\common\management-code.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Injectable()
export class ManagementCodeService {
  dealer(): string {
    return this.create('DLR');
  }

  dealerProfile(): string {
    return this.create('DEALER');
  }

  customer(): string {
    return this.create('CUS');
  }

  customerGroup(): string {
    return this.create('GRP');
  }

  user(): string {
    return this.create('USR');
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
        "services\backend-api\src\management\common\pagination-query.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class PaginationQueryDto {
  @ApiPropertyOptional({ default: 1, minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @ApiPropertyOptional({ default: 20, minimum: 1, maximum: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pageSize = 20;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  search?: string;
}
'@

    Write-Step 4 9 "Writing dealer and dealer-staff APIs"

    Write-Utf8File `
        "services\backend-api\src\management\dealers\dto\create-dealer.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsBoolean,
  IsEmail,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CreateDealerDto {
  @ApiProperty({ example: 'Dhaka Central Dealer' })
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name!: string;

  @ApiPropertyOptional({ example: 'Dhaka Central Dealer Limited' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  legalName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  zoneId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  tradeLicenseNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  taxIdentificationNumber?: string;

  @ApiPropertyOptional({ example: '01712345678' })
  @IsOptional()
  @IsString()
  @MaxLength(30)
  contactMobile?: string;

  @ApiPropertyOptional({ example: 'dealer@example.com' })
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  contactEmail?: string;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  commissionEnabled?: boolean;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\dealers\dto\update-dealer.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

const dealerStatuses = [
  'PENDING',
  'ACTIVE',
  'SUSPENDED',
  'INACTIVE',
  'ARCHIVED',
] as const;

export class UpdateDealerDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  legalName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  zoneId?: string;

  @ApiPropertyOptional({ enum: dealerStatuses })
  @IsOptional()
  @IsIn(dealerStatuses)
  status?: (typeof dealerStatuses)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  tradeLicenseNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  taxIdentificationNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(30)
  contactMobile?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  contactEmail?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  commissionEnabled?: boolean;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\dealers\dto\create-dealer-staff.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

const dealerRoleCodes = [
  'DEALER_OWNER',
  'DEALER_MANAGER',
  'DEALER_INSTALLER',
  'DEALER_ACCOUNTS',
] as const;

export class CreateDealerStaffDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  fullName!: string;

  @ApiProperty({ example: '01812345678' })
  @IsString()
  @MaxLength(30)
  mobileNumber!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  email?: string;

  @ApiPropertyOptional({
    description:
      'Required only when the mobile number does not belong to an existing user.',
  })
  @IsOptional()
  @IsString()
  @MinLength(12)
  @MaxLength(200)
  password?: string;

  @ApiProperty({ enum: dealerRoleCodes })
  @IsIn(dealerRoleCodes)
  roleCode!: (typeof dealerRoleCodes)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\dealers\dto\update-dealer-staff.dto.ts" `
        @'
import { ApiProperty } from '@nestjs/swagger';
import { IsBoolean } from 'class-validator';

export class UpdateDealerStaffDto {
  @ApiProperty()
  @IsBoolean()
  active!: boolean;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\dealers\dealers.service.ts" `
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
import { normalizeMobileNumber } from '../../identity/common/mobile-number.util';
import { PasswordService } from '../../identity/common/password.service';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import type { PaginationQueryDto } from '../common/pagination-query.dto';
import type { CreateDealerDto } from './dto/create-dealer.dto';
import type { CreateDealerStaffDto } from './dto/create-dealer-staff.dto';
import type { UpdateDealerDto } from './dto/update-dealer.dto';
import type { UpdateDealerStaffDto } from './dto/update-dealer-staff.dto';

@Injectable()
export class DealersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly context: ManagementContextService,
    private readonly codes: ManagementCodeService,
    private readonly passwordService: PasswordService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: PaginationQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.context.dealerWhere(auth);
    const searchWhere: Prisma.OrganizationWhereInput = query.search
      ? {
          OR: [
            {
              name: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              code: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              dealerProfile: {
                dealerCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            },
          ],
        }
      : {};

    const where: Prisma.OrganizationWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        {
          status: {
            not: 'ARCHIVED',
          },
        },
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.organization.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          zone: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          dealerProfile: true,
          _count: {
            select: {
              memberships: true,
              customerGroups: true,
              managedCustomers: true,
            },
          },
        },
      }),
      this.prisma.organization.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, dealerId: string) {
    this.context.assertDealer(auth, dealerId);

    const dealer = await this.prisma.organization.findFirst({
      where: {
        id: dealerId,
        type: 'DEALER',
      },
      include: {
        zone: true,
        dealerProfile: true,
        _count: {
          select: {
            memberships: true,
            customerGroups: true,
            managedCustomers: true,
            dealerCommissionEntries: true,
            dealerSettlements: true,
          },
        },
      },
    });

    if (!dealer) {
      throw new NotFoundException('Dealer was not found.');
    }

    return dealer;
  }

  async create(auth: AuthContext, dto: CreateDealerDto) {
    this.context.assertPlatform(auth);

    if (dto.zoneId) {
      const zoneExists = await this.prisma.zone.count({
        where: {
          id: dto.zoneId,
          status: 'ACTIVE',
        },
      });

      if (zoneExists !== 1) {
        throw new BadRequestException(
          'Selected zone does not exist or is not active.',
        );
      }
    }

    const dealer = await this.prisma.$transaction(async (transaction) => {
      const organization = await transaction.organization.create({
        data: {
          code: this.codes.dealer(),
          type: 'DEALER',
          name: dto.name.trim(),
          legalName: dto.legalName?.trim(),
          zoneId: dto.zoneId,
          status: 'ACTIVE',
          dealerProfile: {
            create: {
              dealerCode: this.codes.dealerProfile(),
              tradeLicenseNumber: dto.tradeLicenseNumber?.trim(),
              taxIdentificationNumber:
                dto.taxIdentificationNumber?.trim(),
              contactMobile: dto.contactMobile?.trim(),
              contactEmail: dto.contactEmail?.trim().toLowerCase(),
              commissionEnabled: dto.commissionEnabled ?? true,
            },
          },
        },
        include: {
          zone: true,
          dealerProfile: true,
        },
      });

      return organization;
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'dealer.created',
      resourceType: 'Organization',
      resourceId: dealer.id,
      scopeType: 'DEALER',
      scopeId: dealer.id,
      afterData: dealer,
    });

    return dealer;
  }

  async update(
    auth: AuthContext,
    dealerId: string,
    dto: UpdateDealerDto,
  ) {
    this.context.assertPlatform(auth);

    const before = await this.get(auth, dealerId);

    if (dto.zoneId) {
      const zoneExists = await this.prisma.zone.count({
        where: {
          id: dto.zoneId,
          status: 'ACTIVE',
        },
      });

      if (zoneExists !== 1) {
        throw new BadRequestException(
          'Selected zone does not exist or is not active.',
        );
      }
    }

    const updated = await this.prisma.organization.update({
      where: {
        id: dealerId,
      },
      data: {
        name: dto.name?.trim(),
        legalName: dto.legalName?.trim(),
        zoneId: dto.zoneId,
        status: dto.status,
        archivedAt:
          dto.status === 'ARCHIVED'
            ? new Date()
            : dto.status
              ? null
              : undefined,
        dealerProfile: {
          update: {
            tradeLicenseNumber: dto.tradeLicenseNumber?.trim(),
            taxIdentificationNumber:
              dto.taxIdentificationNumber?.trim(),
            contactMobile: dto.contactMobile?.trim(),
            contactEmail: dto.contactEmail?.trim().toLowerCase(),
            commissionEnabled: dto.commissionEnabled,
          },
        },
      },
      include: {
        zone: true,
        dealerProfile: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'dealer.updated',
      resourceType: 'Organization',
      resourceId: dealerId,
      scopeType: 'DEALER',
      scopeId: dealerId,
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async listStaff(auth: AuthContext, dealerId: string) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    return this.prisma.organizationMembership.findMany({
      where: {
        organizationId: dealerId,
      },
      orderBy: {
        createdAt: 'asc',
      },
      include: {
        user: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
            mobileNumber: true,
            email: true,
            status: true,
            lastLoginAt: true,
          },
        },
        roleAssignments: {
          where: {
            scopeType: 'DEALER',
            scopeId: dealerId,
          },
          include: {
            role: {
              select: {
                id: true,
                code: true,
                name: true,
              },
            },
          },
        },
      },
    });
  }

  async createStaff(
    auth: AuthContext,
    dealerId: string,
    dto: CreateDealerStaffDto,
  ) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    const normalizedMobileNumber = normalizeMobileNumber(
      dto.mobileNumber,
    );

    const role = await this.prisma.role.findUnique({
      where: {
        code: dto.roleCode,
      },
    });

    if (!role || role.status !== 'ACTIVE') {
      throw new BadRequestException(
        'Selected dealer role is not active.',
      );
    }

    const existingUser = await this.prisma.user.findUnique({
      where: {
        normalizedMobileNumber,
      },
    });

    if (existingUser?.status === 'ARCHIVED') {
      throw new ConflictException(
        'The mobile number belongs to an archived user.',
      );
    }

    if (!existingUser && !dto.password) {
      throw new BadRequestException(
        'A strong password is required for a new dealer user.',
      );
    }

    const passwordHash = dto.password
      ? await this.passwordService.hash(dto.password)
      : undefined;

    const result = await this.prisma.$transaction(
      async (transaction) => {
        const user = existingUser
          ? existingUser
          : await transaction.user.create({
              data: {
                userCode: this.codes.user(),
                fullName: dto.fullName.trim(),
                mobileNumber: dto.mobileNumber.trim(),
                normalizedMobileNumber,
                email: dto.email?.trim(),
                normalizedEmail: dto.email
                  ?.trim()
                  .toLowerCase(),
                passwordHash,
                passwordChangedAt: new Date(),
                mobileVerifiedAt: new Date(),
                status: 'ACTIVE',
              },
            });

        const membership =
          await transaction.organizationMembership.upsert({
            where: {
              organizationId_userId: {
                organizationId: dealerId,
                userId: user.id,
              },
            },
            update: {
              membershipType:
                dto.roleCode === 'DEALER_OWNER'
                  ? 'OWNER'
                  : 'EMPLOYEE',
              status: 'ACTIVE',
              joinedAt: new Date(),
              endedAt: null,
              invitedByUserId: auth.userId,
            },
            create: {
              organizationId: dealerId,
              userId: user.id,
              membershipType:
                dto.roleCode === 'DEALER_OWNER'
                  ? 'OWNER'
                  : 'EMPLOYEE',
              status: 'ACTIVE',
              isPrimary: false,
              invitedByUserId: auth.userId,
              joinedAt: new Date(),
            },
          });

        const assignment = await transaction.roleAssignment.upsert({
          where: {
            userId_roleId_scopeType_scopeId: {
              userId: user.id,
              roleId: role.id,
              scopeType: 'DEALER',
              scopeId: dealerId,
            },
          },
          update: {
            organizationMembershipId: membership.id,
            status: 'ACTIVE',
            effectiveFrom: new Date(),
            effectiveUntil: null,
            assignedByUserId: auth.userId,
            revokedByUserId: null,
            revokedAt: null,
            revocationReason: null,
          },
          create: {
            userId: user.id,
            roleId: role.id,
            organizationMembershipId: membership.id,
            scopeType: 'DEALER',
            scopeId: dealerId,
            status: 'ACTIVE',
            assignedByUserId: auth.userId,
          },
        });

        return {
          user: {
            id: user.id,
            userCode: user.userCode,
            fullName: user.fullName,
            mobileNumber: user.mobileNumber,
            email: user.email,
            status: user.status,
          },
          membership,
          roleAssignment: assignment,
        };
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'dealer.staff.provisioned',
      resourceType: 'User',
      resourceId: result.user.id,
      scopeType: 'DEALER',
      scopeId: dealerId,
      afterData: {
        user: result.user,
        membershipId: result.membership.id,
        roleCode: dto.roleCode,
      },
      metadata: {
        administrativelyProvisioned: !existingUser,
      },
    });

    return result;
  }

  async updateStaff(
    auth: AuthContext,
    dealerId: string,
    userId: string,
    dto: UpdateDealerStaffDto,
  ) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    const membership =
      await this.prisma.organizationMembership.findUnique({
        where: {
          organizationId_userId: {
            organizationId: dealerId,
            userId,
          },
        },
      });

    if (!membership) {
      throw new NotFoundException(
        'Dealer staff membership was not found.',
      );
    }

    const now = new Date();

    await this.prisma.$transaction(async (transaction) => {
      await transaction.organizationMembership.update({
        where: {
          id: membership.id,
        },
        data: dto.active
          ? {
              status: 'ACTIVE',
              joinedAt: membership.joinedAt ?? now,
              endedAt: null,
            }
          : {
              status: 'SUSPENDED',
            },
      });

      await transaction.roleAssignment.updateMany({
        where: {
          userId,
          scopeType: 'DEALER',
          scopeId: dealerId,
        },
        data: dto.active
          ? {
              status: 'ACTIVE',
              effectiveUntil: null,
              revokedByUserId: null,
              revokedAt: null,
              revocationReason: null,
            }
          : {
              status: 'SUSPENDED',
              effectiveUntil: now,
              revokedByUserId: auth.userId,
              revokedAt: now,
              revocationReason: 'DEALER_STAFF_SUSPENDED',
            },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: dto.active
        ? 'dealer.staff.activated'
        : 'dealer.staff.suspended',
      resourceType: 'OrganizationMembership',
      resourceId: membership.id,
      scopeType: 'DEALER',
      scopeId: dealerId,
      metadata: {
        userId,
      },
    });

    return this.listStaff(auth, dealerId);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\dealers\dealers.controller.ts" `
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
import { PaginationQueryDto } from '../common/pagination-query.dto';
import { CreateDealerDto } from './dto/create-dealer.dto';
import { CreateDealerStaffDto } from './dto/create-dealer-staff.dto';
import { UpdateDealerDto } from './dto/update-dealer.dto';
import { UpdateDealerStaffDto } from './dto/update-dealer-staff.dto';
import { DealersService } from './dealers.service';

@ApiTags('Dealers')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('dealers')
export class DealersController {
  constructor(private readonly dealersService: DealersService) {}

  @Get()
  @RequirePermissions('dealer.view')
  @ApiOperation({ summary: 'List dealers within the authenticated scope' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: PaginationQueryDto,
  ) {
    return this.dealersService.list(auth, query);
  }

  @Post()
  @RequirePermissions('dealer.manage')
  @ApiOperation({ summary: 'Create a dealer organization' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateDealerDto,
  ) {
    return this.dealersService.create(auth, dto);
  }

  @Get(':dealerId')
  @RequirePermissions('dealer.view')
  @ApiOperation({ summary: 'Read one dealer within scope' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
  ) {
    return this.dealersService.get(auth, dealerId);
  }

  @Patch(':dealerId')
  @RequirePermissions('dealer.manage')
  @ApiOperation({ summary: 'Update a dealer organization' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Body() dto: UpdateDealerDto,
  ) {
    return this.dealersService.update(auth, dealerId, dto);
  }

  @Get(':dealerId/staff')
  @RequirePermissions('dealer.staff.manage')
  @ApiOperation({ summary: 'List dealer staff and scoped roles' })
  listStaff(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
  ) {
    return this.dealersService.listStaff(auth, dealerId);
  }

  @Post(':dealerId/staff')
  @RequirePermissions('dealer.staff.manage')
  @ApiOperation({ summary: 'Provision or attach a dealer staff user' })
  createStaff(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Body() dto: CreateDealerStaffDto,
  ) {
    return this.dealersService.createStaff(auth, dealerId, dto);
  }

  @Patch(':dealerId/staff/:userId')
  @RequirePermissions('dealer.staff.manage')
  @ApiOperation({ summary: 'Activate or suspend dealer staff access' })
  updateStaff(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Param('userId', new ParseUUIDPipe()) userId: string,
    @Body() dto: UpdateDealerStaffDto,
  ) {
    return this.dealersService.updateStaff(
      auth,
      dealerId,
      userId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\dealers\dealers.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import { DealersController } from './dealers.controller';
import { DealersService } from './dealers.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [DealersController],
  providers: [
    DealersService,
    ManagementContextService,
    ManagementCodeService,
  ],
  exports: [DealersService],
})
export class DealersModule {}
'@

    Write-Step 5 9 "Writing customer-group APIs"

    Write-Utf8File `
        "services\backend-api\src\management\customer-groups\dto\create-customer-group.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CreateCustomerGroupDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customer-groups\dto\update-customer-group.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

const groupStatuses = ['ACTIVE', 'INACTIVE', 'ARCHIVED'] as const;

export class UpdateCustomerGroupDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @ApiPropertyOptional({ enum: groupStatuses })
  @IsOptional()
  @IsIn(groupStatuses)
  status?: (typeof groupStatuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customer-groups\customer-groups.service.ts" `
        @'
import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import type { CreateCustomerGroupDto } from './dto/create-customer-group.dto';
import type { UpdateCustomerGroupDto } from './dto/update-customer-group.dto';

@Injectable()
export class CustomerGroupsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly context: ManagementContextService,
    private readonly codes: ManagementCodeService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, dealerId: string) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    return this.prisma.customerGroup.findMany({
      where: {
        dealerOrganizationId: dealerId,
      },
      orderBy: [
        {
          status: 'asc',
        },
        {
          name: 'asc',
        },
      ],
      include: {
        _count: {
          select: {
            customers: true,
          },
        },
      },
    });
  }

  async create(
    auth: AuthContext,
    dealerId: string,
    dto: CreateCustomerGroupDto,
  ) {
    this.context.assertDealer(auth, dealerId);
    await this.context.assertDealerExists(dealerId);

    const normalizedName = dto.name.trim().toLowerCase();

    const duplicate = await this.prisma.customerGroup.count({
      where: {
        dealerOrganizationId: dealerId,
        normalizedName,
      },
    });

    if (duplicate > 0) {
      throw new ConflictException(
        'A customer group with this name already exists for the dealer.',
      );
    }

    const group = await this.prisma.customerGroup.create({
      data: {
        code: this.codes.customerGroup(),
        dealerOrganizationId: dealerId,
        name: dto.name.trim(),
        normalizedName,
        description: dto.description?.trim(),
        status: 'ACTIVE',
        createdByUserId: auth.userId,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'customer_group.created',
      resourceType: 'CustomerGroup',
      resourceId: group.id,
      scopeType: 'CUSTOMER_GROUP',
      scopeId: group.id,
      afterData: group,
      metadata: {
        dealerId,
      },
    });

    return group;
  }

  async update(
    auth: AuthContext,
    dealerId: string,
    groupId: string,
    dto: UpdateCustomerGroupDto,
  ) {
    this.context.assertDealer(auth, dealerId);

    const before = await this.prisma.customerGroup.findFirst({
      where: {
        id: groupId,
        dealerOrganizationId: dealerId,
      },
    });

    if (!before) {
      throw new NotFoundException('Customer group was not found.');
    }

    const normalizedName = dto.name
      ? dto.name.trim().toLowerCase()
      : undefined;

    if (normalizedName && normalizedName !== before.normalizedName) {
      const duplicate = await this.prisma.customerGroup.count({
        where: {
          dealerOrganizationId: dealerId,
          normalizedName,
          id: {
            not: groupId,
          },
        },
      });

      if (duplicate > 0) {
        throw new ConflictException(
          'A customer group with this name already exists for the dealer.',
        );
      }
    }

    const updated = await this.prisma.customerGroup.update({
      where: {
        id: groupId,
      },
      data: {
        name: dto.name?.trim(),
        normalizedName,
        description: dto.description?.trim(),
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
        this.context.actorOrganizationId(auth),
      action: 'customer_group.updated',
      resourceType: 'CustomerGroup',
      resourceId: groupId,
      scopeType: 'CUSTOMER_GROUP',
      scopeId: groupId,
      beforeData: before,
      afterData: updated,
      metadata: {
        dealerId,
      },
    });

    return updated;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customer-groups\customer-groups.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
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
import { CustomerGroupsService } from './customer-groups.service';
import { CreateCustomerGroupDto } from './dto/create-customer-group.dto';
import { UpdateCustomerGroupDto } from './dto/update-customer-group.dto';

@ApiTags('Customer Groups')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('dealers/:dealerId/customer-groups')
export class CustomerGroupsController {
  constructor(
    private readonly customerGroupsService: CustomerGroupsService,
  ) {}

  @Get()
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'List customer groups for a dealer' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
  ) {
    return this.customerGroupsService.list(auth, dealerId);
  }

  @Post()
  @RequirePermissions('customer.create')
  @ApiOperation({ summary: 'Create a dealer customer group' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Body() dto: CreateCustomerGroupDto,
  ) {
    return this.customerGroupsService.create(auth, dealerId, dto);
  }

  @Patch(':groupId')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Update or archive a customer group' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Param('groupId', new ParseUUIDPipe()) groupId: string,
    @Body() dto: UpdateCustomerGroupDto,
  ) {
    return this.customerGroupsService.update(
      auth,
      dealerId,
      groupId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customer-groups\customer-groups.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import { CustomerGroupsController } from './customer-groups.controller';
import { CustomerGroupsService } from './customer-groups.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [CustomerGroupsController],
  providers: [
    CustomerGroupsService,
    ManagementContextService,
    ManagementCodeService,
  ],
  exports: [CustomerGroupsService],
})
export class CustomerGroupsModule {}
'@

    Write-Step 6 9 "Writing customer onboarding, membership, group, and transfer APIs"

    Write-Utf8File `
        "services\backend-api\src\management\customers\dto\address.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class AddressDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  line1?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  line2?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  city?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  district?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(30)
  postalCode?: string;

  @ApiPropertyOptional({ default: 'Bangladesh' })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  country?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\dto\create-individual-customer.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsEmail,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { AddressDto } from './address.dto';

export class CreateIndividualCustomerDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  fullName!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  managingDealerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerGroupId?: string;

  @ApiProperty({ example: '01712345678' })
  @IsString()
  @MaxLength(30)
  primaryMobile!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  primaryEmail?: string;

  @ApiPropertyOptional({ type: AddressDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => AddressDto)
  billingAddress?: AddressDto;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  dateOfBirth?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  emergencyContactName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(30)
  emergencyContactMobile?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\dto\create-organization-customer.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsEmail,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { AddressDto } from './address.dto';

export class CreateOrganizationCustomerDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(200)
  legalName!: string;

  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  displayName!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  managingDealerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerGroupId?: string;

  @ApiProperty({ example: '01712345678' })
  @IsString()
  @MaxLength(30)
  primaryMobile!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  primaryEmail?: string;

  @ApiPropertyOptional({ type: AddressDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => AddressDto)
  billingAddress?: AddressDto;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  registrationNumber?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  taxReference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  contactPersonName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(30)
  contactMobile?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  contactEmail?: string;

  @ApiPropertyOptional({ type: AddressDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => AddressDto)
  operationalAddress?: AddressDto;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\dto\customer-query.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { PaginationQueryDto } from '../../common/pagination-query.dto';

const customerStatuses = [
  'PENDING',
  'ACTIVE',
  'SUSPENDED',
  'INACTIVE',
  'ARCHIVED',
] as const;

const customerTypes = ['INDIVIDUAL', 'ORGANIZATION'] as const;

export class CustomerQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: customerStatuses })
  @IsOptional()
  @IsIn(customerStatuses)
  status?: (typeof customerStatuses)[number];

  @ApiPropertyOptional({ enum: customerTypes })
  @IsOptional()
  @IsIn(customerTypes)
  customerType?: (typeof customerTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  managingDealerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerGroupId?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\dto\assign-customer-group.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsUUID } from 'class-validator';

export class AssignCustomerGroupDto {
  @ApiPropertyOptional({
    nullable: true,
    description: 'Send null or omit to remove the customer from a group.',
  })
  @IsOptional()
  @IsUUID()
  customerGroupId?: string | null;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\dto\transfer-customer.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class TransferCustomerDto {
  @ApiPropertyOptional({
    nullable: true,
    description:
      'Send null or omit to transfer the customer to platform management.',
  })
  @IsOptional()
  @IsUUID()
  targetDealerId?: string | null;

  @ApiPropertyOptional({
    nullable: true,
    description:
      'Optional group belonging to the target dealer.',
  })
  @IsOptional()
  @IsUUID()
  targetCustomerGroupId?: string | null;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\dto\create-customer-member.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsBoolean,
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

const customerRoleCodes = [
  'CUSTOMER_OWNER',
  'CUSTOMER_ADMIN',
  'CUSTOMER_VIEWER',
] as const;

export class CreateCustomerMemberDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  fullName!: string;

  @ApiProperty({ example: '01712345678' })
  @IsString()
  @MaxLength(30)
  mobileNumber!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @MaxLength(254)
  email?: string;

  @ApiPropertyOptional({
    description:
      'Required only when the mobile number does not belong to an existing user.',
  })
  @IsOptional()
  @IsString()
  @MinLength(12)
  @MaxLength(200)
  password?: string;

  @ApiProperty({ enum: customerRoleCodes })
  @IsIn(customerRoleCodes)
  roleCode!: (typeof customerRoleCodes)[number];

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  isPrimary?: boolean;
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\customers.service.ts" `
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
import { normalizeMobileNumber } from '../../identity/common/mobile-number.util';
import { PasswordService } from '../../identity/common/password.service';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import type { AddressDto } from './dto/address.dto';
import type { AssignCustomerGroupDto } from './dto/assign-customer-group.dto';
import type { CreateCustomerMemberDto } from './dto/create-customer-member.dto';
import type { CreateIndividualCustomerDto } from './dto/create-individual-customer.dto';
import type { CreateOrganizationCustomerDto } from './dto/create-organization-customer.dto';
import type { CustomerQueryDto } from './dto/customer-query.dto';
import type { TransferCustomerDto } from './dto/transfer-customer.dto';

@Injectable()
export class CustomersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly context: ManagementContextService,
    private readonly codes: ManagementCodeService,
    private readonly passwordService: PasswordService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: CustomerQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.context.customerWhere(auth);
    const searchWhere: Prisma.CustomerWhereInput = query.search
      ? {
          OR: [
            {
              customerCode: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              primaryMobile: {
                contains: query.search,
              },
            },
            {
              primaryEmail: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              individualProfile: {
                fullName: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            },
            {
              organizationProfile: {
                displayName: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            },
          ],
        }
      : {};

    const where: Prisma.CustomerWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.status
          ? {
              status: query.status,
            }
          : {
              status: {
                not: 'ARCHIVED',
              },
            },
        query.customerType
          ? {
              customerType: query.customerType,
            }
          : {},
        query.managingDealerId
          ? {
              managingDealerId: query.managingDealerId,
            }
          : {},
        query.customerGroupId
          ? {
              customerGroupId: query.customerGroupId,
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.customer.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
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
          customerGroup: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          _count: {
            select: {
              memberships: true,
              vehicles: true,
              billingSubscriptions: true,
            },
          },
        },
      }),
      this.prisma.customer.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, customerId: string) {
    await this.context.assertCustomer(auth, customerId);

    const customer = await this.prisma.customer.findUnique({
      where: {
        id: customerId,
      },
      include: {
        individualProfile: true,
        organizationProfile: true,
        managingDealer: {
          include: {
            dealerProfile: true,
          },
        },
        customerGroup: true,
        memberships: {
          include: {
            user: {
              select: {
                id: true,
                userCode: true,
                fullName: true,
                mobileNumber: true,
                email: true,
                status: true,
              },
            },
          },
        },
        dealerAssignments: {
          orderBy: {
            assignedAt: 'desc',
          },
        },
        _count: {
          select: {
            vehicles: true,
            billingSubscriptions: true,
            invoices: true,
            payments: true,
          },
        },
      },
    });

    if (!customer) {
      throw new NotFoundException('Customer was not found.');
    }

    return customer;
  }

  async createIndividual(
    auth: AuthContext,
    dto: CreateIndividualCustomerDto,
  ) {
    const dealerId = await this.resolveDealer(
      auth,
      dto.managingDealerId,
    );

    const groupId = await this.resolveGroup(
      dealerId,
      dto.customerGroupId,
    );

    const customer = await this.prisma.$transaction(
      async (transaction) => {
        return transaction.customer.create({
          data: {
            customerCode: this.codes.customer(),
            customerType: 'INDIVIDUAL',
            status: 'ACTIVE',
            managingDealerId: dealerId,
            customerGroupId: groupId,
            acquisitionSource: dealerId ? 'DEALER' : 'DIRECT',
            primaryMobile: dto.primaryMobile.trim(),
            primaryEmail: dto.primaryEmail?.trim().toLowerCase(),
            billingAddress: this.address(dto.billingAddress),
            createdByUserId: auth.userId,
            individualProfile: {
              create: {
                fullName: dto.fullName.trim(),
                dateOfBirth: dto.dateOfBirth
                  ? new Date(dto.dateOfBirth)
                  : undefined,
                emergencyContactName:
                  dto.emergencyContactName?.trim(),
                emergencyContactMobile:
                  dto.emergencyContactMobile?.trim(),
              },
            },
            dealerAssignments: {
              create: {
                managementType: dealerId ? 'DEALER' : 'PLATFORM',
                dealerOrganizationId: dealerId,
                assignmentReason: 'INITIAL_ASSIGNMENT',
                assignedByUserId: auth.userId,
              },
            },
          },
          include: {
            individualProfile: true,
            managingDealer: true,
            customerGroup: true,
          },
        });
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'customer.individual.created',
      resourceType: 'Customer',
      resourceId: customer.id,
      scopeType: 'CUSTOMER',
      scopeId: customer.id,
      afterData: customer,
    });

    return customer;
  }

  async createOrganization(
    auth: AuthContext,
    dto: CreateOrganizationCustomerDto,
  ) {
    const dealerId = await this.resolveDealer(
      auth,
      dto.managingDealerId,
    );

    const groupId = await this.resolveGroup(
      dealerId,
      dto.customerGroupId,
    );

    if (dto.registrationNumber) {
      const duplicate = await this.prisma.organizationCustomerProfile.count({
        where: {
          registrationNumber: dto.registrationNumber.trim(),
        },
      });

      if (duplicate > 0) {
        throw new ConflictException(
          'The organization registration number already exists.',
        );
      }
    }

    const customer = await this.prisma.$transaction(
      async (transaction) => {
        return transaction.customer.create({
          data: {
            customerCode: this.codes.customer(),
            customerType: 'ORGANIZATION',
            status: 'ACTIVE',
            managingDealerId: dealerId,
            customerGroupId: groupId,
            acquisitionSource: dealerId ? 'DEALER' : 'DIRECT',
            primaryMobile: dto.primaryMobile.trim(),
            primaryEmail: dto.primaryEmail?.trim().toLowerCase(),
            billingAddress: this.address(dto.billingAddress),
            createdByUserId: auth.userId,
            organizationProfile: {
              create: {
                legalName: dto.legalName.trim(),
                displayName: dto.displayName.trim(),
                registrationNumber:
                  dto.registrationNumber?.trim(),
                taxReference: dto.taxReference?.trim(),
                contactPersonName:
                  dto.contactPersonName?.trim(),
                contactMobile: dto.contactMobile?.trim(),
                contactEmail:
                  dto.contactEmail?.trim().toLowerCase(),
                operationalAddress: this.address(
                  dto.operationalAddress,
                ),
              },
            },
            dealerAssignments: {
              create: {
                managementType: dealerId ? 'DEALER' : 'PLATFORM',
                dealerOrganizationId: dealerId,
                assignmentReason: 'INITIAL_ASSIGNMENT',
                assignedByUserId: auth.userId,
              },
            },
          },
          include: {
            organizationProfile: true,
            managingDealer: true,
            customerGroup: true,
          },
        });
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'customer.organization.created',
      resourceType: 'Customer',
      resourceId: customer.id,
      scopeType: 'CUSTOMER',
      scopeId: customer.id,
      afterData: customer,
    });

    return customer;
  }

  async assignGroup(
    auth: AuthContext,
    customerId: string,
    dto: AssignCustomerGroupDto,
  ) {
    const customer =
      await this.context.assertCustomerManagedByDealer(
        auth,
        customerId,
      );

    if (!customer.managingDealerId && dto.customerGroupId) {
      throw new BadRequestException(
        'A platform-managed customer cannot belong to a dealer group.',
      );
    }

    const groupId = await this.resolveGroup(
      customer.managingDealerId,
      dto.customerGroupId ?? undefined,
    );

    const updated = await this.prisma.customer.update({
      where: {
        id: customerId,
      },
      data: {
        customerGroupId: groupId,
      },
      include: {
        individualProfile: true,
        organizationProfile: true,
        managingDealer: true,
        customerGroup: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'customer.group.changed',
      resourceType: 'Customer',
      resourceId: customerId,
      scopeType: 'CUSTOMER',
      scopeId: customerId,
      beforeData: {
        customerGroupId: customer.customerGroupId,
      },
      afterData: {
        customerGroupId: updated.customerGroupId,
      },
    });

    return updated;
  }

  async transfer(
    auth: AuthContext,
    customerId: string,
    dto: TransferCustomerDto,
  ) {
    this.context.assertPlatform(auth);

    const before = await this.get(auth, customerId);
    const targetDealerId = dto.targetDealerId ?? null;

    if (targetDealerId) {
      await this.context.assertDealerExists(targetDealerId);
    }

    const targetGroupId = await this.resolveGroup(
      targetDealerId,
      dto.targetCustomerGroupId ?? undefined,
    );

    const now = new Date();

    const updated = await this.prisma.$transaction(
      async (transaction) => {
        await transaction.customerDealerAssignment.updateMany({
          where: {
            customerId,
            endedAt: null,
          },
          data: {
            endedAt: now,
          },
        });

        await transaction.customerDealerAssignment.create({
          data: {
            customerId,
            managementType: targetDealerId
              ? 'DEALER'
              : 'PLATFORM',
            dealerOrganizationId: targetDealerId,
            assignmentReason: targetDealerId
              ? 'DEALER_TRANSFER'
              : 'PLATFORM_ASSIGNMENT',
            assignedByUserId: auth.userId,
            notes: dto.notes?.trim(),
          },
        });

        return transaction.customer.update({
          where: {
            id: customerId,
          },
          data: {
            managingDealerId: targetDealerId,
            customerGroupId: targetGroupId,
          },
          include: {
            individualProfile: true,
            organizationProfile: true,
            managingDealer: true,
            customerGroup: true,
          },
        });
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'customer.transferred',
      resourceType: 'Customer',
      resourceId: customerId,
      scopeType: 'CUSTOMER',
      scopeId: customerId,
      beforeData: {
        managingDealerId: before.managingDealerId,
        customerGroupId: before.customerGroupId,
      },
      afterData: {
        managingDealerId: updated.managingDealerId,
        customerGroupId: updated.customerGroupId,
      },
      metadata: {
        notes: dto.notes,
      },
    });

    return updated;
  }

  async listMembers(auth: AuthContext, customerId: string) {
    await this.context.assertCustomer(auth, customerId);

    return this.prisma.customerMembership.findMany({
      where: {
        customerId,
      },
      orderBy: {
        createdAt: 'asc',
      },
      include: {
        user: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
            mobileNumber: true,
            email: true,
            status: true,
            lastLoginAt: true,
          },
        },
      },
    });
  }

  async createMember(
    auth: AuthContext,
    customerId: string,
    dto: CreateCustomerMemberDto,
  ) {
    await this.context.assertCustomerManagedByDealer(
      auth,
      customerId,
    );

    const normalizedMobileNumber = normalizeMobileNumber(
      dto.mobileNumber,
    );

    const role = await this.prisma.role.findUnique({
      where: {
        code: dto.roleCode,
      },
    });

    if (!role || role.status !== 'ACTIVE') {
      throw new BadRequestException(
        'Selected customer role is not active.',
      );
    }

    const existingUser = await this.prisma.user.findUnique({
      where: {
        normalizedMobileNumber,
      },
    });

    if (existingUser?.status === 'ARCHIVED') {
      throw new ConflictException(
        'The mobile number belongs to an archived user.',
      );
    }

    if (!existingUser && !dto.password) {
      throw new BadRequestException(
        'A strong password is required for a new customer user.',
      );
    }

    const passwordHash = dto.password
      ? await this.passwordService.hash(dto.password)
      : undefined;

    const result = await this.prisma.$transaction(
      async (transaction) => {
        const user = existingUser
          ? existingUser
          : await transaction.user.create({
              data: {
                userCode: this.codes.user(),
                fullName: dto.fullName.trim(),
                mobileNumber: dto.mobileNumber.trim(),
                normalizedMobileNumber,
                email: dto.email?.trim(),
                normalizedEmail: dto.email
                  ?.trim()
                  .toLowerCase(),
                passwordHash,
                passwordChangedAt: new Date(),
                mobileVerifiedAt: new Date(),
                status: 'ACTIVE',
              },
            });

        if (dto.isPrimary) {
          await transaction.customerMembership.updateMany({
            where: {
              customerId,
              isPrimary: true,
            },
            data: {
              isPrimary: false,
            },
          });
        }

        const membership =
          await transaction.customerMembership.upsert({
            where: {
              customerId_userId: {
                customerId,
                userId: user.id,
              },
            },
            update: {
              status: 'ACTIVE',
              isPrimary: dto.isPrimary ?? false,
              invitedByUserId: auth.userId,
              joinedAt: new Date(),
              endedAt: null,
            },
            create: {
              customerId,
              userId: user.id,
              status: 'ACTIVE',
              isPrimary: dto.isPrimary ?? false,
              invitedByUserId: auth.userId,
              joinedAt: new Date(),
            },
          });

        const assignment = await transaction.roleAssignment.upsert({
          where: {
            userId_roleId_scopeType_scopeId: {
              userId: user.id,
              roleId: role.id,
              scopeType: 'CUSTOMER',
              scopeId: customerId,
            },
          },
          update: {
            status: 'ACTIVE',
            effectiveFrom: new Date(),
            effectiveUntil: null,
            assignedByUserId: auth.userId,
            revokedByUserId: null,
            revokedAt: null,
            revocationReason: null,
          },
          create: {
            userId: user.id,
            roleId: role.id,
            scopeType: 'CUSTOMER',
            scopeId: customerId,
            status: 'ACTIVE',
            assignedByUserId: auth.userId,
          },
        });

        return {
          user: {
            id: user.id,
            userCode: user.userCode,
            fullName: user.fullName,
            mobileNumber: user.mobileNumber,
            email: user.email,
            status: user.status,
          },
          membership,
          roleAssignment: assignment,
        };
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.context.actorOrganizationId(auth),
      action: 'customer.member.provisioned',
      resourceType: 'User',
      resourceId: result.user.id,
      scopeType: 'CUSTOMER',
      scopeId: customerId,
      afterData: {
        user: result.user,
        membershipId: result.membership.id,
        roleCode: dto.roleCode,
      },
      metadata: {
        administrativelyProvisioned: !existingUser,
      },
    });

    return result;
  }

  private async resolveDealer(
    auth: AuthContext,
    requestedDealerId?: string,
  ): Promise<string | null> {
    if (this.context.isPlatformScoped(auth)) {
      if (!requestedDealerId) {
        return null;
      }

      await this.context.assertDealerExists(requestedDealerId);
      return requestedDealerId;
    }

    const dealerIds = this.context.dealerScopeIds(auth);

    if (requestedDealerId) {
      this.context.assertDealer(auth, requestedDealerId);
      await this.context.assertDealerExists(requestedDealerId);
      return requestedDealerId;
    }

    if (dealerIds.length !== 1) {
      throw new BadRequestException(
        'managingDealerId is required when more than one dealer scope is available.',
      );
    }

    await this.context.assertDealerExists(dealerIds[0]);
    return dealerIds[0];
  }

  private async resolveGroup(
    dealerId: string | null,
    requestedGroupId?: string,
  ): Promise<string | null> {
    if (!requestedGroupId) {
      return null;
    }

    if (!dealerId) {
      throw new BadRequestException(
        'A direct customer cannot belong to a dealer customer group.',
      );
    }

    const group = await this.prisma.customerGroup.findFirst({
      where: {
        id: requestedGroupId,
        dealerOrganizationId: dealerId,
        status: 'ACTIVE',
      },
      select: {
        id: true,
      },
    });

    if (!group) {
      throw new BadRequestException(
        'Customer group does not belong to the selected dealer or is not active.',
      );
    }

    return group.id;
  }

  private address(
    value?: AddressDto,
  ): Prisma.InputJsonValue | undefined {
    if (!value) {
      return undefined;
    }

    return {
      line1: value.line1 ?? '',
      line2: value.line2 ?? '',
      city: value.city ?? '',
      district: value.district ?? '',
      postalCode: value.postalCode ?? '',
      country: value.country ?? 'Bangladesh',
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\customers.controller.ts" `
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
import { AssignCustomerGroupDto } from './dto/assign-customer-group.dto';
import { CreateCustomerMemberDto } from './dto/create-customer-member.dto';
import { CreateIndividualCustomerDto } from './dto/create-individual-customer.dto';
import { CreateOrganizationCustomerDto } from './dto/create-organization-customer.dto';
import { CustomerQueryDto } from './dto/customer-query.dto';
import { TransferCustomerDto } from './dto/transfer-customer.dto';
import { CustomersService } from './customers.service';

@ApiTags('Customers')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('customers')
export class CustomersController {
  constructor(private readonly customersService: CustomersService) {}

  @Get()
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'List customers within effective scope' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: CustomerQueryDto,
  ) {
    return this.customersService.list(auth, query);
  }

  @Post('individual')
  @RequirePermissions('customer.create')
  @ApiOperation({ summary: 'Create an individual customer' })
  createIndividual(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateIndividualCustomerDto,
  ) {
    return this.customersService.createIndividual(auth, dto);
  }

  @Post('organization')
  @RequirePermissions('customer.create')
  @ApiOperation({ summary: 'Create an organization customer' })
  createOrganization(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateOrganizationCustomerDto,
  ) {
    return this.customersService.createOrganization(auth, dto);
  }

  @Get(':customerId')
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'Read one customer within scope' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
  ) {
    return this.customersService.get(auth, customerId);
  }

  @Patch(':customerId/group')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Assign or clear a customer group' })
  assignGroup(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
    @Body() dto: AssignCustomerGroupDto,
  ) {
    return this.customersService.assignGroup(
      auth,
      customerId,
      dto,
    );
  }

  @Post(':customerId/transfer')
  @RequirePermissions('customer.transfer')
  @ApiOperation({
    summary:
      'Transfer a customer to another dealer or platform management',
  })
  transfer(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
    @Body() dto: TransferCustomerDto,
  ) {
    return this.customersService.transfer(auth, customerId, dto);
  }

  @Get(':customerId/members')
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'List customer account members' })
  listMembers(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
  ) {
    return this.customersService.listMembers(auth, customerId);
  }

  @Post(':customerId/members')
  @RequirePermissions('customer.update')
  @ApiOperation({
    summary: 'Provision or attach a customer account member',
  })
  createMember(
    @CurrentAuth() auth: AuthContext,
    @Param('customerId', new ParseUUIDPipe()) customerId: string,
    @Body() dto: CreateCustomerMemberDto,
  ) {
    return this.customersService.createMember(
      auth,
      customerId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\management\customers\customers.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../../identity/access-control/access-control.module';
import { AuditModule } from '../../identity/audit/audit.module';
import { ManagementCodeService } from '../common/management-code.service';
import { ManagementContextService } from '../common/management-context.service';
import { CustomersController } from './customers.controller';
import { CustomersService } from './customers.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [CustomersController],
  providers: [
    CustomersService,
    ManagementContextService,
    ManagementCodeService,
  ],
  exports: [CustomersService],
})
export class CustomersModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\management\dealer-customer-management.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { CustomerGroupsModule } from './customer-groups/customer-groups.module';
import { CustomersModule } from './customers/customers.module';
import { DealersModule } from './dealers/dealers.module';

@Module({
  imports: [
    DealersModule,
    CustomerGroupsModule,
    CustomersModule,
  ],
})
export class DealerCustomerManagementModule {}
'@

    Write-Step 7 9 "Registering the management module and writing E2E coverage"

    $appModulePath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\app.module.ts"

    $appModule = [System.IO.File]::ReadAllText($appModulePath)

    if (-not $appModule.Contains("DealerCustomerManagementModule")) {
        $identityImport =
            "import { IdentityAccessModule } from './identity/identity-access.module';"

        if (-not $appModule.Contains($identityImport)) {
            throw "Could not locate IdentityAccessModule import."
        }

        $appModule = $appModule.Replace(
            $identityImport,
            $identityImport +
            [Environment]::NewLine +
            "import { DealerCustomerManagementModule } from './management/dealer-customer-management.module';"
        )

        $identityModuleEntry = "    IdentityAccessModule,"

        if (-not $appModule.Contains($identityModuleEntry)) {
            throw "Could not locate IdentityAccessModule registration."
        }

        $appModule = $appModule.Replace(
            $identityModuleEntry,
            $identityModuleEntry +
            [Environment]::NewLine +
            "    DealerCustomerManagementModule,"
        )

        [System.IO.File]::WriteAllText(
            $appModulePath,
            $appModule,
            $script:Utf8NoBom
        )

        Write-Host (
            "[UPDATED] services\backend-api\src\app.module.ts"
        ) -ForegroundColor Green
    }

    Write-Utf8File `
        "services\backend-api\test\dealer-customer.e2e-spec.ts" `
        @'
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

describe('Solid Tracker Dealer and Customer Management (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let platformUserId: string;
  let dealerId: string;
  let managerUserId: string;
  let groupId: string;
  let customerId: string;
  let accessToken: string;

  const platformPassword = 'SolidTracker123!';

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
    const suffix = randomUUID().replace(/-/g, '').slice(0, 8);
    const digits = suffix.replace(/[a-f]/g, '7');
    const platformMobile = `+88015${digits}`;

    const platformOrganization =
      await prisma.organization.findUniqueOrThrow({
        where: {
          code: 'ORG-PLATFORM',
        },
      });

    const platformRole = await prisma.role.findUniqueOrThrow({
      where: {
        code: 'PLATFORM_SUPER_ADMIN',
      },
    });

    const platformUser = await prisma.user.create({
      data: {
        userCode: `TEST-${randomUUID()
          .replace(/-/g, '')
          .slice(0, 12)
          .toUpperCase()}`,
        fullName: 'Management E2E Platform User',
        mobileNumber: platformMobile,
        normalizedMobileNumber: platformMobile,
        passwordHash:
          await passwordService.hash(platformPassword),
        passwordChangedAt: new Date(),
        mobileVerifiedAt: new Date(),
        status: 'ACTIVE',
      },
    });

    platformUserId = platformUser.id;

    const membership =
      await prisma.organizationMembership.create({
        data: {
          organizationId: platformOrganization.id,
          userId: platformUser.id,
          membershipType: 'EMPLOYEE',
          status: 'ACTIVE',
          joinedAt: new Date(),
        },
      });

    await prisma.roleAssignment.create({
      data: {
        userId: platformUser.id,
        roleId: platformRole.id,
        organizationMembershipId: membership.id,
        scopeType: 'PLATFORM',
        scopeId: platformOrganization.id,
        status: 'ACTIVE',
      },
    });

    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        mobileNumber: platformMobile,
        password: platformPassword,
        platform: 'WEB',
        deviceName: 'Dealer Customer E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = login.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

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

    if (groupId) {
      await prisma.customerGroup.update({
        where: {
          id: groupId,
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

    for (const userId of [managerUserId, platformUserId]) {
      if (userId) {
        await prisma.userSession.deleteMany({
          where: {
            userId,
          },
        });

        await prisma.user.update({
          where: {
            id: userId,
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

  it('creates a dealer, manager, group, customer, and transfer history', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: 'Management E2E Dealer',
        legalName: 'Management E2E Dealer Limited',
        contactMobile: '01700000000',
        commissionEnabled: true,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const managerSuffix = randomUUID()
      .replace(/-/g, '')
      .slice(0, 8)
      .replace(/[a-f]/g, '8');

    const managerResponse = await request(app.getHttpServer())
      .post(`/api/v1/dealers/${dealerId}/staff`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        fullName: 'Management E2E Dealer Manager',
        mobileNumber: `+88018${managerSuffix}`,
        password: 'DealerManager123!',
        roleCode: 'DEALER_MANAGER',
      })
      .expect(201);

    managerUserId = managerResponse.body.user.id as string;

    const groupResponse = await request(app.getHttpServer())
      .post(`/api/v1/dealers/${dealerId}/customer-groups`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: 'E2E Fleet Customers',
        description: 'Created by the management E2E suite',
      })
      .expect(201);

    groupId = groupResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        fullName: 'Management E2E Customer',
        managingDealerId: dealerId,
        customerGroupId: groupId,
        primaryMobile: '01900000000',
        billingAddress: {
          city: 'Dhaka',
          country: 'Bangladesh',
        },
      })
      .expect(201);

    customerId = customerResponse.body.id as string;

    expect(customerResponse.body.managingDealerId).toBe(dealerId);
    expect(customerResponse.body.customerGroupId).toBe(groupId);

    const listResponse = await request(app.getHttpServer())
      .get('/api/v1/customers')
      .query({
        managingDealerId: dealerId,
      })
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(
      listResponse.body.items.some(
        (customer: { id: string }) => customer.id === customerId,
      ),
    ).toBe(true);

    const transferResponse = await request(app.getHttpServer())
      .post(`/api/v1/customers/${customerId}/transfer`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        targetDealerId: null,
        targetCustomerGroupId: null,
        notes: 'E2E transfer to direct platform management',
      })
      .expect(201);

    expect(transferResponse.body.managingDealerId).toBeNull();
    expect(transferResponse.body.customerGroupId).toBeNull();

    const assignments =
      await prisma.customerDealerAssignment.findMany({
        where: {
          customerId,
        },
        orderBy: {
          assignedAt: 'asc',
        },
      });

    expect(assignments).toHaveLength(2);
    expect(assignments[0].endedAt).not.toBeNull();
    expect(assignments[1].managementType).toBe('PLATFORM');
  });
});
'@

    Write-Step 8 9 "Running format, lint, typecheck, tests, and build"

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
    FROM "roles"
    WHERE "code" IN (
      'PLATFORM_SUPER_ADMIN',
      'DEALER_OWNER',
      'DEALER_MANAGER',
      'CUSTOMER_OWNER'
    )
      AND "status" = 'ACTIVE'
  ) AS required_role_count;
'@

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "Dealer-customer database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $verificationParts = $verificationLine.Split(",")

    if ($verificationParts.Count -ne 3) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTableCount = [int]$verificationParts[0]
    $migrationCount = [int]$verificationParts[1]
    $requiredRoleCount = [int]$verificationParts[2]

    if ($publicTableCount -lt 50) {
        throw "Expected at least 50 public tables."
    }

    if ($migrationCount -lt 5) {
        throw "Expected at least 5 applied migrations."
    }

    if ($requiredRoleCount -ne 4) {
        throw "Required management roles are missing."
    }

    Write-Host "Public tables:       $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:  $migrationCount" -ForegroundColor Green
    Write-Host "Required roles:      $requiredRoleCount" -ForegroundColor Green

    Write-Step 9 9 "Writing architecture documentation and committing"

    Write-Utf8File `
        "docs\architecture\dealer-customer-api.md" `
        @'
# Dealer and Customer Management API

## Scope

This stage adds application services and REST endpoints for:

- dealer organizations;
- dealer staff and scoped dealer roles;
- customer groups;
- individual customer onboarding;
- organization customer onboarding;
- customer members and scoped customer roles;
- customer group assignment;
- dealer-to-dealer and dealer-to-platform transfer;
- scoped queries and immutable audit records.

No database migration is required because the Phase 1 schema already contains the necessary organizations, users, memberships, roles, customers, groups, profiles, and assignment history.

## Authorization model

Permission guards answer:

```text
May this user perform this kind of action?
```

Management-context checks answer:

```text
May this user perform the action on this specific dealer or customer?
```

Both checks are required.

Platform-scoped users can operate across the platform according to their permissions.

Dealer-scoped users can operate only on customers managed by their dealer.

Customer-scoped users can read only customers linked through active membership or customer-scoped role assignment.

## Dealer versus dealer manager

A dealer is an `Organization` with type `DEALER` and a `DealerProfile`.

A dealer manager is a `User` connected to that organization through:

```text
OrganizationMembership
+
RoleAssignment(scopeType = DEALER)
```

Commission, settlement, device allocation, and customer ownership belong to the dealer organization rather than to a manager user.

## Customer onboarding

Individual and organization customers have separate profile tables.

Each creation writes an initial `CustomerDealerAssignment`:

- `PLATFORM` for direct customers;
- `DEALER` for dealer-managed customers.

A customer group is valid only when it belongs to the same managing dealer.

## Transfers

Customer transfer is platform-only and requires `customer.transfer`.

The operation:

1. ends the active historical assignment;
2. creates a new assignment record;
3. updates the current dealer pointer;
4. clears or validates the customer group;
5. writes an immutable audit record.

Historical invoices and commission snapshots remain unchanged.

## Administratively provisioned users

Dealer staff and customer members may reference an existing user by mobile number.

For a new user, a strong password is required. The provisioning action is audited. The password is hashed and never returned.

## API endpoints

```text
GET    /api/v1/dealers
POST   /api/v1/dealers
GET    /api/v1/dealers/:dealerId
PATCH  /api/v1/dealers/:dealerId

GET    /api/v1/dealers/:dealerId/staff
POST   /api/v1/dealers/:dealerId/staff
PATCH  /api/v1/dealers/:dealerId/staff/:userId

GET    /api/v1/dealers/:dealerId/customer-groups
POST   /api/v1/dealers/:dealerId/customer-groups
PATCH  /api/v1/dealers/:dealerId/customer-groups/:groupId

GET    /api/v1/customers
POST   /api/v1/customers/individual
POST   /api/v1/customers/organization
GET    /api/v1/customers/:customerId
PATCH  /api/v1/customers/:customerId/group
POST   /api/v1/customers/:customerId/transfer

GET    /api/v1/customers/:customerId/members
POST   /api/v1/customers/:customerId/members
```

## Next stage

The next stage implements vehicle registration, device inventory, allocation, installation, assignment, and replacement APIs using the existing asset-domain constraints.
'@

    git add --all

    git commit `
        -m "feat(management): establish dealer and customer APIs"

    if ($LASTEXITCODE -ne 0) {
        throw "Dealer and customer API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Dealer and Customer API Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current
    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate
    Write-Host ""
    Write-Host "Recent graph:" -ForegroundColor Yellow
    git log --oneline --decorate --graph -7
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    Write-Host "Next implementation stage:" -ForegroundColor Yellow
    Write-Host (
        "Vehicle and device inventory, allocation, installation, " +
        "assignment, replacement, and removal APIs"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "DEALER AND CUSTOMER API FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "Do not reset or delete any applied migration."
    ) -ForegroundColor Yellow
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
