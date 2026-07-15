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

function Test-GitBranchExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    git show-ref `
        --verify `
        --quiet `
        "refs/heads/$BranchName"

    return $LASTEXITCODE -eq 0
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

function Ensure-EnvEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $content = Get-LfContent $RelativePath
    $pattern = "(?m)^" + [regex]::Escape($Name) + "=.*$"
    $line = "$Name=$Value"

    if ([regex]::IsMatch($content, $pattern)) {
        return
    }

    $updated = $content.TrimEnd() + "`n" + $line + "`n"
    Set-LfContent $RelativePath $updated
    Write-Host "[UPDATED] $RelativePath with $Name" -ForegroundColor Green
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

function Get-PublicTableCount {
    $sql = @'
SELECT COUNT(*)
FROM information_schema.tables
WHERE table_schema = 'public';
'@

    $output = $sql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Could not query the public table count."
    }

    return [int](($output | Out-String).Trim())
}

function Assert-AllowedWorkingTree {
    $allowed = @(
        ".env.example",
        "docs/architecture/mobile-api.md",
        "scripts/solid-tracker-mobile-api.ps1",
        "scripts/solid-tracker-mobile-api-recovery.ps1",
        "services/backend-api/src/app.module.ts",
        "services/backend-api/src/config/environment.validation.ts",
        "services/backend-api/src/tracking/tracking-api.module.ts",
        "services/backend-api/src/mobile/",
        "services/backend-api/test/mobile-api.e2e-spec.ts"
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
        $isAllowed = $false

        foreach ($allowedPath in $allowed) {
            if (
                $path -eq $allowedPath -or
                $path.StartsWith($allowedPath)
            ) {
                $isAllowed = $true
                break
            }
        }

        if (-not $isAllowed) {
            $unexpected.Add($line)
        }
    }

    if ($unexpected.Count -gt 0) {
        Write-Host "Unexpected working-tree changes:" -ForegroundColor Yellow

        foreach ($line in $unexpected) {
            Write-Host $line -ForegroundColor Yellow
        }

        throw "Working tree contains changes outside the mobile API stage."
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Customer Mobile API Platform v8" -ForegroundColor Cyan
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

    Assert-AllowedWorkingTree

    Write-Step 1 10 "Integrating notification delivery and preparing the mobile API branch"

    $currentBranch = ((git branch --show-current) | Out-String).Trim()

    if ($currentBranch -eq "feat/mobile-api") {
        Write-Host "Resuming existing mobile API branch." -ForegroundColor DarkYellow
    }
    else {
        if ($currentBranch -ne "main") {
            Invoke-CheckedCommand "Checkout main" {
                git checkout main
            }
        }

        if (-not (Test-GitBranchExists "feat/notification-delivery")) {
            throw "Source branch feat/notification-delivery was not found."
        }

        $notificationCommit = (
            git rev-parse "feat/notification-delivery"
        ).Trim()

        git merge-base --is-ancestor $notificationCommit main
        $alreadyMerged = $LASTEXITCODE -eq 0

        if (-not $alreadyMerged) {
            Invoke-CheckedCommand "Merge notification delivery into main" {
                git merge `
                    --no-ff `
                    feat/notification-delivery `
                    -m "merge: integrate notification delivery platform"
            }
        }
        else {
            Write-Host "Notification delivery is already integrated into main." -ForegroundColor DarkGreen
        }

        if (Test-GitBranchExists "feat/mobile-api") {
            throw (
                "Branch feat/mobile-api already exists. " +
                "Checkout that branch and rerun the script."
            )
        }

        Invoke-CheckedCommand "Create mobile API branch" {
            git checkout -b feat/mobile-api
        }
    }

    Write-Step 2 10 "Validating infrastructure and immutable migration state"

    Invoke-CheckedCommand "Start PostgreSQL and Redis" {
        docker compose --env-file .env up -d postgres redis
    }

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $migrationCount = Get-AppliedMigrationCount
    $publicTableCount = Get-PublicTableCount

    if ($migrationCount -ne 6) {
        throw "Expected exactly 6 applied migrations."
    }

    if ($publicTableCount -ne 53) {
        throw "Expected exactly 53 public tables."
    }

    foreach ($requiredPath in @(
        "services/backend-api/src/tracking/tracking-api.module.ts",
        "services/backend-api/src/tracking/positions/tracking-positions.service.ts",
        "services/backend-api/src/notification-delivery/notification-delivery.module.ts",
        "services/backend-api/src/billing/billing-api.module.ts"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required platform module is missing: $requiredPath"
        }
    }

    Write-Host "PostgreSQL:         healthy" -ForegroundColor Green
    Write-Host "Redis:              healthy" -ForegroundColor Green
    Write-Host "Applied migrations: 6" -ForegroundColor Green
    Write-Host "Public tables:      53" -ForegroundColor Green
    Write-Host "New migration:      not required" -ForegroundColor Green

    Write-Step 3 10 "Configuring mobile caching and live tracking sessions"

    Ensure-EnvEntry ".env" "MOBILE_API_CACHE_TTL_SECONDS" "15"
    Ensure-EnvEntry ".env" "MOBILE_LIVE_SESSION_TTL_SECONDS" "300"
    Ensure-EnvEntry ".env" "MOBILE_LIVE_POSITION_CACHE_TTL_SECONDS" "5"
    Ensure-EnvEntry ".env" "MOBILE_HISTORY_MAX_HOURS" "168"

    Ensure-EnvEntry ".env.example" "MOBILE_API_CACHE_TTL_SECONDS" "15"
    Ensure-EnvEntry ".env.example" "MOBILE_LIVE_SESSION_TTL_SECONDS" "300"
    Ensure-EnvEntry ".env.example" "MOBILE_LIVE_POSITION_CACHE_TTL_SECONDS" "5"
    Ensure-EnvEntry ".env.example" "MOBILE_HISTORY_MAX_HOURS" "168"

    $validationPath =
        "services/backend-api/src/config/environment.validation.ts"
    $validationContent = Get-LfContent $validationPath

    if (-not $validationContent.Contains("MOBILE_API_CACHE_TTL_SECONDS")) {
        $validationBlock = @'
  MOBILE_API_CACHE_TTL_SECONDS: Joi.number()
    .integer()
    .min(1)
    .max(300)
    .default(15),
  MOBILE_LIVE_SESSION_TTL_SECONDS: Joi.number()
    .integer()
    .min(60)
    .max(900)
    .default(300),
  MOBILE_LIVE_POSITION_CACHE_TTL_SECONDS: Joi.number()
    .integer()
    .min(1)
    .max(30)
    .default(5),
  MOBILE_HISTORY_MAX_HOURS: Joi.number()
    .integer()
    .min(24)
    .max(720)
    .default(168),
'@

        $closingIndex = $validationContent.LastIndexOf("});")

        if ($closingIndex -lt 0) {
            throw "Could not locate the environment validation object."
        }

        $validationContent = (
            $validationContent.Substring(0, $closingIndex) +
            $validationBlock +
            "`n" +
            $validationContent.Substring($closingIndex)
        )

        Set-LfContent $validationPath $validationContent
        Write-Host "[UPDATED] $validationPath" -ForegroundColor Green
    }

    Write-Step 4 10 "Exporting reusable tracking services"

    $trackingModulePath =
        "services/backend-api/src/tracking/tracking-api.module.ts"
    $trackingModuleContent = Get-LfContent $trackingModulePath

    if (-not $trackingModuleContent.Contains("exports: [")) {
        $moduleClose = "`n})`nexport class TrackingApiModule {}"

        if (-not $trackingModuleContent.Contains($moduleClose)) {
            throw "Could not locate the TrackingApiModule closing block."
        }

        $trackingModuleContent = $trackingModuleContent.Replace(
            $moduleClose,
            @'

  exports: [
    TrackingAccessService,
    TrackingPositionsService,
  ],
})
export class TrackingApiModule {}
'@
        )

        Set-LfContent $trackingModulePath $trackingModuleContent
        Write-Host "[UPDATED] $trackingModulePath" -ForegroundColor Green
    }
    elseif (
        -not $trackingModuleContent.Contains(
            "TrackingPositionsService,"
        )
    ) {
        throw "TrackingApiModule exports exist but do not expose tracking positions."
    }

    Write-Step 5 10 "Writing customer-facing mobile API services and contracts"

    Write-Utf8File `
        "services/backend-api/src/mobile/common/mobile-query.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
} from 'class-validator';
import { TrackingEventSeverity } from '../../generated/prisma/client';

export class MobileCursorQueryDto {
  @ApiPropertyOptional({
    description: 'Opaque continuation cursor returned by the previous page',
  })
  @IsOptional()
  @IsUUID()
  cursor?: string;

  @ApiPropertyOptional({
    minimum: 1,
    maximum: 100,
    default: 20,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 20;
}

export class MobileEventQueryDto extends MobileCursorQueryDto {
  @ApiPropertyOptional({ enum: TrackingEventSeverity })
  @IsOptional()
  @IsEnum(TrackingEventSeverity)
  severity?: TrackingEventSeverity;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  eventType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  to?: string;
}

export class MobileHistoryQueryDto {
  @ApiPropertyOptional({
    description: 'ISO-8601 range start; defaults to 24 hours before to',
  })
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional({
    description: 'ISO-8601 range end; defaults to the current time',
  })
  @IsOptional()
  @IsDateString()
  to?: string;
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/common/mobile-json.util.ts" `
        @'
export function mobileJsonSafe<T>(value: T): unknown {
  return JSON.parse(
    JSON.stringify(value, (_key, currentValue) =>
      typeof currentValue === 'bigint'
        ? currentValue.toString()
        : currentValue,
    ),
  ) as unknown;
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/common/mobile-access.service.ts" `
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
export class MobileAccessService {
  constructor(private readonly prisma: PrismaService) {}

  customerIds(auth: AuthContext): string[] {
    const customerIds = Array.from(new Set(auth.customerIds));

    if (customerIds.length === 0) {
      throw new ForbiddenException(
        'An active customer membership is required for the mobile API.',
      );
    }

    return customerIds;
  }

  vehicleWhere(
    auth: AuthContext,
  ): Prisma.VehicleWhereInput {
    return {
      customerId: {
        in: this.customerIds(auth),
      },
      archivedAt: null,
    };
  }

  async assertVehicle(
    auth: AuthContext,
    vehicleId: string,
  ): Promise<{
    id: string;
    customerId: string;
    status: string;
  }> {
    const vehicle = await this.prisma.vehicle.findFirst({
      where: {
        AND: [
          {
            id: vehicleId,
          },
          this.vehicleWhere(auth),
        ],
      },
      select: {
        id: true,
        customerId: true,
        status: true,
      },
    });

    if (!vehicle) {
      throw new NotFoundException(
        'Vehicle was not found within the authenticated customer scope.',
      );
    }

    return vehicle;
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/common/mobile-cache.service.ts" `
        @'
import {
  Injectable,
  OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

@Injectable()
export class MobileCacheService
  implements OnModuleDestroy
{
  private readonly client: Redis;
  readonly defaultTtlSeconds: number;

  constructor(config: ConfigService) {
    this.client = new Redis(
      config.getOrThrow<string>('REDIS_URL'),
      {
        lazyConnect: true,
        maxRetriesPerRequest: 2,
        enableReadyCheck: true,
      },
    );
    this.defaultTtlSeconds = Number(
      config.get('MOBILE_API_CACHE_TTL_SECONDS', 15),
    );
  }

  async getJson<T>(key: string): Promise<T | null> {
    await this.ensureConnected();
    const value = await this.client.get(key);

    if (!value) {
      return null;
    }

    return JSON.parse(value) as T;
  }

  async setJson(
    key: string,
    value: unknown,
    ttlSeconds = this.defaultTtlSeconds,
  ): Promise<void> {
    await this.ensureConnected();
    const serialized = JSON.stringify(
      value,
      (_key, currentValue) =>
        typeof currentValue === 'bigint'
          ? currentValue.toString()
          : currentValue,
    );

    if (serialized === undefined) {
      throw new Error('Mobile cache value is not JSON serializable.');
    }

    await this.client.set(
      key,
      serialized,
      'EX',
      ttlSeconds,
    );
  }

  async delete(key: string): Promise<void> {
    await this.ensureConnected();
    await this.client.del(key);
  }

  async getOrSet<T>(
    key: string,
    ttlSeconds: number,
    factory: () => Promise<T>,
  ): Promise<T> {
    const cached = await this.getJson<T>(key);

    if (cached !== null) {
      return cached;
    }

    const value = await factory();
    await this.setJson(key, value, ttlSeconds);
    return value;
  }

  async onModuleDestroy(): Promise<void> {
    if (this.client.status !== 'end') {
      await this.client.quit();
    }
  }

  private async ensureConnected(): Promise<void> {
    if (this.client.status === 'wait') {
      await this.client.connect();
    }
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/profile/mobile-profile.service.ts" `
        @'
import {
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { MobileAccessService } from '../common/mobile-access.service';
import { mobileJsonSafe } from '../common/mobile-json.util';

@Injectable()
export class MobileProfileService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
  ) {}

  async profile(auth: AuthContext) {
    const customerIds = this.access.customerIds(auth);
    const user = await this.prisma.user.findUnique({
      where: {
        id: auth.userId,
      },
      select: {
        id: true,
        userCode: true,
        fullName: true,
        mobileNumber: true,
        email: true,
        mobileVerifiedAt: true,
        emailVerifiedAt: true,
        lastLoginAt: true,
        customerMemberships: {
          where: {
            customerId: {
              in: customerIds,
            },
            status: 'ACTIVE',
            endedAt: null,
          },
          orderBy: {
            createdAt: 'asc',
          },
          select: {
            id: true,
            isPrimary: true,
            joinedAt: true,
            customer: {
              select: {
                id: true,
                customerCode: true,
                customerType: true,
                status: true,
                primaryMobile: true,
                primaryEmail: true,
                managingDealer: {
                  select: {
                    id: true,
                    code: true,
                    name: true,
                  },
                },
                individualProfile: {
                  select: {
                    fullName: true,
                    emergencyContactName: true,
                    emergencyContactMobile: true,
                  },
                },
                organizationProfile: {
                  select: {
                    legalName: true,
                    displayName: true,
                    contactPersonName: true,
                    contactMobile: true,
                    contactEmail: true,
                  },
                },
              },
            },
          },
        },
      },
    });

    if (!user) {
      throw new NotFoundException('Authenticated user was not found.');
    }

    return mobileJsonSafe({
      data: user,
      meta: {
        generatedAt: new Date().toISOString(),
      },
    });
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/dashboard/mobile-dashboard.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { MobileAccessService } from '../common/mobile-access.service';
import { MobileCacheService } from '../common/mobile-cache.service';
import { mobileJsonSafe } from '../common/mobile-json.util';

@Injectable()
export class MobileDashboardService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
    private readonly cache: MobileCacheService,
  ) {}

  async dashboard(auth: AuthContext) {
    const customerIds = this.access.customerIds(auth);
    const cacheKey = [
      'mobile',
      'dashboard',
      auth.userId,
      ...customerIds.slice().sort(),
    ].join(':');

    return this.cache.getOrSet(
      cacheKey,
      this.cache.defaultTtlSeconds,
      async () => {
        const [
          customers,
          vehicles,
          activeSubscriptions,
          outstandingInvoices,
          recentEvents,
          recentNotifications,
        ] = await Promise.all([
          this.prisma.customer.findMany({
            where: {
              id: {
                in: customerIds,
              },
              archivedAt: null,
            },
            orderBy: {
              createdAt: 'asc',
            },
            select: {
              id: true,
              customerCode: true,
              customerType: true,
              status: true,
              individualProfile: {
                select: {
                  fullName: true,
                },
              },
              organizationProfile: {
                select: {
                  displayName: true,
                },
              },
            },
          }),
          this.prisma.vehicle.findMany({
            where: this.access.vehicleWhere(auth),
            orderBy: {
              createdAt: 'asc',
            },
            select: {
              id: true,
              vehicleCode: true,
              registrationNumber: true,
              vehicleType: true,
              manufacturer: true,
              modelName: true,
              color: true,
              status: true,
              deviceAssignments: {
                where: {
                  status: 'ACTIVE',
                  assignmentType: 'PRIMARY',
                },
                take: 1,
                orderBy: {
                  startedAt: 'desc',
                },
                select: {
                  startedAt: true,
                  device: {
                    select: {
                      id: true,
                      deviceCode: true,
                      lifecycleStatus: true,
                      traccarMappings: {
                        where: {
                          isActive: true,
                          isPrimary: true,
                        },
                        take: 1,
                        select: {
                          syncStatus: true,
                          lastSyncedAt: true,
                          lastSyncError: true,
                        },
                      },
                    },
                  },
                },
              },
              subscriptions: {
                where: {
                  status: {
                    in: [
                      'TRIALING',
                      'ACTIVE',
                      'PAST_DUE',
                      'SUSPENDED',
                    ],
                  },
                },
                take: 1,
                orderBy: {
                  createdAt: 'desc',
                },
                select: {
                  id: true,
                  subscriptionCode: true,
                  status: true,
                  currentPeriodEnd: true,
                  nextBillingAt: true,
                  servicePlan: {
                    select: {
                      name: true,
                      basePrice: true,
                      currency: true,
                    },
                  },
                },
              },
            },
          }),
          this.prisma.subscription.count({
            where: {
              customerId: {
                in: customerIds,
              },
              status: {
                in: ['TRIALING', 'ACTIVE', 'PAST_DUE'],
              },
            },
          }),
          this.prisma.invoice.aggregate({
            where: {
              customerId: {
                in: customerIds,
              },
              status: {
                in: [
                  'ISSUED',
                  'PARTIALLY_PAID',
                  'OVERDUE',
                ],
              },
            },
            _count: {
              _all: true,
            },
            _sum: {
              outstandingAmount: true,
            },
          }),
          this.prisma.trackingEvent.findMany({
            where: {
              customerId: {
                in: customerIds,
              },
            },
            orderBy: {
              occurredAt: 'desc',
            },
            take: 5,
            select: {
              id: true,
              eventCode: true,
              vehicleId: true,
              eventType: true,
              severity: true,
              latitude: true,
              longitude: true,
              occurredAt: true,
              acknowledgedAt: true,
            },
          }),
          this.prisma.notification.findMany({
            where: {
              customerId: {
                in: customerIds,
              },
              OR: [
                {
                  userId: null,
                },
                {
                  userId: auth.userId,
                },
              ],
            },
            orderBy: {
              createdAt: 'desc',
            },
            take: 5,
            select: {
              id: true,
              notificationCode: true,
              channel: true,
              subject: true,
              renderedContent: true,
              status: true,
              createdAt: true,
              deliveredAt: true,
            },
          }),
        ]);

        const activeTrackerCount = vehicles.filter(
          (vehicle) =>
            vehicle.deviceAssignments.length > 0,
        ).length;
        const onlineTrackerCount = vehicles.filter(
          (vehicle) =>
            vehicle.deviceAssignments[0]?.device
              .traccarMappings[0]?.syncStatus === 'SYNCED',
        ).length;
        const vehicleContracts = vehicles.map(
          ({ subscriptions, ...vehicle }) => ({
            ...vehicle,
            subscription:
              subscriptions[0] ?? null,
          }),
        );

        return mobileJsonSafe({
          data: {
            customers,
            summary: {
              customerCount: customers.length,
              vehicleCount: vehicles.length,
              activeTrackerCount,
              onlineTrackerCount,
              activeSubscriptionCount:
                activeSubscriptions,
              outstandingInvoiceCount:
                outstandingInvoices._count._all,
              outstandingAmount:
                outstandingInvoices._sum
                  .outstandingAmount ?? 0,
            },
            vehicles: vehicleContracts,
            recentEvents,
            recentNotifications,
          },
          meta: {
            generatedAt: new Date().toISOString(),
            cacheTtlSeconds:
              this.cache.defaultTtlSeconds,
          },
        });
      },
    );
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/vehicles/mobile-trip-builder.service.ts" `
        @'
import { Injectable } from '@nestjs/common';

interface NormalizedPosition {
  latitude: number;
  longitude: number;
  occurredAt: Date;
  speedKph: number;
  ignition: boolean | null;
}

export interface MobileTripSummary {
  startedAt: string;
  endedAt: string;
  durationSeconds: number;
  distanceKm: number;
  maxSpeedKph: number;
  start: {
    latitude: number;
    longitude: number;
  };
  end: {
    latitude: number;
    longitude: number;
  };
  pointCount: number;
}

@Injectable()
export class MobileTripBuilderService {
  build(input: unknown[]): MobileTripSummary[] {
    const positions = input
      .map((value) => this.normalize(value))
      .filter(
        (
          value,
        ): value is NormalizedPosition =>
          value !== null,
      )
      .sort(
        (left, right) =>
          left.occurredAt.getTime() -
          right.occurredAt.getTime(),
      );
    const trips: MobileTripSummary[] = [];
    let active: NormalizedPosition[] = [];

    for (const position of positions) {
      const moving =
        position.speedKph >= 2 ||
        position.ignition === true;

      if (moving) {
        active.push(position);
        continue;
      }

      if (active.length > 0) {
        this.finish(active, trips);
        active = [];
      }
    }

    if (active.length > 0) {
      this.finish(active, trips);
    }

    return trips.reverse();
  }

  private normalize(
    value: unknown,
  ): NormalizedPosition | null {
    if (
      value === null ||
      typeof value !== 'object' ||
      Array.isArray(value)
    ) {
      return null;
    }

    const record = value as Record<string, unknown>;
    const latitude = Number(record.latitude);
    const longitude = Number(record.longitude);
    const dateValue =
      record.fixTime ??
      record.deviceTime ??
      record.serverTime;
    const occurredAt = new Date(String(dateValue ?? ''));
    const speedKnots = Number(record.speed ?? 0);
    const attributes =
      record.attributes !== null &&
      typeof record.attributes === 'object' &&
      !Array.isArray(record.attributes)
        ? (record.attributes as Record<string, unknown>)
        : {};
    const ignitionValue = attributes.ignition;

    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      Number.isNaN(occurredAt.getTime())
    ) {
      return null;
    }

    return {
      latitude,
      longitude,
      occurredAt,
      speedKph: Number.isFinite(speedKnots)
        ? speedKnots * 1.852
        : 0,
      ignition:
        typeof ignitionValue === 'boolean'
          ? ignitionValue
          : null,
    };
  }

  private finish(
    points: NormalizedPosition[],
    trips: MobileTripSummary[],
  ): void {
    if (points.length === 0) {
      return;
    }

    let distanceKm = 0;
    let maxSpeedKph = 0;

    for (let index = 0; index < points.length; index += 1) {
      maxSpeedKph = Math.max(
        maxSpeedKph,
        points[index].speedKph,
      );

      if (index > 0) {
        distanceKm += this.distance(
          points[index - 1],
          points[index],
        );
      }
    }

    const first = points[0];
    const last = points[points.length - 1];

    trips.push({
      startedAt: first.occurredAt.toISOString(),
      endedAt: last.occurredAt.toISOString(),
      durationSeconds: Math.max(
        0,
        Math.round(
          (last.occurredAt.getTime() -
            first.occurredAt.getTime()) /
            1000,
        ),
      ),
      distanceKm: Number(distanceKm.toFixed(3)),
      maxSpeedKph: Number(maxSpeedKph.toFixed(1)),
      start: {
        latitude: first.latitude,
        longitude: first.longitude,
      },
      end: {
        latitude: last.latitude,
        longitude: last.longitude,
      },
      pointCount: points.length,
    });
  }

  private distance(
    left: NormalizedPosition,
    right: NormalizedPosition,
  ): number {
    const radiusKm = 6371;
    const latitudeDelta = this.radians(
      right.latitude - left.latitude,
    );
    const longitudeDelta = this.radians(
      right.longitude - left.longitude,
    );
    const leftLatitude = this.radians(left.latitude);
    const rightLatitude = this.radians(
      right.latitude,
    );
    const calculation =
      Math.sin(latitudeDelta / 2) ** 2 +
      Math.cos(leftLatitude) *
        Math.cos(rightLatitude) *
        Math.sin(longitudeDelta / 2) ** 2;

    return (
      radiusKm *
      2 *
      Math.atan2(
        Math.sqrt(calculation),
        Math.sqrt(1 - calculation),
      )
    );
  }

  private radians(value: number): number {
    return (value * Math.PI) / 180;
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/vehicles/mobile-trip-builder.service.spec.ts" `
        @'
import { MobileTripBuilderService } from './mobile-trip-builder.service';

describe('MobileTripBuilderService', () => {
  const service = new MobileTripBuilderService();

  it('builds a trip from moving Traccar positions', () => {
    const trips = service.build([
      {
        fixTime: '2026-07-14T10:00:00.000Z',
        latitude: 23.81,
        longitude: 90.41,
        speed: 10,
        attributes: { ignition: true },
      },
      {
        fixTime: '2026-07-14T10:05:00.000Z',
        latitude: 23.82,
        longitude: 90.42,
        speed: 15,
        attributes: { ignition: true },
      },
      {
        fixTime: '2026-07-14T10:06:00.000Z',
        latitude: 23.82,
        longitude: 90.42,
        speed: 0,
        attributes: { ignition: false },
      },
    ]);

    expect(trips).toHaveLength(1);
    expect(trips[0].pointCount).toBe(2);
    expect(trips[0].durationSeconds).toBe(300);
    expect(trips[0].distanceKm).toBeGreaterThan(0);
  });
});
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/vehicles/mobile-vehicles.service.ts" `
        @'
import {
  BadRequestException,
  Injectable,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingPositionsService } from '../../tracking/positions/tracking-positions.service';
import { MobileAccessService } from '../common/mobile-access.service';
import { mobileJsonSafe } from '../common/mobile-json.util';
import type {
  MobileCursorQueryDto,
  MobileEventQueryDto,
  MobileHistoryQueryDto,
} from '../common/mobile-query.dto';
import { MobileTripBuilderService } from './mobile-trip-builder.service';

@Injectable()
export class MobileVehiclesService {
  private readonly historyMaximumHours: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
    private readonly trackingPositions: TrackingPositionsService,
    private readonly trips: MobileTripBuilderService,
    config: ConfigService,
  ) {
    this.historyMaximumHours = Number(
      config.get('MOBILE_HISTORY_MAX_HOURS', 168),
    );
  }

  async list(
    auth: AuthContext,
    query: MobileCursorQueryDto,
  ) {
    const items = await this.prisma.vehicle.findMany({
      where: this.access.vehicleWhere(auth),
      orderBy: [
        {
          createdAt: 'asc',
        },
        {
          id: 'asc',
        },
      ],
      cursor: query.cursor
        ? {
            id: query.cursor,
          }
        : undefined,
      skip: query.cursor ? 1 : 0,
      take: query.limit + 1,
      select: {
        id: true,
        vehicleCode: true,
        registrationNumber: true,
        vehicleType: true,
        manufacturer: true,
        modelName: true,
        manufacturingYear: true,
        color: true,
        status: true,
        customer: {
          select: {
            id: true,
            customerCode: true,
            individualProfile: {
              select: {
                fullName: true,
              },
            },
            organizationProfile: {
              select: {
                displayName: true,
              },
            },
          },
        },
        deviceAssignments: {
          where: {
            status: 'ACTIVE',
            assignmentType: 'PRIMARY',
          },
          orderBy: {
            startedAt: 'desc',
          },
          take: 1,
          select: {
            id: true,
            startedAt: true,
            device: {
              select: {
                id: true,
                deviceCode: true,
                imei: true,
                lifecycleStatus: true,
                firmwareVersion: true,
                deviceModel: {
                  select: {
                    manufacturer: true,
                    modelName: true,
                    protocol: true,
                    networkType: true,
                  },
                },
                traccarMappings: {
                  where: {
                    isActive: true,
                    isPrimary: true,
                  },
                  take: 1,
                  select: {
                    syncStatus: true,
                    lastSyncedAt: true,
                    lastSyncError: true,
                  },
                },
              },
            },
          },
        },
        subscriptions: {
          where: {
            status: {
              in: [
                'TRIALING',
                'ACTIVE',
                'PAST_DUE',
                'SUSPENDED',
              ],
            },
          },
          orderBy: {
            createdAt: 'desc',
          },
          take: 1,
          select: {
            id: true,
            subscriptionCode: true,
            status: true,
            currentPeriodEnd: true,
            nextBillingAt: true,
            servicePlan: {
              select: {
                name: true,
                currency: true,
                basePrice: true,
              },
            },
          },
        },
      },
    });

    const hasMore = items.length > query.limit;

    if (hasMore) {
      items.pop();
    }

    const contracts = items.map(
      ({ subscriptions, ...vehicle }) => ({
        ...vehicle,
        subscription:
          subscriptions[0] ?? null,
      }),
    );

    return mobileJsonSafe({
      data: contracts,
      meta: {
        limit: query.limit,
        count: contracts.length,
        nextCursor:
          hasMore && items.length > 0
            ? items[items.length - 1].id
            : null,
      },
    });
  }

  async detail(
    auth: AuthContext,
    vehicleId: string,
  ) {
    await this.access.assertVehicle(auth, vehicleId);
    const vehicle =
      await this.prisma.vehicle.findUniqueOrThrow({
        where: {
          id: vehicleId,
        },
        include: {
          customer: {
            include: {
              individualProfile: true,
              organizationProfile: true,
            },
          },
          deviceAssignments: {
            where: {
              status: 'ACTIVE',
            },
            orderBy: {
              startedAt: 'desc',
            },
            include: {
              device: {
                include: {
                  deviceModel: true,
                  traccarMappings: {
                    where: {
                      isActive: true,
                    },
                    orderBy: {
                      createdAt: 'desc',
                    },
                  },
                },
              },
              installation: true,
            },
          },
          subscriptions: {
            orderBy: {
              createdAt: 'desc',
            },
            take: 3,
            include: {
              servicePlan: true,
            },
          },
          vehicleGeofenceAssignments: {
            where: {
              status: 'ACTIVE',
            },
            include: {
              geofence: true,
            },
          },
        },
      });

    const {
      subscriptions,
      ...vehicleContract
    } = vehicle;

    return mobileJsonSafe({
      data: {
        ...vehicleContract,
        subscriptions: subscriptions,
      },
      meta: {
        generatedAt: new Date().toISOString(),
      },
    });
  }

  async livePosition(
    auth: AuthContext,
    vehicleId: string,
  ) {
    const result =
      await this.trackingPositions.livePosition(
        auth,
        vehicleId,
      );

    return mobileJsonSafe({
      data: result,
      meta: {
        generatedAt: new Date().toISOString(),
      },
    });
  }

  async history(
    auth: AuthContext,
    vehicleId: string,
    query: MobileHistoryQueryDto,
  ) {
    this.assertHistoryRange(query);
    const result = await this.trackingPositions.history(
      auth,
      vehicleId,
      query,
    );

    return mobileJsonSafe({
      data: result,
      meta: {
        maximumHours: this.historyMaximumHours,
      },
    });
  }

  async tripFeed(
    auth: AuthContext,
    vehicleId: string,
    query: MobileHistoryQueryDto,
  ) {
    this.assertHistoryRange(query);
    const history =
      await this.trackingPositions.history(
        auth,
        vehicleId,
        query,
      );
    const trips = this.trips.build(history.positions);

    return mobileJsonSafe({
      data: trips,
      meta: {
        vehicleId,
        from: history.from,
        to: history.to,
        count: trips.length,
      },
    });
  }

  async eventFeed(
    auth: AuthContext,
    vehicleId: string,
    query: MobileEventQueryDto,
  ) {
    const vehicle =
      await this.access.assertVehicle(auth, vehicleId);
    const occurredAt = this.dateWhere(
      query.from,
      query.to,
    );
    const items =
      await this.prisma.trackingEvent.findMany({
        where: {
          vehicleId,
          customerId: vehicle.customerId,
          severity: query.severity,
          eventType: query.eventType,
          occurredAt,
        },
        orderBy: [
          {
            occurredAt: 'desc',
          },
          {
            id: 'desc',
          },
        ],
        cursor: query.cursor
          ? {
              id: query.cursor,
            }
          : undefined,
        skip: query.cursor ? 1 : 0,
        take: query.limit + 1,
        select: {
          id: true,
          eventCode: true,
          eventType: true,
          severity: true,
          latitude: true,
          longitude: true,
          occurredAt: true,
          receivedAt: true,
          attributes: true,
          processingStatus: true,
          acknowledgedAt: true,
        },
      });
    const hasMore = items.length > query.limit;

    if (hasMore) {
      items.pop();
    }

    return mobileJsonSafe({
      data: items,
      meta: {
        vehicleId,
        limit: query.limit,
        count: items.length,
        nextCursor:
          hasMore && items.length > 0
            ? items[items.length - 1].id
            : null,
      },
    });
  }

  private assertHistoryRange(
    query: MobileHistoryQueryDto,
  ): void {
    const to = query.to ? new Date(query.to) : new Date();
    const from = query.from
      ? new Date(query.from)
      : new Date(to.getTime() - 24 * 60 * 60 * 1000);

    if (from >= to) {
      throw new BadRequestException(
        'History from must be earlier than to.',
      );
    }

    const hours =
      (to.getTime() - from.getTime()) /
      (60 * 60 * 1000);

    if (hours > this.historyMaximumHours) {
      throw new BadRequestException(
        `Mobile history is limited to ${this.historyMaximumHours} hours per request.`,
      );
    }
  }

  private dateWhere(
    from?: string,
    to?: string,
  ):
    | {
        gte?: Date;
        lte?: Date;
      }
    | undefined {
    if (!from && !to) {
      return undefined;
    }

    return {
      gte: from ? new Date(from) : undefined,
      lte: to ? new Date(to) : undefined,
    };
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/billing/mobile-billing.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { MobileAccessService } from '../common/mobile-access.service';
import { mobileJsonSafe } from '../common/mobile-json.util';
import type { MobileCursorQueryDto } from '../common/mobile-query.dto';

@Injectable()
export class MobileBillingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
  ) {}

  async subscriptions(
    auth: AuthContext,
    query: MobileCursorQueryDto,
  ) {
    const customerIds = this.access.customerIds(auth);
    const items =
      await this.prisma.subscription.findMany({
        where: {
          customerId: {
            in: customerIds,
          },
        },
        orderBy: [
          {
            createdAt: 'desc',
          },
          {
            id: 'desc',
          },
        ],
        cursor: query.cursor
          ? {
              id: query.cursor,
            }
          : undefined,
        skip: query.cursor ? 1 : 0,
        take: query.limit + 1,
        include: {
          vehicle: {
            select: {
              id: true,
              vehicleCode: true,
              registrationNumber: true,
              vehicleType: true,
            },
          },
          servicePlan: true,
        },
      });
    const hasMore = items.length > query.limit;

    if (hasMore) {
      items.pop();
    }

    return mobileJsonSafe({
      data: items,
      meta: {
        limit: query.limit,
        count: items.length,
        nextCursor:
          hasMore && items.length > 0
            ? items[items.length - 1].id
            : null,
      },
    });
  }

  async invoices(
    auth: AuthContext,
    query: MobileCursorQueryDto,
  ) {
    const customerIds = this.access.customerIds(auth);
    const items = await this.prisma.invoice.findMany({
      where: {
        customerId: {
          in: customerIds,
        },
      },
      orderBy: [
        {
          issueDate: 'desc',
        },
        {
          id: 'desc',
        },
      ],
      cursor: query.cursor
        ? {
            id: query.cursor,
          }
        : undefined,
      skip: query.cursor ? 1 : 0,
      take: query.limit + 1,
      include: {
        subscription: {
          include: {
            vehicle: {
              select: {
                id: true,
                vehicleCode: true,
                registrationNumber: true,
              },
            },
            servicePlan: {
              select: {
                name: true,
              },
            },
          },
        },
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
      },
    });
    const hasMore = items.length > query.limit;

    if (hasMore) {
      items.pop();
    }

    return mobileJsonSafe({
      data: items,
      meta: {
        limit: query.limit,
        count: items.length,
        nextCursor:
          hasMore && items.length > 0
            ? items[items.length - 1].id
            : null,
      },
    });
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/notifications/mobile-notifications.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { MobileAccessService } from '../common/mobile-access.service';
import { mobileJsonSafe } from '../common/mobile-json.util';
import type { MobileCursorQueryDto } from '../common/mobile-query.dto';

@Injectable()
export class MobileNotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: MobileAccessService,
  ) {}

  async list(
    auth: AuthContext,
    query: MobileCursorQueryDto,
  ) {
    const customerIds = this.access.customerIds(auth);
    const items =
      await this.prisma.notification.findMany({
        where: {
          customerId: {
            in: customerIds,
          },
          OR: [
            {
              userId: null,
            },
            {
              userId: auth.userId,
            },
          ],
        },
        orderBy: [
          {
            createdAt: 'desc',
          },
          {
            id: 'desc',
          },
        ],
        cursor: query.cursor
          ? {
              id: query.cursor,
            }
          : undefined,
        skip: query.cursor ? 1 : 0,
        take: query.limit + 1,
        select: {
          id: true,
          notificationCode: true,
          channel: true,
          recipient: true,
          subject: true,
          renderedContent: true,
          status: true,
          provider: true,
          queuedAt: true,
          sentAt: true,
          deliveredAt: true,
          failedAt: true,
          failureReason: true,
          createdAt: true,
          trackingEvent: {
            select: {
              id: true,
              eventType: true,
              severity: true,
              vehicleId: true,
              latitude: true,
              longitude: true,
              occurredAt: true,
            },
          },
        },
      });
    const hasMore = items.length > query.limit;

    if (hasMore) {
      items.pop();
    }

    return mobileJsonSafe({
      data: items,
      meta: {
        limit: query.limit,
        count: items.length,
        nextCursor:
          hasMore && items.length > 0
            ? items[items.length - 1].id
            : null,
      },
    });
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/live/dto/create-live-session.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  IsUUID,
  Max,
  Min,
} from 'class-validator';

export class CreateLiveSessionDto {
  @ApiProperty()
  @IsUUID()
  vehicleId!: string;

  @ApiPropertyOptional({
    minimum: 60,
    maximum: 900,
    default: 300,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(60)
  @Max(900)
  ttlSeconds?: number;
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/live/mobile-live-session.service.ts" `
        @'
import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingPositionsService } from '../../tracking/positions/tracking-positions.service';
import { MobileAccessService } from '../common/mobile-access.service';
import { MobileCacheService } from '../common/mobile-cache.service';
import { mobileJsonSafe } from '../common/mobile-json.util';
import type { CreateLiveSessionDto } from './dto/create-live-session.dto';

export interface StoredLiveSession {
  token: string;
  userId: string;
  vehicleId: string;
  customerId: string;
  createdAt: string;
  expiresAt: string;
  pollAfterSeconds: number;
}

@Injectable()
export class MobileLiveSessionService {
  private readonly defaultTtlSeconds: number;
  private readonly positionCacheTtlSeconds: number;

  constructor(
    private readonly access: MobileAccessService,
    private readonly cache: MobileCacheService,
    private readonly trackingPositions: TrackingPositionsService,
    config: ConfigService,
  ) {
    this.defaultTtlSeconds = Number(
      config.get('MOBILE_LIVE_SESSION_TTL_SECONDS', 300),
    );
    this.positionCacheTtlSeconds = Number(
      config.get(
        'MOBILE_LIVE_POSITION_CACHE_TTL_SECONDS',
        5,
      ),
    );
  }

  async create(
    auth: AuthContext,
    dto: CreateLiveSessionDto,
  ) {
    const vehicle = await this.access.assertVehicle(
      auth,
      dto.vehicleId,
    );
    const ttlSeconds =
      dto.ttlSeconds ?? this.defaultTtlSeconds;
    const createdAt = new Date();
    const token = randomUUID();
    const session: StoredLiveSession = {
      token,
      userId: auth.userId,
      vehicleId: vehicle.id,
      customerId: vehicle.customerId,
      createdAt: createdAt.toISOString(),
      expiresAt: new Date(
        createdAt.getTime() + ttlSeconds * 1000,
      ).toISOString(),
      pollAfterSeconds: Math.max(
        2,
        this.positionCacheTtlSeconds,
      ),
    };

    await this.cache.setJson(
      this.sessionKey(token),
      session,
      ttlSeconds,
    );

    return {
      data: session,
      meta: {
        ttlSeconds,
      },
    };
  }

  async get(
    auth: AuthContext,
    token: string,
  ) {
    const session = await this.authorizedSession(
      auth,
      token,
    );

    return {
      data: session,
    };
  }

  async position(
    auth: AuthContext,
    token: string,
  ) {
    const session = await this.authorizedSession(
      auth,
      token,
    );
    await this.access.assertVehicle(
      auth,
      session.vehicleId,
    );
    const cacheKey =
      `mobile:live-position:${session.vehicleId}`;
    const cached =
      await this.cache.getJson<unknown>(cacheKey);

    if (cached !== null) {
      return {
        data: cached,
        meta: {
          sessionToken: token,
          cacheHit: true,
          pollAfterSeconds:
            session.pollAfterSeconds,
        },
      };
    }

    const latest =
      await this.trackingPositions.livePosition(
        auth,
        session.vehicleId,
      );
    const safeLatest = mobileJsonSafe(latest);

    await this.cache.setJson(
      cacheKey,
      safeLatest,
      this.positionCacheTtlSeconds,
    );

    return {
      data: safeLatest,
      meta: {
        sessionToken: token,
        cacheHit: false,
        pollAfterSeconds:
          session.pollAfterSeconds,
      },
    };
  }

  async close(
    auth: AuthContext,
    token: string,
  ) {
    await this.authorizedSession(auth, token);
    await this.cache.delete(this.sessionKey(token));

    return {
      data: {
        token,
        closed: true,
      },
    };
  }

  private async authorizedSession(
    auth: AuthContext,
    token: string,
  ): Promise<StoredLiveSession> {
    const session =
      await this.cache.getJson<StoredLiveSession>(
        this.sessionKey(token),
      );

    if (!session) {
      throw new NotFoundException(
        'Live tracking session was not found or has expired.',
      );
    }

    if (session.userId !== auth.userId) {
      throw new ForbiddenException(
        'This live tracking session belongs to another user.',
      );
    }

    return session;
  }

  private sessionKey(token: string): string {
    return `mobile:live-session:${token}`;
  }
}
'@

    Write-Step 6 10 "Writing mobile controllers and module registration"

    Write-Utf8File `
        "services/backend-api/src/mobile/profile/mobile-profile.controller.ts" `
        @'
import {
  Controller,
  Get,
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
import { MobileDashboardService } from '../dashboard/mobile-dashboard.service';
import { MobileProfileService } from './mobile-profile.service';

@ApiTags('Mobile')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile')
export class MobileProfileController {
  constructor(
    private readonly profileService: MobileProfileService,
    private readonly dashboardService: MobileDashboardService,
  ) {}

  @Get('profile')
  @RequirePermissions('customer.view')
  @ApiOperation({
    summary: 'Read the authenticated mobile customer profile',
  })
  profile(@CurrentAuth() auth: AuthContext) {
    return this.profileService.profile(auth);
  }

  @Get('dashboard')
  @RequirePermissions('vehicle.view')
  @ApiOperation({
    summary: 'Read the customer mobile dashboard',
  })
  dashboard(@CurrentAuth() auth: AuthContext) {
    return this.dashboardService.dashboard(auth);
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/vehicles/mobile-vehicles.controller.ts" `
        @'
import {
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
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
import {
  MobileCursorQueryDto,
  MobileEventQueryDto,
  MobileHistoryQueryDto,
} from '../common/mobile-query.dto';
import { MobileVehiclesService } from './mobile-vehicles.service';

@ApiTags('Mobile - Vehicles')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile/vehicles')
export class MobileVehiclesController {
  constructor(
    private readonly vehicles: MobileVehiclesService,
  ) {}

  @Get()
  @RequirePermissions('vehicle.view')
  @ApiOperation({
    summary: 'List vehicles available to the customer app',
  })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: MobileCursorQueryDto,
  ) {
    return this.vehicles.list(auth, query);
  }

  @Get(':vehicleId')
  @RequirePermissions('vehicle.view')
  @ApiOperation({
    summary: 'Read a mobile-ready vehicle detail contract',
  })
  detail(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
  ) {
    return this.vehicles.detail(auth, vehicleId);
  }

  @Get(':vehicleId/live-position')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Read the current vehicle position',
  })
  livePosition(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
  ) {
    return this.vehicles.livePosition(
      auth,
      vehicleId,
    );
  }

  @Get(':vehicleId/position-history')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({
    summary: 'Read bounded position history for the mobile app',
  })
  history(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
    @Query() query: MobileHistoryQueryDto,
  ) {
    return this.vehicles.history(
      auth,
      vehicleId,
      query,
    );
  }

  @Get(':vehicleId/trips')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({
    summary: 'Read a derived trip feed',
  })
  trips(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
    @Query() query: MobileHistoryQueryDto,
  ) {
    return this.vehicles.tripFeed(
      auth,
      vehicleId,
      query,
    );
  }

  @Get(':vehicleId/events')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({
    summary: 'Read the paginated vehicle event feed',
  })
  events(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe())
    vehicleId: string,
    @Query() query: MobileEventQueryDto,
  ) {
    return this.vehicles.eventFeed(
      auth,
      vehicleId,
      query,
    );
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/billing/mobile-billing.controller.ts" `
        @'
import {
  Controller,
  Get,
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
import { MobileCursorQueryDto } from '../common/mobile-query.dto';
import { MobileBillingService } from './mobile-billing.service';

@ApiTags('Mobile - Billing')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile/billing')
export class MobileBillingController {
  constructor(
    private readonly billing: MobileBillingService,
  ) {}

  @Get('subscriptions')
  @RequirePermissions('subscription.view')
  @ApiOperation({
    summary: 'List customer subscriptions for the mobile app',
  })
  subscriptions(
    @CurrentAuth() auth: AuthContext,
    @Query() query: MobileCursorQueryDto,
  ) {
    return this.billing.subscriptions(auth, query);
  }

  @Get('invoices')
  @RequirePermissions('invoice.view')
  @ApiOperation({
    summary: 'List customer invoices for the mobile app',
  })
  invoices(
    @CurrentAuth() auth: AuthContext,
    @Query() query: MobileCursorQueryDto,
  ) {
    return this.billing.invoices(auth, query);
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/notifications/mobile-notifications.controller.ts" `
        @'
import {
  Controller,
  Get,
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
import { MobileCursorQueryDto } from '../common/mobile-query.dto';
import { MobileNotificationsService } from './mobile-notifications.service';

@ApiTags('Mobile - Notifications')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile/notifications')
export class MobileNotificationsController {
  constructor(
    private readonly notifications: MobileNotificationsService,
  ) {}

  @Get()
  @RequirePermissions('customer.view')
  @ApiOperation({
    summary: 'List customer and user notifications',
  })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: MobileCursorQueryDto,
  ) {
    return this.notifications.list(auth, query);
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/live/mobile-live-session.controller.ts" `
        @'
import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
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
import { CreateLiveSessionDto } from './dto/create-live-session.dto';
import { MobileLiveSessionService } from './mobile-live-session.service';

@ApiTags('Mobile - Live tracking')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('mobile/live-sessions')
export class MobileLiveSessionController {
  constructor(
    private readonly sessions: MobileLiveSessionService,
  ) {}

  @Post()
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Create a bounded live tracking session',
  })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateLiveSessionDto,
  ) {
    return this.sessions.create(auth, dto);
  }

  @Get(':sessionToken')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Read live tracking session metadata',
  })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('sessionToken', new ParseUUIDPipe())
    sessionToken: string,
  ) {
    return this.sessions.get(auth, sessionToken);
  }

  @Get(':sessionToken/position')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Read the current position for a live session',
  })
  position(
    @CurrentAuth() auth: AuthContext,
    @Param('sessionToken', new ParseUUIDPipe())
    sessionToken: string,
  ) {
    return this.sessions.position(
      auth,
      sessionToken,
    );
  }

  @Delete(':sessionToken')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({
    summary: 'Close a live tracking session',
  })
  close(
    @CurrentAuth() auth: AuthContext,
    @Param('sessionToken', new ParseUUIDPipe())
    sessionToken: string,
  ) {
    return this.sessions.close(auth, sessionToken);
  }
}
'@

    Write-Utf8File `
        "services/backend-api/src/mobile/mobile-api.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { TrackingApiModule } from '../tracking/tracking-api.module';
import { MobileBillingController } from './billing/mobile-billing.controller';
import { MobileBillingService } from './billing/mobile-billing.service';
import { MobileAccessService } from './common/mobile-access.service';
import { MobileCacheService } from './common/mobile-cache.service';
import { MobileDashboardService } from './dashboard/mobile-dashboard.service';
import { MobileLiveSessionController } from './live/mobile-live-session.controller';
import { MobileLiveSessionService } from './live/mobile-live-session.service';
import { MobileNotificationsController } from './notifications/mobile-notifications.controller';
import { MobileNotificationsService } from './notifications/mobile-notifications.service';
import { MobileProfileController } from './profile/mobile-profile.controller';
import { MobileProfileService } from './profile/mobile-profile.service';
import { MobileTripBuilderService } from './vehicles/mobile-trip-builder.service';
import { MobileVehiclesController } from './vehicles/mobile-vehicles.controller';
import { MobileVehiclesService } from './vehicles/mobile-vehicles.service';

@Module({
  imports: [
    AccessControlModule,
    TrackingApiModule,
  ],
  controllers: [
    MobileProfileController,
    MobileVehiclesController,
    MobileBillingController,
    MobileNotificationsController,
    MobileLiveSessionController,
  ],
  providers: [
    MobileAccessService,
    MobileCacheService,
    MobileProfileService,
    MobileDashboardService,
    MobileTripBuilderService,
    MobileVehiclesService,
    MobileBillingService,
    MobileNotificationsService,
    MobileLiveSessionService,
  ],
})
export class MobileApiModule {}
'@

    $appModulePath = "services/backend-api/src/app.module.ts"
    $appModuleContent = Get-LfContent $appModulePath
    $mobileModuleImport =
        "import { MobileApiModule } from './mobile/mobile-api.module';"

    if (-not $appModuleContent.Contains($mobileModuleImport)) {
        $moduleImportMarker =
            "import { Module } from '@nestjs/common';"

        if (-not $appModuleContent.Contains($moduleImportMarker)) {
            throw "Could not locate the NestJS Module import."
        }

        $appModuleContent = $appModuleContent.Replace(
            $moduleImportMarker,
            $moduleImportMarker + "`n" + $mobileModuleImport
        )
    }

    if (-not $appModuleContent.Contains("MobileApiModule,")) {
        $importsMatch = [regex]::Match(
            $appModuleContent,
            "(?ms)(imports:\s*\[\s*)"
        )

        if (-not $importsMatch.Success) {
            throw "Could not locate AppModule imports."
        }

        $insertAt =
            $importsMatch.Index +
            $importsMatch.Length

        $appModuleContent = (
            $appModuleContent.Substring(0, $insertAt) +
            "MobileApiModule,`n    " +
            $appModuleContent.Substring($insertAt)
        )
    }

    Set-LfContent $appModulePath $appModuleContent
    Write-Host "[UPDATED] $appModulePath" -ForegroundColor Green

    Write-Step 7 10 "Writing mobile-focused end-to-end coverage"

    Write-Utf8File `
        "services/backend-api/test/mobile-api.e2e-spec.ts" `
        @'
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import {
  createServer,
  type Server,
} from 'node:http';
import type { AddressInfo } from 'node:net';
import {
  randomInt,
  randomUUID,
} from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';
import { TokenService } from '../src/identity/common/token.service';
import { TrackingCredentialCryptoService } from '../src/tracking/common/tracking-credential-crypto.service';

describe('Customer mobile API (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let fakeTraccar: Server;
  let fakeTraccarBaseUrl: string;
  let accessToken: string;
  let userId: string;
  let customerId: string;
  let customerMembershipId: string;
  let roleAssignmentId: string;
  let vehicleId: string;
  let deviceId: string;
  let deviceModelId: string;
  let assignmentId: string;
  let traccarServerId: string;
  let mappingId: string;
  let servicePlanId: string;
  let subscriptionId: string;
  let eventId: string;

  const numericSuffix = randomInt(
    10_000_000,
    100_000_000,
  ).toString();
  const codeSuffix = randomUUID()
    .replace(/-/g, '')
    .slice(0, 10)
    .toUpperCase();
  const mobileNumber = `+88016${numericSuffix}`;
  const password = 'SolidTrackerMobile123';

  beforeAll(async () => {
    fakeTraccar = createServer((incoming, outgoing) => {
      const url = new URL(
        incoming.url ?? '/',
        'http://localhost',
      );

      if (
        incoming.method === 'GET' &&
        url.pathname === '/api/positions'
      ) {
        outgoing.setHeader(
          'Content-Type',
          'application/json',
        );
        outgoing.end(
          JSON.stringify([
            {
              id: 7001,
              deviceId: 101,
              protocol: 'osmand',
              serverTime:
                '2026-07-14T10:00:00.000Z',
              deviceTime:
                '2026-07-14T10:00:00.000Z',
              fixTime:
                '2026-07-14T10:00:00.000Z',
              valid: true,
              latitude: 23.8103,
              longitude: 90.4125,
              altitude: 8,
              speed: 12,
              course: 180,
              accuracy: 5,
              attributes: {
                ignition: true,
              },
            },
            {
              id: 7002,
              deviceId: 101,
              protocol: 'osmand',
              serverTime:
                '2026-07-14T10:05:00.000Z',
              deviceTime:
                '2026-07-14T10:05:00.000Z',
              fixTime:
                '2026-07-14T10:05:00.000Z',
              valid: true,
              latitude: 23.8203,
              longitude: 90.4225,
              altitude: 8,
              speed: 14,
              course: 180,
              accuracy: 5,
              attributes: {
                ignition: true,
              },
            },
            {
              id: 7003,
              deviceId: 101,
              protocol: 'osmand',
              serverTime:
                '2026-07-14T10:06:00.000Z',
              deviceTime:
                '2026-07-14T10:06:00.000Z',
              fixTime:
                '2026-07-14T10:06:00.000Z',
              valid: true,
              latitude: 23.8203,
              longitude: 90.4225,
              altitude: 8,
              speed: 0,
              course: 180,
              accuracy: 5,
              attributes: {
                ignition: false,
              },
            },
          ]),
        );
        return;
      }

      outgoing.statusCode = 404;
      outgoing.end();
    });

    await new Promise<void>((resolve) => {
      fakeTraccar.listen(0, '127.0.0.1', resolve);
    });

    const address =
      fakeTraccar.address() as AddressInfo;
    fakeTraccarBaseUrl =
      `http://127.0.0.1:${address.port}`;

    const moduleFixture: TestingModule =
      await Test.createTestingModule({
        imports: [AppModule],
      }).compile();

    app = moduleFixture.createNestApplication();
    configureApplication(app);
    await app.init();

    prisma = app.get(PrismaService);
    const passwordService = app.get(PasswordService);
    const tokenService = app.get(TokenService);
    const credentialCrypto = app.get(
      TrackingCredentialCryptoService,
    );
    const passwordHash =
      await passwordService.hash(password);

    const customer = await prisma.customer.create({
      data: {
        customerCode: `CUS-MOB-${codeSuffix}`,
        customerType: 'INDIVIDUAL',
        status: 'ACTIVE',
        acquisitionSource: 'DIRECT',
        primaryMobile: mobileNumber,
        individualProfile: {
          create: {
            fullName: 'Mobile API E2E Customer',
          },
        },
      },
    });

    customerId = customer.id;

    const user = await prisma.user.create({
      data: {
        userCode: `USR-MOB-${codeSuffix}`,
        fullName: 'Mobile API E2E User',
        mobileNumber,
        normalizedMobileNumber: mobileNumber,
        passwordHash,
        passwordChangedAt: new Date(),
        status: 'ACTIVE',
        mobileVerifiedAt: new Date(),
      },
    });

    userId = user.id;

    const membership =
      await prisma.customerMembership.create({
        data: {
          customerId,
          userId,
          status: 'ACTIVE',
          isPrimary: true,
          joinedAt: new Date(),
        },
      });

    customerMembershipId = membership.id;

    const customerOwnerRole =
      await prisma.role.findUniqueOrThrow({
        where: {
          code: 'CUSTOMER_OWNER',
        },
      });
    const roleAssignment =
      await prisma.roleAssignment.create({
        data: {
          userId,
          roleId: customerOwnerRole.id,
          scopeType: 'CUSTOMER',
          scopeId: customerId,
          status: 'ACTIVE',
          assignedByUserId: userId,
        },
      });

    roleAssignmentId = roleAssignment.id;

    const deviceModel =
      await prisma.deviceModel.create({
        data: {
          modelCode: `DM-MOB-${codeSuffix}`,
          manufacturer: 'Solid Tracker',
          modelName: 'Mobile E2E Tracker',
          protocol: 'osmand',
          networkType: 'LTE_4G',
          status: 'ACTIVE',
        },
      });

    deviceModelId = deviceModel.id;

    const device = await prisma.device.create({
      data: {
        deviceCode: `DEV-MOB-${codeSuffix}`,
        deviceModelId,
        imei: `86${numericSuffix}12345`,
        lifecycleStatus: 'INSTALLED',
        receivedAt: new Date(),
      },
    });

    deviceId = device.id;

    const vehicle = await prisma.vehicle.create({
      data: {
        vehicleCode: `VEH-MOB-${codeSuffix}`,
        customerId,
        registrationNumber:
          `DHAKA-METRO-${codeSuffix}`,
        normalizedRegistrationNumber:
          `DHAKA-METRO-${codeSuffix}`,
        vehicleType: 'CAR',
        manufacturer: 'Toyota',
        modelName: 'Corolla',
        manufacturingYear: 2022,
        color: 'White',
        status: 'ACTIVE',
        createdByUserId: userId,
      },
    });

    vehicleId = vehicle.id;

    const assignment =
      await prisma.vehicleDeviceAssignment.create({
        data: {
          vehicleId,
          deviceId,
          assignmentType: 'PRIMARY',
          status: 'ACTIVE',
          assignedByUserId: userId,
        },
      });

    assignmentId = assignment.id;

    const traccarServer =
      await prisma.traccarServer.create({
        data: {
          serverCode: `TRC-MOB-${codeSuffix}`,
          name: 'Mobile E2E Traccar',
          baseUrl: fakeTraccarBaseUrl,
          encryptedCredentialReference:
            credentialCrypto.encrypt({
              token: 'mobile-e2e-token',
            }),
          status: 'ACTIVE',
          isDefault: false,
          lastHealthStatus: 'UP',
        },
      });

    traccarServerId = traccarServer.id;

    const mapping =
      await prisma.traccarDeviceMapping.create({
        data: {
          deviceId,
          traccarServerId,
          traccarDeviceId: 101n,
          traccarUniqueId:
            `MOBILE-${codeSuffix}`,
          syncStatus: 'SYNCED',
          isPrimary: true,
          isActive: true,
          lastSyncedAt: new Date(),
        },
      });

    mappingId = mapping.id;

    const servicePlan =
      await prisma.servicePlan.create({
        data: {
          planCode: `PLAN-MOB-${codeSuffix}`,
          planFamilyCode:
            `MOBILE-${codeSuffix}`,
          version: 1,
          name: 'Mobile E2E Plan',
          billingIntervalUnit: 'MONTH',
          billingIntervalCount: 1,
          basePrice: '500.00',
          currency: 'BDT',
          status: 'ACTIVE',
          effectiveFrom: new Date(),
        },
      });

    servicePlanId = servicePlan.id;

    const subscription =
      await prisma.subscription.create({
        data: {
          subscriptionCode:
            `SUB-MOB-${codeSuffix}`,
          customerId,
          vehicleId,
          servicePlanId,
          status: 'ACTIVE',
          startedAt: new Date(),
          currentPeriodStart: new Date(),
          currentPeriodEnd: new Date(
            Date.now() + 30 * 24 * 60 * 60 * 1000,
          ),
          nextBillingAt: new Date(
            Date.now() + 30 * 24 * 60 * 60 * 1000,
          ),
          autoRenew: true,
        },
      });

    subscriptionId = subscription.id;

    const event = await prisma.trackingEvent.create({
      data: {
        eventCode: `EVT-MOB-${codeSuffix}`,
        customerId,
        vehicleId,
        deviceId,
        traccarServerId,
        deduplicationKey:
          `mobile-e2e-${codeSuffix}`,
        eventType: 'deviceOnline',
        severity: 'INFO',
        latitude: '23.8103000',
        longitude: '90.4125000',
        occurredAt: new Date(),
        processingStatus: 'PROCESSED',
      },
    });

    eventId = event.id;

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

  });

  afterAll(async () => {
    if (prisma) {
      await prisma.userSession.deleteMany({
        where: {
          userId,
        },
      });
      await prisma.integrationJob.deleteMany({
        where: {
          entityId: vehicleId,
        },
      });
      await prisma.trackingEvent.deleteMany({
        where: {
          id: eventId,
        },
      });
      await prisma.subscription.deleteMany({
        where: {
          id: subscriptionId,
        },
      });
      await prisma.servicePlan.deleteMany({
        where: {
          id: servicePlanId,
        },
      });
      await prisma.traccarDeviceMapping.deleteMany({
        where: {
          id: mappingId,
        },
      });
      await prisma.traccarServer.deleteMany({
        where: {
          id: traccarServerId,
        },
      });
      await prisma.vehicleDeviceAssignment.deleteMany({
        where: {
          id: assignmentId,
        },
      });
      await prisma.device.deleteMany({
        where: {
          id: deviceId,
        },
      });
      await prisma.deviceModel.deleteMany({
        where: {
          id: deviceModelId,
        },
      });
      await prisma.vehicle.deleteMany({
        where: {
          id: vehicleId,
        },
      });
      await prisma.roleAssignment.deleteMany({
        where: {
          id: roleAssignmentId,
        },
      });
      await prisma.customerMembership.deleteMany({
        where: {
          id: customerMembershipId,
        },
      });
      await prisma.customer.deleteMany({
        where: {
          id: customerId,
        },
      });
      await prisma.user.deleteMany({
        where: {
          id: userId,
        },
      });
    }

    if (app) {
      await app.close();
    }

    if (fakeTraccar) {
      await new Promise<void>((resolve, reject) => {
        fakeTraccar.close((error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        });
      });
    }
  });

  it('serves dashboard, vehicle, trip, event, billing, and live-session contracts', async () => {
    const authorization =
      `Bearer ${accessToken}`;

    const profile = await request(
      app.getHttpServer(),
    )
      .get('/api/v1/mobile/profile')
      .set('Authorization', authorization)
      .expect(200);

    expect(profile.body.data.id).toBe(userId);
    expect(
      profile.body.data.customerMemberships,
    ).toHaveLength(1);

    const dashboard = await request(
      app.getHttpServer(),
    )
      .get('/api/v1/mobile/dashboard')
      .set('Authorization', authorization)
      .expect(200);

    expect(
      dashboard.body.data.summary.vehicleCount,
    ).toBe(1);

    const vehicles = await request(
      app.getHttpServer(),
    )
      .get('/api/v1/mobile/vehicles')
      .set('Authorization', authorization)
      .expect(200);

    expect(vehicles.body.data).toHaveLength(1);
    expect(vehicles.body.data[0].id).toBe(
      vehicleId,
    );

    const session = await request(
      app.getHttpServer(),
    )
      .post('/api/v1/mobile/live-sessions')
      .set('Authorization', authorization)
      .send({
        vehicleId,
        ttlSeconds: 120,
      })
      .expect(201);
    const sessionToken =
      session.body.data.token as string;

    const position = await request(
      app.getHttpServer(),
    )
      .get(
        `/api/v1/mobile/live-sessions/${sessionToken}/position`,
      )
      .set('Authorization', authorization)
      .expect(200);

    expect(
      position.body.data.position.latitude,
    ).toBe(23.8203);

    const trips = await request(
      app.getHttpServer(),
    )
      .get(
        `/api/v1/mobile/vehicles/${vehicleId}/trips`,
      )
      .query({
        from: '2026-07-14T09:00:00.000Z',
        to: '2026-07-14T11:00:00.000Z',
      })
      .set('Authorization', authorization)
      .expect(200);

    expect(trips.body.data).toHaveLength(1);

    const events = await request(
      app.getHttpServer(),
    )
      .get(
        `/api/v1/mobile/vehicles/${vehicleId}/events`,
      )
      .set('Authorization', authorization)
      .expect(200);

    expect(events.body.data).toHaveLength(1);

    const subscriptions = await request(
      app.getHttpServer(),
    )
      .get('/api/v1/mobile/billing/subscriptions')
      .set('Authorization', authorization)
      .expect(200);

    expect(subscriptions.body.data).toHaveLength(1);

    await request(app.getHttpServer())
      .delete(
        `/api/v1/mobile/live-sessions/${sessionToken}`,
      )
      .set('Authorization', authorization)
      .expect(200);
  });
});
'@

    Write-Step 8 10 "Running complete backend verification"

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

    Write-Step 9 10 "Verifying mobile API invariants and writing documentation"

    $finalMigrationCount = Get-AppliedMigrationCount
    $finalPublicTableCount = Get-PublicTableCount
    $mobileFileCount = (
        Get-ChildItem `
            -LiteralPath "services/backend-api/src/mobile" `
            -Recurse `
            -File `
            -Filter "*.ts"
    ).Count

    if ($finalMigrationCount -ne 6) {
        throw "Mobile API stage changed the applied migration count."
    }

    if ($finalPublicTableCount -ne 53) {
        throw "Mobile API stage changed the public table count."
    }

    if ($mobileFileCount -lt 19) {
        throw "Expected at least 19 mobile API source files."
    }

    Write-Host "Applied migrations: 6" -ForegroundColor Green
    Write-Host "Public tables:      53" -ForegroundColor Green
    Write-Host "Mobile TS files:    $mobileFileCount" -ForegroundColor Green
    Write-Host "Schema migration:   none" -ForegroundColor Green

    Write-Utf8File `
        "docs/architecture/mobile-api.md" `
        @'
# Customer Mobile API

## Purpose

The mobile API provides stable, customer-scoped contracts for Android and iOS clients without exposing Traccar directly.

All routes are served beneath:

```text
/api/v1/mobile
```

## Authorization

Mobile access requires:

- a valid access token;
- an active customer membership;
- the existing permission required by the requested operation.

The service derives customer scope from the authenticated access-token context and does not accept customer identifiers from the client.

## Contracts

The stage provides:

- authenticated customer profile;
- cached customer dashboard;
- cursor-paginated vehicle summaries;
- detailed vehicle, tracker, subscription, and geofence context;
- live position;
- bounded position history;
- derived trip feed;
- cursor-paginated tracking event feed;
- subscription and invoice feeds;
- notification feed;
- Redis-backed live tracking sessions.

## Live sessions

Live sessions are short-lived, user-bound Redis records. A session cannot be read or closed by another user.

Latest position responses use a small Redis cache to avoid excessive calls to Traccar while the mobile client polls.

## Caching

The dashboard cache is intentionally short-lived. The cache stores only customer-authorized response data and is keyed by user and customer scope.

## Data ownership

PostgreSQL remains the source of truth for customers, vehicles, subscriptions, invoices, events, and notifications.

Traccar remains the telemetry source. The mobile client communicates only with the NestJS API.

## Database impact

This stage introduces no Prisma migration.

The invariant remains:

```text
Applied migrations: 6
Public tables: 53
```
'@

    Write-Step 10 10 "Committing the customer mobile API platform"

    Invoke-CheckedCommand "Git whitespace check" {
        git diff --check
    }

    git add -- `
        ".env.example" `
        "docs/architecture/mobile-api.md" `
        "scripts/solid-tracker-mobile-api.ps1" `
        "scripts/solid-tracker-mobile-api-recovery.ps1" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/mobile" `
        "services/backend-api/src/tracking/tracking-api.module.ts" `
        "services/backend-api/test/mobile-api.e2e-spec.ts"

    if ($LASTEXITCODE -ne 0) {
        throw "Git staging failed."
    }

    git commit `
        -m "feat(mobile): establish customer app APIs and live tracking sessions"

    if ($LASTEXITCODE -ne 0) {
        throw "Mobile API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Customer Mobile API Platform Ready" -ForegroundColor Cyan
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
        "Flutter mobile application foundation, secure token storage, " +
        "API client, authentication flow, dashboard, and live map screens"
    ) -ForegroundColor Green

    exit 0
}
catch {
    Write-Host ""
    Write-Host "CUSTOMER MOBILE API PLATFORM FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host (
        "Do not reset, delete, rename, or edit any of the six applied migrations."
    ) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null
    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current 2>$null
    exit 1
}
