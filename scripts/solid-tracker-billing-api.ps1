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
        "?? scripts/solid-tracker-billing-api.ps1"
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
            "Working tree contains changes other than this billing API script."
        )
    }
}

function New-SecureBase64 {
    $bytes = New-Object byte[] 32
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
    $content = [System.IO.File]::ReadAllText($fullPath)
    $pattern = "(?m)^" + [regex]::Escape($Name) + "="

    if ([regex]::IsMatch($content, $pattern)) {
        Write-Host "[PRESERVED] $RelativePath contains $Name" -ForegroundColor DarkYellow
        return
    }

    if (
        $content.Length -gt 0 -and
        -not $content.EndsWith("`n")
    ) {
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

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Billing API" -ForegroundColor Cyan
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

    Write-Step 1 9 "Merging vehicle-device APIs and creating the billing branch"

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -eq "feat/vehicle-device-api") {
        Assert-CleanExceptSelf

        Invoke-CheckedCommand "Checkout main" {
            git checkout main
        }

        git merge-base --is-ancestor `
            feat/vehicle-device-api `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge vehicle and device APIs into main" {
                git merge `
                    --no-ff `
                    feat/vehicle-device-api `
                    -m "merge: integrate vehicle and device APIs"
            }
        }
        else {
            Write-Host (
                "Vehicle and device APIs are already contained in main."
            ) -ForegroundColor Green
        }

        $branchExists = git branch --list "feat/billing-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing billing API branch" {
                git checkout feat/billing-api
            }
        }
        else {
            Invoke-CheckedCommand "Create billing API branch" {
                git checkout -b feat/billing-api
            }
        }
    }
    elseif ($currentBranch -eq "main") {
        Assert-CleanExceptSelf

        git merge-base --is-ancestor `
            feat/vehicle-device-api `
            main

        if ($LASTEXITCODE -ne 0) {
            Invoke-CheckedCommand "Merge vehicle and device APIs into main" {
                git merge `
                    --no-ff `
                    feat/vehicle-device-api `
                    -m "merge: integrate vehicle and device APIs"
            }
        }

        $branchExists = git branch --list "feat/billing-api"

        if ($branchExists) {
            Invoke-CheckedCommand "Checkout existing billing API branch" {
                git checkout feat/billing-api
            }
        }
        else {
            Invoke-CheckedCommand "Create billing API branch" {
                git checkout -b feat/billing-api
            }
        }
    }
    elseif ($currentBranch -eq "feat/billing-api") {
        Assert-CleanExceptSelf
        Write-Host "Already on feat/billing-api." -ForegroundColor Green
    }
    else {
        throw (
            "Expected feat/vehicle-device-api, main, or feat/billing-api. " +
            "Current branch: $currentBranch"
        )
    }

    Write-Step 2 9 "Validating infrastructure, migrations, and billing schema"

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
        "model ServicePlan {",
        "model Subscription {",
        "model Invoice {",
        "model InvoiceLine {",
        "model Payment {",
        "model PaymentAllocation {",
        "model PaymentGatewayEvent {",
        "model Refund {",
        "model CommissionRule {",
        "model CommissionEntry {",
        "model DealerPayoutAccount {",
        "model DealerSettlement {",
        "model DealerSettlementItem {",
        "model DealerLedgerEntry {"
    )) {
        if (-not $schemaContent.Contains($requiredModel)) {
            throw "Required Prisma billing model is missing: $requiredModel"
        }
    }

    Write-Host "PostgreSQL:    healthy" -ForegroundColor Green
    Write-Host "Redis:         healthy" -ForegroundColor Green
    Write-Host "Billing schema: present" -ForegroundColor Green
    Write-Host "New migration: not required" -ForegroundColor Green

    Write-Step 3 9 "Configuring payout-account encryption"

    Ensure-EnvEntry `
        ".env" `
        "BILLING_PAYOUT_ENCRYPTION_KEY" `
        (New-SecureBase64)

    Ensure-EnvEntry `
        ".env.example" `
        "BILLING_PAYOUT_ENCRYPTION_KEY" `
        "replace-with-a-dedicated-random-secret-at-least-32-characters"

    $validationPath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\config\environment.validation.ts"

    $validationContent = [System.IO.File]::ReadAllText(
        $validationPath
    )

    if (
        -not $validationContent.Contains(
            "BILLING_PAYOUT_ENCRYPTION_KEY"
        )
    ) {
        $closingIndex = $validationContent.LastIndexOf("});")

        if ($closingIndex -lt 0) {
            throw "Could not locate the environment-validation object."
        }

        $validationEntry = (
            "  BILLING_PAYOUT_ENCRYPTION_KEY: " +
            "Joi.string().min(32).required()," +
            [Environment]::NewLine
        )

        $validationContent = $validationContent.Insert(
            $closingIndex,
            $validationEntry
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
            "[PRESERVED] environment validation already contains the billing key"
        ) -ForegroundColor DarkYellow
    }

    Write-Step 4 9 "Writing billing, commission, and settlement APIs"
    Write-Utf8File `
        "services\backend-api\src\billing\common\billing-code.service.ts" `
        @'

import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

@Injectable()
export class BillingCodeService {
  plan(): string {
    return this.create('PLN');
  }

  subscription(): string {
    return this.create('SUB');
  }

  invoice(): string {
    return this.create('INV');
  }

  payment(): string {
    return this.create('PAY');
  }

  refund(): string {
    return this.create('RFD');
  }

  commissionRule(): string {
    return this.create('CMR');
  }

  commission(): string {
    return this.create('COM');
  }

  payoutAccount(): string {
    return this.create('PAC');
  }

  settlement(): string {
    return this.create('SET');
  }

  ledger(): string {
    return this.create('LED');
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
        "services\backend-api\src\billing\common\billing-money.service.ts" `
        @'
import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';

type DecimalInput = Prisma.Decimal | string | number;

@Injectable()
export class BillingMoneyService {
  decimal(value: DecimalInput): Prisma.Decimal {
    return new Prisma.Decimal(value);
  }

  money(value: DecimalInput): Prisma.Decimal {
    return this.decimal(value).toDecimalPlaces(2);
  }

  quantity(value: DecimalInput): Prisma.Decimal {
    return this.decimal(value).toDecimalPlaces(3);
  }

  requireNonNegative(
    value: DecimalInput,
    field: string,
  ): Prisma.Decimal {
    const decimal = this.money(value);

    if (decimal.isNegative()) {
      throw new BadRequestException(`${field} cannot be negative.`);
    }

    return decimal;
  }

  requirePositive(
    value: DecimalInput,
    field: string,
  ): Prisma.Decimal {
    const decimal = this.money(value);

    if (!decimal.isPositive()) {
      throw new BadRequestException(
        `${field} must be greater than zero.`,
      );
    }

    return decimal;
  }

  sum(values: DecimalInput[]): Prisma.Decimal {
    return values.reduce<Prisma.Decimal>(
      (total, value) => total.plus(this.decimal(value)),
      new Prisma.Decimal(0),
    );
  }

  invoiceLine(input: {
    quantity: DecimalInput;
    unitPrice: DecimalInput;
    discountAmount?: DecimalInput;
    taxAmount?: DecimalInput;
  }): {
    quantity: Prisma.Decimal;
    unitPrice: Prisma.Decimal;
    grossAmount: Prisma.Decimal;
    discountAmount: Prisma.Decimal;
    taxAmount: Prisma.Decimal;
    lineTotal: Prisma.Decimal;
  } {
    const quantity = this.quantity(input.quantity);
    const unitPrice = this.requireNonNegative(
      input.unitPrice,
      'unitPrice',
    );
    const discountAmount = this.requireNonNegative(
      input.discountAmount ?? 0,
      'discountAmount',
    );
    const taxAmount = this.requireNonNegative(
      input.taxAmount ?? 0,
      'taxAmount',
    );
    const grossAmount = quantity
      .mul(unitPrice)
      .toDecimalPlaces(2);
    const lineTotal = grossAmount
      .minus(discountAmount)
      .plus(taxAmount)
      .toDecimalPlaces(2);

    if (quantity.lte(0)) {
      throw new BadRequestException(
        'Invoice line quantity must be greater than zero.',
      );
    }

    if (discountAmount.gt(grossAmount)) {
      throw new BadRequestException(
        'Invoice line discount cannot exceed its gross amount.',
      );
    }

    if (lineTotal.isNegative()) {
      throw new BadRequestException(
        'Invoice line total cannot be negative.',
      );
    }

    return {
      quantity,
      unitPrice,
      grossAmount,
      discountAmount,
      taxAmount,
      lineTotal,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\common\billing-date.service.ts" `
        @'

import { Injectable } from '@nestjs/common';

@Injectable()
export class BillingDateService {
  addInterval(
    value: Date,
    unit: 'DAY' | 'MONTH' | 'YEAR',
    count: number,
  ): Date {
    const result = new Date(value);

    if (unit === 'DAY') {
      result.setUTCDate(result.getUTCDate() + count);
      return result;
    }

    if (unit === 'MONTH') {
      const day = result.getUTCDate();
      result.setUTCDate(1);
      result.setUTCMonth(result.getUTCMonth() + count);
      const lastDay = new Date(
        Date.UTC(
          result.getUTCFullYear(),
          result.getUTCMonth() + 1,
          0,
        ),
      ).getUTCDate();
      result.setUTCDate(Math.min(day, lastDay));
      return result;
    }

    const month = result.getUTCMonth();
    const day = result.getUTCDate();
    result.setUTCDate(1);
    result.setUTCFullYear(result.getUTCFullYear() + count);
    result.setUTCMonth(month);
    const lastDay = new Date(
      Date.UTC(
        result.getUTCFullYear(),
        result.getUTCMonth() + 1,
        0,
      ),
    ).getUTCDate();
    result.setUTCDate(Math.min(day, lastDay));
    return result;
  }

  addDays(value: Date, days: number): Date {
    return this.addInterval(value, 'DAY', days);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\common\payout-account-crypto.service.ts" `
        @'

import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  createCipheriv,
  createHash,
  randomBytes,
} from 'node:crypto';

@Injectable()
export class PayoutAccountCryptoService {
  private readonly key: Buffer;

  constructor(configService: ConfigService) {
    this.key = createHash('sha256')
      .update(
        configService.getOrThrow<string>(
          'BILLING_PAYOUT_ENCRYPTION_KEY',
        ),
      )
      .digest();
  }

  encrypt(value: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const encrypted = Buffer.concat([
      cipher.update(value, 'utf8'),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();

    return [
      iv.toString('base64url'),
      tag.toString('base64url'),
      encrypted.toString('base64url'),
    ].join('.');
  }

  mask(value: string): string {
    const trimmed = value.trim();

    if (trimmed.length <= 4) {
      return '*'.repeat(trimmed.length);
    }

    return `${'*'.repeat(Math.min(8, trimmed.length - 4))}${trimmed.slice(-4)}`;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\common\billing-access.service.ts" `
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
export class BillingAccessService {
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

  actorOrganizationId(auth: AuthContext): string | undefined {
    return this.dealerScopeIds(auth)[0] ?? auth.organizationIds[0];
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

  subscriptionWhere(
    auth: AuthContext,
  ): Prisma.SubscriptionWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  invoiceWhere(auth: AuthContext): Prisma.InvoiceWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);
    const scopes: Prisma.InvoiceWhereInput[] = [];

    if (dealerIds.length > 0) {
      scopes.push(
        {
          managingDealerIdAtIssue: {
            in: dealerIds,
          },
        },
        {
          customer: {
            managingDealerId: {
              in: dealerIds,
            },
          },
        },
      );
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

  paymentWhere(auth: AuthContext): Prisma.PaymentWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      customer: this.customerWhere(auth),
    };
  }

  commissionWhere(
    auth: AuthContext,
  ): Prisma.CommissionEntryWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    const scopes: Prisma.CommissionEntryWhereInput[] = [];
    const dealerIds = this.dealerScopeIds(auth);
    const customerIds = this.customerScopeIds(auth);

    if (dealerIds.length > 0) {
      scopes.push({
        dealerOrganizationId: {
          in: dealerIds,
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

  settlementWhere(
    auth: AuthContext,
  ): Prisma.DealerSettlementWhereInput {
    if (this.isPlatformScoped(auth)) {
      return {};
    }

    return {
      dealerOrganizationId: {
        in: this.dealerScopeIds(auth),
      },
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

  async assertFinancialOperator(
    auth: AuthContext,
    customerId: string,
  ): Promise<void> {
    const customer = await this.assertCustomer(auth, customerId);

    if (this.isPlatformScoped(auth)) {
      return;
    }

    if (
      !customer.managingDealerId ||
      !this.dealerScopeIds(auth).includes(
        customer.managingDealerId,
      )
    ) {
      throw new ForbiddenException(
        'Financial confirmation requires platform or matching dealer scope.',
      );
    }
  }

  async assertSubscription(
    auth: AuthContext,
    subscriptionId: string,
  ): Promise<void> {
    const count = await this.prisma.subscription.count({
      where: {
        AND: [
          {
            id: subscriptionId,
          },
          this.subscriptionWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException(
        'Subscription was not found within the authenticated scope.',
      );
    }
  }

  async assertInvoice(
    auth: AuthContext,
    invoiceId: string,
  ): Promise<void> {
    const count = await this.prisma.invoice.count({
      where: {
        AND: [
          {
            id: invoiceId,
          },
          this.invoiceWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException(
        'Invoice was not found within the authenticated scope.',
      );
    }
  }

  async assertPayment(
    auth: AuthContext,
    paymentId: string,
  ): Promise<void> {
    const count = await this.prisma.payment.count({
      where: {
        AND: [
          {
            id: paymentId,
          },
          this.paymentWhere(auth),
        ],
      },
    });

    if (count === 0) {
      throw new NotFoundException(
        'Payment was not found within the authenticated scope.',
      );
    }
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\common\billing-query.dto.ts" `
        @'

import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';

const planStatuses = [
  'DRAFT',
  'ACTIVE',
  'INACTIVE',
  'ARCHIVED',
] as const;

const subscriptionStatuses = [
  'PENDING',
  'TRIALING',
  'ACTIVE',
  'PAST_DUE',
  'SUSPENDED',
  'CANCELLED',
  'EXPIRED',
] as const;

const invoiceStatuses = [
  'DRAFT',
  'ISSUED',
  'PARTIALLY_PAID',
  'PAID',
  'OVERDUE',
  'VOID',
  'REFUNDED',
] as const;

const paymentStatuses = [
  'INITIATED',
  'PENDING',
  'SUCCEEDED',
  'FAILED',
  'CANCELLED',
  'REFUNDED',
  'PARTIALLY_REFUNDED',
] as const;

const commissionStatuses = [
  'PENDING',
  'EARNED',
  'ON_HOLD',
  'AVAILABLE',
  'SETTLEMENT_PENDING',
  'SETTLED',
  'REVERSED',
  'CANCELLED',
] as const;

const settlementStatuses = [
  'DRAFT',
  'PENDING',
  'PROCESSING',
  'COMPLETED',
  'FAILED',
  'CANCELLED',
  'REVERSED',
] as const;

export class ServicePlanQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: planStatuses })
  @IsOptional()
  @IsIn(planStatuses)
  status?: (typeof planStatuses)[number];
}

export class SubscriptionQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  vehicleId?: string;

  @ApiPropertyOptional({ enum: subscriptionStatuses })
  @IsOptional()
  @IsIn(subscriptionStatuses)
  status?: (typeof subscriptionStatuses)[number];
}

export class InvoiceQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @ApiPropertyOptional({ enum: invoiceStatuses })
  @IsOptional()
  @IsIn(invoiceStatuses)
  status?: (typeof invoiceStatuses)[number];
}

export class PaymentQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ enum: paymentStatuses })
  @IsOptional()
  @IsIn(paymentStatuses)
  status?: (typeof paymentStatuses)[number];
}

export class CommissionQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dealerOrganizationId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  customerId?: string;

  @ApiPropertyOptional({ enum: commissionStatuses })
  @IsOptional()
  @IsIn(commissionStatuses)
  status?: (typeof commissionStatuses)[number];
}

export class SettlementQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dealerOrganizationId?: string;

  @ApiPropertyOptional({ enum: settlementStatuses })
  @IsOptional()
  @IsIn(settlementStatuses)
  status?: (typeof settlementStatuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\service-plans\dto\create-service-plan.dto.ts" `
        @'

import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsDecimal,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

const intervalUnits = ['DAY', 'MONTH', 'YEAR'] as const;
const taxBehaviors = ['NONE', 'INCLUSIVE', 'EXCLUSIVE'] as const;

export class CreateServicePlanDto {
  @ApiProperty({ example: 'STANDARD_MONTHLY' })
  @IsString()
  @MinLength(2)
  @MaxLength(60)
  planFamilyCode!: string;

  @ApiProperty({ example: 'Standard Monthly' })
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiProperty({ enum: intervalUnits })
  @IsIn(intervalUnits)
  billingIntervalUnit!: (typeof intervalUnits)[number];

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(120)
  billingIntervalCount = 1;

  @ApiProperty({ example: '500.00' })
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  basePrice!: string;

  @ApiPropertyOptional({ default: 'BDT' })
  @IsOptional()
  @IsString()
  @MaxLength(3)
  currency = 'BDT';

  @ApiPropertyOptional({ enum: taxBehaviors, default: 'NONE' })
  @IsOptional()
  @IsIn(taxBehaviors)
  taxBehavior: (typeof taxBehaviors)[number] = 'NONE';

  @ApiPropertyOptional({ default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(365)
  trialDays = 0;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  features?: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  deviceLimit?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  historyRetentionDays?: number;

  @ApiProperty()
  @IsDateString()
  effectiveFrom!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveUntil?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\service-plans\dto\update-service-plan.dto.ts" `
        @'

import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsDecimal,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

const intervalUnits = ['DAY', 'MONTH', 'YEAR'] as const;
const taxBehaviors = ['NONE', 'INCLUSIVE', 'EXCLUSIVE'] as const;
const statuses = ['DRAFT', 'INACTIVE', 'ARCHIVED'] as const;

export class UpdateServicePlanDto {
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

  @ApiPropertyOptional({ enum: intervalUnits })
  @IsOptional()
  @IsIn(intervalUnits)
  billingIntervalUnit?: (typeof intervalUnits)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(120)
  billingIntervalCount?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  basePrice?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(3)
  currency?: string;

  @ApiPropertyOptional({ enum: taxBehaviors })
  @IsOptional()
  @IsIn(taxBehaviors)
  taxBehavior?: (typeof taxBehaviors)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(365)
  trialDays?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  features?: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  deviceLimit?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  historyRetentionDays?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveUntil?: string;

  @ApiPropertyOptional({ enum: statuses })
  @IsOptional()
  @IsIn(statuses)
  status?: (typeof statuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\service-plans\dto\create-plan-version.dto.ts" `
        @'

import { PartialType } from '@nestjs/swagger';
import { UpdateServicePlanDto } from './update-service-plan.dto';

export class CreatePlanVersionDto extends PartialType(
  UpdateServicePlanDto,
) {}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\subscriptions\dto\create-subscription.dto.ts" `
        @'

import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsOptional,
  IsUUID,
} from 'class-validator';

export class CreateSubscriptionDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiProperty()
  @IsUUID()
  vehicleId!: string;

  @ApiProperty()
  @IsUUID()
  servicePlanId!: string;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  autoRenew = true;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\subscriptions\dto\subscription-action.dto.ts" `
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

export class SubscriptionReasonDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  reason?: string;
}

export class GenerateSubscriptionInvoiceDto {
  @ApiPropertyOptional({ default: 7 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(365)
  dueInDays = 7;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\invoices\dto\create-invoice.dto.ts" `
        @'

import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsDecimal,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateNested,
} from 'class-validator';

const itemTypes = [
  'DEVICE_SALE',
  'INSTALLATION',
  'SUBSCRIPTION',
  'SIM_FEE',
  'REPLACEMENT',
  'ADD_ON',
  'DISCOUNT',
  'OTHER',
] as const;

export class CreateInvoiceLineDto {
  @ApiProperty({ enum: itemTypes })
  @IsIn(itemTypes)
  itemType!: (typeof itemTypes)[number];

  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  description!: string;

  @ApiPropertyOptional({ default: '1.000' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,3', force_decimal: false })
  quantity = '1.000';

  @ApiProperty()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  unitPrice!: string;

  @ApiPropertyOptional({ default: '0.00' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  discountAmount = '0.00';

  @ApiPropertyOptional({ default: '0.00' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  taxAmount = '0.00';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  referenceType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  referenceId?: string;
}

export class CreateInvoiceDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @ApiProperty()
  @IsDateString()
  issueDate!: string;

  @ApiProperty()
  @IsDateString()
  dueDate!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  billingPeriodStart?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  billingPeriodEnd?: string;

  @ApiProperty({
    type: CreateInvoiceLineDto,
    isArray: true,
  })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateInvoiceLineDto)
  lines!: CreateInvoiceLineDto[];
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\invoices\dto\invoice-action.dto.ts" `
        @'

import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsDateString,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class IssueInvoiceDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  issueDate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  dueDate?: string;
}

export class VoidInvoiceDto {
  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  reason!: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\payments\dto\create-payment.dto.ts" `
        @'

import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsDecimal,
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

const methods = [
  'BKASH',
  'NAGAD',
  'BANK_TRANSFER',
  'CARD',
  'CASH',
  'MANUAL_ADJUSTMENT',
] as const;

const gateways = [
  'NONE',
  'BKASH',
  'NAGAD',
  'SSLCOMMERZ',
  'BANK',
  'MANUAL',
  'OTHER',
] as const;

export class CreatePaymentDto {
  @ApiProperty()
  @IsUUID()
  customerId!: string;

  @ApiProperty()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  amount!: string;

  @ApiPropertyOptional({ default: 'BDT' })
  @IsOptional()
  @IsString()
  @MaxLength(3)
  currency = 'BDT';

  @ApiProperty({ enum: methods })
  @IsIn(methods)
  paymentMethod!: (typeof methods)[number];

  @ApiPropertyOptional({ enum: gateways, default: 'NONE' })
  @IsOptional()
  @IsIn(gateways)
  paymentGateway: (typeof gateways)[number] = 'NONE';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  gatewayReference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\payments\dto\confirm-payment.dto.ts" `
        @'

import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsDecimal,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateNested,
} from 'class-validator';

export class PaymentAllocationDto {
  @ApiProperty()
  @IsUUID()
  invoiceId!: string;

  @ApiProperty()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  amount!: string;
}

export class ConfirmPaymentDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  gatewayTransactionId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  gatewayReference?: string;

  @ApiPropertyOptional({
    type: PaymentAllocationDto,
    isArray: true,
  })
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PaymentAllocationDto)
  allocations?: PaymentAllocationDto[];
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\payments\dto\fail-payment.dto.ts" `
        @'

import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength } from 'class-validator';

export class FailPaymentDto {
  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  reason!: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\payments\dto\create-refund.dto.ts" `
        @'

import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsDecimal,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class CreateRefundDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  invoiceId?: string;

  @ApiProperty()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  amount!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  reason!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

export class CompleteRefundDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  gatewayRefundId?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\payments\dto\gateway-event.dto.ts" `
        @'

import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

const gateways = [
  'BKASH',
  'NAGAD',
  'SSLCOMMERZ',
  'BANK',
  'OTHER',
] as const;

export class GatewayEventDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  paymentId?: string;

  @ApiProperty({ enum: gateways })
  @IsIn(gateways)
  gateway!: (typeof gateways)[number];

  @ApiProperty()
  @IsString()
  @MaxLength(200)
  externalEventId!: string;

  @ApiProperty()
  @IsString()
  @MaxLength(120)
  eventType!: string;

  @ApiProperty()
  @IsObject()
  payload!: Record<string, unknown>;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\commissions\dto\create-commission-rule.dto.ts" `
        @'

import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsDecimal,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsUUID,
  Max,
  Min,
} from 'class-validator';

const transactionTypes = [
  'DEVICE_SALE',
  'INSTALLATION',
  'INITIAL_SUBSCRIPTION',
  'SUBSCRIPTION_RENEWAL',
  'UPGRADE',
  'ADD_ON_SERVICE',
] as const;

const calculationTypes = [
  'PERCENTAGE',
  'FIXED_AMOUNT',
  'TIERED',
  'NONE',
] as const;

export class CreateCommissionRuleDto {
  @ApiProperty()
  @IsUUID()
  dealerOrganizationId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  servicePlanId?: string;

  @ApiProperty({ enum: transactionTypes })
  @IsIn(transactionTypes)
  transactionType!: (typeof transactionTypes)[number];

  @ApiProperty({ enum: calculationTypes })
  @IsIn(calculationTypes)
  calculationType!: (typeof calculationTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,4', force_decimal: false })
  percentageRate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  fixedAmount?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  tierDefinition?: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  minimumAmount?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  maximumAmount?: string;

  @ApiPropertyOptional({ default: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10000)
  priority = 100;

  @ApiProperty()
  @IsDateString()
  effectiveFrom!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveUntil?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\commissions\dto\update-commission-rule.dto.ts" `
        @'

import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsDecimal,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  Max,
  Min,
} from 'class-validator';

const calculationTypes = [
  'PERCENTAGE',
  'FIXED_AMOUNT',
  'TIERED',
  'NONE',
] as const;

const statuses = ['DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED'] as const;

export class UpdateCommissionRuleDto {
  @ApiPropertyOptional({ enum: calculationTypes })
  @IsOptional()
  @IsIn(calculationTypes)
  calculationType?: (typeof calculationTypes)[number];

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,4', force_decimal: false })
  percentageRate?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  fixedAmount?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  tierDefinition?: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  minimumAmount?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  maximumAmount?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10000)
  priority?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  effectiveUntil?: string;

  @ApiPropertyOptional({ enum: statuses })
  @IsOptional()
  @IsIn(statuses)
  status?: (typeof statuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\commissions\dto\reverse-commission.dto.ts" `
        @'

import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength } from 'class-validator';

export class ReverseCommissionDto {
  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  reason!: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\settlements\dto\create-payout-account.dto.ts" `
        @'

import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

const accountTypes = [
  'BANK_ACCOUNT',
  'MOBILE_FINANCIAL_SERVICE',
  'PAYMENT_GATEWAY_ACCOUNT',
] as const;

const providers = ['BANK', 'BKASH', 'NAGAD', 'OTHER'] as const;

export class CreatePayoutAccountDto {
  @ApiProperty()
  @IsUUID()
  dealerOrganizationId!: string;

  @ApiProperty({ enum: accountTypes })
  @IsIn(accountTypes)
  accountType!: (typeof accountTypes)[number];

  @ApiProperty({ enum: providers })
  @IsIn(providers)
  provider!: (typeof providers)[number];

  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  accountHolderName!: string;

  @ApiProperty({
    description:
      'Sensitive account number or provider reference. It is encrypted before storage.',
  })
  @IsString()
  @MinLength(4)
  @MaxLength(300)
  accountReference!: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  isDefault = false;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\settlements\dto\update-payout-account.dto.ts" `
        @'

import { ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

const statuses = ['ACTIVE', 'INACTIVE', 'SUSPENDED', 'ARCHIVED'] as const;

export class UpdatePayoutAccountDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(160)
  accountHolderName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(4)
  @MaxLength(300)
  accountReference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;

  @ApiPropertyOptional({ enum: statuses })
  @IsOptional()
  @IsIn(statuses)
  status?: (typeof statuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\settlements\dto\verify-payout-account.dto.ts" `
        @'

import { ApiProperty } from '@nestjs/swagger';
import { IsIn } from 'class-validator';

const verificationStatuses = ['VERIFIED', 'REJECTED'] as const;

export class VerifyPayoutAccountDto {
  @ApiProperty({ enum: verificationStatuses })
  @IsIn(verificationStatuses)
  verificationStatus!: (typeof verificationStatuses)[number];
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\settlements\dto\create-settlement.dto.ts" `
        @'

import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  ArrayMinSize,
  IsArray,
  IsDecimal,
  IsOptional,
  IsUUID,
} from 'class-validator';

export class CreateSettlementDto {
  @ApiProperty()
  @IsUUID()
  dealerOrganizationId!: string;

  @ApiProperty()
  @IsUUID()
  payoutAccountId!: string;

  @ApiProperty({
    type: String,
    isArray: true,
  })
  @IsArray()
  @ArrayMinSize(1)
  @IsUUID('4', { each: true })
  commissionEntryIds!: string[];

  @ApiPropertyOptional({ default: '0.00' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  adjustmentAmount = '0.00';

  @ApiPropertyOptional({ default: '0.00' })
  @IsOptional()
  @IsDecimal({ decimal_digits: '0,2', force_decimal: false })
  feeAmount = '0.00';
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\settlements\dto\settlement-action.dto.ts" `
        @'

import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength } from 'class-validator';

export class CompleteSettlementDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  providerReference?: string;
}

export class FailSettlementDto {
  @ApiProperty()
  @IsString()
  @MaxLength(1000)
  reason!: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\service-plans\service-plans.service.ts" `
        @'

import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';
import type { ServicePlanQueryDto } from '../common/billing-query.dto';
import type { CreatePlanVersionDto } from './dto/create-plan-version.dto';
import type { CreateServicePlanDto } from './dto/create-service-plan.dto';
import type { UpdateServicePlanDto } from './dto/update-service-plan.dto';

@Injectable()
export class ServicePlansService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly auditService: AuditService,
  ) {}

  async list(query: ServicePlanQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.ServicePlanWhereInput = {
      ...(query.status
        ? {
            status: query.status,
          }
        : {
            status: {
              not: 'ARCHIVED',
            },
          }),
      ...(query.search
        ? {
            OR: [
              {
                planCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                planFamilyCode: {
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
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.servicePlan.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: [
          {
            planFamilyCode: 'asc',
          },
          {
            version: 'desc',
          },
        ],
        include: {
          _count: {
            select: {
              subscriptions: true,
              commissionRules: true,
            },
          },
        },
      }),
      this.prisma.servicePlan.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(planId: string) {
    const plan = await this.prisma.servicePlan.findUnique({
      where: {
        id: planId,
      },
      include: {
        subscriptions: {
          orderBy: {
            createdAt: 'desc',
          },
          take: 20,
        },
        commissionRules: {
          orderBy: [
            {
              priority: 'asc',
            },
            {
              effectiveFrom: 'desc',
            },
          ],
        },
      },
    });

    if (!plan) {
      throw new NotFoundException('Service plan was not found.');
    }

    return plan;
  }

  async create(auth: AuthContext, dto: CreateServicePlanDto) {
    this.access.assertPlatform(auth);

    const familyCode = dto.planFamilyCode.trim().toUpperCase();
    const basePrice = this.money.requireNonNegative(
      dto.basePrice,
      'basePrice',
    );
    const effectiveFrom = new Date(dto.effectiveFrom);
    const effectiveUntil = dto.effectiveUntil
      ? new Date(dto.effectiveUntil)
      : null;

    this.assertDateRange(effectiveFrom, effectiveUntil);

    const existingFamily =
      await this.prisma.servicePlan.findFirst({
        where: {
          planFamilyCode: familyCode,
        },
        select: {
          id: true,
        },
      });

    if (existingFamily) {
      throw new ConflictException(
        'Plan family already exists. Create a new version instead.',
      );
    }

    const plan = await this.prisma.servicePlan.create({
      data: {
        planCode: this.codes.plan(),
        planFamilyCode: familyCode,
        version: 1,
        name: dto.name.trim(),
        description: this.optional(dto.description),
        billingIntervalUnit: dto.billingIntervalUnit,
        billingIntervalCount: dto.billingIntervalCount,
        basePrice,
        currency: dto.currency.trim().toUpperCase(),
        taxBehavior: dto.taxBehavior,
        trialDays: dto.trialDays,
        features:
          dto.features as Prisma.InputJsonValue | undefined,
        deviceLimit: dto.deviceLimit,
        historyRetentionDays: dto.historyRetentionDays,
        status: 'DRAFT',
        effectiveFrom,
        effectiveUntil,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'service-plan.created',
      resourceType: 'ServicePlan',
      resourceId: plan.id,
      scopeType: 'PLATFORM',
      afterData: plan,
    });

    return plan;
  }

  async update(
    auth: AuthContext,
    planId: string,
    dto: UpdateServicePlanDto,
  ) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.servicePlan.findUnique({
      where: {
        id: planId,
      },
    });

    if (!before) {
      throw new NotFoundException('Service plan was not found.');
    }

    if (
      before.status !== 'DRAFT' &&
      this.containsCommercialChanges(dto)
    ) {
      throw new ConflictException(
        'Commercial fields of an activated plan version are immutable. Create a new version.',
      );
    }

    const effectiveFrom = dto.effectiveFrom
      ? new Date(dto.effectiveFrom)
      : before.effectiveFrom;
    const effectiveUntil =
      dto.effectiveUntil !== undefined
        ? new Date(dto.effectiveUntil)
        : before.effectiveUntil;

    this.assertDateRange(effectiveFrom, effectiveUntil);

    const updated = await this.prisma.servicePlan.update({
      where: {
        id: planId,
      },
      data: {
        name: dto.name?.trim(),
        description:
          dto.description !== undefined
            ? this.optional(dto.description)
            : undefined,
        billingIntervalUnit: dto.billingIntervalUnit,
        billingIntervalCount: dto.billingIntervalCount,
        basePrice:
          dto.basePrice !== undefined
            ? this.money.requireNonNegative(
                dto.basePrice,
                'basePrice',
              )
            : undefined,
        currency: dto.currency?.trim().toUpperCase(),
        taxBehavior: dto.taxBehavior,
        trialDays: dto.trialDays,
        features:
          dto.features as Prisma.InputJsonValue | undefined,
        deviceLimit: dto.deviceLimit,
        historyRetentionDays: dto.historyRetentionDays,
        effectiveFrom:
          dto.effectiveFrom !== undefined
            ? effectiveFrom
            : undefined,
        effectiveUntil:
          dto.effectiveUntil !== undefined
            ? effectiveUntil
            : undefined,
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
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'service-plan.updated',
      resourceType: 'ServicePlan',
      resourceId: planId,
      scopeType: 'PLATFORM',
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async activate(auth: AuthContext, planId: string) {
    this.access.assertPlatform(auth);

    const plan = await this.prisma.servicePlan.findUnique({
      where: {
        id: planId,
      },
    });

    if (!plan) {
      throw new NotFoundException('Service plan was not found.');
    }

    if (plan.status === 'ARCHIVED') {
      throw new ConflictException(
        'Archived plan versions cannot be activated.',
      );
    }

    const activated = await this.prisma.$transaction(
      async (transaction) => {
        await transaction.servicePlan.updateMany({
          where: {
            planFamilyCode: plan.planFamilyCode,
            id: {
              not: plan.id,
            },
            status: 'ACTIVE',
          },
          data: {
            status: 'INACTIVE',
          },
        });

        return transaction.servicePlan.update({
          where: {
            id: plan.id,
          },
          data: {
            status: 'ACTIVE',
          },
        });
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'service-plan.activated',
      resourceType: 'ServicePlan',
      resourceId: plan.id,
      scopeType: 'PLATFORM',
      beforeData: plan,
      afterData: activated,
    });

    return activated;
  }

  async createVersion(
    auth: AuthContext,
    planId: string,
    dto: CreatePlanVersionDto,
  ) {
    this.access.assertPlatform(auth);

    const source = await this.prisma.servicePlan.findUnique({
      where: {
        id: planId,
      },
    });

    if (!source) {
      throw new NotFoundException('Source service plan was not found.');
    }

    const latest = await this.prisma.servicePlan.findFirst({
      where: {
        planFamilyCode: source.planFamilyCode,
      },
      orderBy: {
        version: 'desc',
      },
      select: {
        version: true,
      },
    });

    const effectiveFrom = dto.effectiveFrom
      ? new Date(dto.effectiveFrom)
      : new Date();
    const effectiveUntil = dto.effectiveUntil
      ? new Date(dto.effectiveUntil)
      : null;

    this.assertDateRange(effectiveFrom, effectiveUntil);

    const version = await this.prisma.servicePlan.create({
      data: {
        planCode: this.codes.plan(),
        planFamilyCode: source.planFamilyCode,
        version: (latest?.version ?? source.version) + 1,
        name: dto.name?.trim() ?? source.name,
        description:
          dto.description !== undefined
            ? this.optional(dto.description)
            : source.description,
        billingIntervalUnit:
          dto.billingIntervalUnit ?? source.billingIntervalUnit,
        billingIntervalCount:
          dto.billingIntervalCount ??
          source.billingIntervalCount,
        basePrice:
          dto.basePrice !== undefined
            ? this.money.requireNonNegative(
                dto.basePrice,
                'basePrice',
              )
            : source.basePrice,
        currency:
          dto.currency?.trim().toUpperCase() ?? source.currency,
        taxBehavior: dto.taxBehavior ?? source.taxBehavior,
        trialDays: dto.trialDays ?? source.trialDays,
        features:
          dto.features !== undefined
            ? (dto.features as Prisma.InputJsonValue)
            : source.features === null
              ? Prisma.JsonNull
              : (source.features as Prisma.InputJsonValue),
        deviceLimit: dto.deviceLimit ?? source.deviceLimit,
        historyRetentionDays:
          dto.historyRetentionDays ??
          source.historyRetentionDays,
        status: 'DRAFT',
        effectiveFrom,
        effectiveUntil,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'service-plan.version-created',
      resourceType: 'ServicePlan',
      resourceId: version.id,
      scopeType: 'PLATFORM',
      beforeData: source,
      afterData: version,
    });

    return version;
  }

  private containsCommercialChanges(
    dto: UpdateServicePlanDto,
  ): boolean {
    return [
      dto.billingIntervalUnit,
      dto.billingIntervalCount,
      dto.basePrice,
      dto.currency,
      dto.taxBehavior,
      dto.trialDays,
      dto.features,
      dto.deviceLimit,
      dto.historyRetentionDays,
      dto.effectiveFrom,
      dto.effectiveUntil,
    ].some((value) => value !== undefined);
  }

  private assertDateRange(
    effectiveFrom: Date,
    effectiveUntil: Date | null,
  ): void {
    if (
      Number.isNaN(effectiveFrom.getTime()) ||
      (effectiveUntil &&
        Number.isNaN(effectiveUntil.getTime()))
    ) {
      throw new BadRequestException(
        'Service-plan effective dates are invalid.',
      );
    }

    if (effectiveUntil && effectiveUntil <= effectiveFrom) {
      throw new BadRequestException(
        'effectiveUntil must be later than effectiveFrom.',
      );
    }
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\service-plans\service-plans.controller.ts" `
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
import { ServicePlanQueryDto } from '../common/billing-query.dto';
import { CreatePlanVersionDto } from './dto/create-plan-version.dto';
import { CreateServicePlanDto } from './dto/create-service-plan.dto';
import { UpdateServicePlanDto } from './dto/update-service-plan.dto';
import { ServicePlansService } from './service-plans.service';

@ApiTags('Service Plans')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('service-plans')
export class ServicePlansController {
  constructor(
    private readonly servicePlansService: ServicePlansService,
  ) {}

  @Get()
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'List service-plan versions' })
  list(@Query() query: ServicePlanQueryDto) {
    return this.servicePlansService.list(query);
  }

  @Post()
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Create a new service-plan family' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateServicePlanDto,
  ) {
    return this.servicePlansService.create(auth, dto);
  }

  @Get(':planId')
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'Read one service-plan version' })
  get(
    @Param('planId', new ParseUUIDPipe()) planId: string,
  ) {
    return this.servicePlansService.get(planId);
  }

  @Patch(':planId')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Update a draft or lifecycle state' })
  update(
    @CurrentAuth() auth: AuthContext,
    @Param('planId', new ParseUUIDPipe()) planId: string,
    @Body() dto: UpdateServicePlanDto,
  ) {
    return this.servicePlansService.update(auth, planId, dto);
  }

  @Post(':planId/activate')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Activate a plan version' })
  activate(
    @CurrentAuth() auth: AuthContext,
    @Param('planId', new ParseUUIDPipe()) planId: string,
  ) {
    return this.servicePlansService.activate(auth, planId);
  }

  @Post(':planId/versions')
  @RequirePermissions('subscription.create')
  @ApiOperation({
    summary: 'Create the next immutable version in a plan family',
  })
  createVersion(
    @CurrentAuth() auth: AuthContext,
    @Param('planId', new ParseUUIDPipe()) planId: string,
    @Body() dto: CreatePlanVersionDto,
  ) {
    return this.servicePlansService.createVersion(
      auth,
      planId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\invoices\invoices.service.ts" `
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
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingDateService } from '../common/billing-date.service';
import { BillingMoneyService } from '../common/billing-money.service';
import type { InvoiceQueryDto } from '../common/billing-query.dto';
import type {
  CreateInvoiceDto,
  CreateInvoiceLineDto,
} from './dto/create-invoice.dto';
import type {
  IssueInvoiceDto,
  VoidInvoiceDto,
} from './dto/invoice-action.dto';

@Injectable()
export class InvoicesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly dates: BillingDateService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: InvoiceQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.invoiceWhere(auth);
    const searchWhere: Prisma.InvoiceWhereInput = query.search
      ? {
          invoiceNumber: {
            contains: query.search,
            mode: 'insensitive',
          },
        }
      : {};

    const where: Prisma.InvoiceWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.subscriptionId
          ? {
              subscriptionId: query.subscriptionId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.invoice.findMany({
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
            },
          },
          subscription: {
            include: {
              servicePlan: true,
              vehicle: true,
            },
          },
          managingDealerAtIssue: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          lines: {
            orderBy: {
              lineNumber: 'asc',
            },
          },
        },
      }),
      this.prisma.invoice.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, invoiceId: string) {
    await this.access.assertInvoice(auth, invoiceId);

    const invoice = await this.prisma.invoice.findUnique({
      where: {
        id: invoiceId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
          },
        },
        subscription: {
          include: {
            servicePlan: true,
            vehicle: true,
          },
        },
        managingDealerAtIssue: true,
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
        paymentAllocations: {
          orderBy: {
            allocatedAt: 'desc',
          },
          include: {
            payment: true,
          },
        },
        refunds: {
          orderBy: {
            requestedAt: 'desc',
          },
        },
        commissionEntries: {
          orderBy: {
            createdAt: 'desc',
          },
        },
      },
    });

    if (!invoice) {
      throw new NotFoundException('Invoice was not found.');
    }

    return invoice;
  }

  async create(auth: AuthContext, dto: CreateInvoiceDto) {
    const customer = await this.access.assertCustomer(
      auth,
      dto.customerId,
    );

    if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
      throw new BadRequestException(
        'Invoice creation requires an active or pending customer.',
      );
    }

    if (!this.access.isPlatformScoped(auth)) {
      await this.access.assertFinancialOperator(
        auth,
        dto.customerId,
      );
    }

    if (dto.subscriptionId) {
      const subscription =
        await this.prisma.subscription.findUnique({
          where: {
            id: dto.subscriptionId,
          },
          select: {
            customerId: true,
          },
        });

      if (
        !subscription ||
        subscription.customerId !== dto.customerId
      ) {
        throw new BadRequestException(
          'Invoice subscription must belong to the selected customer.',
        );
      }
    }

    const issueDate = new Date(dto.issueDate);
    const dueDate = new Date(dto.dueDate);

    this.assertInvoiceDates(issueDate, dueDate);

    const invoice = await this.prisma.$transaction(
      async (transaction) =>
        this.createRecord(transaction, {
          customerId: dto.customerId,
          subscriptionId: dto.subscriptionId ?? null,
          managingDealerIdAtIssue:
            customer.managingDealerId,
          billingPeriodStart: dto.billingPeriodStart
            ? new Date(dto.billingPeriodStart)
            : null,
          billingPeriodEnd: dto.billingPeriodEnd
            ? new Date(dto.billingPeriodEnd)
            : null,
          issueDate,
          dueDate,
          currency: 'BDT',
          lines: dto.lines,
        }),
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'invoice.created',
      resourceType: 'Invoice',
      resourceId: invoice.id,
      scopeType: 'CUSTOMER',
      scopeId: invoice.customerId,
      afterData: invoice,
    });

    return invoice;
  }

  async createFromSubscription(
    auth: AuthContext,
    subscriptionId: string,
    dueInDays: number,
  ) {
    await this.access.assertSubscription(auth, subscriptionId);

    const subscription =
      await this.prisma.subscription.findUnique({
        where: {
          id: subscriptionId,
        },
        include: {
          customer: true,
          vehicle: true,
          servicePlan: true,
        },
      });

    if (!subscription) {
      throw new NotFoundException('Subscription was not found.');
    }

    if (
      ![
        'TRIALING',
        'ACTIVE',
        'PAST_DUE',
        'SUSPENDED',
      ].includes(subscription.status)
    ) {
      throw new ConflictException(
        'Only a current subscription can generate an invoice.',
      );
    }

    const periodStart =
      subscription.currentPeriodStart ?? new Date();
    const periodEnd =
      subscription.currentPeriodEnd ??
      this.dates.addInterval(
        periodStart,
        subscription.servicePlan.billingIntervalUnit,
        subscription.servicePlan.billingIntervalCount,
      );

    const duplicate = await this.prisma.invoice.findFirst({
      where: {
        subscriptionId,
        billingPeriodStart: periodStart,
        billingPeriodEnd: periodEnd,
        status: {
          not: 'VOID',
        },
      },
      select: {
        id: true,
        invoiceNumber: true,
      },
    });

    if (duplicate) {
      throw new ConflictException(
        `Invoice ${duplicate.invoiceNumber} already exists for this billing period.`,
      );
    }

    const issueDate = new Date();
    const dueDate = this.dates.addDays(
      issueDate,
      dueInDays,
    );

    const invoice = await this.prisma.$transaction(
      async (transaction) => {
        const created = await this.createRecord(transaction, {
          customerId: subscription.customerId,
          subscriptionId: subscription.id,
          managingDealerIdAtIssue:
            subscription.customer.managingDealerId,
          billingPeriodStart: periodStart,
          billingPeriodEnd: periodEnd,
          issueDate,
          dueDate,
          currency: subscription.servicePlan.currency,
          lines: [
            {
              itemType: 'SUBSCRIPTION',
              description:
                `${subscription.servicePlan.name} ` +
                `(${periodStart.toISOString()} - ${periodEnd.toISOString()})`,
              quantity: '1.000',
              unitPrice:
                subscription.servicePlan.basePrice.toString(),
              discountAmount: '0.00',
              taxAmount: '0.00',
              referenceType: 'ServicePlan',
              referenceId: subscription.servicePlanId,
            },
          ],
        });

        await transaction.subscription.update({
          where: {
            id: subscription.id,
          },
          data: {
            nextBillingAt: periodEnd,
          },
        });

        return created;
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'invoice.generated-from-subscription',
      resourceType: 'Invoice',
      resourceId: invoice.id,
      scopeType: 'CUSTOMER',
      scopeId: invoice.customerId,
      afterData: invoice,
      metadata: {
        subscriptionId,
      },
    });

    return invoice;
  }

  async issue(
    auth: AuthContext,
    invoiceId: string,
    dto: IssueInvoiceDto,
  ) {
    await this.access.assertInvoice(auth, invoiceId);

    const before = await this.prisma.invoice.findUnique({
      where: {
        id: invoiceId,
      },
    });

    if (!before) {
      throw new NotFoundException('Invoice was not found.');
    }

    await this.access.assertFinancialOperator(
      auth,
      before.customerId,
    );

    if (before.status !== 'DRAFT') {
      throw new ConflictException(
        'Only draft invoices can be issued.',
      );
    }

    const issueDate = dto.issueDate
      ? new Date(dto.issueDate)
      : before.issueDate;
    const dueDate = dto.dueDate
      ? new Date(dto.dueDate)
      : before.dueDate;

    this.assertInvoiceDates(issueDate, dueDate);

    const issued = await this.prisma.invoice.update({
      where: {
        id: invoiceId,
      },
      data: {
        issueDate,
        dueDate,
        status: 'ISSUED',
        issuedAt: new Date(),
      },
      include: {
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'invoice.issued',
      resourceType: 'Invoice',
      resourceId: invoiceId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: issued,
    });

    return issued;
  }

  async void(
    auth: AuthContext,
    invoiceId: string,
    dto: VoidInvoiceDto,
  ) {
    await this.access.assertInvoice(auth, invoiceId);

    const before = await this.prisma.invoice.findUnique({
      where: {
        id: invoiceId,
      },
      include: {
        _count: {
          select: {
            paymentAllocations: true,
          },
        },
      },
    });

    if (!before) {
      throw new NotFoundException('Invoice was not found.');
    }

    await this.access.assertFinancialOperator(
      auth,
      before.customerId,
    );

    if (
      before.status === 'PAID' ||
      before.status === 'REFUNDED' ||
      before._count.paymentAllocations > 0
    ) {
      throw new ConflictException(
        'Paid or allocated invoices cannot be voided.',
      );
    }

    if (before.status === 'VOID') {
      throw new ConflictException('Invoice is already void.');
    }

    const voided = await this.prisma.invoice.update({
      where: {
        id: invoiceId,
      },
      data: {
        status: 'VOID',
        voidedAt: new Date(),
        voidReason: dto.reason.trim(),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'invoice.voided',
      resourceType: 'Invoice',
      resourceId: invoiceId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: voided,
    });

    return voided;
  }

  private async createRecord(
    transaction: Prisma.TransactionClient,
    input: {
      customerId: string;
      subscriptionId: string | null;
      managingDealerIdAtIssue: string | null;
      billingPeriodStart: Date | null;
      billingPeriodEnd: Date | null;
      issueDate: Date;
      dueDate: Date;
      currency: string;
      lines: CreateInvoiceLineDto[];
    },
  ) {
    const calculatedLines = input.lines.map((line) => ({
      input: line,
      calculated: this.money.invoiceLine(line),
    }));

    const subtotal = this.money.sum(
      calculatedLines.map(
        (line) => line.calculated.grossAmount,
      ),
    );
    const discountAmount = this.money.sum(
      calculatedLines.map(
        (line) => line.calculated.discountAmount,
      ),
    );
    const taxAmount = this.money.sum(
      calculatedLines.map(
        (line) => line.calculated.taxAmount,
      ),
    );
    const totalAmount = subtotal
      .minus(discountAmount)
      .plus(taxAmount)
      .toDecimalPlaces(2);

    if (totalAmount.isNegative()) {
      throw new BadRequestException(
        'Invoice total cannot be negative.',
      );
    }

    return transaction.invoice.create({
      data: {
        invoiceNumber: this.codes.invoice(),
        customerId: input.customerId,
        subscriptionId: input.subscriptionId,
        managingDealerIdAtIssue:
          input.managingDealerIdAtIssue,
        billingPeriodStart: input.billingPeriodStart,
        billingPeriodEnd: input.billingPeriodEnd,
        issueDate: input.issueDate,
        dueDate: input.dueDate,
        subtotal,
        discountAmount,
        taxAmount,
        totalAmount,
        paidAmount: 0,
        outstandingAmount: totalAmount,
        currency: input.currency.trim().toUpperCase(),
        status: 'DRAFT',
        lines: {
          create: calculatedLines.map(
            ({ input: line, calculated }, index) => ({
              lineNumber: index + 1,
              itemType: line.itemType,
              description: line.description.trim(),
              quantity: calculated.quantity,
              unitPrice: calculated.unitPrice,
              discountAmount: calculated.discountAmount,
              taxAmount: calculated.taxAmount,
              lineTotal: calculated.lineTotal,
              referenceType:
                this.optional(line.referenceType),
              referenceId: this.optional(line.referenceId),
            }),
          ),
        },
      },
      include: {
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
      },
    });
  }

  private assertInvoiceDates(
    issueDate: Date,
    dueDate: Date,
  ): void {
    if (
      Number.isNaN(issueDate.getTime()) ||
      Number.isNaN(dueDate.getTime())
    ) {
      throw new BadRequestException('Invoice dates are invalid.');
    }

    if (dueDate < issueDate) {
      throw new BadRequestException(
        'Invoice due date cannot be earlier than issue date.',
      );
    }
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\invoices\invoices.controller.ts" `
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
import { InvoiceQueryDto } from '../common/billing-query.dto';
import { CreateInvoiceDto } from './dto/create-invoice.dto';
import {
  IssueInvoiceDto,
  VoidInvoiceDto,
} from './dto/invoice-action.dto';
import { InvoicesService } from './invoices.service';

@ApiTags('Invoices')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('invoices')
export class InvoicesController {
  constructor(private readonly invoicesService: InvoicesService) {}

  @Get()
  @RequirePermissions('invoice.view')
  @ApiOperation({ summary: 'List invoices within effective scope' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: InvoiceQueryDto,
  ) {
    return this.invoicesService.list(auth, query);
  }

  @Post()
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Create a manual draft invoice' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateInvoiceDto,
  ) {
    return this.invoicesService.create(auth, dto);
  }

  @Get(':invoiceId')
  @RequirePermissions('invoice.view')
  @ApiOperation({ summary: 'Read one invoice with financial history' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('invoiceId', new ParseUUIDPipe()) invoiceId: string,
  ) {
    return this.invoicesService.get(auth, invoiceId);
  }

  @Post(':invoiceId/issue')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Issue a draft invoice' })
  issue(
    @CurrentAuth() auth: AuthContext,
    @Param('invoiceId', new ParseUUIDPipe()) invoiceId: string,
    @Body() dto: IssueInvoiceDto,
  ) {
    return this.invoicesService.issue(auth, invoiceId, dto);
  }

  @Post(':invoiceId/void')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Void an unpaid invoice' })
  void(
    @CurrentAuth() auth: AuthContext,
    @Param('invoiceId', new ParseUUIDPipe()) invoiceId: string,
    @Body() dto: VoidInvoiceDto,
  ) {
    return this.invoicesService.void(auth, invoiceId, dto);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\subscriptions\subscriptions.service.ts" `
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
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingDateService } from '../common/billing-date.service';
import type { SubscriptionQueryDto } from '../common/billing-query.dto';
import { InvoicesService } from '../invoices/invoices.service';
import type { CreateSubscriptionDto } from './dto/create-subscription.dto';
import type {
  GenerateSubscriptionInvoiceDto,
  SubscriptionReasonDto,
} from './dto/subscription-action.dto';

@Injectable()
export class SubscriptionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly dates: BillingDateService,
    private readonly invoicesService: InvoicesService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: SubscriptionQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const scopeWhere = this.access.subscriptionWhere(auth);
    const searchWhere: Prisma.SubscriptionWhereInput = query.search
      ? {
          OR: [
            {
              subscriptionCode: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              vehicle: {
                vehicleCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
            },
          ],
        }
      : {};

    const where: Prisma.SubscriptionWhereInput = {
      AND: [
        scopeWhere,
        searchWhere,
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
        query.status
          ? {
              status: query.status,
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.subscription.findMany({
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
          vehicle: true,
          servicePlan: true,
          _count: {
            select: {
              invoices: true,
            },
          },
        },
      }),
      this.prisma.subscription.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, subscriptionId: string) {
    await this.access.assertSubscription(auth, subscriptionId);

    const subscription =
      await this.prisma.subscription.findUnique({
        where: {
          id: subscriptionId,
        },
        include: {
          customer: {
            include: {
              individualProfile: true,
              organizationProfile: true,
              managingDealer: true,
            },
          },
          vehicle: true,
          servicePlan: true,
          invoices: {
            orderBy: {
              createdAt: 'desc',
            },
            include: {
              lines: {
                orderBy: {
                  lineNumber: 'asc',
                },
              },
            },
          },
        },
      });

    if (!subscription) {
      throw new NotFoundException('Subscription was not found.');
    }

    return subscription;
  }

  async create(auth: AuthContext, dto: CreateSubscriptionDto) {
    const customer = await this.access.assertCustomer(
      auth,
      dto.customerId,
    );

    if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
      throw new BadRequestException(
        'Subscription creation requires an active or pending customer.',
      );
    }

    const [vehicle, plan] = await Promise.all([
      this.prisma.vehicle.findUnique({
        where: {
          id: dto.vehicleId,
        },
      }),
      this.prisma.servicePlan.findUnique({
        where: {
          id: dto.servicePlanId,
        },
      }),
    ]);

    if (!vehicle || vehicle.customerId !== dto.customerId) {
      throw new BadRequestException(
        'Subscription vehicle must belong to the selected customer.',
      );
    }

    if (vehicle.status === 'ARCHIVED') {
      throw new ConflictException(
        'Archived vehicles cannot receive subscriptions.',
      );
    }

    if (!plan || plan.status !== 'ACTIVE') {
      throw new BadRequestException(
        'An active service plan is required.',
      );
    }

    const now = new Date();

    if (
      plan.effectiveFrom > now ||
      (plan.effectiveUntil && plan.effectiveUntil < now)
    ) {
      throw new ConflictException(
        'The selected plan is outside its effective date range.',
      );
    }

    const subscription = await this.prisma.subscription.create({
      data: {
        subscriptionCode: this.codes.subscription(),
        customerId: dto.customerId,
        vehicleId: dto.vehicleId,
        servicePlanId: dto.servicePlanId,
        status: 'PENDING',
        autoRenew: dto.autoRenew,
      },
      include: {
        customer: true,
        vehicle: true,
        servicePlan: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'subscription.created',
      resourceType: 'Subscription',
      resourceId: subscription.id,
      scopeType: 'CUSTOMER',
      scopeId: subscription.customerId,
      afterData: subscription,
    });

    return subscription;
  }

  async activate(auth: AuthContext, subscriptionId: string) {
    await this.access.assertSubscription(auth, subscriptionId);

    const before = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
      include: {
        servicePlan: true,
      },
    });

    if (!before) {
      throw new NotFoundException('Subscription was not found.');
    }

    await this.access.assertFinancialOperator(
      auth,
      before.customerId,
    );

    if (before.status !== 'PENDING') {
      throw new ConflictException(
        'Only pending subscriptions can be activated.',
      );
    }

    const now = new Date();
    const periodEnd = this.dates.addInterval(
      now,
      before.servicePlan.billingIntervalUnit,
      before.servicePlan.billingIntervalCount,
    );
    const trialEndsAt =
      before.servicePlan.trialDays > 0
        ? this.dates.addDays(
            now,
            before.servicePlan.trialDays,
          )
        : null;

    const activated = await this.prisma.subscription.update({
      where: {
        id: subscriptionId,
      },
      data: {
        status: trialEndsAt ? 'TRIALING' : 'ACTIVE',
        startedAt: now,
        currentPeriodStart: now,
        currentPeriodEnd: periodEnd,
        nextBillingAt: trialEndsAt ?? periodEnd,
        trialEndsAt,
      },
      include: {
        customer: true,
        vehicle: true,
        servicePlan: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'subscription.activated',
      resourceType: 'Subscription',
      resourceId: subscriptionId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: activated,
    });

    return activated;
  }

  async suspend(
    auth: AuthContext,
    subscriptionId: string,
    dto: SubscriptionReasonDto,
  ) {
    return this.transition(
      auth,
      subscriptionId,
      ['TRIALING', 'ACTIVE', 'PAST_DUE'],
      'SUSPENDED',
      'subscription.suspended',
      dto.reason,
    );
  }

  async resume(
    auth: AuthContext,
    subscriptionId: string,
    dto: SubscriptionReasonDto,
  ) {
    return this.transition(
      auth,
      subscriptionId,
      ['SUSPENDED'],
      'ACTIVE',
      'subscription.resumed',
      dto.reason,
    );
  }

  async cancel(
    auth: AuthContext,
    subscriptionId: string,
    dto: SubscriptionReasonDto,
  ) {
    await this.access.assertSubscription(auth, subscriptionId);

    const before = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
    });

    if (!before) {
      throw new NotFoundException('Subscription was not found.');
    }

    await this.access.assertFinancialOperator(
      auth,
      before.customerId,
    );

    if (
      ['CANCELLED', 'EXPIRED'].includes(before.status)
    ) {
      throw new ConflictException(
        'Subscription is already closed.',
      );
    }

    const cancelled = await this.prisma.subscription.update({
      where: {
        id: subscriptionId,
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: new Date(),
        cancellationReason:
          dto.reason?.trim() ?? 'Cancelled by authorized operator',
        autoRenew: false,
        nextBillingAt: null,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'subscription.cancelled',
      resourceType: 'Subscription',
      resourceId: subscriptionId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: cancelled,
    });

    return cancelled;
  }

  async generateInvoice(
    auth: AuthContext,
    subscriptionId: string,
    dto: GenerateSubscriptionInvoiceDto,
  ) {
    return this.invoicesService.createFromSubscription(
      auth,
      subscriptionId,
      dto.dueInDays,
    );
  }

  private async transition(
    auth: AuthContext,
    subscriptionId: string,
    allowedStatuses: string[],
    targetStatus: 'SUSPENDED' | 'ACTIVE',
    action: string,
    reason?: string,
  ) {
    await this.access.assertSubscription(auth, subscriptionId);

    const before = await this.prisma.subscription.findUnique({
      where: {
        id: subscriptionId,
      },
    });

    if (!before) {
      throw new NotFoundException('Subscription was not found.');
    }

    await this.access.assertFinancialOperator(
      auth,
      before.customerId,
    );

    if (!allowedStatuses.includes(before.status)) {
      throw new ConflictException(
        `Subscription cannot move from ${before.status} to ${targetStatus}.`,
      );
    }

    const updated = await this.prisma.subscription.update({
      where: {
        id: subscriptionId,
      },
      data: {
        status: targetStatus,
        cancellationReason:
          targetStatus === 'SUSPENDED'
            ? this.optional(reason)
            : null,
        nextBillingAt:
          targetStatus === 'ACTIVE'
            ? before.currentPeriodEnd
            : null,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action,
      resourceType: 'Subscription',
      resourceId: subscriptionId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: updated,
      metadata: {
        reason,
      },
    });

    return updated;
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\subscriptions\subscriptions.controller.ts" `
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
import { SubscriptionQueryDto } from '../common/billing-query.dto';
import { CreateSubscriptionDto } from './dto/create-subscription.dto';
import {
  GenerateSubscriptionInvoiceDto,
  SubscriptionReasonDto,
} from './dto/subscription-action.dto';
import { SubscriptionsService } from './subscriptions.service';

@ApiTags('Subscriptions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('subscriptions')
export class SubscriptionsController {
  constructor(
    private readonly subscriptionsService: SubscriptionsService,
  ) {}

  @Get()
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'List subscriptions within effective scope' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: SubscriptionQueryDto,
  ) {
    return this.subscriptionsService.list(auth, query);
  }

  @Post()
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Create a pending vehicle subscription' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateSubscriptionDto,
  ) {
    return this.subscriptionsService.create(auth, dto);
  }

  @Get(':subscriptionId')
  @RequirePermissions('subscription.view')
  @ApiOperation({ summary: 'Read one subscription and invoices' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
  ) {
    return this.subscriptionsService.get(auth, subscriptionId);
  }

  @Post(':subscriptionId/activate')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Activate a pending subscription' })
  activate(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
  ) {
    return this.subscriptionsService.activate(
      auth,
      subscriptionId,
    );
  }

  @Post(':subscriptionId/suspend')
  @RequirePermissions('subscription.suspend')
  @ApiOperation({ summary: 'Suspend a current subscription' })
  suspend(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
    @Body() dto: SubscriptionReasonDto,
  ) {
    return this.subscriptionsService.suspend(
      auth,
      subscriptionId,
      dto,
    );
  }

  @Post(':subscriptionId/resume')
  @RequirePermissions('subscription.suspend')
  @ApiOperation({ summary: 'Resume a suspended subscription' })
  resume(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
    @Body() dto: SubscriptionReasonDto,
  ) {
    return this.subscriptionsService.resume(
      auth,
      subscriptionId,
      dto,
    );
  }

  @Post(':subscriptionId/cancel')
  @RequirePermissions('subscription.suspend')
  @ApiOperation({ summary: 'Cancel a current subscription' })
  cancel(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
    @Body() dto: SubscriptionReasonDto,
  ) {
    return this.subscriptionsService.cancel(
      auth,
      subscriptionId,
      dto,
    );
  }

  @Post(':subscriptionId/generate-invoice')
  @RequirePermissions('subscription.create')
  @ApiOperation({
    summary: 'Generate one draft invoice for the current period',
  })
  generateInvoice(
    @CurrentAuth() auth: AuthContext,
    @Param('subscriptionId', new ParseUUIDPipe())
    subscriptionId: string,
    @Body() dto: GenerateSubscriptionInvoiceDto,
  ) {
    return this.subscriptionsService.generateInvoice(
      auth,
      subscriptionId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\commissions\commission-engine.service.ts" `
        @'

import { Injectable } from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';

type TransactionClient = Prisma.TransactionClient;

@Injectable()
export class CommissionEngineService {
  constructor(
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
  ) {}

  async createForAllocation(
    transaction: TransactionClient,
    input: {
      paymentId: string;
      invoiceId: string;
      allocationAmount: Prisma.Decimal;
      occurredAt: Date;
    },
  ): Promise<void> {
    const invoice = await transaction.invoice.findUnique({
      where: {
        id: input.invoiceId,
      },
      include: {
        lines: {
          orderBy: {
            lineNumber: 'asc',
          },
        },
        subscription: true,
      },
    });

    if (
      !invoice ||
      !invoice.managingDealerIdAtIssue ||
      invoice.totalAmount.lte(0)
    ) {
      return;
    }

    const ratio = input.allocationAmount
      .div(invoice.totalAmount)
      .toDecimalPlaces(8);

    for (const line of invoice.lines) {
      const transactionType =
        await this.resolveTransactionType(
          transaction,
          invoice.subscriptionId,
          invoice.id,
          line.itemType,
        );

      if (!transactionType) {
        continue;
      }

      const duplicate =
        await transaction.commissionEntry.findFirst({
          where: {
            paymentId: input.paymentId,
            invoiceLineId: line.id,
            reversalOfEntryId: null,
            status: {
              not: 'CANCELLED',
            },
          },
          select: {
            id: true,
          },
        });

      if (duplicate) {
        continue;
      }

      const rule = await this.findRule(transaction, {
        dealerOrganizationId:
          invoice.managingDealerIdAtIssue,
        servicePlanId:
          invoice.subscription?.servicePlanId ?? null,
        transactionType,
        occurredAt: input.occurredAt,
      });

      if (!rule || rule.calculationType === 'NONE') {
        continue;
      }

      const baseAmount = line.lineTotal
        .mul(ratio)
        .toDecimalPlaces(2);

      if (baseAmount.lte(0)) {
        continue;
      }

      const calculated = this.calculate(rule, baseAmount, ratio);

      if (calculated.amount.lte(0)) {
        continue;
      }

      const entry = await transaction.commissionEntry.create({
        data: {
          commissionNumber: this.codes.commission(),
          dealerOrganizationId:
            invoice.managingDealerIdAtIssue,
          customerId: invoice.customerId,
          invoiceId: invoice.id,
          invoiceLineId: line.id,
          paymentId: input.paymentId,
          commissionRuleId: rule.id,
          transactionType,
          calculationType: rule.calculationType,
          baseAmount,
          percentageRateSnapshot:
            calculated.percentageRateSnapshot,
          fixedAmountSnapshot:
            calculated.fixedAmountSnapshot,
          commissionAmount: calculated.amount,
          currency: invoice.currency,
          status: 'AVAILABLE',
          earnedAt: input.occurredAt,
          availableAt: input.occurredAt,
        },
      });

      await transaction.dealerLedgerEntry.create({
        data: {
          ledgerNumber: this.codes.ledger(),
          dealerOrganizationId:
            invoice.managingDealerIdAtIssue,
          entryType: 'COMMISSION_EARNED',
          direction: 'CREDIT',
          amount: calculated.amount,
          currency: invoice.currency,
          referenceType: 'CommissionEntry',
          referenceId: entry.id,
          description:
            `Commission earned from invoice ${invoice.invoiceNumber}`,
          occurredAt: input.occurredAt,
        },
      });
    }
  }

  async reverseForRefund(
    transaction: TransactionClient,
    input: {
      paymentId: string;
      refundId: string;
      refundAmount: Prisma.Decimal;
      paymentAmount: Prisma.Decimal;
      occurredAt: Date;
      reason: string;
    },
  ): Promise<void> {
    if (input.paymentAmount.lte(0)) {
      return;
    }

    const originals = await transaction.commissionEntry.findMany({
      where: {
        paymentId: input.paymentId,
        reversalOfEntryId: null,
        commissionAmount: {
          gt: 0,
        },
        status: {
          notIn: ['CANCELLED', 'REVERSED'],
        },
      },
    });

    const ratio = input.refundAmount
      .div(input.paymentAmount)
      .toDecimalPlaces(8);

    for (const original of originals) {
      const reversalAmount = original.commissionAmount
        .mul(ratio)
        .toDecimalPlaces(2);

      if (reversalAmount.lte(0)) {
        continue;
      }

      const reversal =
        await transaction.commissionEntry.create({
          data: {
            commissionNumber: this.codes.commission(),
            dealerOrganizationId:
              original.dealerOrganizationId,
            customerId: original.customerId,
            invoiceId: original.invoiceId,
            invoiceLineId: original.invoiceLineId,
            paymentId: original.paymentId,
            commissionRuleId: original.commissionRuleId,
            reversalOfEntryId: original.id,
            transactionType: original.transactionType,
            calculationType: original.calculationType,
            baseAmount: original.baseAmount,
            percentageRateSnapshot:
              original.percentageRateSnapshot,
            fixedAmountSnapshot:
              original.fixedAmountSnapshot,
            commissionAmount: reversalAmount.negated(),
            currency: original.currency,
            status: 'AVAILABLE',
            earnedAt: input.occurredAt,
            availableAt: input.occurredAt,
            holdReason: input.reason,
          },
        });

      await transaction.dealerLedgerEntry.create({
        data: {
          ledgerNumber: this.codes.ledger(),
          dealerOrganizationId:
            original.dealerOrganizationId,
          entryType: 'COMMISSION_REVERSAL',
          direction: 'DEBIT',
          amount: reversalAmount,
          currency: original.currency,
          referenceType: 'Refund',
          referenceId: input.refundId,
          description:
            `Commission reversal for refund: ${input.reason}`,
          occurredAt: input.occurredAt,
        },
      });

      if (ratio.gte(1) && original.status === 'AVAILABLE') {
        await transaction.commissionEntry.update({
          where: {
            id: original.id,
          },
          data: {
            status: 'REVERSED',
          },
        });

        await transaction.commissionEntry.update({
          where: {
            id: reversal.id,
          },
          data: {
            status: 'REVERSED',
          },
        });
      }
    }
  }

  private async findRule(
    transaction: TransactionClient,
    input: {
      dealerOrganizationId: string;
      servicePlanId: string | null;
      transactionType:
        | 'DEVICE_SALE'
        | 'INSTALLATION'
        | 'INITIAL_SUBSCRIPTION'
        | 'SUBSCRIPTION_RENEWAL'
        | 'UPGRADE'
        | 'ADD_ON_SERVICE';
      occurredAt: Date;
    },
  ) {
    const baseWhere: Prisma.CommissionRuleWhereInput = {
      dealerOrganizationId: input.dealerOrganizationId,
      transactionType: input.transactionType,
      status: 'ACTIVE',
      effectiveFrom: {
        lte: input.occurredAt,
      },
      OR: [
        {
          effectiveUntil: null,
        },
        {
          effectiveUntil: {
            gte: input.occurredAt,
          },
        },
      ],
    };

    if (input.servicePlanId) {
      const specific =
        await transaction.commissionRule.findFirst({
          where: {
            ...baseWhere,
            servicePlanId: input.servicePlanId,
          },
          orderBy: [
            {
              priority: 'asc',
            },
            {
              effectiveFrom: 'desc',
            },
          ],
        });

      if (specific) {
        return specific;
      }
    }

    return transaction.commissionRule.findFirst({
      where: {
        ...baseWhere,
        servicePlanId: null,
      },
      orderBy: [
        {
          priority: 'asc',
        },
        {
          effectiveFrom: 'desc',
        },
      ],
    });
  }

  private calculate(
    rule: {
      calculationType:
        | 'PERCENTAGE'
        | 'FIXED_AMOUNT'
        | 'TIERED'
        | 'NONE';
      percentageRate: Prisma.Decimal | null;
      fixedAmount: Prisma.Decimal | null;
      tierDefinition: Prisma.JsonValue | null;
      minimumAmount: Prisma.Decimal | null;
      maximumAmount: Prisma.Decimal | null;
    },
    baseAmount: Prisma.Decimal,
    allocationRatio: Prisma.Decimal,
  ): {
    amount: Prisma.Decimal;
    percentageRateSnapshot: Prisma.Decimal | null;
    fixedAmountSnapshot: Prisma.Decimal | null;
  } {
    let amount = new Prisma.Decimal(0);
    let percentageRateSnapshot: Prisma.Decimal | null = null;
    let fixedAmountSnapshot: Prisma.Decimal | null = null;

    if (
      rule.calculationType === 'PERCENTAGE' &&
      rule.percentageRate
    ) {
      percentageRateSnapshot = rule.percentageRate;
      amount = baseAmount
        .mul(rule.percentageRate)
        .div(100);
    } else if (
      rule.calculationType === 'FIXED_AMOUNT' &&
      rule.fixedAmount
    ) {
      fixedAmountSnapshot = rule.fixedAmount;
      amount = rule.fixedAmount.mul(allocationRatio);
    } else if (rule.calculationType === 'TIERED') {
      const tier = this.selectTier(
        rule.tierDefinition,
        baseAmount,
      );

      if (tier?.percentageRate !== undefined) {
        percentageRateSnapshot = this.money.decimal(
          tier.percentageRate,
        );
        amount = baseAmount
          .mul(percentageRateSnapshot)
          .div(100);
      } else if (tier?.fixedAmount !== undefined) {
        fixedAmountSnapshot = this.money.decimal(
          tier.fixedAmount,
        );
        amount = fixedAmountSnapshot.mul(allocationRatio);
      }
    }

    amount = amount.toDecimalPlaces(2);

    if (rule.minimumAmount && amount.lt(rule.minimumAmount)) {
      amount = rule.minimumAmount;
    }

    if (rule.maximumAmount && amount.gt(rule.maximumAmount)) {
      amount = rule.maximumAmount;
    }

    return {
      amount: amount.toDecimalPlaces(2),
      percentageRateSnapshot,
      fixedAmountSnapshot,
    };
  }

  private selectTier(
    tierDefinition: Prisma.JsonValue | null,
    baseAmount: Prisma.Decimal,
  ):
    | {
        percentageRate?: string | number;
        fixedAmount?: string | number;
      }
    | undefined {
    const tiers =
      tierDefinition &&
      typeof tierDefinition === 'object' &&
      !Array.isArray(tierDefinition) &&
      'tiers' in tierDefinition &&
      Array.isArray(tierDefinition.tiers)
        ? tierDefinition.tiers
        : [];

    return tiers.find((candidate) => {
      if (
        !candidate ||
        typeof candidate !== 'object' ||
        Array.isArray(candidate)
      ) {
        return false;
      }

      const min =
        'minAmount' in candidate &&
        candidate.minAmount !== undefined
          ? this.money.decimal(
              candidate.minAmount as string | number,
            )
          : new Prisma.Decimal(0);
      const max =
        'maxAmount' in candidate &&
        candidate.maxAmount !== undefined
          ? this.money.decimal(
              candidate.maxAmount as string | number,
            )
          : null;

      return baseAmount.gte(min) && (!max || baseAmount.lte(max));
    }) as
      | {
          percentageRate?: string | number;
          fixedAmount?: string | number;
        }
      | undefined;
  }

  private async resolveTransactionType(
    transaction: TransactionClient,
    subscriptionId: string | null,
    invoiceId: string,
    itemType: string,
  ): Promise<
    | 'DEVICE_SALE'
    | 'INSTALLATION'
    | 'INITIAL_SUBSCRIPTION'
    | 'SUBSCRIPTION_RENEWAL'
    | 'UPGRADE'
    | 'ADD_ON_SERVICE'
    | null
  > {
    if (itemType === 'DEVICE_SALE') {
      return 'DEVICE_SALE';
    }

    if (itemType === 'INSTALLATION') {
      return 'INSTALLATION';
    }

    if (itemType === 'REPLACEMENT') {
      return 'UPGRADE';
    }

    if (itemType === 'ADD_ON') {
      return 'ADD_ON_SERVICE';
    }

    if (itemType !== 'SUBSCRIPTION' || !subscriptionId) {
      return null;
    }

    const previousInvoiceCount = await transaction.invoice.count({
      where: {
        subscriptionId,
        id: {
          not: invoiceId,
        },
        status: {
          not: 'VOID',
        },
      },
    });

    return previousInvoiceCount === 0
      ? 'INITIAL_SUBSCRIPTION'
      : 'SUBSCRIPTION_RENEWAL';
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\commissions\commissions.service.ts" `
        @'

import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import type { PaginationQueryDto } from '../../management/common/pagination-query.dto';
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';
import type { CommissionQueryDto } from '../common/billing-query.dto';
import type { CreateCommissionRuleDto } from './dto/create-commission-rule.dto';
import type { ReverseCommissionDto } from './dto/reverse-commission.dto';
import type { UpdateCommissionRuleDto } from './dto/update-commission-rule.dto';

@Injectable()
export class CommissionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly auditService: AuditService,
  ) {}

  async listRules(
    auth: AuthContext,
    query: PaginationQueryDto,
  ) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.CommissionRuleWhereInput = {
      ...(this.access.isPlatformScoped(auth)
        ? {}
        : {
            dealerOrganizationId: {
              in: this.access.dealerScopeIds(auth),
            },
          }),
      status: {
        not: 'ARCHIVED',
      },
      ...(query.search
        ? {
            OR: [
              {
                ruleCode: {
                  contains: query.search,
                  mode: 'insensitive',
                },
              },
              {
                dealerOrganization: {
                  name: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
              },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.commissionRule.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: [
          {
            priority: 'asc',
          },
          {
            effectiveFrom: 'desc',
          },
        ],
        include: {
          dealerOrganization: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          servicePlan: true,
          _count: {
            select: {
              entries: true,
            },
          },
        },
      }),
      this.prisma.commissionRule.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async createRule(
    auth: AuthContext,
    dto: CreateCommissionRuleDto,
  ) {
    this.access.assertPlatform(auth);
    await this.assertDealerAndPlan(
      dto.dealerOrganizationId,
      dto.servicePlanId,
    );
    this.assertCalculation(dto);

    const rule = await this.prisma.commissionRule.create({
      data: {
        ruleCode: this.codes.commissionRule(),
        dealerOrganizationId: dto.dealerOrganizationId,
        servicePlanId: dto.servicePlanId,
        transactionType: dto.transactionType,
        calculationType: dto.calculationType,
        percentageRate: dto.percentageRate,
        fixedAmount: dto.fixedAmount,
        tierDefinition:
          dto.tierDefinition as Prisma.InputJsonValue | undefined,
        minimumAmount: dto.minimumAmount,
        maximumAmount: dto.maximumAmount,
        priority: dto.priority,
        effectiveFrom: new Date(dto.effectiveFrom),
        effectiveUntil: dto.effectiveUntil
          ? new Date(dto.effectiveUntil)
          : null,
        status: 'DRAFT',
      },
      include: {
        dealerOrganization: true,
        servicePlan: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'commission-rule.created',
      resourceType: 'CommissionRule',
      resourceId: rule.id,
      scopeType: 'DEALER',
      scopeId: rule.dealerOrganizationId,
      afterData: rule,
    });

    return rule;
  }

  async updateRule(
    auth: AuthContext,
    ruleId: string,
    dto: UpdateCommissionRuleDto,
  ) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.commissionRule.findUnique({
      where: {
        id: ruleId,
      },
    });

    if (!before) {
      throw new NotFoundException(
        'Commission rule was not found.',
      );
    }

    const calculationType =
      dto.calculationType ?? before.calculationType;

    this.assertCalculation({
      calculationType,
      percentageRate:
        dto.percentageRate ??
        before.percentageRate?.toString(),
      fixedAmount:
        dto.fixedAmount ?? before.fixedAmount?.toString(),
      tierDefinition:
        dto.tierDefinition ??
        (before.tierDefinition as
          | Record<string, unknown>
          | undefined),
    });

    const updated = await this.prisma.commissionRule.update({
      where: {
        id: ruleId,
      },
      data: {
        calculationType: dto.calculationType,
        percentageRate:
          calculationType === 'PERCENTAGE'
            ? dto.percentageRate ??
              before.percentageRate
            : null,
        fixedAmount:
          calculationType === 'FIXED_AMOUNT'
            ? dto.fixedAmount ?? before.fixedAmount
            : null,
        tierDefinition:
          calculationType === 'TIERED'
            ? ((dto.tierDefinition ??
                before.tierDefinition) as
                | Prisma.InputJsonValue
                | undefined)
            : Prisma.DbNull,
        minimumAmount: dto.minimumAmount,
        maximumAmount: dto.maximumAmount,
        priority: dto.priority,
        effectiveFrom: dto.effectiveFrom
          ? new Date(dto.effectiveFrom)
          : undefined,
        effectiveUntil:
          dto.effectiveUntil !== undefined
            ? new Date(dto.effectiveUntil)
            : undefined,
        status: dto.status,
        archivedAt:
          dto.status === 'ARCHIVED'
            ? new Date()
            : dto.status
              ? null
              : undefined,
      },
      include: {
        dealerOrganization: true,
        servicePlan: true,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'commission-rule.updated',
      resourceType: 'CommissionRule',
      resourceId: ruleId,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: before,
      afterData: updated,
    });

    return updated;
  }

  async listEntries(
    auth: AuthContext,
    query: CommissionQueryDto,
  ) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.CommissionEntryWhereInput = {
      AND: [
        this.access.commissionWhere(auth),
        query.dealerOrganizationId
          ? {
              dealerOrganizationId:
                query.dealerOrganizationId,
            }
          : {},
        query.customerId
          ? {
              customerId: query.customerId,
            }
          : {},
        query.status
          ? {
              status: query.status,
            }
          : {},
        query.search
          ? {
              commissionNumber: {
                contains: query.search,
                mode: 'insensitive',
              },
            }
          : {},
      ],
    };

    const [items, total] = await Promise.all([
      this.prisma.commissionEntry.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          dealerOrganization: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          customer: {
            include: {
              individualProfile: true,
              organizationProfile: true,
            },
          },
          invoice: true,
          payment: true,
          commissionRule: true,
          reversalOf: true,
          settlementItem: {
            include: {
              settlement: true,
            },
          },
        },
      }),
      this.prisma.commissionEntry.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async reverseEntry(
    auth: AuthContext,
    commissionEntryId: string,
    dto: ReverseCommissionDto,
  ) {
    this.access.assertPlatform(auth);

    const original = await this.prisma.commissionEntry.findUnique({
      where: {
        id: commissionEntryId,
      },
    });

    if (!original) {
      throw new NotFoundException(
        'Commission entry was not found.',
      );
    }

    if (
      original.reversalOfEntryId ||
      original.commissionAmount.lte(0) ||
      ['REVERSED', 'CANCELLED'].includes(original.status)
    ) {
      throw new ConflictException(
        'Only a positive unreversed commission can be reversed.',
      );
    }

    const now = new Date();
    const reversal = await this.prisma.$transaction(
      async (transaction) => {
        const created =
          await transaction.commissionEntry.create({
            data: {
              commissionNumber: this.codes.commission(),
              dealerOrganizationId:
                original.dealerOrganizationId,
              customerId: original.customerId,
              invoiceId: original.invoiceId,
              invoiceLineId: original.invoiceLineId,
              paymentId: original.paymentId,
              commissionRuleId: original.commissionRuleId,
              reversalOfEntryId: original.id,
              transactionType: original.transactionType,
              calculationType: original.calculationType,
              baseAmount: original.baseAmount,
              percentageRateSnapshot:
                original.percentageRateSnapshot,
              fixedAmountSnapshot:
                original.fixedAmountSnapshot,
              commissionAmount:
                original.commissionAmount.negated(),
              currency: original.currency,
              status: 'REVERSED',
              earnedAt: now,
              availableAt: now,
              holdReason: dto.reason.trim(),
            },
          });

        if (original.status === 'AVAILABLE') {
          await transaction.commissionEntry.update({
            where: {
              id: original.id,
            },
            data: {
              status: 'REVERSED',
            },
          });
        }

        await transaction.dealerLedgerEntry.create({
          data: {
            ledgerNumber: this.codes.ledger(),
            dealerOrganizationId:
              original.dealerOrganizationId,
            entryType: 'COMMISSION_REVERSAL',
            direction: 'DEBIT',
            amount: original.commissionAmount,
            currency: original.currency,
            referenceType: 'CommissionEntry',
            referenceId: created.id,
            description: dto.reason.trim(),
            occurredAt: now,
          },
        });

        return created;
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'commission.reversed',
      resourceType: 'CommissionEntry',
      resourceId: reversal.id,
      scopeType: 'DEALER',
      scopeId: original.dealerOrganizationId,
      beforeData: original,
      afterData: reversal,
    });

    return reversal;
  }

  async ledger(
    auth: AuthContext,
    dealerOrganizationId: string,
    query: PaginationQueryDto,
  ) {
    this.access.assertDealer(auth, dealerOrganizationId);
    const skip = (query.page - 1) * query.pageSize;

    const [items, total, aggregates] = await Promise.all([
      this.prisma.dealerLedgerEntry.findMany({
        where: {
          dealerOrganizationId,
        },
        skip,
        take: query.pageSize,
        orderBy: {
          occurredAt: 'desc',
        },
      }),
      this.prisma.dealerLedgerEntry.count({
        where: {
          dealerOrganizationId,
        },
      }),
      this.prisma.dealerLedgerEntry.groupBy({
        by: ['direction'],
        where: {
          dealerOrganizationId,
        },
        _sum: {
          amount: true,
        },
      }),
    ]);

    const credit =
      aggregates.find((item) => item.direction === 'CREDIT')
        ?._sum.amount ?? new Prisma.Decimal(0);
    const debit =
      aggregates.find((item) => item.direction === 'DEBIT')
        ?._sum.amount ?? new Prisma.Decimal(0);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
      balance: credit.minus(debit).toDecimalPlaces(2),
      credit,
      debit,
    };
  }

  private async assertDealerAndPlan(
    dealerOrganizationId: string,
    servicePlanId?: string,
  ): Promise<void> {
    const dealer = await this.prisma.organization.findFirst({
      where: {
        id: dealerOrganizationId,
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
      throw new BadRequestException(
        'An active dealer organization is required.',
      );
    }

    if (servicePlanId) {
      const plan = await this.prisma.servicePlan.findUnique({
        where: {
          id: servicePlanId,
        },
        select: {
          id: true,
        },
      });

      if (!plan) {
        throw new BadRequestException(
          'Commission service plan was not found.',
        );
      }
    }
  }

  private assertCalculation(input: {
    calculationType: string;
    percentageRate?: string;
    fixedAmount?: string;
    tierDefinition?: Record<string, unknown>;
  }): void {
    if (input.calculationType === 'PERCENTAGE') {
      if (!input.percentageRate) {
        throw new BadRequestException(
          'percentageRate is required for percentage commission.',
        );
      }

      const rate = this.money.decimal(input.percentageRate);

      if (rate.lt(0) || rate.gt(100)) {
        throw new BadRequestException(
          'percentageRate must be between 0 and 100.',
        );
      }

      return;
    }

    if (input.calculationType === 'FIXED_AMOUNT') {
      if (!input.fixedAmount) {
        throw new BadRequestException(
          'fixedAmount is required for fixed commission.',
        );
      }

      this.money.requireNonNegative(
        input.fixedAmount,
        'fixedAmount',
      );
      return;
    }

    if (
      input.calculationType === 'TIERED' &&
      !input.tierDefinition
    ) {
      throw new BadRequestException(
        'tierDefinition is required for tiered commission.',
      );
    }
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\commissions\commissions.controller.ts" `
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
import { CommissionQueryDto } from '../common/billing-query.dto';
import { CommissionsService } from './commissions.service';
import { CreateCommissionRuleDto } from './dto/create-commission-rule.dto';
import { ReverseCommissionDto } from './dto/reverse-commission.dto';
import { UpdateCommissionRuleDto } from './dto/update-commission-rule.dto';

@ApiTags('Commissions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller()
export class CommissionsController {
  constructor(
    private readonly commissionsService: CommissionsService,
  ) {}

  @Get('commission-rules')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'List commission rules within scope' })
  listRules(
    @CurrentAuth() auth: AuthContext,
    @Query() query: PaginationQueryDto,
  ) {
    return this.commissionsService.listRules(auth, query);
  }

  @Post('commission-rules')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Create a platform commission rule' })
  createRule(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateCommissionRuleDto,
  ) {
    return this.commissionsService.createRule(auth, dto);
  }

  @Patch('commission-rules/:ruleId')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Update a platform commission rule' })
  updateRule(
    @CurrentAuth() auth: AuthContext,
    @Param('ruleId', new ParseUUIDPipe()) ruleId: string,
    @Body() dto: UpdateCommissionRuleDto,
  ) {
    return this.commissionsService.updateRule(
      auth,
      ruleId,
      dto,
    );
  }

  @Get('commissions')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'List commission entries within scope' })
  listEntries(
    @CurrentAuth() auth: AuthContext,
    @Query() query: CommissionQueryDto,
  ) {
    return this.commissionsService.listEntries(auth, query);
  }

  @Post('commissions/:commissionEntryId/reverse')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Create an append-only commission reversal' })
  reverseEntry(
    @CurrentAuth() auth: AuthContext,
    @Param('commissionEntryId', new ParseUUIDPipe())
    commissionEntryId: string,
    @Body() dto: ReverseCommissionDto,
  ) {
    return this.commissionsService.reverseEntry(
      auth,
      commissionEntryId,
      dto,
    );
  }

  @Get('dealers/:dealerId/ledger')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Read dealer ledger and balance' })
  ledger(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Query() query: PaginationQueryDto,
  ) {
    return this.commissionsService.ledger(
      auth,
      dealerId,
      query,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\payments\payments.service.ts" `
        @'

import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';
import type { PaymentQueryDto } from '../common/billing-query.dto';
import { CommissionEngineService } from '../commissions/commission-engine.service';
import type { CompleteRefundDto, CreateRefundDto } from './dto/create-refund.dto';
import type { CreatePaymentDto } from './dto/create-payment.dto';
import type { ConfirmPaymentDto } from './dto/confirm-payment.dto';
import type { FailPaymentDto } from './dto/fail-payment.dto';
import type { GatewayEventDto } from './dto/gateway-event.dto';

@Injectable()
export class PaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly commissionEngine: CommissionEngineService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: PaymentQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.PaymentWhereInput = {
      AND: [
        this.access.paymentWhere(auth),
        query.customerId
          ? {
              customerId: query.customerId,
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
                  paymentNumber: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  gatewayTransactionId: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  gatewayReference: {
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
      this.prisma.payment.findMany({
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
            },
          },
          allocations: {
            include: {
              invoice: true,
            },
          },
          refunds: {
            orderBy: {
              requestedAt: 'desc',
            },
          },
        },
      }),
      this.prisma.payment.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, paymentId: string) {
    await this.access.assertPayment(auth, paymentId);

    const payment = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
      include: {
        customer: {
          include: {
            individualProfile: true,
            organizationProfile: true,
          },
        },
        allocations: {
          orderBy: {
            allocatedAt: 'desc',
          },
          include: {
            invoice: {
              include: {
                lines: {
                  orderBy: {
                    lineNumber: 'asc',
                  },
                },
              },
            },
          },
        },
        gatewayEvents: {
          orderBy: {
            receivedAt: 'desc',
          },
        },
        refunds: {
          orderBy: {
            requestedAt: 'desc',
          },
        },
        commissionEntries: {
          orderBy: {
            createdAt: 'desc',
          },
        },
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment was not found.');
    }

    return payment;
  }

  async create(auth: AuthContext, dto: CreatePaymentDto) {
    const customer = await this.access.assertCustomer(
      auth,
      dto.customerId,
    );

    if (!['PENDING', 'ACTIVE'].includes(customer.status)) {
      throw new BadRequestException(
        'Payment initiation requires an active or pending customer.',
      );
    }

    const amount = this.money.requirePositive(
      dto.amount,
      'amount',
    );

    const payment = await this.prisma.payment.create({
      data: {
        paymentNumber: this.codes.payment(),
        customerId: dto.customerId,
        amount,
        currency: dto.currency.trim().toUpperCase(),
        paymentMethod: dto.paymentMethod,
        paymentGateway: dto.paymentGateway,
        gatewayReference: this.optional(
          dto.gatewayReference,
        ),
        status: 'PENDING',
        metadata:
          dto.metadata as Prisma.InputJsonValue | undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment.created',
      resourceType: 'Payment',
      resourceId: payment.id,
      scopeType: 'CUSTOMER',
      scopeId: payment.customerId,
      afterData: payment,
    });

    return payment;
  }

  async confirm(
    auth: AuthContext,
    paymentId: string,
    dto: ConfirmPaymentDto,
  ) {
    await this.access.assertPayment(auth, paymentId);

    const before = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
    });

    if (!before) {
      throw new NotFoundException('Payment was not found.');
    }

    await this.access.assertFinancialOperator(
      auth,
      before.customerId,
    );

    if (!['INITIATED', 'PENDING'].includes(before.status)) {
      throw new ConflictException(
        'Only initiated or pending payments can be confirmed.',
      );
    }

    const allocations = dto.allocations ?? [];
    const invoiceIds = allocations.map(
      (allocation) => allocation.invoiceId,
    );

    if (new Set(invoiceIds).size !== invoiceIds.length) {
      throw new BadRequestException(
        'A payment may allocate to each invoice only once.',
      );
    }

    const allocationAmounts = allocations.map((allocation) =>
      this.money.requirePositive(
        allocation.amount,
        'allocation amount',
      ),
    );
    const allocatedTotal = this.money.sum(allocationAmounts);

    if (allocatedTotal.gt(before.amount)) {
      throw new BadRequestException(
        'Payment allocations exceed the payment amount.',
      );
    }

    const now = new Date();

    const confirmed = await this.prisma.$transaction(
      async (transaction) => {
        const invoices =
          invoiceIds.length > 0
            ? await transaction.invoice.findMany({
                where: {
                  id: {
                    in: invoiceIds,
                  },
                },
              })
            : [];

        if (invoices.length !== invoiceIds.length) {
          throw new BadRequestException(
            'One or more allocation invoices were not found.',
          );
        }

        for (const invoice of invoices) {
          if (invoice.customerId !== before.customerId) {
            throw new BadRequestException(
              'Payment and invoice customers must match.',
            );
          }

          if (invoice.currency !== before.currency) {
            throw new BadRequestException(
              'Payment and invoice currencies must match.',
            );
          }

          if (
            ![
              'ISSUED',
              'PARTIALLY_PAID',
              'OVERDUE',
            ].includes(invoice.status)
          ) {
            throw new ConflictException(
              `Invoice ${invoice.invoiceNumber} is not payable.`,
            );
          }
        }

        const payment = await transaction.payment.update({
          where: {
            id: paymentId,
          },
          data: {
            status: 'SUCCEEDED',
            gatewayTransactionId: this.optional(
              dto.gatewayTransactionId,
            ),
            gatewayReference:
              dto.gatewayReference !== undefined
                ? this.optional(dto.gatewayReference)
                : undefined,
            confirmedAt: now,
            failedAt: null,
            failureReason: null,
          },
        });

        for (let index = 0; index < allocations.length; index++) {
          const allocation = allocations[index];
          const amount = allocationAmounts[index];

          await transaction.paymentAllocation.create({
            data: {
              paymentId,
              invoiceId: allocation.invoiceId,
              amount,
              allocatedAt: now,
            },
          });

          await this.commissionEngine.createForAllocation(
            transaction,
            {
              paymentId,
              invoiceId: allocation.invoiceId,
              allocationAmount: amount,
              occurredAt: now,
            },
          );
        }

        return transaction.payment.findUniqueOrThrow({
          where: {
            id: payment.id,
          },
          include: {
            allocations: {
              include: {
                invoice: true,
              },
            },
            commissionEntries: true,
          },
        });
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment.confirmed',
      resourceType: 'Payment',
      resourceId: paymentId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: confirmed,
    });

    return confirmed;
  }

  async fail(
    auth: AuthContext,
    paymentId: string,
    dto: FailPaymentDto,
  ) {
    await this.access.assertPayment(auth, paymentId);

    const before = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
    });

    if (!before) {
      throw new NotFoundException('Payment was not found.');
    }

    await this.access.assertFinancialOperator(
      auth,
      before.customerId,
    );

    if (!['INITIATED', 'PENDING'].includes(before.status)) {
      throw new ConflictException(
        'Only initiated or pending payments can fail.',
      );
    }

    const failed = await this.prisma.payment.update({
      where: {
        id: paymentId,
      },
      data: {
        status: 'FAILED',
        failedAt: new Date(),
        failureReason: dto.reason.trim(),
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment.failed',
      resourceType: 'Payment',
      resourceId: paymentId,
      scopeType: 'CUSTOMER',
      scopeId: before.customerId,
      beforeData: before,
      afterData: failed,
    });

    return failed;
  }

  async createRefund(
    auth: AuthContext,
    paymentId: string,
    dto: CreateRefundDto,
  ) {
    await this.access.assertPayment(auth, paymentId);

    const payment = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
      include: {
        allocations: true,
        refunds: {
          where: {
            status: {
              in: ['REQUESTED', 'PENDING', 'SUCCEEDED'],
            },
          },
        },
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment was not found.');
    }

    await this.access.assertFinancialOperator(
      auth,
      payment.customerId,
    );

    if (
      ![
        'SUCCEEDED',
        'PARTIALLY_REFUNDED',
        'REFUNDED',
      ].includes(payment.status)
    ) {
      throw new ConflictException(
        'Only confirmed payments can be refunded.',
      );
    }

    if (
      dto.invoiceId &&
      !payment.allocations.some(
        (allocation) =>
          allocation.invoiceId === dto.invoiceId,
      )
    ) {
      throw new BadRequestException(
        'Refund invoice must be allocated to this payment.',
      );
    }

    const amount = this.money.requirePositive(
      dto.amount,
      'refund amount',
    );
    const alreadyRefunded = this.money.sum(
      payment.refunds.map((refund) => refund.amount),
    );

    if (alreadyRefunded.plus(amount).gt(payment.amount)) {
      throw new BadRequestException(
        'Refund total exceeds the payment amount.',
      );
    }

    const refund = await this.prisma.refund.create({
      data: {
        refundNumber: this.codes.refund(),
        paymentId,
        customerId: payment.customerId,
        invoiceId: dto.invoiceId,
        amount,
        currency: payment.currency,
        reason: dto.reason.trim(),
        status: 'REQUESTED',
        metadata:
          dto.metadata as Prisma.InputJsonValue | undefined,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'refund.requested',
      resourceType: 'Refund',
      resourceId: refund.id,
      scopeType: 'CUSTOMER',
      scopeId: payment.customerId,
      afterData: refund,
    });

    return refund;
  }

  async completeRefund(
    auth: AuthContext,
    refundId: string,
    dto: CompleteRefundDto,
  ) {
    this.access.assertPlatform(auth);

    const refund = await this.prisma.refund.findUnique({
      where: {
        id: refundId,
      },
      include: {
        payment: true,
      },
    });

    if (!refund) {
      throw new NotFoundException('Refund was not found.');
    }

    if (!['REQUESTED', 'PENDING'].includes(refund.status)) {
      throw new ConflictException(
        'Only requested or pending refunds can be completed.',
      );
    }

    const now = new Date();

    const completed = await this.prisma.$transaction(
      async (transaction) => {
        const updated = await transaction.refund.update({
          where: {
            id: refund.id,
          },
          data: {
            status: 'SUCCEEDED',
            gatewayRefundId: this.optional(
              dto.gatewayRefundId,
            ),
            completedAt: now,
            failedAt: null,
            failureReason: null,
          },
        });

        const succeededRefunds =
          await transaction.refund.aggregate({
            where: {
              paymentId: refund.paymentId,
              status: 'SUCCEEDED',
            },
            _sum: {
              amount: true,
            },
          });

        const refundedTotal =
          succeededRefunds._sum.amount ??
          new Prisma.Decimal(0);
        const paymentStatus = refundedTotal.gte(
          refund.payment.amount,
        )
          ? 'REFUNDED'
          : 'PARTIALLY_REFUNDED';

        await transaction.payment.update({
          where: {
            id: refund.paymentId,
          },
          data: {
            status: paymentStatus,
          },
        });

        if (
          refund.invoiceId &&
          paymentStatus === 'REFUNDED'
        ) {
          await transaction.invoice.update({
            where: {
              id: refund.invoiceId,
            },
            data: {
              status: 'REFUNDED',
            },
          });
        }

        await this.commissionEngine.reverseForRefund(
          transaction,
          {
            paymentId: refund.paymentId,
            refundId: refund.id,
            refundAmount: refund.amount,
            paymentAmount: refund.payment.amount,
            occurredAt: now,
            reason: refund.reason,
          },
        );

        return updated;
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'refund.completed',
      resourceType: 'Refund',
      resourceId: refund.id,
      scopeType: 'CUSTOMER',
      scopeId: refund.customerId,
      beforeData: refund,
      afterData: completed,
    });

    return completed;
  }

  async gatewayEvent(auth: AuthContext, dto: GatewayEventDto) {
    this.access.assertPlatform(auth);

    if (dto.paymentId) {
      const payment = await this.prisma.payment.findUnique({
        where: {
          id: dto.paymentId,
        },
        select: {
          id: true,
        },
      });

      if (!payment) {
        throw new BadRequestException(
          'Gateway event payment was not found.',
        );
      }
    }

    const payload = dto.payload as Prisma.InputJsonValue;
    const payloadHash = createHash('sha256')
      .update(JSON.stringify(dto.payload))
      .digest('hex');

    const event = await this.prisma.paymentGatewayEvent.upsert({
      where: {
        gateway_externalEventId: {
          gateway: dto.gateway,
          externalEventId: dto.externalEventId,
        },
      },
      create: {
        paymentId: dto.paymentId,
        gateway: dto.gateway,
        externalEventId: dto.externalEventId,
        eventType: dto.eventType.trim(),
        payload,
        payloadHash,
        status: 'RECEIVED',
      },
      update: {},
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payment-gateway-event.received',
      resourceType: 'PaymentGatewayEvent',
      resourceId: event.id,
      scopeType: 'PLATFORM',
      afterData: {
        id: event.id,
        paymentId: event.paymentId,
        gateway: event.gateway,
        externalEventId: event.externalEventId,
        eventType: event.eventType,
        payloadHash: event.payloadHash,
        status: event.status,
      },
    });

    return event;
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\payments\payments.controller.ts" `
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
import { PaymentQueryDto } from '../common/billing-query.dto';
import { CompleteRefundDto, CreateRefundDto } from './dto/create-refund.dto';
import { CreatePaymentDto } from './dto/create-payment.dto';
import { ConfirmPaymentDto } from './dto/confirm-payment.dto';
import { FailPaymentDto } from './dto/fail-payment.dto';
import { GatewayEventDto } from './dto/gateway-event.dto';
import { PaymentsService } from './payments.service';

@ApiTags('Payments')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller()
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Get('payments')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'List payments within effective scope' })
  list(
    @CurrentAuth() auth: AuthContext,
    @Query() query: PaymentQueryDto,
  ) {
    return this.paymentsService.list(auth, query);
  }

  @Post('payments')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'Initiate or record a pending payment' })
  create(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreatePaymentDto,
  ) {
    return this.paymentsService.create(auth, dto);
  }

  @Get('payments/:paymentId')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'Read one payment and allocations' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', new ParseUUIDPipe()) paymentId: string,
  ) {
    return this.paymentsService.get(auth, paymentId);
  }

  @Post('payments/:paymentId/confirm')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary:
      'Confirm a payment, allocate invoices, and calculate commissions',
  })
  confirm(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', new ParseUUIDPipe()) paymentId: string,
    @Body() dto: ConfirmPaymentDto,
  ) {
    return this.paymentsService.confirm(auth, paymentId, dto);
  }

  @Post('payments/:paymentId/fail')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'Mark an initiated payment failed' })
  fail(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', new ParseUUIDPipe()) paymentId: string,
    @Body() dto: FailPaymentDto,
  ) {
    return this.paymentsService.fail(auth, paymentId, dto);
  }

  @Post('payments/:paymentId/refunds')
  @RequirePermissions('payment.view')
  @ApiOperation({ summary: 'Request a refund against a payment' })
  createRefund(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', new ParseUUIDPipe()) paymentId: string,
    @Body() dto: CreateRefundDto,
  ) {
    return this.paymentsService.createRefund(
      auth,
      paymentId,
      dto,
    );
  }

  @Post('refunds/:refundId/complete')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary:
      'Complete a refund and append commission reversals',
  })
  completeRefund(
    @CurrentAuth() auth: AuthContext,
    @Param('refundId', new ParseUUIDPipe()) refundId: string,
    @Body() dto: CompleteRefundDto,
  ) {
    return this.paymentsService.completeRefund(
      auth,
      refundId,
      dto,
    );
  }

  @Post('payment-gateway-events')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary:
      'Record an idempotent provider event for a future gateway adapter',
  })
  gatewayEvent(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: GatewayEventDto,
  ) {
    return this.paymentsService.gatewayEvent(auth, dto);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\settlements\payout-accounts.service.ts" `
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
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { PayoutAccountCryptoService } from '../common/payout-account-crypto.service';
import type { CreatePayoutAccountDto } from './dto/create-payout-account.dto';
import type { UpdatePayoutAccountDto } from './dto/update-payout-account.dto';
import type { VerifyPayoutAccountDto } from './dto/verify-payout-account.dto';

@Injectable()
export class PayoutAccountsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly crypto: PayoutAccountCryptoService,
    private readonly auditService: AuditService,
  ) {}

  async list(
    auth: AuthContext,
    dealerOrganizationId: string,
  ) {
    this.access.assertDealer(auth, dealerOrganizationId);

    const accounts =
      await this.prisma.dealerPayoutAccount.findMany({
        where: {
          dealerOrganizationId,
          status: {
            not: 'ARCHIVED',
          },
        },
        orderBy: [
          {
            isDefault: 'desc',
          },
          {
            createdAt: 'desc',
          },
        ],
      });

    return accounts.map((account) => this.sanitize(account));
  }

  async create(auth: AuthContext, dto: CreatePayoutAccountDto) {
    this.access.assertDealer(
      auth,
      dto.dealerOrganizationId,
    );

    const dealer = await this.prisma.organization.findFirst({
      where: {
        id: dto.dealerOrganizationId,
        type: 'DEALER',
        status: 'ACTIVE',
      },
      select: {
        id: true,
      },
    });

    if (!dealer) {
      throw new BadRequestException(
        'An active dealer organization is required.',
      );
    }

    const encryptedReference = this.crypto.encrypt(
      dto.accountReference.trim(),
    );
    const maskedAccountNumber = this.crypto.mask(
      dto.accountReference,
    );

    const account = await this.prisma.$transaction(
      async (transaction) => {
        if (dto.isDefault) {
          await transaction.dealerPayoutAccount.updateMany({
            where: {
              dealerOrganizationId:
                dto.dealerOrganizationId,
              status: 'ACTIVE',
              isDefault: true,
            },
            data: {
              isDefault: false,
            },
          });
        }

        return transaction.dealerPayoutAccount.create({
          data: {
            accountCode: this.codes.payoutAccount(),
            dealerOrganizationId:
              dto.dealerOrganizationId,
            accountType: dto.accountType,
            provider: dto.provider,
            accountHolderName:
              dto.accountHolderName.trim(),
            maskedAccountNumber,
            encryptedAccountReference: encryptedReference,
            verificationStatus: 'UNVERIFIED',
            isDefault: dto.isDefault,
            status: 'ACTIVE',
          },
        });
      },
    );

    const sanitized = this.sanitize(account);

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payout-account.created',
      resourceType: 'DealerPayoutAccount',
      resourceId: account.id,
      scopeType: 'DEALER',
      scopeId: account.dealerOrganizationId,
      afterData: sanitized,
    });

    return sanitized;
  }

  async update(
    auth: AuthContext,
    payoutAccountId: string,
    dto: UpdatePayoutAccountDto,
  ) {
    const before =
      await this.prisma.dealerPayoutAccount.findUnique({
        where: {
          id: payoutAccountId,
        },
      });

    if (!before) {
      throw new NotFoundException(
        'Payout account was not found.',
      );
    }

    this.access.assertDealer(
      auth,
      before.dealerOrganizationId,
    );

    if (
      dto.status === 'ARCHIVED' &&
      before.isDefault
    ) {
      throw new ConflictException(
        'Select another default payout account before archiving this account.',
      );
    }

    const encryptedReference = dto.accountReference
      ? this.crypto.encrypt(dto.accountReference.trim())
      : undefined;
    const maskedAccountNumber = dto.accountReference
      ? this.crypto.mask(dto.accountReference)
      : undefined;

    const updated = await this.prisma.$transaction(
      async (transaction) => {
        if (dto.isDefault === true) {
          await transaction.dealerPayoutAccount.updateMany({
            where: {
              dealerOrganizationId:
                before.dealerOrganizationId,
              id: {
                not: before.id,
              },
              status: 'ACTIVE',
              isDefault: true,
            },
            data: {
              isDefault: false,
            },
          });
        }

        return transaction.dealerPayoutAccount.update({
          where: {
            id: before.id,
          },
          data: {
            accountHolderName:
              dto.accountHolderName?.trim(),
            encryptedAccountReference:
              encryptedReference,
            maskedAccountNumber,
            verificationStatus: dto.accountReference
              ? 'UNVERIFIED'
              : undefined,
            verifiedAt: dto.accountReference
              ? null
              : undefined,
            isDefault: dto.isDefault,
            status: dto.status,
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

    const sanitizedBefore = this.sanitize(before);
    const sanitizedUpdated = this.sanitize(updated);

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payout-account.updated',
      resourceType: 'DealerPayoutAccount',
      resourceId: before.id,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: sanitizedBefore,
      afterData: sanitizedUpdated,
    });

    return sanitizedUpdated;
  }

  async verify(
    auth: AuthContext,
    payoutAccountId: string,
    dto: VerifyPayoutAccountDto,
  ) {
    this.access.assertPlatform(auth);

    const before =
      await this.prisma.dealerPayoutAccount.findUnique({
        where: {
          id: payoutAccountId,
        },
      });

    if (!before) {
      throw new NotFoundException(
        'Payout account was not found.',
      );
    }

    if (before.status !== 'ACTIVE') {
      throw new ConflictException(
        'Only active payout accounts can be verified.',
      );
    }

    const verified =
      await this.prisma.dealerPayoutAccount.update({
        where: {
          id: payoutAccountId,
        },
        data: {
          verificationStatus:
            dto.verificationStatus,
          verifiedAt:
            dto.verificationStatus === 'VERIFIED'
              ? new Date()
              : null,
        },
      });

    const sanitizedBefore = this.sanitize(before);
    const sanitizedVerified = this.sanitize(verified);

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'payout-account.verification-updated',
      resourceType: 'DealerPayoutAccount',
      resourceId: before.id,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: sanitizedBefore,
      afterData: sanitizedVerified,
    });

    return sanitizedVerified;
  }

  private sanitize(account: {
    id: string;
    accountCode: string;
    dealerOrganizationId: string;
    accountType: string;
    provider: string;
    accountHolderName: string;
    maskedAccountNumber: string;
    verificationStatus: string;
    isDefault: boolean;
    status: string;
    verifiedAt: Date | null;
    createdAt: Date;
    updatedAt: Date;
    archivedAt: Date | null;
  }) {
    return {
      id: account.id,
      accountCode: account.accountCode,
      dealerOrganizationId:
        account.dealerOrganizationId,
      accountType: account.accountType,
      provider: account.provider,
      accountHolderName: account.accountHolderName,
      maskedAccountNumber: account.maskedAccountNumber,
      verificationStatus:
        account.verificationStatus,
      isDefault: account.isDefault,
      status: account.status,
      verifiedAt: account.verifiedAt,
      createdAt: account.createdAt,
      updatedAt: account.updatedAt,
      archivedAt: account.archivedAt,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\settlements\settlements.service.ts" `
        @'

import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../common/billing-access.service';
import { BillingCodeService } from '../common/billing-code.service';
import { BillingMoneyService } from '../common/billing-money.service';
import type { SettlementQueryDto } from '../common/billing-query.dto';
import type { CreateSettlementDto } from './dto/create-settlement.dto';
import type {
  CompleteSettlementDto,
  FailSettlementDto,
} from './dto/settlement-action.dto';

@Injectable()
export class SettlementsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly codes: BillingCodeService,
    private readonly money: BillingMoneyService,
    private readonly auditService: AuditService,
  ) {}

  async list(auth: AuthContext, query: SettlementQueryDto) {
    const skip = (query.page - 1) * query.pageSize;
    const where: Prisma.DealerSettlementWhereInput = {
      AND: [
        this.access.settlementWhere(auth),
        query.dealerOrganizationId
          ? {
              dealerOrganizationId:
                query.dealerOrganizationId,
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
                  settlementNumber: {
                    contains: query.search,
                    mode: 'insensitive',
                  },
                },
                {
                  providerReference: {
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
      this.prisma.dealerSettlement.findMany({
        where,
        skip,
        take: query.pageSize,
        orderBy: {
          createdAt: 'desc',
        },
        include: {
          dealerOrganization: {
            select: {
              id: true,
              code: true,
              name: true,
            },
          },
          payoutAccount: {
            select: {
              id: true,
              accountCode: true,
              provider: true,
              maskedAccountNumber: true,
              verificationStatus: true,
              status: true,
            },
          },
          _count: {
            select: {
              items: true,
            },
          },
        },
      }),
      this.prisma.dealerSettlement.count({ where }),
    ]);

    return {
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      totalPages: Math.ceil(total / query.pageSize),
    };
  }

  async get(auth: AuthContext, settlementId: string) {
    const settlement =
      await this.prisma.dealerSettlement.findFirst({
        where: {
          AND: [
            {
              id: settlementId,
            },
            this.access.settlementWhere(auth),
          ],
        },
        include: {
          dealerOrganization: true,
          payoutAccount: {
            select: {
              id: true,
              accountCode: true,
              provider: true,
              accountHolderName: true,
              maskedAccountNumber: true,
              verificationStatus: true,
              status: true,
            },
          },
          items: {
            include: {
              commissionEntry: {
                include: {
                  invoice: true,
                  payment: true,
                  customer: {
                    include: {
                      individualProfile: true,
                      organizationProfile: true,
                    },
                  },
                },
              },
            },
          },
        },
      });

    if (!settlement) {
      throw new NotFoundException(
        'Settlement was not found within the authenticated scope.',
      );
    }

    return settlement;
  }

  async create(auth: AuthContext, dto: CreateSettlementDto) {
    this.access.assertDealer(
      auth,
      dto.dealerOrganizationId,
    );

    const uniqueEntryIds = Array.from(
      new Set(dto.commissionEntryIds),
    );

    if (uniqueEntryIds.length !== dto.commissionEntryIds.length) {
      throw new BadRequestException(
        'Settlement commission entries must be unique.',
      );
    }

    const [payoutAccount, entries] = await Promise.all([
      this.prisma.dealerPayoutAccount.findFirst({
        where: {
          id: dto.payoutAccountId,
          dealerOrganizationId:
            dto.dealerOrganizationId,
          status: 'ACTIVE',
          verificationStatus: 'VERIFIED',
        },
      }),
      this.prisma.commissionEntry.findMany({
        where: {
          id: {
            in: uniqueEntryIds,
          },
          dealerOrganizationId:
            dto.dealerOrganizationId,
          status: 'AVAILABLE',
          commissionAmount: {
            gt: 0,
          },
        },
      }),
    ]);

    if (!payoutAccount) {
      throw new BadRequestException(
        'An active verified payout account owned by the dealer is required.',
      );
    }

    if (entries.length !== uniqueEntryIds.length) {
      throw new BadRequestException(
        'One or more commission entries are unavailable or outside the dealer.',
      );
    }

    const currencies = new Set(
      entries.map((entry) => entry.currency),
    );

    if (currencies.size !== 1) {
      throw new BadRequestException(
        'Settlement commission entries must use one currency.',
      );
    }

    const grossCommissionAmount = this.money.sum(
      entries.map((entry) => entry.commissionAmount),
    );
    const adjustmentAmount = this.money.money(
      dto.adjustmentAmount,
    );
    const feeAmount = this.money.requireNonNegative(
      dto.feeAmount,
      'feeAmount',
    );
    const netSettlementAmount = grossCommissionAmount
      .plus(adjustmentAmount)
      .minus(feeAmount)
      .toDecimalPlaces(2);

    if (netSettlementAmount.isNegative()) {
      throw new BadRequestException(
        'Settlement net amount cannot be negative.',
      );
    }

    const settlement = await this.prisma.$transaction(
      async (transaction) => {
        const created =
          await transaction.dealerSettlement.create({
            data: {
              settlementNumber: this.codes.settlement(),
              dealerOrganizationId:
                dto.dealerOrganizationId,
              payoutAccountId: dto.payoutAccountId,
              grossCommissionAmount,
              adjustmentAmount,
              feeAmount,
              netSettlementAmount,
              currency: entries[0].currency,
              status: 'DRAFT',
            },
          });

        await transaction.dealerSettlementItem.createMany({
          data: entries.map((entry) => ({
            settlementId: created.id,
            commissionEntryId: entry.id,
            amount: entry.commissionAmount,
          })),
        });

        await transaction.commissionEntry.updateMany({
          where: {
            id: {
              in: uniqueEntryIds,
            },
          },
          data: {
            status: 'SETTLEMENT_PENDING',
          },
        });

        return transaction.dealerSettlement.findUniqueOrThrow({
          where: {
            id: created.id,
          },
          include: {
            payoutAccount: {
              select: {
                id: true,
                accountCode: true,
                provider: true,
                maskedAccountNumber: true,
                verificationStatus: true,
              },
            },
            items: {
              include: {
                commissionEntry: true,
              },
            },
          },
        });
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'settlement.created',
      resourceType: 'DealerSettlement',
      resourceId: settlement.id,
      scopeType: 'DEALER',
      scopeId: settlement.dealerOrganizationId,
      afterData: settlement,
    });

    return settlement;
  }

  async submit(auth: AuthContext, settlementId: string) {
    const before = await this.getForMutation(
      auth,
      settlementId,
    );

    if (before.status !== 'DRAFT') {
      throw new ConflictException(
        'Only draft settlements can be submitted.',
      );
    }

    const submitted =
      await this.prisma.dealerSettlement.update({
        where: {
          id: settlementId,
        },
        data: {
          status: 'PENDING',
          initiatedAt: new Date(),
          failedAt: null,
          failureReason: null,
        },
        include: {
          payoutAccount: {
            select: {
              id: true,
              provider: true,
              maskedAccountNumber: true,
              verificationStatus: true,
            },
          },
          items: true,
        },
      });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'settlement.submitted',
      resourceType: 'DealerSettlement',
      resourceId: settlementId,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: before,
      afterData: submitted,
    });

    return submitted;
  }

  async complete(
    auth: AuthContext,
    settlementId: string,
    dto: CompleteSettlementDto,
  ) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.dealerSettlement.findUnique({
      where: {
        id: settlementId,
      },
      include: {
        items: true,
      },
    });

    if (!before) {
      throw new NotFoundException('Settlement was not found.');
    }

    if (!['PENDING', 'PROCESSING'].includes(before.status)) {
      throw new ConflictException(
        'Only pending or processing settlements can be completed.',
      );
    }

    const now = new Date();
    const commissionEntryIds = before.items.map(
      (item) => item.commissionEntryId,
    );

    const completed = await this.prisma.$transaction(
      async (transaction) => {
        const updated =
          await transaction.dealerSettlement.update({
            where: {
              id: settlementId,
            },
            data: {
              status: 'COMPLETED',
              providerReference:
                this.optional(dto.providerReference),
              completedAt: now,
              failedAt: null,
              failureReason: null,
            },
          });

        await transaction.commissionEntry.updateMany({
          where: {
            id: {
              in: commissionEntryIds,
            },
          },
          data: {
            status: 'SETTLED',
            settledAt: now,
          },
        });

        if (before.netSettlementAmount.gt(0)) {
          await transaction.dealerLedgerEntry.create({
            data: {
              ledgerNumber: this.codes.ledger(),
              dealerOrganizationId:
                before.dealerOrganizationId,
              entryType: 'SETTLEMENT',
              direction: 'DEBIT',
              amount: before.netSettlementAmount,
              currency: before.currency,
              referenceType: 'DealerSettlement',
              referenceId: before.id,
              description:
                `Settlement ${before.settlementNumber} completed`,
              occurredAt: now,
            },
          });
        }

        if (before.feeAmount.gt(0)) {
          await transaction.dealerLedgerEntry.create({
            data: {
              ledgerNumber: this.codes.ledger(),
              dealerOrganizationId:
                before.dealerOrganizationId,
              entryType: 'FEE',
              direction: 'DEBIT',
              amount: before.feeAmount,
              currency: before.currency,
              referenceType: 'DealerSettlement',
              referenceId: before.id,
              description:
                `Settlement fee for ${before.settlementNumber}`,
              occurredAt: now,
            },
          });
        }

        if (!before.adjustmentAmount.isZero()) {
          await transaction.dealerLedgerEntry.create({
            data: {
              ledgerNumber: this.codes.ledger(),
              dealerOrganizationId:
                before.dealerOrganizationId,
              entryType: 'MANUAL_ADJUSTMENT',
              direction: before.adjustmentAmount.isPositive()
                ? 'CREDIT'
                : 'DEBIT',
              amount: before.adjustmentAmount.abs(),
              currency: before.currency,
              referenceType: 'DealerSettlement',
              referenceId: before.id,
              description:
                `Settlement adjustment for ${before.settlementNumber}`,
              occurredAt: now,
            },
          });
        }

        return updated;
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'settlement.completed',
      resourceType: 'DealerSettlement',
      resourceId: settlementId,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: before,
      afterData: completed,
    });

    return completed;
  }

  async fail(
    auth: AuthContext,
    settlementId: string,
    dto: FailSettlementDto,
  ) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.dealerSettlement.findUnique({
      where: {
        id: settlementId,
      },
      include: {
        items: true,
      },
    });

    if (!before) {
      throw new NotFoundException('Settlement was not found.');
    }

    if (!['PENDING', 'PROCESSING'].includes(before.status)) {
      throw new ConflictException(
        'Only pending or processing settlements can fail.',
      );
    }

    const failed = await this.prisma.$transaction(
      async (transaction) => {
        const updated =
          await transaction.dealerSettlement.update({
            where: {
              id: settlementId,
            },
            data: {
              status: 'FAILED',
              failedAt: new Date(),
              failureReason: dto.reason.trim(),
              completedAt: null,
            },
          });

        await transaction.commissionEntry.updateMany({
          where: {
            id: {
              in: before.items.map(
                (item) => item.commissionEntryId,
              ),
            },
            status: 'SETTLEMENT_PENDING',
          },
          data: {
            status: 'AVAILABLE',
          },
        });

        return updated;
      },
    );

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'settlement.failed',
      resourceType: 'DealerSettlement',
      resourceId: settlementId,
      scopeType: 'DEALER',
      scopeId: before.dealerOrganizationId,
      beforeData: before,
      afterData: failed,
    });

    return failed;
  }

  private async getForMutation(
    auth: AuthContext,
    settlementId: string,
  ) {
    const settlement =
      await this.prisma.dealerSettlement.findUnique({
        where: {
          id: settlementId,
        },
        include: {
          payoutAccount: true,
          items: true,
        },
      });

    if (!settlement) {
      throw new NotFoundException('Settlement was not found.');
    }

    this.access.assertDealer(
      auth,
      settlement.dealerOrganizationId,
    );

    return settlement;
  }

  private optional(value?: string): string | null {
    const trimmed = value?.trim();

    return trimmed ? trimmed : null;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\settlements\settlements.controller.ts" `
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
import { SettlementQueryDto } from '../common/billing-query.dto';
import { CreatePayoutAccountDto } from './dto/create-payout-account.dto';
import { CreateSettlementDto } from './dto/create-settlement.dto';
import {
  CompleteSettlementDto,
  FailSettlementDto,
} from './dto/settlement-action.dto';
import { UpdatePayoutAccountDto } from './dto/update-payout-account.dto';
import { VerifyPayoutAccountDto } from './dto/verify-payout-account.dto';
import { PayoutAccountsService } from './payout-accounts.service';
import { SettlementsService } from './settlements.service';

@ApiTags('Dealer Settlements')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller()
export class SettlementsController {
  constructor(
    private readonly payoutAccountsService: PayoutAccountsService,
    private readonly settlementsService: SettlementsService,
  ) {}

  @Get('dealers/:dealerId/payout-accounts')
  @RequirePermissions('settlement.create')
  @ApiOperation({ summary: 'List masked dealer payout accounts' })
  listPayoutAccounts(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
  ) {
    return this.payoutAccountsService.list(auth, dealerId);
  }

  @Post('dealer-payout-accounts')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Create an encrypted dealer payout account',
  })
  createPayoutAccount(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreatePayoutAccountDto,
  ) {
    return this.payoutAccountsService.create(auth, dto);
  }

  @Patch('dealer-payout-accounts/:payoutAccountId')
  @RequirePermissions('settlement.create')
  @ApiOperation({ summary: 'Update a dealer payout account' })
  updatePayoutAccount(
    @CurrentAuth() auth: AuthContext,
    @Param('payoutAccountId', new ParseUUIDPipe())
    payoutAccountId: string,
    @Body() dto: UpdatePayoutAccountDto,
  ) {
    return this.payoutAccountsService.update(
      auth,
      payoutAccountId,
      dto,
    );
  }

  @Post('dealer-payout-accounts/:payoutAccountId/verify')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Verify or reject a payout account as platform',
  })
  verifyPayoutAccount(
    @CurrentAuth() auth: AuthContext,
    @Param('payoutAccountId', new ParseUUIDPipe())
    payoutAccountId: string,
    @Body() dto: VerifyPayoutAccountDto,
  ) {
    return this.payoutAccountsService.verify(
      auth,
      payoutAccountId,
      dto,
    );
  }

  @Get('settlements')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'List settlements within scope' })
  listSettlements(
    @CurrentAuth() auth: AuthContext,
    @Query() query: SettlementQueryDto,
  ) {
    return this.settlementsService.list(auth, query);
  }

  @Post('settlements')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Create a draft settlement from available commission',
  })
  createSettlement(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: CreateSettlementDto,
  ) {
    return this.settlementsService.create(auth, dto);
  }

  @Get('settlements/:settlementId')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Read settlement details' })
  getSettlement(
    @CurrentAuth() auth: AuthContext,
    @Param('settlementId', new ParseUUIDPipe())
    settlementId: string,
  ) {
    return this.settlementsService.get(
      auth,
      settlementId,
    );
  }

  @Post('settlements/:settlementId/submit')
  @RequirePermissions('settlement.create')
  @ApiOperation({ summary: 'Submit a draft settlement' })
  submitSettlement(
    @CurrentAuth() auth: AuthContext,
    @Param('settlementId', new ParseUUIDPipe())
    settlementId: string,
  ) {
    return this.settlementsService.submit(
      auth,
      settlementId,
    );
  }

  @Post('settlements/:settlementId/complete')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Complete a settlement and append ledger debits',
  })
  completeSettlement(
    @CurrentAuth() auth: AuthContext,
    @Param('settlementId', new ParseUUIDPipe())
    settlementId: string,
    @Body() dto: CompleteSettlementDto,
  ) {
    return this.settlementsService.complete(
      auth,
      settlementId,
      dto,
    );
  }

  @Post('settlements/:settlementId/fail')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Fail a settlement and release commission entries',
  })
  failSettlement(
    @CurrentAuth() auth: AuthContext,
    @Param('settlementId', new ParseUUIDPipe())
    settlementId: string,
    @Body() dto: FailSettlementDto,
  ) {
    return this.settlementsService.fail(
      auth,
      settlementId,
      dto,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\billing-api.module.ts" `
        @'

import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { AuditModule } from '../identity/audit/audit.module';
import { BillingAccessService } from './common/billing-access.service';
import { BillingCodeService } from './common/billing-code.service';
import { BillingDateService } from './common/billing-date.service';
import { BillingMoneyService } from './common/billing-money.service';
import { PayoutAccountCryptoService } from './common/payout-account-crypto.service';
import { CommissionEngineService } from './commissions/commission-engine.service';
import { CommissionsController } from './commissions/commissions.controller';
import { CommissionsService } from './commissions/commissions.service';
import { InvoicesController } from './invoices/invoices.controller';
import { InvoicesService } from './invoices/invoices.service';
import { PaymentsController } from './payments/payments.controller';
import { PaymentsService } from './payments/payments.service';
import { ServicePlansController } from './service-plans/service-plans.controller';
import { ServicePlansService } from './service-plans/service-plans.service';
import { PayoutAccountsService } from './settlements/payout-accounts.service';
import { SettlementsController } from './settlements/settlements.controller';
import { SettlementsService } from './settlements/settlements.service';
import { SubscriptionsController } from './subscriptions/subscriptions.controller';
import { SubscriptionsService } from './subscriptions/subscriptions.service';

@Module({
  imports: [
    ConfigModule,
    AccessControlModule,
    AuditModule,
  ],
  controllers: [
    ServicePlansController,
    SubscriptionsController,
    InvoicesController,
    PaymentsController,
    CommissionsController,
    SettlementsController,
  ],
  providers: [
    BillingAccessService,
    BillingCodeService,
    BillingDateService,
    BillingMoneyService,
    PayoutAccountCryptoService,
    CommissionEngineService,
    ServicePlansService,
    InvoicesService,
    SubscriptionsService,
    PaymentsService,
    CommissionsService,
    PayoutAccountsService,
    SettlementsService,
  ],
})
export class BillingApiModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\billing\common\billing-money.service.spec.ts" `
        @'

import { BillingMoneyService } from './billing-money.service';

describe('BillingMoneyService', () => {
  const service = new BillingMoneyService();

  it('calculates invoice lines with decimal precision', () => {
    const line = service.invoiceLine({
      quantity: '2.500',
      unitPrice: '100.00',
      discountAmount: '10.00',
      taxAmount: '5.00',
    });

    expect(line.grossAmount.toFixed(2)).toBe('250.00');
    expect(line.lineTotal.toFixed(2)).toBe('245.00');
  });

  it('sums monetary values without binary floating-point drift', () => {
    expect(
      service.sum(['0.10', '0.20']).toFixed(2),
    ).toBe('0.30');
  });
});
'@

    Write-Utf8File `
        "services\backend-api\src\billing\common\billing-date.service.spec.ts" `
        @'

import { BillingDateService } from './billing-date.service';

describe('BillingDateService', () => {
  const service = new BillingDateService();

  it('preserves month-end semantics', () => {
    const result = service.addInterval(
      new Date('2026-01-31T00:00:00.000Z'),
      'MONTH',
      1,
    );

    expect(result.toISOString()).toBe(
      '2026-02-28T00:00:00.000Z',
    );
  });
});
'@

    Write-Utf8File `
        "services\backend-api\test\billing.e2e-spec.ts" `
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

describe('Billing, commission, and settlement lifecycle (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let accessToken: string;
  let platformUserId: string;
  let platformMembershipId: string;
  let platformRoleAssignmentId: string;
  let dealerId: string;
  let customerId: string;
  let vehicleId: string;
  let planId: string;
  let subscriptionId: string;
  let invoiceId: string;
  let paymentId: string;
  let commissionRuleId: string;
  let commissionEntryId: string;
  let payoutAccountId: string;
  let settlementId: string;

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
        userCode: `USR-BILL-${codeSuffix}`,
        fullName: 'Billing E2E Administrator',
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
        deviceName: 'Billing E2E',
        appVersion: 'test',
      })
      .expect(200);

    accessToken = loginResponse.body.accessToken as string;
  });

  afterAll(async () => {
    const now = new Date();

    if (prisma) {
      if (subscriptionId) {
        await prisma.subscription.update({
          where: {
            id: subscriptionId,
          },
          data: {
            status: 'CANCELLED',
            cancelledAt: now,
            cancellationReason: 'E2E cleanup',
            autoRenew: false,
            nextBillingAt: null,
          },
        });
      }

      if (payoutAccountId) {
        await prisma.dealerPayoutAccount.update({
          where: {
            id: payoutAccountId,
          },
          data: {
            status: 'ARCHIVED',
            isDefault: false,
            archivedAt: now,
          },
        });
      }

      if (commissionRuleId) {
        await prisma.commissionRule.update({
          where: {
            id: commissionRuleId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

      if (planId) {
        await prisma.servicePlan.update({
          where: {
            id: planId,
          },
          data: {
            status: 'ARCHIVED',
            archivedAt: now,
          },
        });
      }

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

  it('runs subscription, invoice, payment, commission, and settlement accounting', async () => {
    const dealerResponse = await request(app.getHttpServer())
      .post('/api/v1/dealers')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        name: `Billing E2E Dealer ${codeSuffix}`,
        contactMobile: `017${numericSuffix}`,
      })
      .expect(201);

    dealerId = dealerResponse.body.id as string;

    const customerResponse = await request(app.getHttpServer())
      .post('/api/v1/customers/individual')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        managingDealerId: dealerId,
        fullName: `Billing E2E Customer ${codeSuffix}`,
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
        registrationNumber: `BILL-E2E-${codeSuffix}`,
        manufacturer: 'Solid Tracker Test',
        modelName: 'Billing Car',
        manufacturingYear: 2026,
      })
      .expect(201);

    vehicleId = vehicleResponse.body.id as string;

    const effectiveFrom = new Date(
      Date.now() - 24 * 60 * 60 * 1000,
    ).toISOString();

    const planResponse = await request(app.getHttpServer())
      .post('/api/v1/service-plans')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        planFamilyCode: `MONTHLY_${codeSuffix}`,
        name: `Monthly Tracking ${codeSuffix}`,
        billingIntervalUnit: 'MONTH',
        billingIntervalCount: 1,
        basePrice: '500.00',
        currency: 'BDT',
        taxBehavior: 'NONE',
        trialDays: 0,
        effectiveFrom,
        features: {
          liveTracking: true,
          historyDays: 90,
        },
      })
      .expect(201);

    planId = planResponse.body.id as string;

    await request(app.getHttpServer())
      .post(`/api/v1/service-plans/${planId}/activate`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({})
      .expect(201);

    const subscriptionResponse = await request(
      app.getHttpServer(),
    )
      .post('/api/v1/subscriptions')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        vehicleId,
        servicePlanId: planId,
        autoRenew: true,
      })
      .expect(201);

    subscriptionId = subscriptionResponse.body.id as string;

    await request(app.getHttpServer())
      .post(
        `/api/v1/subscriptions/${subscriptionId}/activate`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({})
      .expect(201);

    const invoiceResponse = await request(
      app.getHttpServer(),
    )
      .post(
        `/api/v1/subscriptions/${subscriptionId}/generate-invoice`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dueInDays: 7,
      })
      .expect(201);

    invoiceId = invoiceResponse.body.id as string;
    expect(Number(invoiceResponse.body.totalAmount)).toBe(500);

    await request(app.getHttpServer())
      .post(`/api/v1/invoices/${invoiceId}/issue`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({})
      .expect(201);

    const ruleResponse = await request(app.getHttpServer())
      .post('/api/v1/commission-rules')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        servicePlanId: planId,
        transactionType: 'INITIAL_SUBSCRIPTION',
        calculationType: 'PERCENTAGE',
        percentageRate: '10.0000',
        priority: 10,
        effectiveFrom,
      })
      .expect(201);

    commissionRuleId = ruleResponse.body.id as string;

    await request(app.getHttpServer())
      .patch(
        `/api/v1/commission-rules/${commissionRuleId}`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        status: 'ACTIVE',
      })
      .expect(200);

    const paymentResponse = await request(app.getHttpServer())
      .post('/api/v1/payments')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        customerId,
        amount: '500.00',
        currency: 'BDT',
        paymentMethod: 'CASH',
        paymentGateway: 'MANUAL',
        gatewayReference: `CASH-${codeSuffix}`,
      })
      .expect(201);

    paymentId = paymentResponse.body.id as string;

    const confirmedPaymentResponse = await request(
      app.getHttpServer(),
    )
      .post(`/api/v1/payments/${paymentId}/confirm`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        gatewayTransactionId: `TXN-${codeSuffix}`,
        allocations: [
          {
            invoiceId,
            amount: '500.00',
          },
        ],
      })
      .expect(201);

    expect(confirmedPaymentResponse.body.status).toBe(
      'SUCCEEDED',
    );
    expect(confirmedPaymentResponse.body.allocations).toHaveLength(
      1,
    );
    expect(
      confirmedPaymentResponse.body.commissionEntries,
    ).toHaveLength(1);

    const commissionResponse = await request(
      app.getHttpServer(),
    )
      .get(
        `/api/v1/commissions?dealerOrganizationId=${dealerId}`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(commissionResponse.body.items).toHaveLength(1);
    commissionEntryId =
      commissionResponse.body.items[0].id as string;
    expect(
      Number(
        commissionResponse.body.items[0].commissionAmount,
      ),
    ).toBe(50);

    const payoutResponse = await request(app.getHttpServer())
      .post('/api/v1/dealer-payout-accounts')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        accountType: 'MOBILE_FINANCIAL_SERVICE',
        provider: 'BKASH',
        accountHolderName: `Dealer ${codeSuffix}`,
        accountReference: `019${numericSuffix}`,
        isDefault: true,
      })
      .expect(201);

    payoutAccountId = payoutResponse.body.id as string;
    expect(
      payoutResponse.body.encryptedAccountReference,
    ).toBeUndefined();

    await request(app.getHttpServer())
      .post(
        `/api/v1/dealer-payout-accounts/${payoutAccountId}/verify`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        verificationStatus: 'VERIFIED',
      })
      .expect(201);

    const settlementResponse = await request(
      app.getHttpServer(),
    )
      .post('/api/v1/settlements')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        dealerOrganizationId: dealerId,
        payoutAccountId,
        commissionEntryIds: [commissionEntryId],
        adjustmentAmount: '0.00',
        feeAmount: '0.00',
      })
      .expect(201);

    settlementId = settlementResponse.body.id as string;
    expect(
      Number(settlementResponse.body.netSettlementAmount),
    ).toBe(50);

    await request(app.getHttpServer())
      .post(`/api/v1/settlements/${settlementId}/submit`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send({})
      .expect(201);

    const completedSettlementResponse = await request(
      app.getHttpServer(),
    )
      .post(
        `/api/v1/settlements/${settlementId}/complete`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        providerReference: `PAYOUT-${codeSuffix}`,
      })
      .expect(201);

    expect(completedSettlementResponse.body.status).toBe(
      'COMPLETED',
    );

    const ledgerResponse = await request(app.getHttpServer())
      .get(`/api/v1/dealers/${dealerId}/ledger`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(ledgerResponse.body.items).toHaveLength(2);
    expect(Number(ledgerResponse.body.balance)).toBe(0);
  });
});
'@

    Write-Step 5 9 "Registering the billing module"

    $appModulePath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\app.module.ts"

    $appModuleContent = [System.IO.File]::ReadAllText(
        $appModulePath
    )

    $billingImport =
        "import { BillingApiModule } from './billing/billing-api.module';"

    if (-not $appModuleContent.Contains($billingImport)) {
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
            $billingImport +
            $appModuleContent.Substring(
                $moduleMatch.Index + $moduleMatch.Length
            )
        )
    }

    if (-not $appModuleContent.Contains("BillingApiModule,")) {
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
            "BillingApiModule," +
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

    Write-Step 7 9 "Verifying billing database invariants"

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
      'subscription.view',
      'subscription.create',
      'subscription.suspend',
      'invoice.view',
      'payment.view',
      'commission.view',
      'settlement.create'
    )
      AND "status" = 'ACTIVE'
  ) AS billing_permission_count,
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'subscriptions_one_current_per_vehicle',
        'dealer_payout_accounts_one_default_per_dealer'
      )
  ) AS billing_invariant_index_count,
  (
    SELECT COUNT(DISTINCT trigger_name)
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'subscriptions_validate_vehicle',
        'invoices_validate_context',
        'payment_allocations_validate',
        'payment_allocations_block_update',
        'payment_allocations_block_delete',
        'refunds_validate',
        'commission_entries_validate',
        'payout_accounts_validate_dealer',
        'settlements_validate_context',
        'settlement_items_validate_context',
        'dealer_ledger_entries_validate_dealer',
        'dealer_ledger_entries_block_update',
        'dealer_ledger_entries_block_delete'
      )
  ) AS billing_trigger_count;
'@

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -AtF ","'

    if ($LASTEXITCODE -ne 0) {
        throw "Billing database verification failed."
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

    if ($migrationCount -ne 5) {
        throw "Expected exactly 5 applied migrations."
    }

    if ($permissionCount -ne 7) {
        throw "Expected 7 active billing permissions."
    }

    if ($indexCount -ne 2) {
        throw "Expected 2 billing invariant indexes."
    }

    if ($triggerCount -ne 13) {
        throw "Expected 13 distinct billing triggers."
    }

    Write-Host "Public tables:       $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:  $migrationCount" -ForegroundColor Green
    Write-Host "Billing permissions: $permissionCount" -ForegroundColor Green
    Write-Host "Billing indexes:     $indexCount" -ForegroundColor Green
    Write-Host "Billing triggers:    $triggerCount" -ForegroundColor Green

    Write-Step 8 9 "Writing billing architecture documentation"
    Write-Utf8File `
        "docs\architecture\billing-api.md" `
        @'

# Billing, Commission, and Settlement API

## Scope

This stage exposes the existing billing foundation through authenticated REST APIs and transactional application services.

It implements:

- service-plan families and immutable versions;
- vehicle subscriptions and lifecycle transitions;
- manual and subscription-generated invoices;
- payment initiation, confirmation, and invoice allocation;
- provider-event idempotency storage;
- refund requests and completion;
- dealer commission rules and calculated commission snapshots;
- append-only commission reversals;
- encrypted dealer payout accounts;
- dealer settlements and immutable ledger movements.

No new Prisma migration is introduced. The existing billing migration already provides the required tables, constraints, partial indexes, and validation triggers.

## Service-plan versioning

Activated plan versions keep their commercial terms immutable. Changes to interval, price, tax behavior, trial, features, or effective dates require a new version.

Activating a version makes older active versions in the same family inactive without changing historical subscriptions.

## Subscription flow

```text
PENDING
  ↓ activate
TRIALING or ACTIVE
  ↓ suspend/resume
SUSPENDED ⇄ ACTIVE
  ↓ cancel
CANCELLED
```

The database permits only one current subscription per vehicle across pending, trialing, active, past-due, and suspended states.

## Invoice accounting

Invoice lines are calculated with decimal arithmetic.

```text
line total = quantity × unit price - discount + tax

invoice total = subtotal - discount + tax

paid amount + outstanding amount = total amount
```

Payment allocations remain append-only. Database triggers prevent allocation beyond a payment, beyond an invoice, across customers, across currencies, or from an unconfirmed payment.

## Payment-gateway boundary

The API stores provider-neutral payment state and idempotent gateway events.

Actual bKash, Nagad, SSLCommerz, or bank adapter credentials and outbound API calls are intentionally isolated for a later integration stage.

`gateway + externalEventId` is unique, so a repeated webhook cannot create a second event effect.

## Dealer commission

When a confirmed payment is allocated to an invoice, commission calculation evaluates each eligible invoice line.

Rule precedence is:

1. dealer + service-plan-specific active rule;
2. dealer-wide active rule;
3. no commission.

Supported calculations are percentage, fixed amount, tiered definition, and none.

Every commission entry stores calculation snapshots. Refunds and manual corrections append negative reversal entries and dealer-ledger debits rather than deleting financial history.

## Payout-account security

Raw bank or mobile-financial-service account references are encrypted with AES-256-GCM before storage.

API responses return only masked account identifiers. The encryption key is supplied through:

```text
BILLING_PAYOUT_ENCRYPTION_KEY
```

Verification is a separate platform operation.

## Settlement flow

```text
AVAILABLE commission
  ↓ create settlement
SETTLEMENT_PENDING
  ↓ submit
PENDING
  ↓ provider processing
COMPLETED or FAILED
```

Completion:

- marks settlement items settled;
- appends settlement, fee, and adjustment ledger entries;
- preserves all commission and settlement history.

Failure releases pending commission entries back to `AVAILABLE`.

## Authorization

Existing permission codes are used:

- `subscription.view`
- `subscription.create`
- `subscription.suspend`
- `invoice.view`
- `payment.view`
- `commission.view`
- `settlement.create`

Permission checks are combined with resource scope:

- platform scope can administer all financial records;
- dealer scope is limited to its managed customers, commission, payout accounts, and settlements;
- customer scope is limited to its own subscriptions, invoices, and payments;
- payment confirmation and refund processing require platform or matching dealer authority;
- commission-rule administration and payout verification require platform scope.

## Endpoints

```text
GET    /api/v1/service-plans
POST   /api/v1/service-plans
GET    /api/v1/service-plans/:planId
PATCH  /api/v1/service-plans/:planId
POST   /api/v1/service-plans/:planId/activate
POST   /api/v1/service-plans/:planId/versions

GET    /api/v1/subscriptions
POST   /api/v1/subscriptions
GET    /api/v1/subscriptions/:subscriptionId
POST   /api/v1/subscriptions/:subscriptionId/activate
POST   /api/v1/subscriptions/:subscriptionId/suspend
POST   /api/v1/subscriptions/:subscriptionId/resume
POST   /api/v1/subscriptions/:subscriptionId/cancel
POST   /api/v1/subscriptions/:subscriptionId/generate-invoice

GET    /api/v1/invoices
POST   /api/v1/invoices
GET    /api/v1/invoices/:invoiceId
POST   /api/v1/invoices/:invoiceId/issue
POST   /api/v1/invoices/:invoiceId/void

GET    /api/v1/payments
POST   /api/v1/payments
GET    /api/v1/payments/:paymentId
POST   /api/v1/payments/:paymentId/confirm
POST   /api/v1/payments/:paymentId/fail
POST   /api/v1/payments/:paymentId/refunds
POST   /api/v1/refunds/:refundId/complete
POST   /api/v1/payment-gateway-events

GET    /api/v1/commission-rules
POST   /api/v1/commission-rules
PATCH  /api/v1/commission-rules/:ruleId
GET    /api/v1/commissions
POST   /api/v1/commissions/:commissionEntryId/reverse
GET    /api/v1/dealers/:dealerId/ledger

GET    /api/v1/dealers/:dealerId/payout-accounts
POST   /api/v1/dealer-payout-accounts
PATCH  /api/v1/dealer-payout-accounts/:payoutAccountId
POST   /api/v1/dealer-payout-accounts/:payoutAccountId/verify

GET    /api/v1/settlements
POST   /api/v1/settlements
GET    /api/v1/settlements/:settlementId
POST   /api/v1/settlements/:settlementId/submit
POST   /api/v1/settlements/:settlementId/complete
POST   /api/v1/settlements/:settlementId/fail
```

## E2E coverage

The billing E2E workflow verifies:

```text
dealer
→ customer
→ vehicle
→ active service plan
→ active subscription
→ issued invoice
→ active percentage commission rule
→ confirmed and allocated payment
→ automatic commission and ledger credit
→ encrypted verified payout account
→ draft settlement
→ submitted settlement
→ completed settlement
→ balanced dealer ledger
```
'@

    Write-Step 9 9 "Committing the billing API"

    git add -- `
        ".env.example" `
        "docs/architecture/billing-api.md" `
        "scripts/solid-tracker-billing-api.ps1" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/billing" `
        "services/backend-api/test/billing.e2e-spec.ts"

    git commit `
        -m "feat(billing): establish billing commission and settlement APIs"

    if ($LASTEXITCODE -ne 0) {
        throw "Billing API commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Billing API Ready" -ForegroundColor Cyan
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
        "Traccar synchronization, live positions, events, geofences, " +
        "commands, and notification APIs"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "BILLING API FAILED" -ForegroundColor Red
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
