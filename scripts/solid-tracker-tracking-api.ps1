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

function New-SecureBase64 {
    $bytes = New-Object byte[] 48
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    return [Convert]::ToBase64String($bytes)
}

function Ensure-EnvEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $content = if (Test-Path -LiteralPath $fullPath) {
        [System.IO.File]::ReadAllText($fullPath)
    }
    else {
        ""
    }

    $pattern = "(?m)^" + [regex]::Escape($Name) + "="

    if ([regex]::IsMatch($content, $pattern)) {
        Write-Host "[PRESERVED] $RelativePath already contains $Name" -ForegroundColor DarkYellow
        return
    }

    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
        $content += [Environment]::NewLine
    }

    $content += "$Name=$Value" + [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        $fullPath,
        $content,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED] $RelativePath with $Name" -ForegroundColor Green
}

function Assert-CleanExceptSelf {
    $allowedEntries = @(
        "?? scripts/solid-tracker-tracking-api.ps1"
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
            "tracking API script."
        )
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Tracking and Traccar API" -ForegroundColor Cyan
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
        "services\backend-api\src\config\environment.validation.ts",
        "services\backend-api\src\identity\audit\audit.service.ts",
        "services\backend-api\src\management\common\pagination-query.dto.ts",
        "services\backend-api\test\jest-e2e.json"
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file is missing: $requiredPath"
        }
    }

    Write-Step 1 9 "Merging billing APIs and creating the tracking branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/billing-api") {
        Assert-CleanExceptSelf

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        git merge-base --is-ancestor feat/billing-api main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge billing APIs into main" {
                git merge `
                    --no-ff `
                    feat/billing-api `
                    -m "merge: integrate billing APIs"
            }
        }
        else {
            Write-Host "Billing APIs are already contained in main." -ForegroundColor Green
        }

        $branchExists = git branch --list "feat/tracking-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing tracking API branch" {
                git checkout feat/tracking-api
            }
        }
        else {
            Invoke-CheckedCommand "Create tracking API branch" {
                git checkout -b feat/tracking-api
            }
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-CleanExceptSelf

        git merge-base --is-ancestor feat/billing-api main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge billing APIs into main" {
                git merge `
                    --no-ff `
                    feat/billing-api `
                    -m "merge: integrate billing APIs"
            }
        }

        $branchExists = git branch --list "feat/tracking-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing tracking API branch" {
                git checkout feat/tracking-api
            }
        }
        else {
            Invoke-CheckedCommand "Create tracking API branch" {
                git checkout -b feat/tracking-api
            }
        }
    }
    elseif ($currentBranch -eq "feat/tracking-api") {
        Assert-CleanExceptSelf
        Write-Host "Already on feat/tracking-api." -ForegroundColor Green
    }
    else {
        throw (
            "Expected feat/billing-api, main, or feat/tracking-api. " +
            "Current branch: $currentBranch"
        )
    }

    Write-Step 2 9 "Validating infrastructure, migrations, and tracking schema"

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

    $schemaPath = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\schema.prisma"

    $schemaContent = [System.IO.File]::ReadAllText($schemaPath)

    foreach ($requiredModel in @(
        "model TraccarServer {",
        "model TraccarDeviceMapping {",
        "model TrackingEvent {",
        "model Geofence {",
        "model VehicleGeofenceAssignment {",
        "model NotificationRule {",
        "model Notification {",
        "model DeviceCommandRequest {",
        "model IntegrationJob {"
    )) {
        if (-not $schemaContent.Contains($requiredModel)) {
            throw "Required Prisma tracking model is missing: $requiredModel"
        }
    }

    $migrationSql = @'
SELECT COUNT(*)
FROM "_prisma_migrations"
WHERE finished_at IS NOT NULL
  AND rolled_back_at IS NULL;
'@

    $migrationOutput = $migrationSql |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify the applied migration count."
    }

    $migrationCount = [int](($migrationOutput | Out-String).Trim())

    if ($migrationCount -ne 5) {
        throw "Expected exactly 5 applied migrations."
    }

    Write-Host "PostgreSQL:      healthy" -ForegroundColor Green
    Write-Host "Redis:           healthy" -ForegroundColor Green
    Write-Host "Tracking schema: present" -ForegroundColor Green
    Write-Host "Migrations:      5 applied" -ForegroundColor Green
    Write-Host "New migration:   not required" -ForegroundColor Green

    Write-Step 3 9 "Configuring Traccar credential and webhook security"

    Ensure-EnvEntry `
        ".env" `
        "TRACKING_CREDENTIAL_ENCRYPTION_KEY" `
        (New-SecureBase64)

    Ensure-EnvEntry `
        ".env" `
        "TRACKING_WEBHOOK_SECRET" `
        (New-SecureBase64)

    Ensure-EnvEntry `
        ".env" `
        "TRACKING_HTTP_TIMEOUT_MS" `
        "10000"

    Ensure-EnvEntry `
        ".env.example" `
        "TRACKING_CREDENTIAL_ENCRYPTION_KEY" `
        "replace-with-a-dedicated-random-secret-at-least-32-characters"

    Ensure-EnvEntry `
        ".env.example" `
        "TRACKING_WEBHOOK_SECRET" `
        "replace-with-a-dedicated-random-webhook-secret-at-least-32-characters"

    Ensure-EnvEntry `
        ".env.example" `
        "TRACKING_HTTP_TIMEOUT_MS" `
        "10000"

    $validationPath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\config\environment.validation.ts"

    $validationContent = [System.IO.File]::ReadAllText(
        $validationPath
    )

    if (
        -not $validationContent.Contains(
            "TRACKING_CREDENTIAL_ENCRYPTION_KEY"
        )
    ) {
        $closingIndex = $validationContent.LastIndexOf("});")

        if ($closingIndex -lt 0) {
            throw "Could not locate the environment-validation object."
        }

        $validationEntry = @'
  TRACKING_CREDENTIAL_ENCRYPTION_KEY: Joi.string().min(32).required(),
  TRACKING_WEBHOOK_SECRET: Joi.string().min(32).required(),
  TRACKING_HTTP_TIMEOUT_MS: Joi.number().integer().min(1000).default(10000),
'@

        $validationContent = $validationContent.Insert(
            $closingIndex,
            $validationEntry + [Environment]::NewLine
        )

        [System.IO.File]::WriteAllText(
            $validationPath,
            $validationContent,
            $script:Utf8NoBom
        )

        Write-Host (
            "[UPDATED] services\backend-api\src\config\environment.validation.ts"
        ) -ForegroundColor Green
    }
    else {
        Write-Host (
            "[PRESERVED] tracking environment validation already exists"
        ) -ForegroundColor DarkYellow
    }

    Write-Step 4 9 "Writing Traccar synchronization and tracking APIs"

    Write-Utf8File `
        "services\backend-api\src\tracking\commands\device-commands.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
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
import { CommandQueryDto } from '../common/tracking-query.dto';
import { DeviceCommandsService } from './device-commands.service';
import { ApproveDeviceCommandDto } from './dto/approve-device-command.dto';
import { CreateDeviceCommandDto } from './dto/create-device-command.dto';

@ApiTags('Tracking - Device Commands')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/commands')
export class DeviceCommandsController {
  constructor(
    private readonly deviceCommandsService: DeviceCommandsService,
  ) {}

  @Get()
  @RequirePermissions('command.send')
  @ApiOperation({ summary: 'List device command requests' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: CommandQueryDto,
  ) {
    return this.deviceCommandsService.list(auth, query);
  }

  @Post()
  @RequirePermissions('command.send')
  @ApiOperation({ summary: 'Request a device command' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateDeviceCommandDto,
  ) {
    return this.deviceCommandsService.create(auth, dto);
  }

  @Get(':commandId')
  @RequirePermissions('command.send')
  @ApiOperation({ summary: 'Read one device command request' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('commandId', new ParseUUIDPipe())
    commandId: string,
  ) {
    return this.deviceCommandsService.get(auth, commandId);
  }

  @Post(':commandId/approve')
  @RequirePermissions(
    'command.send',
    'command.engine_cutoff',
  )
  @ApiOperation({
    summary:
      'Approve and send a high-risk engine-control command',
  })
  approve(
    @CurrentAuth() auth: AuthContext,
    @Param('commandId', new ParseUUIDPipe())
    commandId: string,
    @Body() dto: ApproveDeviceCommandDto,
  ) {
    return this.deviceCommandsService.approve(
      auth,
      commandId,
      dto,
    );
  }

  @Post(':commandId/cancel')
  @RequirePermissions('command.send')
  @ApiOperation({ summary: 'Cancel a pending device command' })
  cancel(
    @CurrentAuth() auth: AuthContext,
    @Param('commandId', new ParseUUIDPipe())
    commandId: string,
  ) {
    return this.deviceCommandsService.cancel(
      auth,
      commandId,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\commands\device-commands.service.ts" `
        @'
import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type { CommandQueryDto } from '../common/tracking-query.dto';
import { jsonSafe, toInputJson } from '../common/tracking-json.util';
import { TraccarClientService } from '../common/traccar-client.service';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import type { ApproveDeviceCommandDto } from './dto/approve-device-command.dto';
import type { CreateDeviceCommandDto } from './dto/create-device-command.dto';

@Injectable()
export class DeviceCommandsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly client: TraccarClientService,
    private readonly jobs: IntegrationJobsService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: CommandQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.commandWhere(auth);
    const where: Prisma.DeviceCommandRequestWhereInput = {
      AND: [
        scopeWhere,
        query.deviceId
          ? {
              deviceId: query.deviceId,
            }
          : {},
        query.vehicleId
          ? {
              vehicleId: query.vehicleId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  commandCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  reason: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.deviceCommandRequest.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          requestedAt: 'desc',
        },
        include: {
          device: true,
          vehicle: true,
          traccarServer: {
            select: {
              id: true,
              serverCode: true,
              name: true,
            },
          },
          requestedBy: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
          approvedBy: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
        },
      }),
      this.prisma.deviceCommandRequest.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async get(auth: AuthContext, commandId: string) {
    await this.access.assertCommand(auth, commandId);

    const command = await this.prisma.deviceCommandRequest.findUnique({
      where: {
        id: commandId,
      },
      include: {
        device: true,
        vehicle: true,
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
          },
        },
        requestedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
        approvedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
      },
    });

    return jsonSafe(command);
  }

  async create(auth: AuthContext, dto: CreateDeviceCommandDto) {
    await this.access.assertDevice(auth, dto.deviceId);

    const engineControl = ['ENGINE_CUTOFF', 'ENGINE_RESTORE'].includes(dto.commandType);

    if (engineControl && !auth.permissions.includes('command.engine_cutoff')) {
      throw new ForbiddenException('Engine-control permission is required.');
    }

    const mapping = await this.prisma.traccarDeviceMapping.findFirst({
      where: {
        deviceId: dto.deviceId,
        isActive: true,
        isPrimary: true,
        syncStatus: 'SYNCED',
      },
      include: {
        traccarServer: true,
      },
    });

    if (!mapping) {
      throw new NotFoundException('The device has no active synchronized Traccar mapping.');
    }

    let vehicleId = dto.vehicleId;

    if (vehicleId) {
      await this.access.assertVehicle(auth, vehicleId);
      const assignment = await this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          deviceId: dto.deviceId,
          vehicleId,
          status: 'ACTIVE',
        },
        select: {
          id: true,
        },
      });

      if (!assignment) {
        throw new BadRequestException(
          'Command device must be actively assigned to the selected vehicle.',
        );
      }
    } else if (engineControl) {
      const assignment = await this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          deviceId: dto.deviceId,
          status: 'ACTIVE',
        },
        select: {
          vehicleId: true,
        },
      });

      vehicleId = assignment?.vehicleId;

      if (!vehicleId) {
        throw new BadRequestException(
          'Engine-control commands require an active vehicle assignment.',
        );
      }
    }

    const expiresAt = dto.expiresAt
      ? new Date(dto.expiresAt)
      : new Date(Date.now() + 15 * 60 * 1000);

    if (expiresAt <= new Date()) {
      throw new BadRequestException('Command expiry must be in the future.');
    }

    const command = await this.prisma.deviceCommandRequest.create({
      data: {
        commandCode: this.codes.command(),
        deviceId: dto.deviceId,
        vehicleId,
        traccarServerId: mapping.traccarServerId,
        requestedByUserId: auth.userId,
        commandType: dto.commandType,
        parameters: toInputJson(dto.parameters),
        reason: dto.reason.trim(),
        status: engineControl ? 'PENDING_APPROVAL' : 'QUEUED',
        requiresApproval: engineControl,
        expiresAt,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.command.requested',
      resourceType: 'DeviceCommandRequest',
      resourceId: command.id,
      scopeType: command.vehicleId ? 'VEHICLE' : this.access.isPlatformScoped(auth) ? 'PLATFORM' : undefined,
      scopeId: command.vehicleId ?? undefined,
      afterData: jsonSafe(command),
    });

    if (engineControl) {
      return jsonSafe(command);
    }

    return this.send(command.id);
  }

  async approve(auth: AuthContext, commandId: string, dto: ApproveDeviceCommandDto) {
    if (!auth.permissions.includes('command.engine_cutoff')) {
      throw new ForbiddenException('Engine-control permission is required.');
    }

    const command = await this.prisma.deviceCommandRequest.findUnique({
      where: {
        id: commandId,
      },
    });

    if (!command) {
      throw new NotFoundException('Device command was not found.');
    }

    if (command.status !== 'PENDING_APPROVAL') {
      throw new BadRequestException('Only pending-approval commands may be approved.');
    }

    if (command.requestedByUserId === auth.userId) {
      throw new ForbiddenException(
        'The command requester cannot approve the same high-risk command.',
      );
    }

    if (command.expiresAt && command.expiresAt <= new Date()) {
      await this.prisma.deviceCommandRequest.update({
        where: {
          id: commandId,
        },
        data: {
          status: 'EXPIRED',
        },
      });

      throw new BadRequestException('The command approval window has expired.');
    }

    const approved = await this.prisma.deviceCommandRequest.update({
      where: {
        id: commandId,
      },
      data: {
        approvedByUserId: auth.userId,
        approvedAt: new Date(),
        status: 'QUEUED',
        parameters: toInputJson({
          ...(command.parameters && typeof command.parameters === 'object'
            ? command.parameters
            : {}),
          approvalNote: dto.approvalNote,
        }),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.command.approved',
      resourceType: 'DeviceCommandRequest',
      resourceId: commandId,
      scopeType: command.vehicleId ? 'VEHICLE' : this.access.isPlatformScoped(auth) ? 'PLATFORM' : undefined,
      scopeId: command.vehicleId ?? undefined,
      beforeData: jsonSafe(command),
      afterData: jsonSafe(approved),
    });

    return this.send(commandId);
  }

  async cancel(auth: AuthContext, commandId: string) {
    await this.access.assertCommand(auth, commandId);

    const command = await this.prisma.deviceCommandRequest.findUnique({
      where: {
        id: commandId,
      },
    });

    if (!command) {
      throw new NotFoundException('Device command was not found.');
    }

    if (!['PENDING_APPROVAL', 'QUEUED'].includes(command.status)) {
      throw new BadRequestException('The command cannot be cancelled in its current state.');
    }

    if (command.requestedByUserId !== auth.userId && !this.access.isPlatformScoped(auth)) {
      throw new ForbiddenException(
        'Only the requester or platform operator may cancel the command.',
      );
    }

    const updated = await this.prisma.deviceCommandRequest.update({
      where: {
        id: commandId,
      },
      data: {
        status: 'CANCELLED',
        failureReason: 'Cancelled by an authorized user.',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.command.cancelled',
      resourceType: 'DeviceCommandRequest',
      resourceId: commandId,
      scopeType: command.vehicleId ? 'VEHICLE' : this.access.isPlatformScoped(auth) ? 'PLATFORM' : undefined,
      scopeId: command.vehicleId ?? undefined,
      beforeData: jsonSafe(command),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  private async send(commandId: string) {
    const command = await this.prisma.deviceCommandRequest.findUniqueOrThrow({
      where: {
        id: commandId,
      },
      include: {
        traccarServer: true,
        device: {
          include: {
            traccarMappings: {
              where: {
                isActive: true,
                isPrimary: true,
                syncStatus: 'SYNCED',
              },
              take: 1,
            },
          },
        },
      },
    });

    if (!command.traccarServer) {
      throw new NotFoundException('Command Traccar server was not found.');
    }

    const mapping = command.device.traccarMappings[0];

    if (!mapping) {
      throw new NotFoundException('Command device mapping was not found.');
    }

    const job = await this.jobs.create({
      jobType: 'SEND_COMMAND',
      traccarServerId: command.traccarServerId ?? undefined,
      entityType: 'DeviceCommandRequest',
      entityId: command.id,
      idempotencyKey: `send-command:${command.id}`,
      payload: {
        commandType: command.commandType,
        parameters: command.parameters,
      },
      maximumAttempts: 3,
    });

    if (job.status === 'SUCCEEDED' && command.status === 'COMPLETED') {
      return jsonSafe(command);
    }

    await this.jobs.processing(job.id);

    try {
      await this.prisma.deviceCommandRequest.update({
        where: {
          id: command.id,
        },
        data: {
          status: 'SENT',
          sentAt: new Date(),
        },
      });

      const response = await this.client.sendCommand(
        command.traccarServer,
        mapping.traccarDeviceId,
        {
          type: this.traccarCommandType(command.commandType),
          attributes:
            command.parameters && typeof command.parameters === 'object'
              ? (command.parameters as Record<string, unknown>)
              : {},
        },
      );

      const completed = await this.prisma.deviceCommandRequest.update({
        where: {
          id: command.id,
        },
        data: {
          status: 'COMPLETED',
          traccarCommandId: response.id !== undefined ? BigInt(response.id) : undefined,
          acknowledgedAt: new Date(),
          completedAt: new Date(),
          failureReason: null,
        },
      });

      await this.jobs.succeeded(job.id, response);

      return jsonSafe(completed);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown command error';

      await this.prisma.deviceCommandRequest.update({
        where: {
          id: command.id,
        },
        data: {
          status: 'FAILED',
          failedAt: new Date(),
          failureReason: message,
        },
      });

      await this.jobs.failed(job.id, error);
      throw error;
    }
  }

  private traccarCommandType(
    commandType:
      | 'REQUEST_POSITION'
      | 'RESTART_DEVICE'
      | 'SET_REPORTING_INTERVAL'
      | 'ACTIVATE_RELAY'
      | 'DEACTIVATE_RELAY'
      | 'ENGINE_CUTOFF'
      | 'ENGINE_RESTORE'
      | 'CHANGE_SERVER'
      | 'CUSTOM',
  ): string {
    const mapping: Record<string, string> = {
      REQUEST_POSITION: 'positionSingle',
      RESTART_DEVICE: 'rebootDevice',
      SET_REPORTING_INTERVAL: 'custom',
      ACTIVATE_RELAY: 'custom',
      DEACTIVATE_RELAY: 'custom',
      ENGINE_CUTOFF: 'engineStop',
      ENGINE_RESTORE: 'engineResume',
      CHANGE_SERVER: 'custom',
      CUSTOM: 'custom',
    };

    return mapping[commandType];
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\commands\dto\approve-device-command.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength } from 'class-validator';

export class ApproveDeviceCommandDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  approvalNote?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\commands\dto\create-device-command.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsDateString,
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

const commandTypes = [
  'REQUEST_POSITION',
  'RESTART_DEVICE',
  'SET_REPORTING_INTERVAL',
  'ACTIVATE_RELAY',
  'DEACTIVATE_RELAY',
  'ENGINE_CUTOFF',
  'ENGINE_RESTORE',
  'CHANGE_SERVER',
  'CUSTOM',
] as const;

export class CreateDeviceCommandDto {
  @ApiProperty()
  @IsUUID()
  deviceId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiProperty({ enum: commandTypes })
  @IsIn(commandTypes)
  commandType!: (typeof commandTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  parameters?: Record<string, unknown>;

  @ApiProperty()
  @IsString()
  @MinLength(3)
  @MaxLength(1000)
  reason!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  expiresAt?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\common\traccar-client.service.ts" `
        @'
import {
  BadGatewayException,
  GatewayTimeoutException,
  Injectable,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { TraccarServer } from '../../generated/prisma/client';
import {
  TrackingCredentialCryptoService,
  type TraccarCredentials,
} from './tracking-credential-crypto.service';

export interface TraccarDevice {
  id: number;
  name: string;
  uniqueId: string;
  status?: string;
  disabled?: boolean;
  category?: string;
  attributes?: Record<string, unknown>;
}

export interface TraccarPosition {
  id: number;
  deviceId: number;
  protocol?: string;
  serverTime?: string;
  deviceTime?: string;
  fixTime?: string;
  outdated?: boolean;
  valid?: boolean;
  latitude: number;
  longitude: number;
  altitude?: number;
  speed?: number;
  course?: number;
  address?: string;
  accuracy?: number;
  network?: Record<string, unknown>;
  attributes?: Record<string, unknown>;
}

export interface TraccarEvent {
  id: number;
  type: string;
  eventTime?: string;
  deviceId: number;
  positionId?: number;
  geofenceId?: number;
  maintenanceId?: number;
  attributes?: Record<string, unknown>;
}

export interface TraccarGeofence {
  id: number;
  name: string;
  description?: string;
  area: string;
  calendarId?: number;
  attributes?: Record<string, unknown>;
}

export interface TraccarCommandResult {
  id?: number;
  deviceId?: number;
  type?: string;
  textChannel?: boolean;
  attributes?: Record<string, unknown>;
}

export interface TraccarServerHealth {
  id?: number;
  version?: string;
  registration?: boolean;
  readonly?: boolean;
  map?: string;
  bingKey?: string;
  forceSettings?: boolean;
  coordinateFormat?: string;
  limitCommands?: boolean;
  attributes?: Record<string, unknown>;
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  query?: Record<string, string | number | boolean | undefined>;
  body?: unknown;
}

@Injectable()
export class TraccarClientService {
  private readonly timeoutMs: number;

  constructor(
    private readonly credentialCrypto: TrackingCredentialCryptoService,
    configService: ConfigService,
  ) {
    this.timeoutMs = configService.get<number>(
      'TRACKING_HTTP_TIMEOUT_MS',
      10000,
    );
  }

  health(server: TraccarServer): Promise<TraccarServerHealth> {
    return this.request<TraccarServerHealth>(
      server,
      '/api/server',
    );
  }

  findDeviceByUniqueId(
    server: TraccarServer,
    uniqueId: string,
  ): Promise<TraccarDevice[]> {
    return this.request<TraccarDevice[]>(
      server,
      '/api/devices',
      {
        query: {
          uniqueId,
        },
      },
    );
  }

  createDevice(
    server: TraccarServer,
    input: {
      name: string;
      uniqueId: string;
      disabled?: boolean;
      category?: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarDevice> {
    return this.request<TraccarDevice>(
      server,
      '/api/devices',
      {
        method: 'POST',
        body: input,
      },
    );
  }

  updateDevice(
    server: TraccarServer,
    traccarDeviceId: bigint,
    input: {
      id: number;
      name: string;
      uniqueId: string;
      disabled?: boolean;
      category?: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarDevice> {
    return this.request<TraccarDevice>(
      server,
      `/api/devices/${this.safeNumber(traccarDeviceId)}`,
      {
        method: 'PUT',
        body: input,
      },
    );
  }

  latestPositions(
    server: TraccarServer,
    traccarDeviceId: bigint,
  ): Promise<TraccarPosition[]> {
    return this.request<TraccarPosition[]>(
      server,
      '/api/positions',
      {
        query: {
          deviceId: this.safeNumber(traccarDeviceId),
        },
      },
    );
  }

  positionHistory(
    server: TraccarServer,
    traccarDeviceId: bigint,
    from: Date,
    to: Date,
  ): Promise<TraccarPosition[]> {
    return this.request<TraccarPosition[]>(
      server,
      '/api/positions',
      {
        query: {
          deviceId: this.safeNumber(traccarDeviceId),
          from: from.toISOString(),
          to: to.toISOString(),
        },
      },
    );
  }

  eventHistory(
    server: TraccarServer,
    traccarDeviceId: bigint,
    from: Date,
    to: Date,
  ): Promise<TraccarEvent[]> {
    return this.request<TraccarEvent[]>(
      server,
      '/api/events',
      {
        query: {
          deviceId: this.safeNumber(traccarDeviceId),
          from: from.toISOString(),
          to: to.toISOString(),
        },
      },
    );
  }

  createGeofence(
    server: TraccarServer,
    input: {
      name: string;
      description?: string;
      area: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarGeofence> {
    return this.request<TraccarGeofence>(
      server,
      '/api/geofences',
      {
        method: 'POST',
        body: input,
      },
    );
  }

  updateGeofence(
    server: TraccarServer,
    traccarGeofenceId: bigint,
    input: {
      id: number;
      name: string;
      description?: string;
      area: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarGeofence> {
    return this.request<TraccarGeofence>(
      server,
      `/api/geofences/${this.safeNumber(traccarGeofenceId)}`,
      {
        method: 'PUT',
        body: input,
      },
    );
  }

  deleteGeofence(
    server: TraccarServer,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    return this.request<void>(
      server,
      `/api/geofences/${this.safeNumber(traccarGeofenceId)}`,
      {
        method: 'DELETE',
      },
    );
  }

  linkDeviceGeofence(
    server: TraccarServer,
    traccarDeviceId: bigint,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    return this.request<void>(
      server,
      '/api/permissions',
      {
        method: 'POST',
        body: {
          deviceId: this.safeNumber(traccarDeviceId),
          geofenceId: this.safeNumber(traccarGeofenceId),
        },
      },
    );
  }

  unlinkDeviceGeofence(
    server: TraccarServer,
    traccarDeviceId: bigint,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    return this.request<void>(
      server,
      '/api/permissions',
      {
        method: 'DELETE',
        body: {
          deviceId: this.safeNumber(traccarDeviceId),
          geofenceId: this.safeNumber(traccarGeofenceId),
        },
      },
    );
  }

  sendCommand(
    server: TraccarServer,
    traccarDeviceId: bigint,
    input: {
      type: string;
      attributes?: Record<string, unknown>;
    },
  ): Promise<TraccarCommandResult> {
    return this.request<TraccarCommandResult>(
      server,
      '/api/commands/send',
      {
        method: 'POST',
        body: {
          deviceId: this.safeNumber(traccarDeviceId),
          type: input.type,
          attributes: input.attributes ?? {},
        },
      },
    );
  }

  private async request<T>(
    server: TraccarServer,
    path: string,
    options: RequestOptions = {},
  ): Promise<T> {
    const credentials = this.credentialCrypto.decrypt(
      server.encryptedCredentialReference,
    );
    const url = this.createUrl(server.baseUrl, path, options.query);
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      this.timeoutMs,
    );

    try {
      const response = await fetch(url, {
        method: options.method ?? 'GET',
        headers: this.headers(credentials, options.body !== undefined),
        body:
          options.body === undefined
            ? undefined
            : JSON.stringify(options.body),
        signal: controller.signal,
      });

      if (!response.ok) {
        const body = await response.text();

        throw new BadGatewayException({
          message: 'Traccar request failed.',
          traccarStatus: response.status,
          traccarBody: body.slice(0, 1000),
        });
      }

      if (response.status === 204) {
        return undefined as T;
      }

      const text = await response.text();

      if (!text) {
        return undefined as T;
      }

      return JSON.parse(text) as T;
    } catch (error) {
      if (
        error instanceof Error &&
        error.name === 'AbortError'
      ) {
        throw new GatewayTimeoutException(
          'Traccar request timed out.',
        );
      }

      if (
        error instanceof BadGatewayException ||
        error instanceof GatewayTimeoutException
      ) {
        throw error;
      }

      throw new BadGatewayException({
        message: 'Could not communicate with Traccar.',
        cause:
          error instanceof Error
            ? error.message
            : 'Unknown Traccar error',
      });
    } finally {
      clearTimeout(timeout);
    }
  }

  private createUrl(
    baseUrl: string,
    path: string,
    query?: Record<
      string,
      string | number | boolean | undefined
    >,
  ): string {
    const url = new URL(
      path,
      `${baseUrl.replace(/\/+$/, '')}/`,
    );

    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined) {
        url.searchParams.set(key, String(value));
      }
    }

    return url.toString();
  }

  private headers(
    credentials: TraccarCredentials,
    hasBody: boolean,
  ): Record<string, string> {
    const headers: Record<string, string> = {
      Accept: 'application/json',
    };

    if (hasBody) {
      headers['Content-Type'] = 'application/json';
    }

    if (credentials.token) {
      headers.Authorization = `Bearer ${credentials.token}`;
    } else if (
      credentials.username !== undefined &&
      credentials.password !== undefined
    ) {
      headers.Authorization = `Basic ${Buffer.from(
        `${credentials.username}:${credentials.password}`,
      ).toString('base64')}`;
    }

    return headers;
  }

  private safeNumber(value: bigint): number {
    const number = Number(value);

    if (!Number.isSafeInteger(number)) {
      throw new BadGatewayException(
        'Traccar identifier exceeds the JavaScript safe-integer range.',
      );
    }

    return number;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\common\tracking-access.service.ts" `
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
export class TrackingAccessService {
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

  actorOrganizationId(auth: AuthContext): string | undefined {
    return this.dealerScopeIds(auth)[0] ?? auth.organizationIds[0];
  }

  assertPlatform(auth: AuthContext): void {
    if (!this.isPlatformScoped(auth)) {
      throw new ForbiddenException(
        'This operation requires platform scope.',
      );
    }
  }

  customerWhere(auth: AuthContext): Prisma.CustomerWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const scopes: Prisma.CustomerWhereInput[] = [];
    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);

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

  vehicleWhere(auth: AuthContext): Prisma.VehicleWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  deviceWhere(auth: AuthContext): Prisma.DeviceWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      vehicleAssignments: {
        some: {
          status: 'ACTIVE',
          vehicle: this.vehicleWhere(auth),
        },
      },
    };
  }

  eventWhere(auth: AuthContext): Prisma.TrackingEventWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  geofenceWhere(auth: AuthContext): Prisma.GeofenceWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  notificationRuleWhere(
    auth: AuthContext,
  ): Prisma.NotificationRuleWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  notificationWhere(
    auth: AuthContext,
  ): Prisma.NotificationWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  commandWhere(
    auth: AuthContext,
  ): Prisma.DeviceCommandRequestWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      OR: [
        {
          vehicle: this.vehicleWhere(auth),
        },
        {
          device: this.deviceWhere(auth),
        },
      ],
    };
  }

  async assertCustomer(
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
        customer: {
          select: {
            managingDealerId: true,
            status: true,
          },
        },
      },
    });

    if (!vehicle) {
      throw new NotFoundException(
        'Vehicle was not found within the authenticated scope.',
      );
    }

    return vehicle;
  }

  async assertDevice(
    auth: AuthContext,
    deviceId: string,
  ): Promise<void> {
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

  async assertGeofence(
    auth: AuthContext,
    geofenceId: string,
  ): Promise<void> {
    const count = await this.prisma.geofence.count({
      where: {
        AND: [
          {
            id: geofenceId,
          },
          this.geofenceWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException(
        'Geofence was not found within the authenticated scope.',
      );
    }
  }

  async assertTrackingEvent(
    auth: AuthContext,
    eventId: string,
  ): Promise<void> {
    const count = await this.prisma.trackingEvent.count({
      where: {
        AND: [
          {
            id: eventId,
          },
          this.eventWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException(
        'Tracking event was not found within the authenticated scope.',
      );
    }
  }

  async assertNotification(
    auth: AuthContext,
    notificationId: string,
  ): Promise<void> {
    const count = await this.prisma.notification.count({
      where: {
        AND: [
          {
            id: notificationId,
          },
          this.notificationWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException(
        'Notification was not found within the authenticated scope.',
      );
    }
  }

  async assertCommand(
    auth: AuthContext,
    commandId: string,
  ): Promise<void> {
    const count = await this.prisma.deviceCommandRequest.count({
      where: {
        AND: [
          {
            id: commandId,
          },
          this.commandWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException(
        'Command was not found within the authenticated scope.',
      );
    }
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\common\tracking-code.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Injectable()
export class TrackingCodeService {
  server(): string {
    return this.create('TRS');
  }

  event(): string {
    return this.create('EVT');
  }

  geofence(): string {
    return this.create('GEO');
  }

  notificationRule(): string {
    return this.create('NTR');
  }

  notification(): string {
    return this.create('NTF');
  }

  command(): string {
    return this.create('CMD');
  }

  job(): string {
    return this.create('JOB');
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
        "services\backend-api\src\tracking\common\tracking-credential-crypto.service.spec.ts" `
        @'
import { ConfigService } from '@nestjs/config';
import { TrackingCredentialCryptoService } from './tracking-credential-crypto.service';

describe('TrackingCredentialCryptoService', () => {
  it('encrypts and decrypts Traccar credentials', () => {
    const config = {
      getOrThrow: () =>
        'solid-tracker-test-tracking-encryption-key-123456789',
    } as unknown as ConfigService;
    const service = new TrackingCredentialCryptoService(config);
    const encrypted = service.encrypt({
      username: 'api-user',
      password: 'api-password',
    });

    expect(encrypted).not.toContain('api-password');
    expect(service.decrypt(encrypted)).toEqual({
      username: 'api-user',
      password: 'api-password',
    });
  });
});
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\common\tracking-credential-crypto.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from 'node:crypto';

export interface TraccarCredentials {
  username?: string;
  password?: string;
  token?: string;
}

@Injectable()
export class TrackingCredentialCryptoService {
  private readonly key: Buffer;

  constructor(configService: ConfigService) {
    const source = configService.getOrThrow<string>(
      'TRACKING_CREDENTIAL_ENCRYPTION_KEY',
    );

    this.key = createHash('sha256').update(source).digest();
  }

  encrypt(credentials: TraccarCredentials): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const plaintext = Buffer.from(
      JSON.stringify(credentials),
      'utf8',
    );
    const encrypted = Buffer.concat([
      cipher.update(plaintext),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();

    return [
      'v1',
      iv.toString('base64url'),
      tag.toString('base64url'),
      encrypted.toString('base64url'),
    ].join('.');
  }

  decrypt(reference: string): TraccarCredentials {
    const [version, ivPart, tagPart, encryptedPart] =
      reference.split('.');

    if (
      version !== 'v1' ||
      !ivPart ||
      !tagPart ||
      !encryptedPart
    ) {
      throw new Error('Tracking credential reference is invalid.');
    }

    const decipher = createDecipheriv(
      'aes-256-gcm',
      this.key,
      Buffer.from(ivPart, 'base64url'),
    );

    decipher.setAuthTag(Buffer.from(tagPart, 'base64url'));

    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(encryptedPart, 'base64url')),
      decipher.final(),
    ]).toString('utf8');

    return JSON.parse(plaintext) as TraccarCredentials;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\common\tracking-json.util.ts" `
        @'
import type { Prisma } from '../../generated/prisma/client';

export function toInputJson(
  value: unknown,
): Prisma.InputJsonValue | undefined {
  if (value === undefined) {
    return undefined;
  }

  return JSON.parse(
    JSON.stringify(value, (_key, currentValue) =>
      typeof currentValue === 'bigint'
        ? currentValue.toString()
        : currentValue,
    ),
  ) as Prisma.InputJsonValue;
}

export function jsonSafe<T>(value: T): unknown {
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
        "services\backend-api\src\tracking\common\tracking-query.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';

const eventSeverities = ['INFO', 'WARNING', 'CRITICAL'] as const;
const eventProcessingStatuses = [
  'RECEIVED',
  'PROCESSING',
  'PROCESSED',
  'FAILED',
  'IGNORED',
] as const;
const geofenceStatuses = [
  'DRAFT',
  'ACTIVE',
  'INACTIVE',
  'ARCHIVED',
] as const;
const notificationStatuses = [
  'QUEUED',
  'PROCESSING',
  'SENT',
  'DELIVERED',
  'FAILED',
  'CANCELLED',
] as const;
const commandStatuses = [
  'PENDING_APPROVAL',
  'QUEUED',
  'SENT',
  'ACKNOWLEDGED',
  'COMPLETED',
  'FAILED',
  'CANCELLED',
  'EXPIRED',
] as const;
const integrationJobStatuses = [
  'PENDING',
  'PROCESSING',
  'SUCCEEDED',
  'FAILED',
  'CANCELLED',
  'DEAD_LETTER',
] as const;

export class PositionHistoryQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  to?: string;
}

export class TrackingEventQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  deviceId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  eventType?: string;

  @ApiPropertyOptional({ enum: eventSeverities })
  @IsOptional()
  @IsIn(eventSeverities)
  severity?: (typeof eventSeverities)[number];

  @ApiPropertyOptional({ enum: eventProcessingStatuses })
  @IsOptional()
  @IsIn(eventProcessingStatuses)
  processingStatus?: (typeof eventProcessingStatuses)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  to?: string;
}

export class GeofenceQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ enum: geofenceStatuses })
  @IsOptional()
  @IsIn(geofenceStatuses)
  status?: (typeof geofenceStatuses)[number];
}

export class NotificationRuleQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;
}

export class NotificationQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  trackingEventId?: string;

  @ApiPropertyOptional({ enum: notificationStatuses })
  @IsOptional()
  @IsIn(notificationStatuses)
  status?: (typeof notificationStatuses)[number];
}

export class CommandQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  deviceId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiPropertyOptional({ enum: commandStatuses })
  @IsOptional()
  @IsIn(commandStatuses)
  status?: (typeof commandStatuses)[number];
}

export class IntegrationJobQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: integrationJobStatuses })
  @IsOptional()
  @IsIn(integrationJobStatuses)
  status?: (typeof integrationJobStatuses)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  entityType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  entityId?: string;

  @ApiPropertyOptional({ default: 100, minimum: 1, maximum: 1000 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1000)
  priority?: number;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\devices\device-tracking.controller.ts" `
        @'
import {
  Body,
  Controller,
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
import { DeviceTrackingService } from './device-tracking.service';
import { SyncTrackingDeviceDto } from './dto/sync-tracking-device.dto';

@ApiTags('Tracking - Device Synchronization')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/devices')
export class DeviceTrackingController {
  constructor(
    private readonly deviceTrackingService: DeviceTrackingService,
  ) {}

  @Get(':deviceId/mappings')
  @RequirePermissions('device.view')
  @ApiOperation({ summary: 'Read Traccar mappings for a device' })
  mapping(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
  ) {
    return this.deviceTrackingService.mapping(auth, deviceId);
  }

  @Post(':deviceId/sync')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Synchronize a device with Traccar' })
  sync(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
    @Body() dto: SyncTrackingDeviceDto,
  ) {
    return this.deviceTrackingService.sync(
      auth,
      deviceId,
      dto,
    );
  }

  @Post(':deviceId/disable')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Disable a device in Traccar' })
  disable(
    @CurrentAuth() auth: AuthContext,
    @Param('deviceId', new ParseUUIDPipe()) deviceId: string,
  ) {
    return this.deviceTrackingService.disable(auth, deviceId);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\devices\device-tracking.service.ts" `
        @'
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { jsonSafe } from '../common/tracking-json.util';
import { TraccarClientService } from '../common/traccar-client.service';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import { TraccarServersService } from '../servers/traccar-servers.service';
import type { SyncTrackingDeviceDto } from './dto/sync-tracking-device.dto';

@Injectable()
export class DeviceTrackingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly client: TraccarClientService,
    private readonly servers: TraccarServersService,
    private readonly jobs: IntegrationJobsService,
    private readonly auditService: AuditService,
  ) {}

  async mapping(auth: AuthContext, deviceId: string) {
    await this.access.assertDevice(auth, deviceId);

    const mappings = await this.prisma.traccarDeviceMapping.findMany({
      where: {
        deviceId,
      },
      orderBy: [
        {
          isActive: 'desc',
        },
        {
          isPrimary: 'desc',
        },
        {
          createdAt: 'desc',
        },
      ],
      include: {
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
            baseUrl: true,
            status: true,
            lastHealthStatus: true,
          },
        },
      },
    });

    return jsonSafe(mappings);
  }

  async sync(auth: AuthContext, deviceId: string, dto: SyncTrackingDeviceDto) {
    this.access.assertPlatform(auth);

    const device = await this.prisma.device.findUnique({
      where: {
        id: deviceId,
      },
      include: {
        deviceModel: true,
        vehicleAssignments: {
          where: {
            status: 'ACTIVE',
          },
          include: {
            vehicle: true,
          },
          take: 1,
        },
      },
    });

    if (!device) {
      throw new NotFoundException('Device was not found.');
    }

    if (['LOST', 'DAMAGED', 'RETIRED'].includes(device.lifecycleStatus)) {
      throw new ConflictException('This device lifecycle state cannot be synchronized.');
    }

    const uniqueId = device.imei ?? device.serialNumber;

    if (!uniqueId) {
      throw new BadRequestException(
        'The device requires an IMEI or serial number before Traccar synchronization.',
      );
    }

    const server = dto.serverId
      ? await this.prisma.traccarServer.findFirst({
          where: {
            id: dto.serverId,
            status: {
              in: ['ACTIVE', 'DEGRADED'],
            },
          },
        })
      : await this.servers.defaultActive();

    if (!server) {
      throw new NotFoundException('The selected active Traccar server was not found.');
    }

    const job = await this.jobs.create({
      jobType: 'SYNC_DEVICE',
      traccarServerId: server.id,
      entityType: 'Device',
      entityId: deviceId,
      idempotencyKey: dto.forceUpdate
        ? undefined
        : `sync-device:${deviceId}:${server.id}:${device.updatedAt.toISOString()}`,
      payload: {
        uniqueId,
        forceUpdate: dto.forceUpdate ?? false,
      },
    });

    if (job.status === 'SUCCEEDED') {
      const existing = await this.prisma.traccarDeviceMapping.findUnique({
        where: {
          deviceId_traccarServerId: {
            deviceId,
            traccarServerId: server.id,
          },
        },
        include: {
          traccarServer: true,
        },
      });

      return jsonSafe({
        mapping: existing,
        job,
        reused: true,
      });
    }

    await this.jobs.processing(job.id);

    try {
      const matches = await this.client.findDeviceByUniqueId(server, uniqueId);
      const assignedVehicle = device.vehicleAssignments[0]?.vehicle;
      const name =
        assignedVehicle?.registrationNumber ?? assignedVehicle?.vehicleCode ?? device.deviceCode;

      let externalDevice = matches[0];

      if (externalDevice) {
        externalDevice = await this.client.updateDevice(server, BigInt(externalDevice.id), {
          id: externalDevice.id,
          name,
          uniqueId,
          disabled: false,
          category: device.deviceModel.modelName.toLowerCase().includes('motor')
            ? 'motorcycle'
            : 'car',
          attributes: {
            solidTrackerDeviceId: device.id,
            solidTrackerDeviceCode: device.deviceCode,
            hardwareVersion: device.hardwareVersion,
            firmwareVersion: device.firmwareVersion,
          },
        });
      } else {
        externalDevice = await this.client.createDevice(server, {
          name,
          uniqueId,
          disabled: false,
          category: device.deviceModel.modelName.toLowerCase().includes('motor')
            ? 'motorcycle'
            : 'car',
          attributes: {
            solidTrackerDeviceId: device.id,
            solidTrackerDeviceCode: device.deviceCode,
            hardwareVersion: device.hardwareVersion,
            firmwareVersion: device.firmwareVersion,
          },
        });
      }

      const now = new Date();

      const mapping = await this.prisma.$transaction(async (transaction) => {
        await transaction.traccarDeviceMapping.updateMany({
          where: {
            deviceId,
            isActive: true,
            isPrimary: true,
            NOT: {
              traccarServerId: server.id,
            },
          },
          data: {
            isActive: false,
            isPrimary: false,
            syncStatus: 'DISABLED',
            disabledAt: now,
          },
        });

        return transaction.traccarDeviceMapping.upsert({
          where: {
            deviceId_traccarServerId: {
              deviceId,
              traccarServerId: server.id,
            },
          },
          create: {
            deviceId,
            traccarServerId: server.id,
            traccarDeviceId: BigInt(externalDevice.id),
            traccarUniqueId: externalDevice.uniqueId,
            syncStatus: 'SYNCED',
            isPrimary: true,
            isActive: true,
            lastSyncAttemptAt: now,
            lastSyncedAt: now,
            lastSyncError: null,
          },
          update: {
            traccarDeviceId: BigInt(externalDevice.id),
            traccarUniqueId: externalDevice.uniqueId,
            syncStatus: 'SYNCED',
            isPrimary: true,
            isActive: true,
            lastSyncAttemptAt: now,
            lastSyncedAt: now,
            lastSyncError: null,
            disabledAt: null,
          },
          include: {
            traccarServer: true,
          },
        });
      });

      await this.jobs.succeeded(job.id, {
        traccarDeviceId: externalDevice.id,
        mappingId: mapping.id,
      });

      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId: this.access.actorOrganizationId(auth),
        action: 'tracking.device.synchronized',
        resourceType: 'TraccarDeviceMapping',
        resourceId: mapping.id,
        scopeType: 'PLATFORM',
        afterData: jsonSafe(mapping),
      });

      return jsonSafe({
        mapping,
        jobId: job.id,
        reused: false,
      });
    } catch (error) {
      await this.jobs.failed(job.id, error);

      await this.prisma.traccarDeviceMapping.updateMany({
        where: {
          deviceId,
          traccarServerId: server.id,
        },
        data: {
          syncStatus: 'FAILED',
          lastSyncAttemptAt: new Date(),
          lastSyncError: error instanceof Error ? error.message : 'Unknown synchronization error',
        },
      });

      throw error;
    }
  }

  async disable(auth: AuthContext, deviceId: string) {
    this.access.assertPlatform(auth);

    const mapping = await this.prisma.traccarDeviceMapping.findFirst({
      where: {
        deviceId,
        isActive: true,
        isPrimary: true,
      },
      include: {
        traccarServer: true,
        device: {
          include: {
            vehicleAssignments: {
              where: {
                status: 'ACTIVE',
              },
              include: {
                vehicle: true,
              },
              take: 1,
            },
          },
        },
      },
    });

    if (!mapping) {
      throw new NotFoundException('An active primary Traccar mapping was not found.');
    }

    const job = await this.jobs.create({
      jobType: 'DISABLE_DEVICE',
      traccarServerId: mapping.traccarServerId,
      entityType: 'Device',
      entityId: deviceId,
      idempotencyKey: `disable-device:${mapping.id}:${mapping.updatedAt.toISOString()}`,
    });

    await this.jobs.processing(job.id);

    try {
      const assignedVehicle = mapping.device.vehicleAssignments[0]?.vehicle;

      await this.client.updateDevice(mapping.traccarServer, mapping.traccarDeviceId, {
        id: Number(mapping.traccarDeviceId),
        name:
          assignedVehicle?.registrationNumber ??
          assignedVehicle?.vehicleCode ??
          mapping.device.deviceCode,
        uniqueId: mapping.traccarUniqueId,
        disabled: true,
        attributes: {
          solidTrackerDeviceId: deviceId,
        },
      });

      const updated = await this.prisma.traccarDeviceMapping.update({
        where: {
          id: mapping.id,
        },
        data: {
          syncStatus: 'DISABLED',
          isActive: false,
          isPrimary: false,
          disabledAt: new Date(),
          lastSyncAttemptAt: new Date(),
          lastSyncedAt: new Date(),
          lastSyncError: null,
        },
      });

      await this.jobs.succeeded(job.id, {
        mappingId: mapping.id,
      });

      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId: this.access.actorOrganizationId(auth),
        action: 'tracking.device.disabled',
        resourceType: 'TraccarDeviceMapping',
        resourceId: mapping.id,
        scopeType: 'PLATFORM',
        afterData: jsonSafe(updated),
      });

      return jsonSafe(updated);
    } catch (error) {
      await this.jobs.failed(job.id, error);
      throw error;
    }
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\devices\dto\sync-tracking-device.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsUUID } from 'class-validator';

export class SyncTrackingDeviceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  serverId?: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  forceUpdate?: boolean;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\events\dto\traccar-webhook.dto.ts" `
        @'
import { ApiProperty } from '@nestjs/swagger';
import {
  IsObject,
  IsString,
  MaxLength,
} from 'class-validator';

export class TraccarWebhookDto {
  @ApiProperty()
  @IsString()
  @MaxLength(60)
  serverCode!: string;

  @ApiProperty()
  @IsObject()
  event!: Record<string, unknown>;

  @ApiProperty()
  @IsObject()
  device!: Record<string, unknown>;

  @ApiProperty()
  @IsObject()
  position!: Record<string, unknown>;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\events\tracking-events.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiHeader,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { TrackingEventQueryDto } from '../common/tracking-query.dto';
import { TraccarWebhookDto } from './dto/traccar-webhook.dto';
import { TrackingEventsService } from './tracking-events.service';
import { TrackingWebhookGuard } from './tracking-webhook.guard';

@ApiTags('Tracking - Events')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/events')
export class TrackingEventsController {
  constructor(
    private readonly trackingEventsService: TrackingEventsService,
  ) {}

  @Get()
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'List normalized tracking events' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: TrackingEventQueryDto,
  ) {
    return this.trackingEventsService.list(auth, query);
  }

  @Get(':eventId')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'Read one normalized tracking event' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('eventId', new ParseUUIDPipe()) eventId: string,
  ) {
    return this.trackingEventsService.get(auth, eventId);
  }

  @Post(':eventId/acknowledge')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'Acknowledge a tracking event' })
  acknowledge(
    @CurrentAuth() auth: AuthContext,
    @Param('eventId', new ParseUUIDPipe()) eventId: string,
  ) {
    return this.trackingEventsService.acknowledge(
      auth,
      eventId,
    );
  }
}

@ApiTags('Tracking - Webhooks')
@Controller('tracking/webhooks')
export class TrackingWebhooksController {
  constructor(
    private readonly trackingEventsService: TrackingEventsService,
  ) {}

  @Post('traccar')
  @UseGuards(TrackingWebhookGuard)
  @ApiHeader({
    name: 'X-Tracking-Webhook-Secret',
    required: true,
  })
  @ApiOperation({
    summary:
      'Receive and normalize a Traccar event webhook securely',
  })
  ingest(@Body() dto: TraccarWebhookDto) {
    return this.trackingEventsService.ingest(dto);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\events\tracking-events.service.ts" `
        @'
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type { TrackingEventQueryDto } from '../common/tracking-query.dto';
import { jsonSafe, toInputJson } from '../common/tracking-json.util';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import { NotificationsService } from '../notifications/notifications.service';
import type { TraccarWebhookDto } from './dto/traccar-webhook.dto';

@Injectable()
export class TrackingEventsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly jobs: IntegrationJobsService,
    private readonly notifications: NotificationsService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: TrackingEventQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.eventWhere(auth);
    const occurredAt = query.from || query.to
        ? {
            gte: query.from ? new Date(query.from) : undefined,
            lte: query.to ? new Date(query.to) : undefined,
          }
        : undefined;

    const where: Prisma.TrackingEventWhereInput = {
      AND: [
        scopeWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.vehicleId
          ? {
              vehicleId: query.vehicleId,
            }
          : {},
        query.deviceId
          ? {
              deviceId: query.deviceId,
            }
          : {},
        query.eventType
          ? {
              eventType: query.eventType,
            }
          : {},
        query.severity
          ? {
              severity: query.severity,
            }
          : {},
        query.processingStatus
          ? {
              processingStatus: query.processingStatus,
            }
          : {},
        occurredAt
          ? {
              occurredAt,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  eventCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  eventType: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  deduplicationKey: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.trackingEvent.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          occurredAt: 'desc',
        },
        include: {
          customer: true,
          vehicle: true,
          device: true,
          traccarServer: {
            select: {
              id: true,
              serverCode: true,
              name: true,
            },
          },
          acknowledgedBy: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
          _count: {
            select: {
              notifications: true,
            },
          },
        },
      }),
      this.prisma.trackingEvent.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async get(auth: AuthContext, eventId: string) {
    await this.access.assertTrackingEvent(auth, eventId);

    const event = await this.prisma.trackingEvent.findUnique({
      where: {
        id: eventId,
      },
      include: {
        customer: true,
        vehicle: true,
        device: true,
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
          },
        },
        acknowledgedBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
        notifications: true,
      },
    });

    return jsonSafe(event);
  }

  async acknowledge(auth: AuthContext, eventId: string) {
    await this.access.assertTrackingEvent(auth, eventId);

    const before = await this.prisma.trackingEvent.findUnique({
      where: {
        id: eventId,
      },
    });

    if (!before) {
      throw new NotFoundException('Tracking event was not found.');
    }

    const updated = await this.prisma.trackingEvent.update({
      where: {
        id: eventId,
      },
      data: {
        acknowledgedAt: before.acknowledgedAt ?? new Date(),
        acknowledgedByUserId:
          before.acknowledgedByUserId ?? auth.userId,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.event.acknowledged',
      resourceType: 'TrackingEvent',
      resourceId: eventId,
      scopeType: 'VEHICLE',
      scopeId: updated.vehicleId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async ingest(dto: TraccarWebhookDto) {
    const server = await this.prisma.traccarServer.findFirst({
      where: {
        serverCode: dto.serverCode,
        status: {
          in: ['ACTIVE', 'DEGRADED', 'MAINTENANCE'],
        },
      },
    });

    if (!server) {
      throw new NotFoundException(
        'Webhook Traccar server was not found.',
      );
    }

    const externalDeviceId = this.bigInt(
      dto.device.id ?? dto.event.deviceId,
      'device.id',
    );
    const uniqueId = this.stringValue(dto.device.uniqueId);
    const mappingConditions: Prisma.TraccarDeviceMappingWhereInput[] = [
      {
        traccarDeviceId: externalDeviceId,
      },
    ];

    if (uniqueId) {
      mappingConditions.push({
        traccarUniqueId: uniqueId,
      });
    }

    const mapping =
      await this.prisma.traccarDeviceMapping.findFirst({
        where: {
          traccarServerId: server.id,
          isActive: true,
          OR: mappingConditions,
        },
      });

    if (!mapping) {
      throw new NotFoundException(
        'Webhook device does not have an active Solid Tracker mapping.',
      );
    }

    const assignment =
      await this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          deviceId: mapping.deviceId,
          status: 'ACTIVE',
        },
        include: {
          vehicle: true,
        },
      });

    if (!assignment) {
      throw new BadRequestException(
        'Webhook device is not actively assigned to a vehicle.',
      );
    }

    const eventType =
      this.stringValue(dto.event.type) ?? 'unknown';
    const occurredAt = this.dateValue(
      dto.event.eventTime ??
        dto.position.fixTime ??
        dto.position.deviceTime ??
        dto.position.serverTime,
    );
    const traccarEventId = this.optionalBigInt(dto.event.id);
    const deduplicationKey = traccarEventId
      ? `${server.id}:${traccarEventId.toString()}`
      : this.fallbackDeduplicationKey({
          serverId: server.id,
          deviceId: mapping.deviceId,
          eventType,
          occurredAt,
          positionId: dto.position.id,
        });

    const existing =
      await this.prisma.trackingEvent.findUnique({
        where: {
          deduplicationKey,
        },
      });

    if (existing) {
      return jsonSafe({
        event: existing,
        duplicate: true,
      });
    }

    const job = await this.jobs.create({
      jobType: 'PROCESS_EVENT',
      traccarServerId: server.id,
      entityType: 'TraccarEvent',
      entityId:
        traccarEventId?.toString() ?? deduplicationKey,
      idempotencyKey: `process-event:${deduplicationKey}`,
      payload: dto,
      correlationId: deduplicationKey.slice(0, 100),
    });

    await this.jobs.processing(job.id);

    const event = await this.prisma.trackingEvent.create({
      data: {
        eventCode: this.codes.event(),
        customerId: assignment.vehicle.customerId,
        vehicleId: assignment.vehicleId,
        deviceId: mapping.deviceId,
        traccarServerId: server.id,
        traccarEventId,
        deduplicationKey,
        eventType,
        severity: this.severity(eventType, dto.event.attributes),
        latitude: this.optionalNumber(dto.position.latitude),
        longitude: this.optionalNumber(dto.position.longitude),
        occurredAt,
        attributes: toInputJson({
          event: dto.event,
          position: dto.position,
          device: {
            id: dto.device.id,
            uniqueId: dto.device.uniqueId,
            name: dto.device.name,
          },
        }),
        processingStatus: 'PROCESSING',
      },
    });

    try {
      const notifications =
        await this.notifications.enqueueForEvent(event);
      const processed = await this.prisma.trackingEvent.update({
        where: {
          id: event.id,
        },
        data: {
          processingStatus: 'PROCESSED',
          processingError: null,
        },
      });

      await this.jobs.succeeded(job.id, {
        trackingEventId: event.id,
        notificationCount: notifications.length,
      });

      return jsonSafe({
        event: processed,
        notifications,
        duplicate: false,
      });
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : 'Unknown event-processing error';

      await this.prisma.trackingEvent.update({
        where: {
          id: event.id,
        },
        data: {
          processingStatus: 'FAILED',
          processingError: message,
        },
      });

      await this.jobs.failed(job.id, error);
      throw error;
    }
  }

  private severity(
    eventType: string,
    attributes: unknown,
  ): 'INFO' | 'WARNING' | 'CRITICAL' {
    const normalized = eventType.toLowerCase();
    const alarm =
      attributes &&
      typeof attributes === 'object' &&
      'alarm' in attributes
        ? String(
            (attributes as Record<string, unknown>).alarm,
          ).toLowerCase()
        : '';

    if (
      normalized.includes('sos') ||
      normalized.includes('panic') ||
      normalized.includes('tamper') ||
      alarm.includes('sos') ||
      alarm.includes('panic')
    ) {
      return 'CRITICAL';
    }

    if (
      normalized.includes('overspeed') ||
      normalized.includes('geofence') ||
      normalized.includes('offline') ||
      normalized.includes('alarm') ||
      alarm.length > 0
    ) {
      return 'WARNING';
    }

    return 'INFO';
  }

  private fallbackDeduplicationKey(input: {
    serverId: string;
    deviceId: string;
    eventType: string;
    occurredAt: Date;
    positionId: unknown;
  }): string {
    return createHash('sha256')
      .update(
        JSON.stringify({
          ...input,
          occurredAt: input.occurredAt.toISOString(),
        }),
      )
      .digest('hex');
  }

  private bigInt(value: unknown, field: string): bigint {
    const parsed = this.optionalBigInt(value);

    if (parsed === null) {
      throw new BadRequestException(
        `${field} must be a valid integer.`,
      );
    }

    return parsed;
  }

  private optionalBigInt(value: unknown): bigint | null {
    if (
      typeof value === 'bigint' ||
      typeof value === 'number' ||
      typeof value === 'string'
    ) {
      try {
        return BigInt(value);
      } catch {
        return null;
      }
    }

    return null;
  }

  private stringValue(value: unknown): string | null {
    return typeof value === 'string' && value.trim()
      ? value.trim()
      : null;
  }

  private dateValue(value: unknown): Date {
    const date =
      value instanceof Date
        ? new Date(value.getTime())
        : typeof value === 'string' ||
            typeof value === 'number'
          ? new Date(value)
          : new Date();

    if (Number.isNaN(date.getTime())) {
      throw new BadRequestException(
        'Webhook event time is invalid.',
      );
    }

    return date;
  }

  private optionalNumber(value: unknown): number | undefined {
    const number =
      typeof value === 'number'
        ? value
        : typeof value === 'string'
          ? Number(value)
          : Number.NaN;

    return Number.isFinite(number) ? number : undefined;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\events\tracking-webhook.guard.ts" `
        @'
import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { timingSafeEqual } from 'node:crypto';

@Injectable()
export class TrackingWebhookGuard implements CanActivate {
  private readonly expectedSecret: Buffer;

  constructor(configService: ConfigService) {
    this.expectedSecret = Buffer.from(
      configService.getOrThrow<string>(
        'TRACKING_WEBHOOK_SECRET',
      ),
      'utf8',
    );
  }

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<{
      headers: Record<string, string | string[] | undefined>;
    }>();
    const header = request.headers['x-tracking-webhook-secret'];
    const supplied = Array.isArray(header) ? header[0] : header;

    if (!supplied) {
      throw new UnauthorizedException(
        'Tracking webhook secret is required.',
      );
    }

    const actual = Buffer.from(supplied, 'utf8');

    if (
      actual.length !== this.expectedSecret.length ||
      !timingSafeEqual(actual, this.expectedSecret)
    ) {
      throw new UnauthorizedException(
        'Tracking webhook secret is invalid.',
      );
    }

    return true;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\geofences\dto\assign-geofence.dto.ts" `
        @'
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsDateString,
  IsOptional,
  IsUUID,
} from 'class-validator';

export class AssignGeofenceDto {
  @ApiProperty()
  @IsUUID()
  vehicleId!: string;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  monitorEntry?: boolean;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  monitorExit?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  activeFrom?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  activeUntil?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\geofences\dto\create-geofence.dto.ts" `
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
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

const geometryTypes = [
  'CIRCLE',
  'POLYGON',
  'POLYLINE',
] as const;
const statuses = ['DRAFT', 'ACTIVE', 'INACTIVE'] as const;

export class CreateGeofenceDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiProperty({ enum: geometryTypes })
  @IsIn(geometryTypes)
  geometryType!: (typeof geometryTypes)[number];

  @ApiProperty({
    description:
      'CIRCLE uses {center:{latitude,longitude},radius}; POLYGON and POLYLINE use {points:[{latitude,longitude}]}',
  })
  @IsObject()
  geometryData!: Record<string, unknown>;

  @ApiPropertyOptional({ enum: statuses, default: 'DRAFT' })
  @IsOptional()
  @IsIn(statuses)
  status?: (typeof statuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\geofences\dto\sync-geofence.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsUUID } from 'class-validator';

export class SyncGeofenceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  serverId?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\geofences\dto\update-geofence.dto.ts" `
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

const geometryTypes = [
  'CIRCLE',
  'POLYGON',
  'POLYLINE',
] as const;
const statuses = ['DRAFT', 'ACTIVE', 'INACTIVE'] as const;

export class UpdateGeofenceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiPropertyOptional({ enum: geometryTypes })
  @IsOptional()
  @IsIn(geometryTypes)
  geometryType?: (typeof geometryTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  geometryData?: Record<string, unknown>;

  @ApiPropertyOptional({ enum: statuses })
  @IsOptional()
  @IsIn(statuses)
  status?: (typeof statuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\geofences\geofences.controller.ts" `
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
import { GeofenceQueryDto } from '../common/tracking-query.dto';
import { AssignGeofenceDto } from './dto/assign-geofence.dto';
import { CreateGeofenceDto } from './dto/create-geofence.dto';
import { SyncGeofenceDto } from './dto/sync-geofence.dto';
import { UpdateGeofenceDto } from './dto/update-geofence.dto';
import { GeofencesService } from './geofences.service';

@ApiTags('Tracking - Geofences')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/geofences')
export class GeofencesController {
  constructor(private readonly geofencesService: GeofencesService) {}

  @Get()
  @RequirePermissions('vehicle.view')
  @ApiOperation({ summary: 'List geofences within scope' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: GeofenceQueryDto,
  ) {
    return this.geofencesService.list(auth, query);
  }

  @Post()
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Create a customer geofence' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateGeofenceDto,
  ) {
    return this.geofencesService.create(auth, dto);
  }

  @Get(':geofenceId')
  @RequirePermissions('vehicle.view')
  @ApiOperation({ summary: 'Read one geofence' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
  ) {
    return this.geofencesService.get(auth, geofenceId);
  }

  @Patch(':geofenceId')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Update a geofence' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
    @Body() dto: UpdateGeofenceDto,
  ) {
    return this.geofencesService.update(
      auth,
      geofenceId,
      dto,
    );
  }

  @Post(':geofenceId/archive')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Archive a geofence' })
  archive(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
  ) {
    return this.geofencesService.archive(auth, geofenceId);
  }

  @Post(':geofenceId/sync')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Synchronize a geofence to Traccar' })
  sync(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
    @Body() dto: SyncGeofenceDto,
  ) {
    return this.geofencesService.sync(
      auth,
      geofenceId,
      dto,
    );
  }

  @Post(':geofenceId/assignments')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Assign a vehicle to a geofence' })
  assign(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
    @Body() dto: AssignGeofenceDto,
  ) {
    return this.geofencesService.assign(
      auth,
      geofenceId,
      dto,
    );
  }

  @Post(':geofenceId/assignments/:vehicleId/end')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'End a vehicle geofence assignment' })
  unassign(
    @CurrentAuth() auth: AuthContext,
    @Param('geofenceId', new ParseUUIDPipe())
    geofenceId: string,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
  ) {
    return this.geofencesService.unassign(
      auth,
      geofenceId,
      vehicleId,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\geofences\geofences.service.ts" `
        @'
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type {
  Prisma,
  TraccarServer,
} from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type { GeofenceQueryDto } from '../common/tracking-query.dto';
import { jsonSafe, toInputJson } from '../common/tracking-json.util';
import { TraccarClientService } from '../common/traccar-client.service';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';
import { TraccarServersService } from '../servers/traccar-servers.service';
import type { AssignGeofenceDto } from './dto/assign-geofence.dto';
import type { CreateGeofenceDto } from './dto/create-geofence.dto';
import type { SyncGeofenceDto } from './dto/sync-geofence.dto';
import type { UpdateGeofenceDto } from './dto/update-geofence.dto';

interface Coordinate {
  latitude: number;
  longitude: number;
}

@Injectable()
export class GeofencesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly client: TraccarClientService,
    private readonly servers: TraccarServersService,
    private readonly jobs: IntegrationJobsService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: GeofenceQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.geofenceWhere(auth);
    const where: Prisma.GeofenceWhereInput = {
      AND: [
        scopeWhere,
        query.customerId
          ? {
              customerId: query.customerId,
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
        query.search
          ? {
              OR: [
                {
                  geofenceCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  name: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  description: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.geofence.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          customer: true,
          traccarServer: {
            select: {
              id: true,
              serverCode: true,
              name: true,
              status: true,
            },
          },
          assignments: {
            where: {
              status: 'ACTIVE',
            },
            include: {
              vehicle: true,
            },
          },
        },
      }),
      this.prisma.geofence.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async get(auth: AuthContext, geofenceId: string) {
    await this.access.assertGeofence(auth, geofenceId);

    const geofence = await this.prisma.geofence.findUnique({
      where: {
        id: geofenceId,
      },
      include: {
        customer: true,
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
            status: true,
          },
        },
        createdBy: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
          },
        },
        assignments: {
          orderBy: {
            createdAt: 'desc',
          },
          include: {
            vehicle: true,
          },
        },
      },
    });

    return jsonSafe(geofence);
  }

  async create(auth: AuthContext, dto: CreateGeofenceDto) {
    await this.access.assertCustomer(auth, dto.customerId);
    this.validateGeometry(dto.geometryType, dto.geometryData);
    const normalizedName = this.normalizeName(dto.name);

    const duplicate = await this.prisma.geofence.findUnique({
      where: {
        customerId_normalizedName: {
          customerId: dto.customerId,
          normalizedName,
        },
      },
      select: {
        id: true,
      },
    });

    if (duplicate) {
      throw new ConflictException(
        'A geofence with this name already exists for the customer.',
      );
    }

    const geometryData = toInputJson(dto.geometryData);

    if (!geometryData) {
      throw new BadRequestException(
        'Geofence geometry data is required.',
      );
    }

    const geofence = await this.prisma.geofence.create({
      data: {
        geofenceCode: this.codes.geofence(),
        customerId: dto.customerId,
        name: dto.name.trim(),
        normalizedName,
        description: dto.description?.trim() || null,
        geometryType: dto.geometryType,
        geometryData,
        status: dto.status ?? 'DRAFT',
        syncStatus: 'PENDING',
        createdByUserId: auth.userId,
      },
      include: {
        customer: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.created',
      resourceType: 'Geofence',
      resourceId: geofence.id,
      scopeType: 'CUSTOMER',
      scopeId: geofence.customerId,
      afterData: jsonSafe(geofence),
    });

    return jsonSafe(geofence);
  }

  async update(
    auth: AuthContext,
    geofenceId: string,
    dto: UpdateGeofenceDto,
  ) {
    await this.access.assertGeofence(auth, geofenceId);
    const before = await this.prisma.geofence.findUnique({
      where: {
        id: geofenceId,
      },
    });

    if (!before) {
      throw new NotFoundException('Geofence was not found.');
    }

    const geometryType =
      dto.geometryType ?? before.geometryType;
    const geometryData =
      dto.geometryData ??
      (before.geometryData as Record<string, unknown>);

    this.validateGeometry(geometryType, geometryData);

    const updated = await this.prisma.geofence.update({
      where: {
        id: geofenceId,
      },
      data: {
        name: dto.name?.trim(),
        normalizedName:
          dto.name !== undefined
            ? this.normalizeName(dto.name)
            : undefined,
        description:
          dto.description !== undefined
            ? dto.description.trim() || null
            : undefined,
        geometryType: dto.geometryType,
        geometryData:
          dto.geometryData !== undefined
            ? toInputJson(dto.geometryData)
            : undefined,
        status: dto.status,
        syncStatus:
          dto.name !== undefined ||
          dto.description !== undefined ||
          dto.geometryType !== undefined ||
          dto.geometryData !== undefined
            ? 'PENDING'
            : undefined,
        lastSyncError:
          dto.name !== undefined ||
          dto.description !== undefined ||
          dto.geometryType !== undefined ||
          dto.geometryData !== undefined
            ? null
            : undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.updated',
      resourceType: 'Geofence',
      resourceId: geofenceId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async archive(auth: AuthContext, geofenceId: string) {
    await this.access.assertGeofence(auth, geofenceId);

    const activeAssignments =
      await this.prisma.vehicleGeofenceAssignment.count({
        where: {
          geofenceId,
          status: 'ACTIVE',
        },
      });

    if (activeAssignments > 0) {
      throw new ConflictException(
        'End active vehicle assignments before archiving the geofence.',
      );
    }

    const before = await this.prisma.geofence.findUniqueOrThrow({
      where: {
        id: geofenceId,
      },
    });

    const updated = await this.prisma.geofence.update({
      where: {
        id: geofenceId,
      },
      data: {
        status: 'ARCHIVED',
        archivedAt: new Date(),
        syncStatus: 'DISABLED',
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.archived',
      resourceType: 'Geofence',
      resourceId: geofenceId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async assign(
    auth: AuthContext,
    geofenceId: string,
    dto: AssignGeofenceDto,
  ) {
    await this.access.assertGeofence(auth, geofenceId);
    const vehicle = await this.access.assertVehicle(
      auth,
      dto.vehicleId,
    );
    const geofence = await this.prisma.geofence.findUniqueOrThrow({
      where: {
        id: geofenceId,
      },
      include: {
        traccarServer: true,
      },
    });

    if (geofence.customerId !== vehicle.customerId) {
      throw new BadRequestException(
        'Geofence and vehicle must belong to the same customer.',
      );
    }

    const activeFrom = dto.activeFrom
      ? new Date(dto.activeFrom)
      : new Date();
    const activeUntil = dto.activeUntil
      ? new Date(dto.activeUntil)
      : null;

    if (activeUntil && activeUntil <= activeFrom) {
      throw new BadRequestException(
        'Geofence assignment end must be after its start.',
      );
    }

    const existing =
      await this.prisma.vehicleGeofenceAssignment.findFirst({
        where: {
          geofenceId,
          vehicleId: dto.vehicleId,
          status: 'ACTIVE',
        },
      });

    if (existing) {
      throw new ConflictException(
        'This vehicle already has an active assignment to the geofence.',
      );
    }

    const assignment =
      await this.prisma.vehicleGeofenceAssignment.create({
        data: {
          geofenceId,
          vehicleId: dto.vehicleId,
          monitorEntry: dto.monitorEntry ?? true,
          monitorExit: dto.monitorExit ?? true,
          activeFrom,
          activeUntil,
          status: 'ACTIVE',
        },
        include: {
          geofence: true,
          vehicle: true,
        },
      });

    if (
      geofence.traccarServer &&
      geofence.traccarGeofenceId &&
      geofence.syncStatus === 'SYNCED'
    ) {
      await this.linkVehicle(
        dto.vehicleId,
        geofence.traccarServer,
        geofence.traccarGeofenceId,
      );
    }

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.assigned',
      resourceType: 'VehicleGeofenceAssignment',
      resourceId: assignment.id,
      scopeType: 'VEHICLE',
      scopeId: dto.vehicleId,
      afterData: jsonSafe(assignment),
    });

    return jsonSafe(assignment);
  }

  async unassign(
    auth: AuthContext,
    geofenceId: string,
    vehicleId: string,
  ) {
    await this.access.assertGeofence(auth, geofenceId);
    await this.access.assertVehicle(auth, vehicleId);

    const assignment =
      await this.prisma.vehicleGeofenceAssignment.findFirst({
        where: {
          geofenceId,
          vehicleId,
          status: 'ACTIVE',
        },
        include: {
          geofence: {
            include: {
              traccarServer: true,
            },
          },
        },
      });

    if (!assignment) {
      throw new NotFoundException(
        'Active geofence assignment was not found.',
      );
    }

    if (
      assignment.geofence.traccarServer &&
      assignment.geofence.traccarGeofenceId &&
      assignment.geofence.syncStatus === 'SYNCED'
    ) {
      await this.unlinkVehicle(
        vehicleId,
        assignment.geofence.traccarServer,
        assignment.geofence.traccarGeofenceId,
      );
    }

    const updated =
      await this.prisma.vehicleGeofenceAssignment.update({
        where: {
          id: assignment.id,
        },
        data: {
          status: 'ENDED',
          activeUntil: new Date(),
        },
      });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.geofence.unassigned',
      resourceType: 'VehicleGeofenceAssignment',
      resourceId: assignment.id,
      scopeType: 'VEHICLE',
      scopeId: vehicleId,
      beforeData: jsonSafe(assignment),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async sync(
    auth: AuthContext,
    geofenceId: string,
    dto: SyncGeofenceDto,
  ) {
    this.access.assertPlatform(auth);

    const geofence = await this.prisma.geofence.findUnique({
      where: {
        id: geofenceId,
      },
      include: {
        assignments: {
          where: {
            status: 'ACTIVE',
          },
        },
      },
    });

    if (!geofence || geofence.status === 'ARCHIVED') {
      throw new NotFoundException(
        'Active geofence was not found.',
      );
    }

    const server = dto.serverId
      ? await this.prisma.traccarServer.findFirst({
          where: {
            id: dto.serverId,
            status: {
              in: ['ACTIVE', 'DEGRADED'],
            },
          },
        })
      : await this.servers.defaultActive();

    if (!server) {
      throw new NotFoundException(
        'The selected Traccar server was not found.',
      );
    }

    const job = await this.jobs.create({
      jobType: 'SYNC_GEOFENCE',
      traccarServerId: server.id,
      entityType: 'Geofence',
      entityId: geofenceId,
      idempotencyKey: `sync-geofence:${geofenceId}:${server.id}:${geofence.updatedAt.toISOString()}`,
      payload: {
        geometryType: geofence.geometryType,
      },
    });

    if (job.status === 'SUCCEEDED') {
      return jsonSafe({
        geofence,
        job,
        reused: true,
      });
    }

    await this.jobs.processing(job.id);

    try {
      const area = this.toTraccarArea(
        geofence.geometryType,
        geofence.geometryData as Record<string, unknown>,
      );

      const external =
        geofence.traccarGeofenceId &&
        geofence.traccarServerId === server.id
          ? await this.client.updateGeofence(
              server,
              geofence.traccarGeofenceId,
              {
                id: Number(geofence.traccarGeofenceId),
                name: geofence.name,
                description: geofence.description ?? undefined,
                area,
                attributes: {
                  solidTrackerGeofenceId: geofence.id,
                  solidTrackerGeofenceCode:
                    geofence.geofenceCode,
                },
              },
            )
          : await this.client.createGeofence(server, {
              name: geofence.name,
              description: geofence.description ?? undefined,
              area,
              attributes: {
                solidTrackerGeofenceId: geofence.id,
                solidTrackerGeofenceCode:
                  geofence.geofenceCode,
              },
            });

      const updated = await this.prisma.geofence.update({
        where: {
          id: geofenceId,
        },
        data: {
          traccarServerId: server.id,
          traccarGeofenceId: BigInt(external.id),
          syncStatus: 'SYNCED',
          lastSyncAttemptAt: new Date(),
          lastSyncedAt: new Date(),
          lastSyncError: null,
        },
        include: {
          traccarServer: true,
        },
      });

      for (const assignment of geofence.assignments) {
        await this.linkVehicle(
          assignment.vehicleId,
          server,
          BigInt(external.id),
        );
      }

      await this.jobs.succeeded(job.id, {
        traccarGeofenceId: external.id,
      });

      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId:
          this.access.actorOrganizationId(auth),
        action: 'tracking.geofence.synchronized',
        resourceType: 'Geofence',
        resourceId: geofenceId,
        scopeType: 'CUSTOMER',
        scopeId: geofence.customerId,
        afterData: jsonSafe(updated),
      });

      return jsonSafe({
        geofence: updated,
        jobId: job.id,
        reused: false,
      });
    } catch (error) {
      await this.jobs.failed(job.id, error);

      await this.prisma.geofence.update({
        where: {
          id: geofenceId,
        },
        data: {
          syncStatus: 'FAILED',
          lastSyncAttemptAt: new Date(),
          lastSyncError:
            error instanceof Error
              ? error.message
              : 'Unknown geofence synchronization error',
        },
      });

      throw error;
    }
  }

  private validateGeometry(
    geometryType: 'CIRCLE' | 'POLYGON' | 'POLYLINE',
    data: Record<string, unknown>,
  ): void {
    if (geometryType === 'CIRCLE') {
      const center = this.coordinate(data.center);
      const radius = Number(data.radius);

      if (!center || !Number.isFinite(radius) || radius <= 0) {
        throw new BadRequestException(
          'Circle geometry requires a valid center and positive radius.',
        );
      }

      return;
    }

    const points = this.points(data.points);
    const minimum = geometryType === 'POLYGON' ? 3 : 2;

    if (points.length < minimum) {
      throw new BadRequestException(
        `${geometryType} geometry requires at least ${minimum} valid points.`,
      );
    }
  }

  private toTraccarArea(
    geometryType: 'CIRCLE' | 'POLYGON' | 'POLYLINE',
    data: Record<string, unknown>,
  ): string {
    if (geometryType === 'CIRCLE') {
      const center = this.coordinate(data.center);
      const radius = Number(data.radius);

      if (!center) {
        throw new BadRequestException(
          'Circle center is invalid.',
        );
      }

      return `CIRCLE (${center.latitude} ${center.longitude}, ${radius})`;
    }

    const points = this.points(data.points);
    const serialized = points
      .map((point) => `${point.latitude} ${point.longitude}`)
      .join(', ');

    return geometryType === 'POLYGON'
      ? `POLYGON ((${serialized}))`
      : `LINESTRING (${serialized})`;
  }

  private points(value: unknown): Coordinate[] {
    if (!Array.isArray(value)) {
      return [];
    }

    return value
      .map((point) => this.coordinate(point))
      .filter(
        (point): point is Coordinate => point !== null,
      );
  }

  private coordinate(value: unknown): Coordinate | null {
    if (!value || typeof value !== 'object') {
      return null;
    }

    const record = value as Record<string, unknown>;
    const latitude = Number(record.latitude);
    const longitude = Number(record.longitude);

    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return null;
    }

    return {
      latitude,
      longitude,
    };
  }

  private normalizeName(value: string): string {
    return value.trim().replace(/\s+/g, ' ').toLowerCase();
  }

  private async linkVehicle(
    vehicleId: string,
    server: TraccarServer,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    const mapping = await this.vehicleMapping(vehicleId, server.id);

    if (mapping) {
      await this.client.linkDeviceGeofence(
        server,
        mapping.traccarDeviceId,
        traccarGeofenceId,
      );
    }
  }

  private async unlinkVehicle(
    vehicleId: string,
    server: TraccarServer,
    traccarGeofenceId: bigint,
  ): Promise<void> {
    const mapping = await this.vehicleMapping(vehicleId, server.id);

    if (mapping) {
      await this.client.unlinkDeviceGeofence(
        server,
        mapping.traccarDeviceId,
        traccarGeofenceId,
      );
    }
  }

  private vehicleMapping(
    vehicleId: string,
    serverId: string,
  ) {
    return this.prisma.traccarDeviceMapping.findFirst({
      where: {
        traccarServerId: serverId,
        isActive: true,
        isPrimary: true,
        syncStatus: 'SYNCED',
        device: {
          vehicleAssignments: {
            some: {
              vehicleId,
              status: 'ACTIVE',
              assignmentType: 'PRIMARY',
            },
          },
        },
      },
    });
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\jobs\integration-jobs.controller.ts" `
        @'
import {
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
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
import { IntegrationJobQueryDto } from '../common/tracking-query.dto';
import { IntegrationJobsService } from './integration-jobs.service';

@ApiTags('Tracking - Integration Jobs')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/integration-jobs')
export class IntegrationJobsController {
  constructor(
    private readonly integrationJobsService: IntegrationJobsService,
  ) {}

  @Get()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'List Traccar integration jobs' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: IntegrationJobQueryDto,
  ) {
    return this.integrationJobsService.list(auth, query);
  }

  @Get(':jobId')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Read one Traccar integration job' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('jobId', new ParseUUIDPipe()) jobId: string,
  ) {
    return this.integrationJobsService.get(auth, jobId);
  }

  @Post(':jobId/retry')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Queue a failed integration job again' })
  retry(
    @CurrentAuth() auth: AuthContext,
    @Param('jobId', new ParseUUIDPipe()) jobId: string,
  ) {
    return this.integrationJobsService.retry(auth, jobId);
  }

  @Post(':jobId/cancel')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Cancel an integration job' })
  cancel(
    @CurrentAuth() auth: AuthContext,
    @Param('jobId', new ParseUUIDPipe()) jobId: string,
  ) {
    return this.integrationJobsService.cancel(auth, jobId);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\jobs\integration-jobs.service.ts" `
        @'
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type { IntegrationJobQueryDto } from '../common/tracking-query.dto';
import { jsonSafe, toInputJson } from '../common/tracking-json.util';

@Injectable()
export class IntegrationJobsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
  ) {}

  async list(auth: AuthContext, query: IntegrationJobQueryDto) {
    this.access.assertPlatform(auth);
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.IntegrationJobWhereInput = {
      ...(query.status
        ? {
            status: query.status,
          }
        : {}),
      ...(query.entityType
        ? {
            entityType: query.entityType,
          }
        : {}),
      ...(query.entityId
        ? {
            entityId: query.entityId,
          }
        : {}),
      ...(query.priority
        ? {
            priority: {
              lte: query.priority,
            },
          }
        : {}),
      ...(query.search
        ? {
            OR: [
              {
                jobCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                idempotencyKey: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                correlationId: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.integrationJob.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: [
          {
            priority: 'asc',
          },
          {
            createdAt: 'desc',
          },
        ],
        include: {
          traccarServer: {
            select: {
              id: true,
              serverCode: true,
              name: true,
              status: true,
            },
          },
        },
      }),
      this.prisma.integrationJob.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async get(auth: AuthContext, jobId: string) {
    this.access.assertPlatform(auth);

    const job = await this.prisma.integrationJob.findUnique({
      where: {
        id: jobId,
      },
      include: {
        traccarServer: {
          select: {
            id: true,
            serverCode: true,
            name: true,
            status: true,
          },
        },
      },
    });

    if (!job) {
      throw new NotFoundException(
        'Integration job was not found.',
      );
    }

    return jsonSafe(job);
  }

  async retry(auth: AuthContext, jobId: string) {
    this.access.assertPlatform(auth);

    const job = await this.prisma.integrationJob.findUnique({
      where: {
        id: jobId,
      },
    });

    if (!job) {
      throw new NotFoundException(
        'Integration job was not found.',
      );
    }

    if (!['FAILED', 'DEAD_LETTER'].includes(job.status)) {
      throw new BadRequestException(
        'Only failed or dead-letter jobs may be retried.',
      );
    }

    const updated = await this.prisma.integrationJob.update({
      where: {
        id: jobId,
      },
      data: {
        status: 'PENDING',
        nextAttemptAt: new Date(),
        lockedAt: null,
        startedAt: null,
        completedAt: null,
        failedAt: null,
        lastError: null,
      },
    });

    return jsonSafe(updated);
  }

  async cancel(auth: AuthContext, jobId: string) {
    this.access.assertPlatform(auth);

    const job = await this.prisma.integrationJob.findUnique({
      where: {
        id: jobId,
      },
    });

    if (!job) {
      throw new NotFoundException(
        'Integration job was not found.',
      );
    }

    if (
      ['SUCCEEDED', 'CANCELLED', 'DEAD_LETTER'].includes(
        job.status,
      )
    ) {
      throw new BadRequestException(
        'The integration job cannot be cancelled in its current state.',
      );
    }

    const updated = await this.prisma.integrationJob.update({
      where: {
        id: jobId,
      },
      data: {
        status: 'CANCELLED',
        lockedAt: null,
      },
    });

    return jsonSafe(updated);
  }

  async create(input: {
    jobType:
      | 'CREATE_DEVICE'
      | 'UPDATE_DEVICE'
      | 'DISABLE_DEVICE'
      | 'SYNC_DEVICE'
      | 'FETCH_LATEST_POSITION'
      | 'PROCESS_EVENT'
      | 'SYNC_GEOFENCE'
      | 'SEND_COMMAND'
      | 'RETRY_FAILED_SYNC';
    traccarServerId?: string;
    entityType: string;
    entityId: string;
    idempotencyKey?: string;
    payload?: unknown;
    correlationId?: string;
    priority?: number;
    maximumAttempts?: number;
  }) {
    if (input.idempotencyKey) {
      const existing =
        await this.prisma.integrationJob.findUnique({
          where: {
            idempotencyKey: input.idempotencyKey,
          },
        });

      if (existing) {
        return existing;
      }
    }

    return this.prisma.integrationJob.create({
      data: {
        jobCode: this.codes.job(),
        jobType: input.jobType,
        traccarServerId: input.traccarServerId,
        entityType: input.entityType,
        entityId: input.entityId,
        idempotencyKey: input.idempotencyKey,
        payload: toInputJson(input.payload),
        correlationId: input.correlationId,
        priority: input.priority ?? 100,
        maximumAttempts: input.maximumAttempts ?? 5,
        status: 'PENDING',
        nextAttemptAt: new Date(),
      },
    });
  }

  async processing(jobId: string) {
    return this.prisma.integrationJob.update({
      where: {
        id: jobId,
      },
      data: {
        status: 'PROCESSING',
        attemptCount: {
          increment: 1,
        },
        lockedAt: new Date(),
        startedAt: new Date(),
        failedAt: null,
        lastError: null,
      },
    });
  }

  async succeeded(jobId: string, result?: unknown) {
    return this.prisma.integrationJob.update({
      where: {
        id: jobId,
      },
      data: {
        status: 'SUCCEEDED',
        lockedAt: null,
        completedAt: new Date(),
        failedAt: null,
        lastError: null,
        result: toInputJson(result),
      },
    });
  }

  async failed(jobId: string, error: unknown) {
    const job = await this.prisma.integrationJob.findUniqueOrThrow({
      where: {
        id: jobId,
      },
    });
    const message =
      error instanceof Error
        ? error.message
        : 'Unknown integration error';
    const deadLetter =
      job.attemptCount >= job.maximumAttempts;

    return this.prisma.integrationJob.update({
      where: {
        id: jobId,
      },
      data: {
        status: deadLetter ? 'DEAD_LETTER' : 'FAILED',
        lockedAt: null,
        failedAt: new Date(),
        lastError: message,
        nextAttemptAt: deadLetter
          ? null
          : new Date(Date.now() + 60_000),
      },
    });
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\notifications\dto\create-notification-rule.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

const severities = ['INFO', 'WARNING', 'CRITICAL'] as const;
const channels = [
  'PUSH',
  'SMS',
  'EMAIL',
  'IN_APP',
  'WHATSAPP',
  'VOICE_CALL',
] as const;
const recipientTypes = [
  'USER',
  'CUSTOMER_OWNER',
  'CUSTOMER_ADMIN',
  'CUSTOM_ADDRESS',
] as const;

export class CreateNotificationRuleDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiProperty({
    description:
      'Normalized event type, or ANY to match every event type.',
  })
  @IsString()
  @MaxLength(100)
  eventType!: string;

  @ApiProperty({ enum: severities })
  @IsIn(severities)
  minimumSeverity!: (typeof severities)[number];

  @ApiProperty({ enum: channels })
  @IsIn(channels)
  channel!: (typeof channels)[number];

  @ApiProperty({ enum: recipientTypes })
  @IsIn(recipientTypes)
  recipientType!: (typeof recipientTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  recipientUserId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(320)
  recipientAddress?: string;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @ApiPropertyOptional({ minimum: 0, maximum: 1439 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(1439)
  quietHoursStartMinute?: number;

  @ApiPropertyOptional({ minimum: 0, maximum: 1439 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(1439)
  quietHoursEndMinute?: number;

  @ApiPropertyOptional({ default: 0, minimum: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  cooldownSeconds?: number;

  @ApiPropertyOptional({ minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  dailyLimit?: number;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\notifications\dto\update-notification-delivery.dto.ts" `
        @'
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

const statuses = [
  'PROCESSING',
  'SENT',
  'DELIVERED',
  'FAILED',
  'CANCELLED',
] as const;

export class UpdateNotificationDeliveryDto {
  @ApiProperty({ enum: statuses })
  @IsIn(statuses)
  status!: (typeof statuses)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  provider?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  providerMessageId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  failureReason?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\notifications\dto\update-notification-rule.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

const severities = ['INFO', 'WARNING', 'CRITICAL'] as const;
const channels = [
  'PUSH',
  'SMS',
  'EMAIL',
  'IN_APP',
  'WHATSAPP',
  'VOICE_CALL',
] as const;
const recipientTypes = [
  'USER',
  'CUSTOMER_OWNER',
  'CUSTOMER_ADMIN',
  'CUSTOM_ADDRESS',
] as const;

export class UpdateNotificationRuleDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  eventType?: string;

  @ApiPropertyOptional({ enum: severities })
  @IsOptional()
  @IsIn(severities)
  minimumSeverity?: (typeof severities)[number];

  @ApiPropertyOptional({ enum: channels })
  @IsOptional()
  @IsIn(channels)
  channel?: (typeof channels)[number];

  @ApiPropertyOptional({ enum: recipientTypes })
  @IsOptional()
  @IsIn(recipientTypes)
  recipientType?: (typeof recipientTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  recipientUserId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(320)
  recipientAddress?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @ApiPropertyOptional({ minimum: 0, maximum: 1439 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(1439)
  quietHoursStartMinute?: number;

  @ApiPropertyOptional({ minimum: 0, maximum: 1439 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(1439)
  quietHoursEndMinute?: number;

  @ApiPropertyOptional({ minimum: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  cooldownSeconds?: number;

  @ApiPropertyOptional({ minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  dailyLimit?: number;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\notifications\notifications.controller.ts" `
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
import {
  NotificationQueryDto,
  NotificationRuleQueryDto,
} from '../common/tracking-query.dto';
import { CreateNotificationRuleDto } from './dto/create-notification-rule.dto';
import { UpdateNotificationDeliveryDto } from './dto/update-notification-delivery.dto';
import { UpdateNotificationRuleDto } from './dto/update-notification-rule.dto';
import { NotificationsService } from './notifications.service';

@ApiTags('Tracking - Notification Rules')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/notification-rules')
export class NotificationRulesController {
  constructor(
    private readonly notificationsService: NotificationsService,
  ) {}

  @Get()
  @RequirePermissions('customer.view')
  @ApiOperation({ summary: 'List notification rules' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: NotificationRuleQueryDto,
  ) {
    return this.notificationsService.listRules(auth, query);
  }

  @Post()
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Create a notification rule' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateNotificationRuleDto,
  ) {
    return this.notificationsService.createRule(auth, dto);
  }

  @Patch(':ruleId')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Update a notification rule' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('ruleId', new ParseUUIDPipe()) ruleId: string,
    @Body() dto: UpdateNotificationRuleDto,
  ) {
    return this.notificationsService.updateRule(
      auth,
      ruleId,
      dto,
    );
  }

  @Post(':ruleId/archive')
  @RequirePermissions('customer.update')
  @ApiOperation({ summary: 'Archive a notification rule' })
  archive(
    @CurrentAuth() auth: AuthContext,
    @Param('ruleId', new ParseUUIDPipe()) ruleId: string,
  ) {
    return this.notificationsService.archiveRule(
      auth,
      ruleId,
    );
  }
}

@ApiTags('Tracking - Notifications')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/notifications')
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
  ) {}

  @Get()
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'List generated tracking notifications' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: NotificationQueryDto,
  ) {
    return this.notificationsService.listNotifications(
      auth,
      query,
    );
  }

  @Get(':notificationId')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'Read one tracking notification' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('notificationId', new ParseUUIDPipe())
    notificationId: string,
  ) {
    return this.notificationsService.getNotification(
      auth,
      notificationId,
    );
  }

  @Post(':notificationId/delivery-status')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({
    summary: 'Update delivery status from an internal provider adapter',
  })
  updateDelivery(
    @CurrentAuth() auth: AuthContext,
    @Param('notificationId', new ParseUUIDPipe())
    notificationId: string,
    @Body() dto: UpdateNotificationDeliveryDto,
  ) {
    return this.notificationsService.updateDelivery(
      auth,
      notificationId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\notifications\notifications.service.ts" `
        @'
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type {
  NotificationRule,
  Prisma,
  TrackingEvent,
} from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import type {
  NotificationQueryDto,
  NotificationRuleQueryDto,
} from '../common/tracking-query.dto';
import { jsonSafe } from '../common/tracking-json.util';
import type { CreateNotificationRuleDto } from './dto/create-notification-rule.dto';
import type { UpdateNotificationDeliveryDto } from './dto/update-notification-delivery.dto';
import type { UpdateNotificationRuleDto } from './dto/update-notification-rule.dto';

interface ResolvedRecipient {
  userId?: string;
  address: string;
}

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly auditService: AuditService,
  ) {}

  async listRules(
    auth: AuthContext,
    query: NotificationRuleQueryDto,
  ) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.notificationRuleWhere(auth);
    const where: Prisma.NotificationRuleWhereInput = {
      AND: [
        scopeWhere,
        {
          archivedAt: null,
        },
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.vehicleId
          ? {
              vehicleId: query.vehicleId,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  ruleCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  eventType: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  recipientAddress: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.notificationRule.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          customer: true,
          vehicle: true,
          recipientUser: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
              mobileNumber: true,
              email: true,
            },
          },
          _count: {
            select: {
              notifications: true,
            },
          },
        },
      }),
      this.prisma.notificationRule.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async createRule(
    auth: AuthContext,
    dto: CreateNotificationRuleDto,
  ) {
    await this.access.assertCustomer(auth, dto.customerId);
    await this.assertVehicleCustomer(
      dto.customerId,
      dto.vehicleId,
    );
    await this.assertRecipient({
      customerId: dto.customerId,
      recipientType: dto.recipientType,
      recipientUserId: dto.recipientUserId,
      recipientAddress: dto.recipientAddress,
    });
    this.assertQuietHours(
      dto.quietHoursStartMinute,
      dto.quietHoursEndMinute,
    );

    const rule = await this.prisma.notificationRule.create({
      data: {
        ruleCode: this.codes.notificationRule(),
        customerId: dto.customerId,
        vehicleId: dto.vehicleId,
        eventType: dto.eventType.trim(),
        minimumSeverity: dto.minimumSeverity,
        channel: dto.channel,
        recipientType: dto.recipientType,
        recipientUserId:
          dto.recipientType === 'USER'
            ? dto.recipientUserId
            : null,
        recipientAddress:
          dto.recipientType === 'CUSTOM_ADDRESS'
            ? dto.recipientAddress?.trim()
            : null,
        enabled: dto.enabled ?? true,
        quietHoursStartMinute: dto.quietHoursStartMinute,
        quietHoursEndMinute: dto.quietHoursEndMinute,
        cooldownSeconds: dto.cooldownSeconds ?? 0,
        dailyLimit: dto.dailyLimit,
        createdByUserId: auth.userId,
      },
      include: {
        customer: true,
        vehicle: true,
        recipientUser: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.notification-rule.created',
      resourceType: 'NotificationRule',
      resourceId: rule.id,
      scopeType: 'CUSTOMER',
      scopeId: rule.customerId,
      afterData: jsonSafe(rule),
    });

    return jsonSafe(rule);
  }

  async updateRule(
    auth: AuthContext,
    ruleId: string,
    dto: UpdateNotificationRuleDto,
  ) {
    const before = await this.prisma.notificationRule.findFirst({
      where: {
        AND: [
          {
            id: ruleId,
            archivedAt: null,
          },
          this.access.notificationRuleWhere(auth),
        ],
      },
    });

    if (!before) {
      throw new NotFoundException(
        'Notification rule was not found within the authenticated scope.',
      );
    }

    const recipientType =
      dto.recipientType ?? before.recipientType;
    const recipientUserId =
      dto.recipientUserId ?? before.recipientUserId ?? undefined;
    const recipientAddress =
      dto.recipientAddress ??
      before.recipientAddress ??
      undefined;

    await this.assertVehicleCustomer(
      before.customerId,
      dto.vehicleId ?? before.vehicleId ?? undefined,
    );
    await this.assertRecipient({
      customerId: before.customerId,
      recipientType,
      recipientUserId,
      recipientAddress,
    });
    this.assertQuietHours(
      dto.quietHoursStartMinute ??
        before.quietHoursStartMinute ??
        undefined,
      dto.quietHoursEndMinute ??
        before.quietHoursEndMinute ??
        undefined,
    );

    const updated = await this.prisma.notificationRule.update({
      where: {
        id: ruleId,
      },
      data: {
        vehicleId: dto.vehicleId,
        eventType: dto.eventType?.trim(),
        minimumSeverity: dto.minimumSeverity,
        channel: dto.channel,
        recipientType: dto.recipientType,
        recipientUserId:
          recipientType === 'USER'
            ? recipientUserId
            : null,
        recipientAddress:
          recipientType === 'CUSTOM_ADDRESS'
            ? recipientAddress?.trim()
            : null,
        enabled: dto.enabled,
        quietHoursStartMinute: dto.quietHoursStartMinute,
        quietHoursEndMinute: dto.quietHoursEndMinute,
        cooldownSeconds: dto.cooldownSeconds,
        dailyLimit: dto.dailyLimit,
      },
      include: {
        customer: true,
        vehicle: true,
        recipientUser: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.notification-rule.updated',
      resourceType: 'NotificationRule',
      resourceId: ruleId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async archiveRule(auth: AuthContext, ruleId: string) {
    const before = await this.prisma.notificationRule.findFirst({
      where: {
        AND: [
          {
            id: ruleId,
            archivedAt: null,
          },
          this.access.notificationRuleWhere(auth),
        ],
      },
    });

    if (!before) {
      throw new NotFoundException(
        'Notification rule was not found within the authenticated scope.',
      );
    }

    const updated = await this.prisma.notificationRule.update({
      where: {
        id: ruleId,
      },
      data: {
        enabled: false,
        archivedAt: new Date(),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.notification-rule.archived',
      resourceType: 'NotificationRule',
      resourceId: ruleId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async listNotifications(
    auth: AuthContext,
    query: NotificationQueryDto,
  ) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.notificationWhere(auth);
    const where: Prisma.NotificationWhereInput = {
      AND: [
        scopeWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.trackingEventId
          ? {
              trackingEventId: query.trackingEventId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
        query.search
          ? {
              OR: [
                {
                  notificationCode: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  recipient: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  subject: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              ],
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.notification.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          queuedAt: 'desc',
        },
        include: {
          user: {
            select: {
              id: true,
              userCode: true,
              fullName: true,
            },
          },
          trackingEvent: true,
          notificationRule: true,
        },
      }),
      this.prisma.notification.count({ where }),
    ]);

    return jsonSafe({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    });
  }

  async getNotification(
    auth: AuthContext,
    notificationId: string,
  ) {
    await this.access.assertNotification(auth, notificationId);

    const notification = await this.prisma.notification.findUnique({
      where: {
        id: notificationId,
      },
      include: {
        customer: true,
        user: {
          select: {
            id: true,
            userCode: true,
            fullName: true,
            mobileNumber: true,
            email: true,
          },
        },
        trackingEvent: true,
        notificationRule: true,
      },
    });

    return jsonSafe(notification);
  }

  async updateDelivery(
    auth: AuthContext,
    notificationId: string,
    dto: UpdateNotificationDeliveryDto,
  ) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.notification.findUnique({
      where: {
        id: notificationId,
      },
    });

    if (!before) {
      throw new NotFoundException('Notification was not found.');
    }

    const now = new Date();
    const updated = await this.prisma.notification.update({
      where: {
        id: notificationId,
      },
      data: {
        status: dto.status,
        provider: dto.provider,
        providerMessageId: dto.providerMessageId,
        failureReason:
          dto.status === 'FAILED'
            ? dto.failureReason ?? 'Provider delivery failed.'
            : null,
        processingAt:
          dto.status === 'PROCESSING'
            ? now
            : before.processingAt,
        sentAt:
          dto.status === 'SENT' ||
          dto.status === 'DELIVERED'
            ? before.sentAt ?? now
            : before.sentAt,
        deliveredAt:
          dto.status === 'DELIVERED'
            ? now
            : before.deliveredAt,
        failedAt:
          dto.status === 'FAILED'
            ? now
            : before.failedAt,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.notification.delivery-updated',
      resourceType: 'Notification',
      resourceId: notificationId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: jsonSafe(before),
      afterData: jsonSafe(updated),
    });

    return jsonSafe(updated);
  }

  async enqueueForEvent(event: TrackingEvent) {
    const rules = await this.prisma.notificationRule.findMany({
      where: {
        customerId: event.customerId,
        enabled: true,
        archivedAt: null,
        eventType: {
          in: [event.eventType, 'ANY'],
        },
        OR: [
          {
            vehicleId: null,
          },
          {
            vehicleId: event.vehicleId,
          },
        ],
      },
    });

    const created: unknown[] = [];

    for (const rule of rules) {
      if (!this.severityAllowed(event.severity, rule.minimumSeverity)) {
        continue;
      }

      if (this.inQuietHours(rule, event.occurredAt)) {
        continue;
      }

      if (!(await this.withinDeliveryLimits(rule))) {
        continue;
      }

      const recipients = await this.resolveRecipients(rule);

      for (const recipient of recipients) {
        const notification = await this.prisma.notification.create({
          data: {
            notificationCode: this.codes.notification(),
            customerId: event.customerId,
            userId: recipient.userId,
            trackingEventId: event.id,
            notificationRuleId: rule.id,
            channel: rule.channel,
            recipient: recipient.address,
            subject: `${event.eventType} alert`,
            renderedContent:
              `${event.eventType} was detected for vehicle ` +
              `${event.vehicleId} at ${event.occurredAt.toISOString()}.`,
            status: 'QUEUED',
          },
        });

        created.push(notification);
      }
    }

    return created;
  }

  private async assertVehicleCustomer(
    customerId: string,
    vehicleId?: string,
  ): Promise<void> {
    if (!vehicleId) {
      return;
    }

    const vehicle = await this.prisma.vehicle.findFirst({
      where: {
        id: vehicleId,
        customerId,
      },
      select: {
        id: true,
      },
    });

    if (!vehicle) {
      throw new BadRequestException(
        'Notification-rule vehicle must belong to the selected customer.',
      );
    }
  }

  private async assertRecipient(input: {
    customerId: string;
    recipientType:
      | 'USER'
      | 'CUSTOMER_OWNER'
      | 'CUSTOMER_ADMIN'
      | 'CUSTOM_ADDRESS';
    recipientUserId?: string;
    recipientAddress?: string;
  }): Promise<void> {
    if (input.recipientType === 'USER') {
      if (!input.recipientUserId) {
        throw new BadRequestException(
          'recipientUserId is required for USER recipients.',
        );
      }

      const membership =
        await this.prisma.customerMembership.findFirst({
          where: {
            customerId: input.customerId,
            userId: input.recipientUserId,
            status: 'ACTIVE',
          },
          select: {
            id: true,
          },
        });

      if (!membership) {
        throw new BadRequestException(
          'Recipient user must be an active customer member.',
        );
      }
    }

    if (
      input.recipientType === 'CUSTOM_ADDRESS' &&
      !input.recipientAddress?.trim()
    ) {
      throw new BadRequestException(
        'recipientAddress is required for CUSTOM_ADDRESS recipients.',
      );
    }
  }

  private assertQuietHours(
    start?: number,
    end?: number,
  ): void {
    const oneProvided =
      (start === undefined) !== (end === undefined);

    if (oneProvided) {
      throw new BadRequestException(
        'Both quiet-hours start and end must be provided together.',
      );
    }
  }

  private severityAllowed(
    actual: 'INFO' | 'WARNING' | 'CRITICAL',
    minimum: 'INFO' | 'WARNING' | 'CRITICAL',
  ): boolean {
    const rank = {
      INFO: 1,
      WARNING: 2,
      CRITICAL: 3,
    } as const;

    return rank[actual] >= rank[minimum];
  }

  private inQuietHours(
    rule: NotificationRule,
    occurredAt: Date,
  ): boolean {
    if (
      rule.quietHoursStartMinute === null ||
      rule.quietHoursEndMinute === null
    ) {
      return false;
    }

    const minute =
      occurredAt.getUTCHours() * 60 +
      occurredAt.getUTCMinutes();
    const start = rule.quietHoursStartMinute;
    const end = rule.quietHoursEndMinute;

    if (start === end) {
      return true;
    }

    return start < end
      ? minute >= start && minute < end
      : minute >= start || minute < end;
  }

  private async withinDeliveryLimits(
    rule: NotificationRule,
  ): Promise<boolean> {
    const now = new Date();

    if (rule.cooldownSeconds > 0) {
      const recent = await this.prisma.notification.findFirst({
        where: {
          notificationRuleId: rule.id,
          queuedAt: {
            gte: new Date(
              now.getTime() - rule.cooldownSeconds * 1000,
            ),
          },
        },
        select: {
          id: true,
        },
      });

      if (recent) {
        return false;
      }
    }

    if (rule.dailyLimit !== null) {
      const startOfDay = new Date(now);
      startOfDay.setUTCHours(0, 0, 0, 0);

      const count = await this.prisma.notification.count({
        where: {
          notificationRuleId: rule.id,
          queuedAt: {
            gte: startOfDay,
          },
        },
      });

      if (count >= rule.dailyLimit) {
        return false;
      }
    }

    return true;
  }

  private async resolveRecipients(
    rule: NotificationRule,
  ): Promise<ResolvedRecipient[]> {
    if (rule.recipientType === 'CUSTOM_ADDRESS') {
      return rule.recipientAddress
        ? [
            {
              address: rule.recipientAddress,
            },
          ]
        : [];
    }

    if (rule.recipientType === 'USER') {
      if (!rule.recipientUserId) {
        return [];
      }

      const user = await this.prisma.user.findUnique({
        where: {
          id: rule.recipientUserId,
        },
        select: {
          id: true,
          mobileNumber: true,
          email: true,
        },
      });

      return user
        ? this.userRecipient(rule.channel, user)
        : [];
    }

    const roleCode =
      rule.recipientType === 'CUSTOMER_OWNER'
        ? 'CUSTOMER_OWNER'
        : 'CUSTOMER_ADMIN';

    const users = await this.prisma.user.findMany({
      where: {
        status: 'ACTIVE',
        roleAssignments: {
          some: {
            scopeType: 'CUSTOMER',
            scopeId: rule.customerId,
            status: 'ACTIVE',
            role: {
              code: roleCode,
            },
          },
        },
      },
      select: {
        id: true,
        mobileNumber: true,
        email: true,
      },
    });

    return users.flatMap((user) =>
      this.userRecipient(rule.channel, user),
    );
  }

  private userRecipient(
    channel: NotificationRule['channel'],
    user: {
      id: string;
      mobileNumber: string;
      email: string | null;
    },
  ): ResolvedRecipient[] {
    if (channel === 'EMAIL') {
      return user.email
        ? [
            {
              userId: user.id,
              address: user.email,
            },
          ]
        : [];
    }

    if (
      ['SMS', 'WHATSAPP', 'VOICE_CALL'].includes(channel)
    ) {
      return [
        {
          userId: user.id,
          address: user.mobileNumber,
        },
      ];
    }

    return [
      {
        userId: user.id,
        address: `user:${user.id}`,
      },
    ];
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\positions\tracking-positions.controller.ts" `
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
import { PositionHistoryQueryDto } from '../common/tracking-query.dto';
import { TrackingPositionsService } from './tracking-positions.service';

@ApiTags('Tracking - Positions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/vehicles')
export class TrackingPositionsController {
  constructor(
    private readonly trackingPositionsService: TrackingPositionsService,
  ) {}

  @Get(':vehicleId/live-position')
  @RequirePermissions('vehicle.location.view')
  @ApiOperation({ summary: 'Read the latest Traccar position' })
  livePosition(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
  ) {
    return this.trackingPositionsService.livePosition(
      auth,
      vehicleId,
    );
  }

  @Get(':vehicleId/position-history')
  @RequirePermissions('vehicle.history.view')
  @ApiOperation({ summary: 'Read Traccar position history' })
  history(
    @CurrentAuth() auth: AuthContext,
    @Param('vehicleId', new ParseUUIDPipe()) vehicleId: string,
    @Query() query: PositionHistoryQueryDto,
  ) {
    return this.trackingPositionsService.history(
      auth,
      vehicleId,
      query,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\positions\tracking-positions.service.ts" `
        @'
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import type { PositionHistoryQueryDto } from '../common/tracking-query.dto';
import { TraccarClientService } from '../common/traccar-client.service';
import { IntegrationJobsService } from '../jobs/integration-jobs.service';

@Injectable()
export class TrackingPositionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly client: TraccarClientService,
    private readonly jobs: IntegrationJobsService,
  ) {}

  async livePosition(auth: AuthContext, vehicleId: string) {
    await this.access.assertVehicle(auth, vehicleId);
    const assignment = await this.activePrimaryMapping(vehicleId);

    const job = await this.jobs.create({
      jobType: 'FETCH_LATEST_POSITION',
      traccarServerId:
        assignment.device.traccarMappings[0].traccarServerId,
      entityType: 'Vehicle',
      entityId: vehicleId,
      idempotencyKey: undefined,
      payload: {
        deviceId: assignment.deviceId,
      },
      maximumAttempts: 3,
    });

    await this.jobs.processing(job.id);

    try {
      const mapping = assignment.device.traccarMappings[0];
      const positions = await this.client.latestPositions(
        mapping.traccarServer,
        mapping.traccarDeviceId,
      );
      const latest = [...positions].sort((left, right) => {
        const leftTime = Date.parse(
          left.fixTime ?? left.deviceTime ?? left.serverTime ?? '0',
        );
        const rightTime = Date.parse(
          right.fixTime ??
            right.deviceTime ??
            right.serverTime ??
            '0',
        );

        return rightTime - leftTime;
      })[0];

      await this.jobs.succeeded(job.id, {
        positionId: latest?.id,
      });

      return {
        vehicleId,
        deviceId: assignment.deviceId,
        mappingId: mapping.id,
        traccarServerId: mapping.traccarServerId,
        position: latest ?? null,
      };
    } catch (error) {
      await this.jobs.failed(job.id, error);
      throw error;
    }
  }

  async history(
    auth: AuthContext,
    vehicleId: string,
    query: PositionHistoryQueryDto,
  ) {
    await this.access.assertVehicle(auth, vehicleId);
    const assignment = await this.activePrimaryMapping(vehicleId);
    const { from, to } = this.range(query);
    const mapping = assignment.device.traccarMappings[0];
    const positions = await this.client.positionHistory(
      mapping.traccarServer,
      mapping.traccarDeviceId,
      from,
      to,
    );

    return {
      vehicleId,
      deviceId: assignment.deviceId,
      mappingId: mapping.id,
      from,
      to,
      positions,
    };
  }

  private async activePrimaryMapping(vehicleId: string) {
    const assignment =
      await this.prisma.vehicleDeviceAssignment.findFirst({
        where: {
          vehicleId,
          status: 'ACTIVE',
          assignmentType: 'PRIMARY',
        },
        include: {
          device: {
            include: {
              traccarMappings: {
                where: {
                  isActive: true,
                  isPrimary: true,
                  syncStatus: 'SYNCED',
                },
                include: {
                  traccarServer: true,
                },
                take: 1,
              },
            },
          },
        },
      });

    if (!assignment) {
      throw new NotFoundException(
        'The vehicle has no active primary tracker.',
      );
    }

    if (assignment.device.traccarMappings.length === 0) {
      throw new NotFoundException(
        'The active tracker has no synchronized Traccar mapping.',
      );
    }

    return assignment;
  }

  private range(query: PositionHistoryQueryDto): {
    from: Date;
    to: Date;
  } {
    const to = query.to ? new Date(query.to) : new Date();
    const from = query.from
      ? new Date(query.from)
      : new Date(to.getTime() - 24 * 60 * 60 * 1000);

    if (from >= to) {
      throw new BadRequestException(
        'Position-history from must be earlier than to.',
      );
    }

    const maximumRangeMs = 31 * 24 * 60 * 60 * 1000;

    if (to.getTime() - from.getTime() > maximumRangeMs) {
      throw new BadRequestException(
        'Position-history range cannot exceed 31 days.',
      );
    }

    return {
      from,
      to,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\servers\dto\create-traccar-server.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsBoolean,
  IsOptional,
  IsString,
  IsUrl,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CreateTraccarServerDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name!: string;

  @ApiProperty({ example: 'http://localhost:8082' })
  @IsUrl({
    require_tld: false,
    require_protocol: true,
  })
  @MaxLength(500)
  baseUrl!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  username?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(300)
  password?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  token?: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\servers\dto\update-traccar-server.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  IsUrl,
  MaxLength,
  MinLength,
} from 'class-validator';

const serverStatuses = [
  'ACTIVE',
  'INACTIVE',
  'DEGRADED',
  'MAINTENANCE',
  'ARCHIVED',
] as const;

export class UpdateTraccarServerDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUrl({
    require_tld: false,
    require_protocol: true,
  })
  @MaxLength(500)
  baseUrl?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  username?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(300)
  password?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  token?: string;

  @ApiPropertyOptional({ enum: serverStatuses })
  @IsOptional()
  @IsIn(serverStatuses)
  status?: (typeof serverStatuses)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\servers\traccar-servers.controller.ts" `
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
import { CreateTraccarServerDto } from './dto/create-traccar-server.dto';
import { UpdateTraccarServerDto } from './dto/update-traccar-server.dto';
import { TraccarServersService } from './traccar-servers.service';

@ApiTags('Tracking - Traccar Servers')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('tracking/traccar-servers')
export class TraccarServersController {
  constructor(
    private readonly traccarServersService: TraccarServersService,
  ) {}

  @Get()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'List configured Traccar servers' })
  list(@CurrentAuth() auth: AuthContext) {
    return this.traccarServersService.list(auth);
  }

  @Post()
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Register a Traccar server securely' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateTraccarServerDto,
  ) {
    return this.traccarServersService.create(auth, dto);
  }

  @Get(':serverId')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Read one Traccar server' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('serverId', new ParseUUIDPipe()) serverId: string,
  ) {
    return this.traccarServersService.get(auth, serverId);
  }

  @Patch(':serverId')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Update a Traccar server' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('serverId', new ParseUUIDPipe()) serverId: string,
    @Body() dto: UpdateTraccarServerDto,
  ) {
    return this.traccarServersService.update(
      auth,
      serverId,
      dto,
    );
  }

  @Post(':serverId/health-check')
  @RequirePermissions('device.register')
  @ApiOperation({ summary: 'Check Traccar server health' })
  health(
    @CurrentAuth() auth: AuthContext,
    @Param('serverId', new ParseUUIDPipe()) serverId: string,
  ) {
    return this.traccarServersService.health(auth, serverId);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\servers\traccar-servers.service.ts" `
        @'
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { TrackingAccessService } from '../common/tracking-access.service';
import { TrackingCodeService } from '../common/tracking-code.service';
import { TrackingCredentialCryptoService } from '../common/tracking-credential-crypto.service';
import { TraccarClientService } from '../common/traccar-client.service';
import type { CreateTraccarServerDto } from './dto/create-traccar-server.dto';
import type { UpdateTraccarServerDto } from './dto/update-traccar-server.dto';

@Injectable()
export class TraccarServersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: TrackingAccessService,
    private readonly codes: TrackingCodeService,
    private readonly credentialCrypto: TrackingCredentialCryptoService,
    private readonly client: TraccarClientService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext) {
    this.access.assertPlatform(auth);

    const servers = await this.prisma.traccarServer.findMany({
      where: {
        status: {
          not: 'ARCHIVED',
        },
      },
      orderBy: [
        {
          isDefault: 'desc',
        },
        {
          name: 'asc',
        },
      ],
      include: {
        _count: {
          select: {
            deviceMappings: true,
            geofences: true,
            commandRequests: true,
            integrationJobs: true,
          },
        },
      },
    });

    return servers.map((server) => this.sanitize(server));
  }

  async get(auth: AuthContext, serverId: string) {
    this.access.assertPlatform(auth);

    const server = await this.prisma.traccarServer.findUnique({
      where: {
        id: serverId,
      },
      include: {
        _count: {
          select: {
            deviceMappings: true,
            trackingEvents: true,
            geofences: true,
            commandRequests: true,
            integrationJobs: true,
          },
        },
      },
    });

    if (!server) {
      throw new NotFoundException('Traccar server was not found.');
    }

    return this.sanitize(server);
  }

  async create(
    auth: AuthContext,
    dto: CreateTraccarServerDto,
  ) {
    this.access.assertPlatform(auth);
    this.assertCredentialInput(dto);

    const normalizedBaseUrl = this.normalizeBaseUrl(dto.baseUrl);
    const duplicate = await this.prisma.traccarServer.findUnique({
      where: {
        baseUrl: normalizedBaseUrl,
      },
      select: {
        id: true,
      },
    });

    if (duplicate) {
      throw new ConflictException(
        'A Traccar server with this base URL already exists.',
      );
    }

    const encryptedCredentialReference =
      this.credentialCrypto.encrypt({
        username: dto.username?.trim(),
        password: dto.password,
        token: dto.token,
      });

    const server = await this.prisma.$transaction(
      async (transaction) => {
        if (dto.isDefault) {
          await transaction.traccarServer.updateMany({
            where: {
              isDefault: true,
              status: 'ACTIVE',
            },
            data: {
              isDefault: false,
            },
          });
        }

        return transaction.traccarServer.create({
          data: {
            serverCode: this.codes.server(),
            name: dto.name.trim(),
            baseUrl: normalizedBaseUrl,
            apiUsernameReference: dto.username?.trim() || null,
            encryptedCredentialReference,
            status: 'ACTIVE',
            isDefault: dto.isDefault ?? false,
          },
        });
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.traccar-server.created',
      resourceType: 'TraccarServer',
      resourceId: server.id,
      scopeType: 'PLATFORM',
      afterData: this.sanitize(server),
    });

    return this.sanitize(server);
  }

  async update(
    auth: AuthContext,
    serverId: string,
    dto: UpdateTraccarServerDto,
  ) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.traccarServer.findUnique({
      where: {
        id: serverId,
      },
    });

    if (!before) {
      throw new NotFoundException('Traccar server was not found.');
    }

    const effectiveStatus = dto.status ?? before.status;

    if (
      dto.isDefault === true &&
      effectiveStatus !== 'ACTIVE'
    ) {
      throw new BadRequestException(
        'Only an active Traccar server may be the default.',
      );
    }

    if (
      dto.status === 'ARCHIVED' &&
      before.isDefault &&
      dto.isDefault !== false
    ) {
      throw new BadRequestException(
        'Clear the default flag before archiving the server.',
      );
    }

    const credentialFieldsProvided =
      dto.username !== undefined ||
      dto.password !== undefined ||
      dto.token !== undefined;

    if (credentialFieldsProvided) {
      this.assertCredentialInput(dto);
    }

    const updated = await this.prisma.$transaction(
      async (transaction) => {
        if (dto.isDefault) {
          await transaction.traccarServer.updateMany({
            where: {
              id: {
                not: serverId,
              },
              isDefault: true,
              status: 'ACTIVE',
            },
            data: {
              isDefault: false,
            },
          });
        }

        return transaction.traccarServer.update({
          where: {
            id: serverId,
          },
          data: {
            name: dto.name?.trim(),
            baseUrl:
              dto.baseUrl !== undefined
                ? this.normalizeBaseUrl(dto.baseUrl)
                : undefined,
            apiUsernameReference:
              credentialFieldsProvided
                ? dto.username?.trim() || null
                : undefined,
            encryptedCredentialReference:
              credentialFieldsProvided
                ? this.credentialCrypto.encrypt({
                    username: dto.username?.trim(),
                    password: dto.password,
                    token: dto.token,
                  })
                : undefined,
            status: dto.status,
            isDefault:
              dto.status === 'ARCHIVED'
                ? false
                : dto.isDefault,
            archivedAt:
              dto.status === 'ARCHIVED'
                ? new Date()
                : dto.status
                  ? null
                  : undefined,
          },
        });
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'tracking.traccar-server.updated',
      resourceType: 'TraccarServer',
      resourceId: serverId,
      scopeType: 'PLATFORM',
      beforeData: this.sanitize(before),
      afterData: this.sanitize(updated),
    });

    return this.sanitize(updated);
  }

  async health(auth: AuthContext, serverId: string) {
    this.access.assertPlatform(auth);

    const server = await this.prisma.traccarServer.findUnique({
      where: {
        id: serverId,
      },
    });

    if (!server) {
      throw new NotFoundException('Traccar server was not found.');
    }

    const checkedAt = new Date();

    try {
      const response = await this.client.health(server);

      const updated = await this.prisma.traccarServer.update({
        where: {
          id: serverId,
        },
        data: {
          lastHealthCheckAt: checkedAt,
          lastHealthStatus: 'UP',
          lastHealthError: null,
          status:
            server.status === 'DEGRADED'
              ? 'ACTIVE'
              : server.status,
        },
      });

      return {
        server: this.sanitize(updated),
        health: response,
      };
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : 'Unknown Traccar health error';

      await this.prisma.traccarServer.update({
        where: {
          id: serverId,
        },
        data: {
          lastHealthCheckAt: checkedAt,
          lastHealthStatus: 'DOWN',
          lastHealthError: message,
          status:
            server.status === 'ACTIVE'
              ? 'DEGRADED'
              : server.status,
        },
      });

      throw error;
    }
  }

  async defaultActive() {
    const server = await this.prisma.traccarServer.findFirst({
      where: {
        status: {
          in: ['ACTIVE', 'DEGRADED'],
        },
        isDefault: true,
      },
    });

    if (!server) {
      throw new NotFoundException(
        'An active default Traccar server is not configured.',
      );
    }

    return server;
  }

  private assertCredentialInput(input: {
    username?: string;
    password?: string;
    token?: string;
  }): void {
    const hasToken = Boolean(input.token?.trim());
    const hasBasic =
      Boolean(input.username?.trim()) &&
      input.password !== undefined;

    if (!hasToken && !hasBasic) {
      throw new BadRequestException(
        'Provide either a token or username and password.',
      );
    }

    if (hasToken && hasBasic) {
      throw new BadRequestException(
        'Use either token authentication or basic authentication, not both.',
      );
    }
  }

  private normalizeBaseUrl(value: string): string {
    return value.trim().replace(/\/+$/, '');
  }

  private sanitize<T extends {
    encryptedCredentialReference: string;
  }>(server: T): Omit<T, 'encryptedCredentialReference'> & {
    credentialConfigured: true;
  } {
    const {
      encryptedCredentialReference,
      ...safe
    } = server;

    void encryptedCredentialReference;

    return {
      ...safe,
      credentialConfigured: true,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\tracking\tracking-api.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { AuditModule } from '../identity/audit/audit.module';
import { DeviceCommandsController } from './commands/device-commands.controller';
import { DeviceCommandsService } from './commands/device-commands.service';
import { TrackingAccessService } from './common/tracking-access.service';
import { TrackingCodeService } from './common/tracking-code.service';
import { TrackingCredentialCryptoService } from './common/tracking-credential-crypto.service';
import { TraccarClientService } from './common/traccar-client.service';
import { DeviceTrackingController } from './devices/device-tracking.controller';
import { DeviceTrackingService } from './devices/device-tracking.service';
import {
  TrackingEventsController,
  TrackingWebhooksController,
} from './events/tracking-events.controller';
import { TrackingEventsService } from './events/tracking-events.service';
import { TrackingWebhookGuard } from './events/tracking-webhook.guard';
import { GeofencesController } from './geofences/geofences.controller';
import { GeofencesService } from './geofences/geofences.service';
import { IntegrationJobsController } from './jobs/integration-jobs.controller';
import { IntegrationJobsService } from './jobs/integration-jobs.service';
import {
  NotificationRulesController,
  NotificationsController,
} from './notifications/notifications.controller';
import { NotificationsService } from './notifications/notifications.service';
import { TrackingPositionsController } from './positions/tracking-positions.controller';
import { TrackingPositionsService } from './positions/tracking-positions.service';
import { TraccarServersController } from './servers/traccar-servers.controller';
import { TraccarServersService } from './servers/traccar-servers.service';

@Module({
  imports: [AccessControlModule, AuditModule],
  controllers: [
    TraccarServersController,
    DeviceTrackingController,
    TrackingPositionsController,
    TrackingEventsController,
    TrackingWebhooksController,
    GeofencesController,
    NotificationRulesController,
    NotificationsController,
    DeviceCommandsController,
    IntegrationJobsController,
  ],
  providers: [
    TrackingAccessService,
    TrackingCodeService,
    TrackingCredentialCryptoService,
    TraccarClientService,
    TraccarServersService,
    IntegrationJobsService,
    DeviceTrackingService,
    TrackingPositionsService,
    NotificationsService,
    TrackingEventsService,
    GeofencesService,
    DeviceCommandsService,
    TrackingWebhookGuard,
  ],
})
export class TrackingApiModule {}
'@

    Write-Utf8File `
        "services\backend-api\test\tracking.e2e-spec.ts" `
        @'
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from 'node:http';
import type { AddressInfo } from 'node:net';
import { randomInt, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';

interface FakeDevice {
  id: number;
  name: string;
  uniqueId: string;
  disabled?: boolean;
  category?: string;
  attributes?: Record<string, unknown>;
}

interface FakeGeofence {
  id: number;
  name: string;
  description?: string;
  area: string;
  attributes?: Record<string, unknown>;
}

describe('Tracking and Traccar integration lifecycle (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let fakeTraccar: Server;
  let fakeTraccarBaseUrl: string;
  let accessToken: string;
  let platformUserId: string;
  let platformMembershipId: string;
  let platformRoleAssignmentId: string;
  let dealerId: string;
  let customerId: string;
  let vehicleId: string;
  let deviceModelId: string;
  let deviceId: string;
  let traccarServerId: string;
  let geofenceId: string;
  let notificationRuleId: string;
  let trackingEventId: string;

  const fakeDevices: FakeDevice[] = [];
  const fakeGeofences: FakeGeofence[] = [];
  let nextDeviceId = 101;
  let nextGeofenceId = 201;
  let nextCommandId = 301;

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
  const imei = `86${Date.now()
    .toString()
    .slice(-13)
    .padStart(13, '0')}`;

  beforeAll(async () => {
    fakeTraccar = createServer(
      (
        incoming: IncomingMessage,
        outgoing: ServerResponse,
      ) => {
        void handleFakeTraccar(incoming, outgoing);
      },
    );

    await new Promise<void>((resolve, reject) => {
      fakeTraccar.once('error', reject);
      fakeTraccar.listen(0, '127.0.0.1', () => {
        fakeTraccar.off('error', reject);
        resolve();
      });
    });

    const address = fakeTraccar.address() as AddressInfo;
    fakeTraccarBaseUrl = `http://127.0.0.1:${address.port}`;

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
        userCode: `USR-TRK-${codeSuffix}`,
        fullName: 'Tracking E2E Administrator',
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

    const roleAssignment = await prisma.roleAssignment.create({
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

    platformRoleAssignmentId = roleAssignment.id;

    const loginResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login')
      .send({
        mobileNumber,
        password,
        platform: 'WEB',
        deviceName: 'Tracking E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = loginResponse.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

    if (prisma) {
      if (notificationRuleId) {
        await prisma.notificationRule.updateMany({
          where: {
            id: notificationRuleId,
          },
          data: {
            enabled: false,
            archivedAt: now,
          },
        });
      }

      if (geofenceId) {
        await prisma.vehicleGeofenceAssignment.updateMany({
          where: {
            geofenceId,
            status: 'ACTIVE',
          },
          data: {
            status: 'ENDED',
            activeUntil: now,
          },
        });

        await prisma.geofence.updateMany({
          where: {
            id: geofenceId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
            syncStatus: 'DISABLED',
          },
        });
      }

      if (deviceId) {
        await prisma.traccarDeviceMapping.updateMany({
          where: {
            deviceId,
          },
          data: {
            isActive: false,
            isPrimary: false,
            syncStatus: 'DISABLED',
            disabledAt: now,
          },
        });

        await prisma.vehicleDeviceAssignment.updateMany({
          where: {
            deviceId,
            status: 'ACTIVE',
          },
          data: {
            status: 'ENDED',
            endedAt: now,
            endReason: 'OTHER',
            endNotes: 'Tracking E2E cleanup',
            endedByUserId: platformUserId,
          },
        });

        await prisma.deviceInstallation.updateMany({
          where: {
            deviceId,
            status: {
              in: ['SCHEDULED', 'IN_PROGRESS', 'COMPLETED'],
            },
          },
          data: {
            status: 'REMOVED',
            removedAt: now,
            removalReason: 'OTHER',
          },
        });

        await prisma.device.updateMany({
          where: {
            id: deviceId,
          },
          data: {
            lifecycleStatus: 'RETIRED',
            retiredAt: now,
          },
        });
      }

      if (traccarServerId) {
        await prisma.traccarServer.updateMany({
          where: {
            id: traccarServerId,
          },
          data: {
            isDefault: false,
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (deviceModelId) {
        await prisma.deviceModel.updateMany({
          where: {
            id: deviceModelId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (vehicleId) {
        await prisma.vehicle.updateMany({
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
        await prisma.customer.updateMany({
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
        await prisma.organization.updateMany({
          where: {
            id: dealerId,
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

    if (fakeTraccar) {
      await new Promise<void>((resolve, reject) => {
        fakeTraccar.close((error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        });
      });
    }
  });

  it('synchronizes tracking, positions, events, geofences, notifications, commands, and jobs', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Tracking E2E Dealer ${codeSuffix}`,
        contactMobile: `017${numericSuffix}`,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        managingDealerId: dealerId,
        fullName: `Tracking E2E Customer ${codeSuffix}`,
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
        registrationNumber: `DHAKA-TRK-${codeSuffix}`,
        manufacturer: 'Solid Tracker Test',
        modelName: 'Tracking Lifecycle Car',
        manufacturingYear: 2026,
      })
      .expect(201);

    vehicleId = vehicleResponse.body.id as string;

    const modelResponse = await request(app.getHttpServer())
      .post('/api/v1/device-models')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        manufacturer: `Tracking E2E ${codeSuffix}`,
        modelName: 'ST-TRACK-100',
        protocol: 'osmand',
        networkType: 'LTE_4G',
        capabilities: {
          ignition: true,
          relay: true,
          commands: true,
        },
      })
      .expect(201);

    deviceModelId = modelResponse.body.id as string;

    const deviceResponse = await request(app.getHttpServer())
      .post('/api/v1/devices')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceModelId,
        imei,
        serialNumber: `ST-TRK-${codeSuffix}`,
        hardwareVersion: '1.0',
        firmwareVersion: '1.0.0',
      })
      .expect(201);

    deviceId = deviceResponse.body.id as string;

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${deviceId}/allocate`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        notes: 'Tracking E2E allocation',
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/api/v1/devices/${deviceId}/install`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        vehicleId,
        latitude: 23.8103,
        longitude: 90.4125,
        ignitionConnected: true,
        relayConnected: true,
        powerConnectionType: 'BATTERY_DIRECT',
      })
      .expect(201);

    const serverResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/traccar-servers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Fake Traccar ${codeSuffix}`,
        baseUrl: fakeTraccarBaseUrl,
        username: 'tracking-api',
        password: 'tracking-secret',
        isDefault: true,
      })
      .expect(201);

    traccarServerId = serverResponse.body.id as string;
    const serverCode = serverResponse.body.serverCode as string;

    await request(app.getHttpServer())
      .post(
        `/api/v1/tracking/traccar-servers/${traccarServerId}/health-check`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);

    const syncResponse = await request(app.getHttpServer())
      .post(`/api/v1/tracking/devices/${deviceId}/sync`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        serverId: traccarServerId,
      })
      .expect(201);

    expect(syncResponse.body.mapping.syncStatus).toBe('SYNCED');
    expect(syncResponse.body.mapping.traccarDeviceId).toBe('101');

    const liveResponse = await request(app.getHttpServer())
      .get(
        `/api/v1/tracking/vehicles/${vehicleId}/live-position`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(liveResponse.body.position.latitude).toBe(23.8103);
    expect(liveResponse.body.position.longitude).toBe(90.4125);

    const geofenceResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/geofences')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        name: `E2E Safe Zone ${codeSuffix}`,
        geometryType: 'CIRCLE',
        geometryData: {
          center: {
            latitude: 23.8103,
            longitude: 90.4125,
          },
          radius: 500,
        },
        status: 'ACTIVE',
      })
      .expect(201);

    geofenceId = geofenceResponse.body.id as string;

    const geofenceSyncResponse = await request(
      app.getHttpServer(),
    )
      .post(
        `/api/v1/tracking/geofences/${geofenceId}/sync`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        serverId: traccarServerId,
      })
      .expect(201);

    expect(
      geofenceSyncResponse.body.geofence.syncStatus,
    ).toBe('SYNCED');

    await request(app.getHttpServer())
      .post(
        `/api/v1/tracking/geofences/${geofenceId}/assignments`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        vehicleId,
        monitorEntry: true,
        monitorExit: true,
      })
      .expect(201);

    const ruleResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/notification-rules')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        vehicleId,
        eventType: 'deviceOverspeed',
        minimumSeverity: 'WARNING',
        channel: 'IN_APP',
        recipientType: 'CUSTOM_ADDRESS',
        recipientAddress: `in-app:e2e:${codeSuffix}`,
        enabled: true,
        cooldownSeconds: 0,
        dailyLimit: 10,
      })
      .expect(201);

    notificationRuleId = ruleResponse.body.id as string;

    const eventTime = new Date().toISOString();
    const webhookSecret = process.env.TRACKING_WEBHOOK_SECRET;

    if (!webhookSecret) {
      throw new Error(
        'TRACKING_WEBHOOK_SECRET is required for tracking E2E.',
      );
    }

    const webhookResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/webhooks/traccar')
      .set('X-Tracking-Webhook-Secret', webhookSecret)
      .send({
        serverCode,
        event: {
          id: 7001,
          type: 'deviceOverspeed',
          eventTime,
          deviceId: 101,
          attributes: {
            speedLimit: 60,
          },
        },
        device: {
          id: 101,
          uniqueId: imei,
          name: `DHAKA-TRK-${codeSuffix}`,
        },
        position: {
          id: 5001,
          deviceId: 101,
          fixTime: eventTime,
          latitude: 23.8103,
          longitude: 90.4125,
          speed: 80,
          attributes: {
            ignition: true,
          },
        },
      })
      .expect(201);

    expect(webhookResponse.body.duplicate).toBe(false);
    expect(webhookResponse.body.event.severity).toBe('WARNING');
    expect(webhookResponse.body.notifications).toHaveLength(1);

    trackingEventId = webhookResponse.body.event.id as string;

    const eventListResponse = await request(app.getHttpServer())
      .get(
        `/api/v1/tracking/events?vehicleId=${vehicleId}`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(eventListResponse.body.total).toBeGreaterThanOrEqual(1);

    const acknowledgedResponse = await request(
      app.getHttpServer(),
    )
      .post(
        `/api/v1/tracking/events/${trackingEventId}/acknowledge`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);

    expect(acknowledgedResponse.body.acknowledgedAt).toBeTruthy();

    const notificationsResponse = await request(
      app.getHttpServer(),
    )
      .get(
        `/api/v1/tracking/notifications?trackingEventId=${trackingEventId}`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(notificationsResponse.body.total).toBe(1);
    expect(notificationsResponse.body.items[0].status).toBe(
      'QUEUED',
    );

    const commandResponse = await request(app.getHttpServer())
      .post('/api/v1/tracking/commands')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        deviceId,
        vehicleId,
        commandType: 'REQUEST_POSITION',
        parameters: {},
        reason: 'Tracking E2E position request',
      })
      .expect(201);

    expect(commandResponse.body.status).toBe('COMPLETED');
    expect(commandResponse.body.traccarCommandId).toBe('301');

    const jobsResponse = await request(app.getHttpServer())
      .get('/api/v1/tracking/integration-jobs')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(jobsResponse.body.total).toBeGreaterThanOrEqual(5);

    await request(app.getHttpServer())
      .post(
        `/api/v1/tracking/geofences/${geofenceId}/assignments/${vehicleId}/end`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);
  });

  async function handleFakeTraccar(
    incoming: IncomingMessage,
    outgoing: ServerResponse,
  ): Promise<void> {
    const url = new URL(
      incoming.url ?? '/',
      fakeTraccarBaseUrl || 'http://127.0.0.1',
    );
    const method = incoming.method ?? 'GET';

    if (!incoming.headers.authorization) {
      respond(outgoing, 401, {
        message: 'Authorization required',
      });
      return;
    }

    if (method === 'GET' && url.pathname === '/api/server') {
      respond(outgoing, 200, {
        id: 1,
        version: '6.14.5-test',
        registration: false,
        readonly: false,
      });
      return;
    }

    if (method === 'GET' && url.pathname === '/api/devices') {
      const uniqueId = url.searchParams.get('uniqueId');
      respond(
        outgoing,
        200,
        uniqueId
          ? fakeDevices.filter(
              (device) => device.uniqueId === uniqueId,
            )
          : fakeDevices,
      );
      return;
    }

    if (method === 'POST' && url.pathname === '/api/devices') {
      const body = (await readJson(incoming)) as Omit<
        FakeDevice,
        'id'
      >;
      const device: FakeDevice = {
        ...body,
        id: nextDeviceId++,
      };

      fakeDevices.push(device);
      respond(outgoing, 200, device);
      return;
    }

    if (
      method === 'PUT' &&
      /^\/api\/devices\/\d+$/.test(url.pathname)
    ) {
      const id = Number(url.pathname.split('/').at(-1));
      const body = (await readJson(incoming)) as FakeDevice;
      const index = fakeDevices.findIndex(
        (device) => device.id === id,
      );
      const device = {
        ...body,
        id,
      };

      if (index >= 0) {
        fakeDevices[index] = device;
      } else {
        fakeDevices.push(device);
      }

      respond(outgoing, 200, device);
      return;
    }

    if (
      method === 'GET' &&
      url.pathname === '/api/positions'
    ) {
      respond(outgoing, 200, [
        {
          id: 5001,
          deviceId: 101,
          protocol: 'osmand',
          serverTime: new Date().toISOString(),
          deviceTime: new Date().toISOString(),
          fixTime: new Date().toISOString(),
          valid: true,
          latitude: 23.8103,
          longitude: 90.4125,
          altitude: 8,
          speed: 25,
          course: 180,
          accuracy: 5,
          attributes: {
            ignition: true,
          },
        },
      ]);
      return;
    }

    if (
      method === 'POST' &&
      url.pathname === '/api/geofences'
    ) {
      const body = (await readJson(incoming)) as Omit<
        FakeGeofence,
        'id'
      >;
      const geofence: FakeGeofence = {
        ...body,
        id: nextGeofenceId++,
      };

      fakeGeofences.push(geofence);
      respond(outgoing, 200, geofence);
      return;
    }

    if (
      method === 'PUT' &&
      /^\/api\/geofences\/\d+$/.test(url.pathname)
    ) {
      const id = Number(url.pathname.split('/').at(-1));
      const body = (await readJson(incoming)) as FakeGeofence;
      const index = fakeGeofences.findIndex(
        (geofence) => geofence.id === id,
      );
      const geofence = {
        ...body,
        id,
      };

      if (index >= 0) {
        fakeGeofences[index] = geofence;
      } else {
        fakeGeofences.push(geofence);
      }

      respond(outgoing, 200, geofence);
      return;
    }

    if (
      ['POST', 'DELETE'].includes(method) &&
      url.pathname === '/api/permissions'
    ) {
      await readJson(incoming);
      outgoing.statusCode = 204;
      outgoing.end();
      return;
    }

    if (
      method === 'POST' &&
      url.pathname === '/api/commands/send'
    ) {
      const body = (await readJson(incoming)) as {
        deviceId: number;
        type: string;
        attributes?: Record<string, unknown>;
      };
      const command = {
        id: nextCommandId++,
        ...body,
      };

      respond(outgoing, 200, command);
      return;
    }

    respond(outgoing, 404, {
      message: `${method} ${url.pathname} not implemented`,
    });
  }

  async function readJson(
    incoming: IncomingMessage,
  ): Promise<unknown> {
    const chunks: Buffer[] = [];

    for await (const chunk of incoming) {
      chunks.push(Buffer.from(chunk));
    }

    if (chunks.length === 0) {
      return {};
    }

    return JSON.parse(
      Buffer.concat(chunks).toString('utf8'),
    ) as unknown;
  }

  function respond(
    outgoing: ServerResponse,
    status: number,
    body: unknown,
  ): void {
    outgoing.statusCode = status;
    outgoing.setHeader('Content-Type', 'application/json');
    outgoing.end(JSON.stringify(body));
  }
});
'@


    Write-Step 5 9 "Registering the tracking module"

    $appModulePath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\app.module.ts"

    $appModuleContent = [System.IO.File]::ReadAllText(
        $appModulePath
    )

    $trackingImport =
        "import { TrackingApiModule } from './tracking/tracking-api.module';"

    if (-not $appModuleContent.Contains($trackingImport)) {
        $modulePattern =
            "(?m)^import \{ Module \} from '@nestjs/common';\r?$"
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
            $trackingImport +
            $appModuleContent.Substring(
                $moduleMatch.Index + $moduleMatch.Length
            )
        )
    }

    if (-not $appModuleContent.Contains("TrackingApiModule,")) {
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
            "TrackingApiModule," +
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

    Write-Step 6 9 "Running complete backend verification"

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

    Write-Step 7 9 "Verifying tracking permissions and database invariants"

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
      'vehicle.location.view',
      'vehicle.history.view',
      'command.send',
      'command.engine_cutoff'
    )
      AND "status" = 'ACTIVE'
  ) AS tracking_permission_count,
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'traccar_servers_one_active_default',
        'traccar_device_mappings_one_active_primary_per_device',
        'vehicle_geofence_assignments_one_active_pair'
      )
  ) AS tracking_index_count,
  (
    SELECT COUNT(DISTINCT trigger_name)
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'traccar_mappings_validate_server',
        'tracking_events_validate_context',
        'geofences_validate_context',
        'geofence_assignments_validate_context',
        'notification_rules_validate_context',
        'notifications_validate_context',
        'device_commands_validate_context',
        'integration_jobs_validate_context'
      )
  ) AS tracking_trigger_count;
'@

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "Tracking database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split(",")

    if ($parts.Count -ne 5) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTableCount = [int]$parts[0]
    $appliedMigrationCount = [int]$parts[1]
    $permissionCount = [int]$parts[2]
    $indexCount = [int]$parts[3]
    $triggerCount = [int]$parts[4]

    if ($publicTableCount -lt 50) {
        throw "Expected at least 50 public tables."
    }

    if ($appliedMigrationCount -ne 5) {
        throw "Expected exactly 5 applied migrations."
    }

    if ($permissionCount -ne 4) {
        throw "Expected 4 active tracking permissions."
    }

    if ($indexCount -ne 3) {
        throw "Expected 3 tracking invariant indexes."
    }

    if ($triggerCount -ne 8) {
        throw "Expected 8 distinct tracking triggers."
    }

    Write-Host "Public tables:        $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:   $appliedMigrationCount" -ForegroundColor Green
    Write-Host "Tracking permissions: $permissionCount" -ForegroundColor Green
    Write-Host "Tracking indexes:     $indexCount" -ForegroundColor Green
    Write-Host "Tracking triggers:    $triggerCount" -ForegroundColor Green

    Write-Step 8 9 "Writing tracking architecture documentation"

    Write-Utf8File `
        "docs\architecture\tracking-api.md" `
        @'
# Tracking and Traccar Operations API

## Scope

This stage exposes the existing Traccar integration foundation through authenticated REST APIs and secure webhook processing.

It implements:

- encrypted Traccar server credentials;
- Traccar server health checks;
- physical-device synchronization and mappings;
- live vehicle positions and bounded position history;
- normalized and deduplicated tracking events;
- secure Traccar webhook ingestion;
- geofence CRUD, Traccar synchronization, and vehicle assignment;
- notification rules and queued notification history;
- device commands with engine-control approval;
- integration-job history, retry, and cancellation;
- platform, dealer, and customer resource scopes;
- audit history and full E2E coverage.

No Prisma migration is introduced. The existing tracking foundation already contains the required tables, constraints, indexes, and validation triggers.

## System boundary

```text
GPS device
    ↓ protocol
Traccar
    ↓ REST and webhook integration
Solid Tracker NestJS API
    ↓ authenticated business API
Android, web, dealer, customer, and operations clients
```

Clients never connect directly to Traccar. Solid Tracker applies authentication, permissions, resource scope, customer ownership, assignment validation, and command safety before communicating with Traccar.

## Credential security

Traccar usernames, passwords, and tokens are encrypted using AES-256-GCM. The encryption key is stored only in the runtime environment.

The API never returns encrypted credential material. Responses expose only whether credentials are configured.

## Device synchronization

A physical device is synchronized using its IMEI or serial number.

The mapping stores:

- Solid Tracker device ID;
- Traccar server ID;
- Traccar device ID;
- Traccar unique ID;
- active and primary status;
- synchronization attempts, timestamps, and errors.

The database allows only one active primary mapping per physical device.

## Positions

The live-position endpoint resolves:

```text
vehicle
→ active primary vehicle-device assignment
→ active synchronized Traccar mapping
→ latest Traccar position
```

Position history is bounded to 31 days per request.

## Events and notifications

The Traccar webhook requires `X-Tracking-Webhook-Secret`.

Incoming events are normalized, deduplicated, connected to the current customer, vehicle, device, and Traccar server, and then evaluated against notification rules.

Notification rules support severity thresholds, quiet hours, cooldowns, daily limits, vehicle scope, recipient types, and multiple delivery channels. Delivery-provider adapters remain separate from event normalization.

## Geofences

Solid Tracker owns geofence business configuration. Traccar performs geographic detection.

Circle, polygon, and polyline geometry is validated before synchronization. A vehicle and geofence must belong to the same customer. Only one active assignment may exist for a geofence and vehicle pair.

## Device commands

Normal commands are sent after permission and active-mapping checks.

Engine cutoff and restore require:

1. `command.send`;
2. `command.engine_cutoff`;
3. an active vehicle-device assignment;
4. approval by a different authorized user;
5. an unexpired approval window.

Command requests preserve requester, approver, reason, parameters, Traccar command ID, lifecycle timestamps, and failure details.

## Integration jobs

Every external synchronization operation creates an integration job with idempotency, attempt counts, retry timing, result data, and error history.

The current stage executes requested operations synchronously while preserving the job boundary required for a future background worker and queue.
'@

    Write-Step 9 9 "Committing the tracking API"

    git add -- `
        ".env.example" `
        "docs/architecture/tracking-api.md" `
        "scripts/solid-tracker-tracking-api.ps1" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/tracking" `
        "services/backend-api/test/tracking.e2e-spec.ts"

    git commit `
        -m "feat(tracking): establish Traccar synchronization and operations APIs"

    if ($LASTEXITCODE -ne 0) {
        throw "Tracking API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Tracking and Traccar API Ready" -ForegroundColor Cyan
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
        "Payment-gateway adapters, recurring billing automation, " +
        "webhook signatures, and reconciliation"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "TRACKING AND TRACCAR API FAILED" -ForegroundColor Red
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
