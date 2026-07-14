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

    $fullPath = Join-Path $script:RootPath $RelativePath
    $content = [System.IO.File]::ReadAllText($fullPath)
    $pattern = "(?m)^" + [regex]::Escape($Name) + "=.*$"
    $line = "$Name=$Value"

    if ([regex]::IsMatch($content, $pattern)) {
        $updated = [regex]::Replace(
            $content,
            $pattern,
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)
                return $line
            },
            1
        )
    }
    else {
        $updated = (
            $content.TrimEnd() +
            [Environment]::NewLine +
            $line +
            [Environment]::NewLine
        )
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $updated,
        $script:Utf8NoBom
    )

    Write-Host "[UPDATED] $RelativePath with $Name" -ForegroundColor Green
}

function New-SecureBase64 {
    $bytes = New-Object byte[] 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return [Convert]::ToBase64String($bytes)
}

function Assert-InitialRepositoryState {
    $allowedPath =
        "scripts/solid-tracker-payment-gateway-automation.ps1"
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

        if ($path -ne $allowedPath) {
            $unexpected.Add($line)
        }
    }

    if ($unexpected.Count -gt 0) {
        Write-Host "Unexpected repository changes:" -ForegroundColor Yellow

        foreach ($line in $unexpected) {
            Write-Host $line -ForegroundColor Yellow
        }

        throw (
            "Commit, discard, or move unrelated changes before running " +
            "the payment gateway automation stage."
        )
    }
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - Payment Gateway and Billing Automation" -ForegroundColor Cyan
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

    if ($currentBranch -ne "feat/tracking-api") {
        throw (
            "Expected branch feat/tracking-api, " +
            "but current branch is $currentBranch"
        )
    }

    Assert-InitialRepositoryState

    Write-Step 1 9 "Merging tracking APIs and creating the payment automation branch"

    Invoke-CheckedCommand "Checkout main" {
        git checkout main
    }

    Invoke-CheckedCommand "Merge tracking APIs into main" {
        git merge `
            --no-ff `
            feat/tracking-api `
            -m "merge: integrate tracking APIs"
    }

    Invoke-CheckedCommand "Create payment gateway automation branch" {
        git checkout -b feat/payment-gateway-automation
    }

    Write-Step 2 9 "Validating infrastructure, migrations, and billing schema"

    Invoke-CheckedCommand "Prisma migration status" {
        pnpm.cmd `
            --filter "@solid-tracker/backend-api" `
            exec prisma migrate status `
            --config prisma.config.ts
    }

    $postgresHealth = docker inspect `
        --format='{{.State.Health.Status}}' `
        solid-tracker-postgres

    if ($LASTEXITCODE -ne 0 -or $postgresHealth.Trim() -ne "healthy") {
        throw "PostgreSQL container is not healthy."
    }

    $redisHealth = docker inspect `
        --format='{{.State.Health.Status}}' `
        solid-tracker-redis

    if ($LASTEXITCODE -ne 0 -or $redisHealth.Trim() -ne "healthy") {
        throw "Redis container is not healthy."
    }

    $schemaPath = Join-Path `
        $script:RootPath `
        "services\backend-api\prisma\schema.prisma"

    $schemaContent = [System.IO.File]::ReadAllText($schemaPath)

    foreach ($requiredModel in @(
        "model Subscription {",
        "model Invoice {",
        "model Payment {",
        "model PaymentGatewayEvent {",
        "model Refund {"
    )) {
        if (-not $schemaContent.Contains($requiredModel)) {
            throw "Required billing model is missing: $requiredModel"
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

    Write-Host "PostgreSQL:          healthy" -ForegroundColor Green
    Write-Host "Redis:               healthy" -ForegroundColor Green
    Write-Host "Billing schema:      present" -ForegroundColor Green
    Write-Host "Applied migrations:  5" -ForegroundColor Green
    Write-Host "New migration:       not required" -ForegroundColor Green

    Write-Step 3 9 "Configuring gateway security and recurring billing"

    Ensure-EnvEntry ".env" "PAYMENT_AUTOMATION_ENABLED" "false"
    Ensure-EnvEntry ".env" "PAYMENT_AUTOMATION_INTERVAL_MS" "60000"
    Ensure-EnvEntry ".env" "PAYMENT_AUTOMATION_BATCH_SIZE" "50"
    Ensure-EnvEntry ".env" "PAYMENT_AUTOMATION_DUE_IN_DAYS" "7"
    Ensure-EnvEntry ".env" "PAYMENT_GATEWAY_HTTP_TIMEOUT_MS" "15000"
    Ensure-EnvEntry `
        ".env" `
        "PAYMENT_CALLBACK_BASE_URL" `
        "http://localhost:3000/api/v1/payment-gateways/webhooks"
    Ensure-EnvEntry `
        ".env" `
        "PAYMENT_SANDBOX_WEBHOOK_SECRET" `
        (New-SecureBase64)
    Ensure-EnvEntry ".env" "BKASH_GATEWAY_PROXY_URL" ""
    Ensure-EnvEntry ".env" "BKASH_GATEWAY_PROXY_SECRET" ""
    Ensure-EnvEntry ".env" "NAGAD_GATEWAY_PROXY_URL" ""
    Ensure-EnvEntry ".env" "NAGAD_GATEWAY_PROXY_SECRET" ""
    Ensure-EnvEntry ".env" "SSLCOMMERZ_BASE_URL" ""
    Ensure-EnvEntry ".env" "SSLCOMMERZ_STORE_ID" ""
    Ensure-EnvEntry ".env" "SSLCOMMERZ_STORE_PASSWORD" ""

    Ensure-EnvEntry ".env.example" "PAYMENT_AUTOMATION_ENABLED" "false"
    Ensure-EnvEntry ".env.example" "PAYMENT_AUTOMATION_INTERVAL_MS" "60000"
    Ensure-EnvEntry ".env.example" "PAYMENT_AUTOMATION_BATCH_SIZE" "50"
    Ensure-EnvEntry ".env.example" "PAYMENT_AUTOMATION_DUE_IN_DAYS" "7"
    Ensure-EnvEntry ".env.example" "PAYMENT_GATEWAY_HTTP_TIMEOUT_MS" "15000"
    Ensure-EnvEntry `
        ".env.example" `
        "PAYMENT_CALLBACK_BASE_URL" `
        "https://api.example.com/api/v1/payment-gateways/webhooks"
    Ensure-EnvEntry `
        ".env.example" `
        "PAYMENT_SANDBOX_WEBHOOK_SECRET" `
        "replace-with-a-dedicated-random-secret-at-least-32-characters"
    Ensure-EnvEntry ".env.example" "BKASH_GATEWAY_PROXY_URL" ""
    Ensure-EnvEntry ".env.example" "BKASH_GATEWAY_PROXY_SECRET" ""
    Ensure-EnvEntry ".env.example" "NAGAD_GATEWAY_PROXY_URL" ""
    Ensure-EnvEntry ".env.example" "NAGAD_GATEWAY_PROXY_SECRET" ""
    Ensure-EnvEntry ".env.example" "SSLCOMMERZ_BASE_URL" ""
    Ensure-EnvEntry ".env.example" "SSLCOMMERZ_STORE_ID" ""
    Ensure-EnvEntry ".env.example" "SSLCOMMERZ_STORE_PASSWORD" ""

    $validationPath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\config\environment.validation.ts"

    $validationContent = [System.IO.File]::ReadAllText(
        $validationPath
    )

    if (-not $validationContent.Contains("PAYMENT_AUTOMATION_ENABLED")) {
        $validationBlock = @'
  PAYMENT_AUTOMATION_ENABLED: Joi.boolean()
    .truthy('true')
    .falsy('false')
    .default(false),
  PAYMENT_AUTOMATION_INTERVAL_MS: Joi.number()
    .integer()
    .min(60000)
    .default(60000),
  PAYMENT_AUTOMATION_BATCH_SIZE: Joi.number()
    .integer()
    .min(1)
    .max(200)
    .default(50),
  PAYMENT_AUTOMATION_DUE_IN_DAYS: Joi.number()
    .integer()
    .min(0)
    .max(90)
    .default(7),
  PAYMENT_GATEWAY_HTTP_TIMEOUT_MS: Joi.number()
    .integer()
    .min(1000)
    .max(120000)
    .default(15000),
  PAYMENT_CALLBACK_BASE_URL: Joi.string().uri().required(),
  PAYMENT_SANDBOX_WEBHOOK_SECRET: Joi.string().min(32).required(),
  BKASH_GATEWAY_PROXY_URL: Joi.string().allow('').default(''),
  BKASH_GATEWAY_PROXY_SECRET: Joi.string().allow('').default(''),
  NAGAD_GATEWAY_PROXY_URL: Joi.string().allow('').default(''),
  NAGAD_GATEWAY_PROXY_SECRET: Joi.string().allow('').default(''),
  SSLCOMMERZ_BASE_URL: Joi.string().allow('').default(''),
  SSLCOMMERZ_STORE_ID: Joi.string().allow('').default(''),
  SSLCOMMERZ_STORE_PASSWORD: Joi.string().allow('').default(''),
'@

        $closingIndex = $validationContent.LastIndexOf("});")

        if ($closingIndex -lt 0) {
            throw "Could not locate the environment validation object."
        }

        $validationContent = (
            $validationContent.Substring(0, $closingIndex) +
            $validationBlock +
            [Environment]::NewLine +
            $validationContent.Substring($closingIndex)
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

    Write-Step 4 9 "Writing gateway adapters and billing automation APIs"

    Write-Utf8File `
        "services\backend-api\src\payment-automation\common\gateway-types.ts" `
        @'
import type {
  Payment,
  PaymentGateway,
} from '../../generated/prisma/client';

export type AutomatedPaymentGateway =
  | 'OTHER'
  | 'BKASH'
  | 'NAGAD'
  | 'SSLCOMMERZ';

export type GatewayOutcome =
  | 'PENDING'
  | 'SUCCEEDED'
  | 'FAILED'
  | 'CANCELLED';

export interface GatewayPaymentContext {
  paymentId: string;
  paymentNumber: string;
  gateway: PaymentGateway;
  amount: string;
  currency: string;
  customerName: string;
  customerMobile?: string;
  customerEmail?: string;
  invoiceId: string;
  invoiceNumber: string;
  callbackUrl: string;
  successUrl?: string;
  cancelUrl?: string;
  failureUrl?: string;
}

export interface GatewayInitializationResult {
  gatewayReference: string;
  gatewayTransactionId?: string;
  redirectUrl?: string;
  raw: Record<string, unknown>;
}

export interface GatewayResult {
  externalEventId: string;
  eventType: string;
  paymentReference: string;
  gatewayTransactionId?: string;
  gatewayReference?: string;
  status: GatewayOutcome;
  amount?: string;
  currency?: string;
  failureReason?: string;
  raw: Record<string, unknown>;
}

export interface GatewayWebhookHeaders {
  signature?: string;
  eventId?: string;
  authorization?: string;
}

export interface PaymentGatewayAdapter {
  readonly gateway: PaymentGateway;

  initialize(
    context: GatewayPaymentContext,
  ): Promise<GatewayInitializationResult>;

  verifyWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<boolean>;

  parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult>;

  query(payment: Payment): Promise<GatewayResult>;
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\common\gateway-signature.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import {
  createHash,
  createHmac,
  timingSafeEqual,
} from 'node:crypto';

@Injectable()
export class GatewaySignatureService {
  canonicalize(value: unknown): string {
    return JSON.stringify(this.sortValue(value));
  }

  hash(value: unknown): string {
    return createHash('sha256')
      .update(this.canonicalize(value))
      .digest('hex');
  }

  sign(secret: string, value: unknown): string {
    return createHmac('sha256', secret)
      .update(this.canonicalize(value))
      .digest('hex');
  }

  verify(
    secret: string,
    value: unknown,
    providedSignature?: string,
  ): boolean {
    if (!providedSignature) {
      return false;
    }

    const expected = Buffer.from(
      this.sign(secret, value),
      'utf8',
    );
    const provided = Buffer.from(
      providedSignature.trim().toLowerCase(),
      'utf8',
    );

    if (expected.length !== provided.length) {
      return false;
    }

    return timingSafeEqual(expected, provided);
  }

  private sortValue(value: unknown): unknown {
    if (Array.isArray(value)) {
      return value.map((item) => this.sortValue(item));
    }

    if (
      value !== null &&
      typeof value === 'object'
    ) {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>)
          .sort(([left], [right]) =>
            left.localeCompare(right),
          )
          .map(([key, item]) => [
            key,
            this.sortValue(item),
          ]),
      );
    }

    return value;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\common\gateway-http.service.ts" `
        @'
import {
  BadGatewayException,
  GatewayTimeoutException,
  Injectable,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

interface GatewayRequestOptions {
  method?: 'GET' | 'POST';
  headers?: Record<string, string>;
  body?: string;
}

@Injectable()
export class GatewayHttpService {
  private readonly timeoutMs: number;

  constructor(configService: ConfigService) {
    this.timeoutMs = configService.get<number>(
      'PAYMENT_GATEWAY_HTTP_TIMEOUT_MS',
      15000,
    );
  }

  async json<T>(
    url: string,
    options: GatewayRequestOptions = {},
  ): Promise<T> {
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      this.timeoutMs,
    );

    try {
      const response = await fetch(url, {
        method: options.method ?? 'GET',
        headers: options.headers,
        body: options.body,
        signal: controller.signal,
      });

      const text = await response.text();
      let payload: unknown = {};

      if (text.trim()) {
        try {
          payload = JSON.parse(text);
        } catch {
          payload = {
            raw: text,
          };
        }
      }

      if (!response.ok) {
        throw new BadGatewayException(
          `Gateway HTTP ${response.status}: ${text.slice(0, 500)}`,
        );
      }

      return payload as T;
    } catch (error) {
      if (
        error instanceof Error &&
        error.name === 'AbortError'
      ) {
        throw new GatewayTimeoutException(
          'Payment gateway request timed out.',
        );
      }

      if (
        error instanceof BadGatewayException ||
        error instanceof GatewayTimeoutException
      ) {
        throw error;
      }

      throw new BadGatewayException(
        error instanceof Error
          ? error.message
          : 'Unknown payment gateway error.',
      );
    } finally {
      clearTimeout(timeout);
    }
  }

  form<T>(
    url: string,
    fields: Record<string, string>,
  ): Promise<T> {
    return this.json<T>(url, {
      method: 'POST',
      headers: {
        'content-type':
          'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams(fields).toString(),
    });
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\common\automation-run-key.service.ts" `
        @'
import { Injectable } from '@nestjs/common';

@Injectable()
export class AutomationRunKeyService {
  key(asOf: Date, intervalMs: number): string {
    const safeInterval = Math.max(intervalMs, 60_000);
    const bucket = Math.floor(
      asOf.getTime() / safeInterval,
    );

    return `billing-automation:${bucket}`;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\common\automation-identity.service.ts" `
        @'
import {
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';

@Injectable()
export class AutomationIdentityService {
  constructor(private readonly prisma: PrismaService) {}

  async platformAuth(): Promise<AuthContext> {
    const assignment =
      await this.prisma.roleAssignment.findFirst({
        where: {
          status: 'ACTIVE',
          scopeType: 'PLATFORM',
          user: {
            status: 'ACTIVE',
          },
          role: {
            status: 'ACTIVE',
          },
        },
        orderBy: {
          createdAt: 'asc',
        },
        include: {
          user: true,
          role: true,
        },
      });

    if (!assignment) {
      throw new ServiceUnavailableException(
        'Billing automation requires an active platform role assignment.',
      );
    }

    return {
      userId: assignment.userId,
      sessionId: 'billing-automation',
      userCode: assignment.user.userCode,
      fullName: assignment.user.fullName,
      mobileNumber: assignment.user.mobileNumber,
      roles: [
        {
          code: assignment.role.code,
          scopeType: 'PLATFORM',
          scopeId: assignment.scopeId,
        },
      ],
      permissions: [],
      organizationIds: [assignment.scopeId],
      customerIds: [],
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\adapters\sandbox-gateway.adapter.ts" `
        @'
import {
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import type { Payment } from '../../generated/prisma/client';
import { GatewaySignatureService } from '../common/gateway-signature.service';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
  PaymentGatewayAdapter,
} from '../common/gateway-types';

@Injectable()
export class SandboxGatewayAdapter
  implements PaymentGatewayAdapter
{
  readonly gateway = 'OTHER' as const;
  private readonly secret: string;

  constructor(
    configService: ConfigService,
    private readonly signatures: GatewaySignatureService,
  ) {
    this.secret =
      configService.get<string>(
        'PAYMENT_SANDBOX_WEBHOOK_SECRET',
      ) ?? '';
  }

  async initialize(
    context: GatewayPaymentContext,
  ): Promise<GatewayInitializationResult> {
    this.assertConfigured();

    const gatewayReference =
      `SANDBOX-${context.paymentNumber}-${randomUUID()}`;

    return {
      gatewayReference,
      redirectUrl: undefined,
      raw: {
        mode: 'sandbox',
        gatewayReference,
        callbackUrl: context.callbackUrl,
      },
    };
  }

  async verifyWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<boolean> {
    this.assertConfigured();

    return this.signatures.verify(
      this.secret,
      payload,
      headers.signature,
    );
  }

  async parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult> {
    const paymentReference = this.requiredString(
      payload.paymentReference,
      'paymentReference',
    );
    const status = this.status(payload.status);
    const transactionId = this.optionalString(
      payload.transactionId,
    );
    const eventId =
      headers.eventId ??
      this.optionalString(payload.eventId) ??
      `${paymentReference}:${status}:${transactionId ?? 'none'}`;

    return {
      externalEventId: eventId,
      eventType: `SANDBOX_${status}`,
      paymentReference,
      gatewayTransactionId: transactionId,
      gatewayReference: paymentReference,
      status,
      amount: this.optionalString(payload.amount),
      currency: this.optionalString(payload.currency),
      failureReason: this.optionalString(
        payload.failureReason,
      ),
      raw: payload,
    };
  }

  async query(payment: Payment): Promise<GatewayResult> {
    return {
      externalEventId:
        `sandbox-query:${payment.id}:${payment.updatedAt.toISOString()}`,
      eventType: 'SANDBOX_QUERY',
      paymentReference:
        payment.gatewayReference ?? payment.paymentNumber,
      gatewayTransactionId:
        payment.gatewayTransactionId ?? undefined,
      gatewayReference:
        payment.gatewayReference ?? undefined,
      status:
        payment.status === 'SUCCEEDED'
          ? 'SUCCEEDED'
          : payment.status === 'FAILED'
            ? 'FAILED'
            : 'PENDING',
      amount: payment.amount.toString(),
      currency: payment.currency,
      failureReason:
        payment.failureReason ?? undefined,
      raw: {
        localStatus: payment.status,
      },
    };
  }

  private assertConfigured(): void {
    if (this.secret.length < 32) {
      throw new ServiceUnavailableException(
        'Sandbox gateway secret is not configured.',
      );
    }
  }

  private status(value: unknown): GatewayResult['status'] {
    const normalized = this.requiredString(
      value,
      'status',
    ).toUpperCase();

    if (
      normalized === 'SUCCEEDED' ||
      normalized === 'SUCCESS' ||
      normalized === 'VALID'
    ) {
      return 'SUCCEEDED';
    }

    if (
      normalized === 'FAILED' ||
      normalized === 'FAILURE'
    ) {
      return 'FAILED';
    }

    if (
      normalized === 'CANCELLED' ||
      normalized === 'CANCELED'
    ) {
      return 'CANCELLED';
    }

    return 'PENDING';
  }

  private requiredString(
    value: unknown,
    field: string,
  ): string {
    const parsed = this.optionalString(value);

    if (!parsed) {
      throw new Error(
        `Sandbox callback is missing ${field}.`,
      );
    }

    return parsed;
  }

  private optionalString(
    value: unknown,
  ): string | undefined {
    return typeof value === 'string' &&
      value.trim().length > 0
      ? value.trim()
      : typeof value === 'number'
        ? value.toString()
        : undefined;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\adapters\signed-proxy-client.service.ts" `
        @'
import {
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type {
  Payment,
  PaymentGateway,
} from '../../generated/prisma/client';
import { GatewayHttpService } from '../common/gateway-http.service';
import { GatewaySignatureService } from '../common/gateway-signature.service';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
} from '../common/gateway-types';

interface ProxyConfiguration {
  urlKey: string;
  secretKey: string;
}

@Injectable()
export class SignedProxyClientService {
  constructor(
    private readonly config: ConfigService,
    private readonly http: GatewayHttpService,
    private readonly signatures: GatewaySignatureService,
  ) {}

  async initialize(
    gateway: PaymentGateway,
    configuration: ProxyConfiguration,
    context: GatewayPaymentContext,
  ): Promise<GatewayInitializationResult> {
    const { baseUrl, secret } =
      this.configuration(configuration);

    return this.http.json<GatewayInitializationResult>(
      `${baseUrl}/payments`,
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${secret}`,
          'x-solid-gateway': gateway,
        },
        body: JSON.stringify(context),
      },
    );
  }

  verifyWebhook(
    configuration: ProxyConfiguration,
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): boolean {
    const { secret } =
      this.configuration(configuration);

    return this.signatures.verify(
      secret,
      payload,
      headers.signature,
    );
  }

  parseWebhook(
    gateway: PaymentGateway,
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): GatewayResult {
    const paymentReference = this.required(
      payload.paymentReference,
      'paymentReference',
    );
    const rawStatus = this.required(
      payload.status,
      'status',
    ).toUpperCase();
    const status: GatewayResult['status'] =
      ['SUCCEEDED', 'SUCCESS', 'COMPLETED'].includes(
        rawStatus,
      )
        ? 'SUCCEEDED'
        : ['FAILED', 'FAILURE'].includes(rawStatus)
          ? 'FAILED'
          : ['CANCELLED', 'CANCELED'].includes(rawStatus)
            ? 'CANCELLED'
            : 'PENDING';
    const transactionId = this.optional(
      payload.transactionId,
    );
    const eventId =
      headers.eventId ??
      this.optional(payload.eventId) ??
      `${gateway}:${paymentReference}:${status}:${transactionId ?? 'none'}`;

    return {
      externalEventId: eventId,
      eventType: `${gateway}_${status}`,
      paymentReference,
      gatewayTransactionId: transactionId,
      gatewayReference:
        this.optional(payload.gatewayReference) ??
        paymentReference,
      status,
      amount: this.optional(payload.amount),
      currency: this.optional(payload.currency),
      failureReason: this.optional(
        payload.failureReason,
      ),
      raw: payload,
    };
  }

  async query(
    gateway: PaymentGateway,
    configuration: ProxyConfiguration,
    payment: Payment,
  ): Promise<GatewayResult> {
    const { baseUrl, secret } =
      this.configuration(configuration);
    const reference = encodeURIComponent(
      payment.gatewayReference ??
        payment.paymentNumber,
    );

    return this.http.json<GatewayResult>(
      `${baseUrl}/payments/${reference}`,
      {
        headers: {
          authorization: `Bearer ${secret}`,
          'x-solid-gateway': gateway,
        },
      },
    );
  }

  private configuration(
    configuration: ProxyConfiguration,
  ): {
    baseUrl: string;
    secret: string;
  } {
    const baseUrl = (
      this.config.get<string>(configuration.urlKey) ??
      ''
    ).replace(/\/+$/, '');
    const secret =
      this.config.get<string>(
        configuration.secretKey,
      ) ?? '';

    if (!baseUrl || secret.length < 32) {
      throw new ServiceUnavailableException(
        `${configuration.urlKey} and ${configuration.secretKey} must be configured.`,
      );
    }

    return {
      baseUrl,
      secret,
    };
  }

  private required(
    value: unknown,
    field: string,
  ): string {
    const parsed = this.optional(value);

    if (!parsed) {
      throw new Error(
        `Gateway proxy payload is missing ${field}.`,
      );
    }

    return parsed;
  }

  private optional(
    value: unknown,
  ): string | undefined {
    return typeof value === 'string' &&
      value.trim().length > 0
      ? value.trim()
      : typeof value === 'number'
        ? value.toString()
        : undefined;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\adapters\bkash-gateway.adapter.ts" `
        @'
import { Injectable } from '@nestjs/common';
import type { Payment } from '../../generated/prisma/client';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
  PaymentGatewayAdapter,
} from '../common/gateway-types';
import { SignedProxyClientService } from './signed-proxy-client.service';

@Injectable()
export class BkashGatewayAdapter
  implements PaymentGatewayAdapter
{
  readonly gateway = 'BKASH' as const;
  private readonly configuration = {
    urlKey: 'BKASH_GATEWAY_PROXY_URL',
    secretKey: 'BKASH_GATEWAY_PROXY_SECRET',
  };

  constructor(
    private readonly proxy: SignedProxyClientService,
  ) {}

  initialize(
    context: GatewayPaymentContext,
  ): Promise<GatewayInitializationResult> {
    return this.proxy.initialize(
      this.gateway,
      this.configuration,
      context,
    );
  }

  verifyWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<boolean> {
    return Promise.resolve(
      this.proxy.verifyWebhook(
        this.configuration,
        headers,
        payload,
      ),
    );
  }

  parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult> {
    return Promise.resolve(
      this.proxy.parseWebhook(
        this.gateway,
        headers,
        payload,
      ),
    );
  }

  query(payment: Payment): Promise<GatewayResult> {
    return this.proxy.query(
      this.gateway,
      this.configuration,
      payment,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\adapters\nagad-gateway.adapter.ts" `
        @'
import { Injectable } from '@nestjs/common';
import type { Payment } from '../../generated/prisma/client';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
  PaymentGatewayAdapter,
} from '../common/gateway-types';
import { SignedProxyClientService } from './signed-proxy-client.service';

@Injectable()
export class NagadGatewayAdapter
  implements PaymentGatewayAdapter
{
  readonly gateway = 'NAGAD' as const;
  private readonly configuration = {
    urlKey: 'NAGAD_GATEWAY_PROXY_URL',
    secretKey: 'NAGAD_GATEWAY_PROXY_SECRET',
  };

  constructor(
    private readonly proxy: SignedProxyClientService,
  ) {}

  initialize(
    context: GatewayPaymentContext,
  ): Promise<GatewayInitializationResult> {
    return this.proxy.initialize(
      this.gateway,
      this.configuration,
      context,
    );
  }

  verifyWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<boolean> {
    return Promise.resolve(
      this.proxy.verifyWebhook(
        this.configuration,
        headers,
        payload,
      ),
    );
  }

  parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult> {
    return Promise.resolve(
      this.proxy.parseWebhook(
        this.gateway,
        headers,
        payload,
      ),
    );
  }

  query(payment: Payment): Promise<GatewayResult> {
    return this.proxy.query(
      this.gateway,
      this.configuration,
      payment,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\adapters\sslcommerz-gateway.adapter.ts" `
        @'
import {
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Payment } from '../../generated/prisma/client';
import { GatewayHttpService } from '../common/gateway-http.service';
import type {
  GatewayInitializationResult,
  GatewayPaymentContext,
  GatewayResult,
  GatewayWebhookHeaders,
  PaymentGatewayAdapter,
} from '../common/gateway-types';

interface SslCommerzInitializationResponse {
  status?: string;
  failedreason?: string;
  sessionkey?: string;
  GatewayPageURL?: string;
}

interface SslCommerzValidationResponse {
  status?: string;
  tran_id?: string;
  val_id?: string;
  bank_tran_id?: string;
  amount?: string;
  currency?: string;
  error?: string;
}

@Injectable()
export class SslCommerzGatewayAdapter
  implements PaymentGatewayAdapter
{
  readonly gateway = 'SSLCOMMERZ' as const;

  constructor(
    private readonly config: ConfigService,
    private readonly http: GatewayHttpService,
  ) {}

  async initialize(
    context: GatewayPaymentContext,
  ): Promise<GatewayInitializationResult> {
    const settings = this.settings();
    const response =
      await this.http.form<SslCommerzInitializationResponse>(
        `${settings.baseUrl}/gwprocess/v4/api.php`,
        {
          store_id: settings.storeId,
          store_passwd: settings.storePassword,
          total_amount: context.amount,
          currency: context.currency,
          tran_id: context.paymentNumber,
          success_url:
            context.successUrl ?? context.callbackUrl,
          fail_url:
            context.failureUrl ?? context.callbackUrl,
          cancel_url:
            context.cancelUrl ?? context.callbackUrl,
          ipn_url: context.callbackUrl,
          cus_name: context.customerName,
          cus_email:
            context.customerEmail ??
            'billing@solid-tracker.local',
          cus_add1: 'Bangladesh',
          cus_city: 'Dhaka',
          cus_country: 'Bangladesh',
          cus_phone:
            context.customerMobile ?? '00000000000',
          shipping_method: 'NO',
          product_name:
            `Solid Tracker ${context.invoiceNumber}`,
          product_category: 'GPS Tracking',
          product_profile: 'general',
        },
      );

    if (
      response.status?.toUpperCase() !== 'SUCCESS' ||
      !response.sessionkey ||
      !response.GatewayPageURL
    ) {
      throw new ServiceUnavailableException(
        response.failedreason ??
          'SSLCOMMERZ did not create a payment session.',
      );
    }

    return {
      gatewayReference: response.sessionkey,
      redirectUrl: response.GatewayPageURL,
      raw: response as unknown as Record<string, unknown>,
    };
  }

  async verifyWebhook(
    _headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<boolean> {
    const validation = await this.validatePayload(payload);

    return ['VALID', 'VALIDATED'].includes(
      validation.status?.toUpperCase() ?? '',
    );
  }

  async parseWebhook(
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ): Promise<GatewayResult> {
    const validation = await this.validatePayload(payload);
    const rawStatus = (
      validation.status ??
      this.optional(payload.status) ??
      'PENDING'
    ).toUpperCase();
    const status: GatewayResult['status'] =
      ['VALID', 'VALIDATED'].includes(rawStatus)
        ? 'SUCCEEDED'
        : ['FAILED', 'INVALID_TRANSACTION'].includes(
              rawStatus,
            )
          ? 'FAILED'
          : ['CANCELLED', 'CANCELED'].includes(
                rawStatus,
              )
            ? 'CANCELLED'
            : 'PENDING';
    const paymentReference =
      validation.tran_id ??
      this.required(payload.tran_id, 'tran_id');
    const validationId =
      validation.val_id ??
      this.optional(payload.val_id);
    const transactionId =
      validation.bank_tran_id ??
      this.optional(payload.bank_tran_id);
    const externalEventId =
      headers.eventId ??
      validationId ??
      transactionId ??
      `${paymentReference}:${rawStatus}`;

    return {
      externalEventId,
      eventType: `SSLCOMMERZ_${rawStatus}`,
      paymentReference,
      gatewayTransactionId: transactionId,
      gatewayReference:
        validationId ?? paymentReference,
      status,
      amount:
        validation.amount ??
        this.optional(payload.amount),
      currency:
        validation.currency ??
        this.optional(payload.currency),
      failureReason:
        validation.error ??
        this.optional(payload.error),
      raw: {
        callback: payload,
        validation,
      },
    };
  }

  async query(payment: Payment): Promise<GatewayResult> {
    if (!payment.gatewayReference) {
      return this.pending(payment);
    }

    const validation = await this.validate(
      payment.gatewayReference,
    );
    const rawStatus =
      validation.status?.toUpperCase() ?? 'PENDING';
    const status: GatewayResult['status'] =
      ['VALID', 'VALIDATED'].includes(rawStatus)
        ? 'SUCCEEDED'
        : rawStatus === 'FAILED'
          ? 'FAILED'
          : 'PENDING';

    return {
      externalEventId:
        `sslcommerz-query:${payment.id}:${validation.val_id ?? payment.gatewayReference}`,
      eventType: `SSLCOMMERZ_QUERY_${rawStatus}`,
      paymentReference:
        validation.tran_id ?? payment.paymentNumber,
      gatewayTransactionId:
        validation.bank_tran_id ?? undefined,
      gatewayReference:
        validation.val_id ?? payment.gatewayReference,
      status,
      amount:
        validation.amount ?? payment.amount.toString(),
      currency:
        validation.currency ?? payment.currency,
      failureReason: validation.error,
      raw: validation as unknown as Record<string, unknown>,
    };
  }

  private async validatePayload(
    payload: Record<string, unknown>,
  ): Promise<SslCommerzValidationResponse> {
    const validationId = this.required(
      payload.val_id,
      'val_id',
    );

    return this.validate(validationId);
  }

  private validate(
    validationId: string,
  ): Promise<SslCommerzValidationResponse> {
    const settings = this.settings();
    const query = new URLSearchParams({
      val_id: validationId,
      store_id: settings.storeId,
      store_passwd: settings.storePassword,
      v: '1',
      format: 'json',
    });

    return this.http.json<SslCommerzValidationResponse>(
      `${settings.baseUrl}/validator/api/validationserverAPI.php?${query.toString()}`,
    );
  }

  private pending(payment: Payment): GatewayResult {
    return {
      externalEventId:
        `sslcommerz-query:${payment.id}:pending`,
      eventType: 'SSLCOMMERZ_QUERY_PENDING',
      paymentReference: payment.paymentNumber,
      gatewayReference:
        payment.gatewayReference ?? undefined,
      gatewayTransactionId:
        payment.gatewayTransactionId ?? undefined,
      status: 'PENDING',
      amount: payment.amount.toString(),
      currency: payment.currency,
      raw: {},
    };
  }

  private settings(): {
    baseUrl: string;
    storeId: string;
    storePassword: string;
  } {
    const baseUrl = (
      this.config.get<string>(
        'SSLCOMMERZ_BASE_URL',
      ) ?? ''
    ).replace(/\/+$/, '');
    const storeId =
      this.config.get<string>(
        'SSLCOMMERZ_STORE_ID',
      ) ?? '';
    const storePassword =
      this.config.get<string>(
        'SSLCOMMERZ_STORE_PASSWORD',
      ) ?? '';

    if (
      !baseUrl ||
      !storeId ||
      !storePassword
    ) {
      throw new ServiceUnavailableException(
        'SSLCOMMERZ credentials are not configured.',
      );
    }

    return {
      baseUrl,
      storeId,
      storePassword,
    };
  }

  private required(
    value: unknown,
    field: string,
  ): string {
    const parsed = this.optional(value);

    if (!parsed) {
      throw new Error(
        `SSLCOMMERZ payload is missing ${field}.`,
      );
    }

    return parsed;
  }

  private optional(
    value: unknown,
  ): string | undefined {
    return typeof value === 'string' &&
      value.trim().length > 0
      ? value.trim()
      : typeof value === 'number'
        ? value.toString()
        : undefined;
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\adapters\gateway-registry.service.ts" `
        @'
import {
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { PaymentGateway } from '../../generated/prisma/client';
import type { PaymentGatewayAdapter } from '../common/gateway-types';
import { BkashGatewayAdapter } from './bkash-gateway.adapter';
import { NagadGatewayAdapter } from './nagad-gateway.adapter';
import { SandboxGatewayAdapter } from './sandbox-gateway.adapter';
import { SslCommerzGatewayAdapter } from './sslcommerz-gateway.adapter';

@Injectable()
export class GatewayRegistryService {
  constructor(
    private readonly sandbox: SandboxGatewayAdapter,
    private readonly bkash: BkashGatewayAdapter,
    private readonly nagad: NagadGatewayAdapter,
    private readonly sslcommerz: SslCommerzGatewayAdapter,
  ) {}

  get(gateway: PaymentGateway): PaymentGatewayAdapter {
    switch (gateway) {
      case 'OTHER':
        return this.sandbox;
      case 'BKASH':
        return this.bkash;
      case 'NAGAD':
        return this.nagad;
      case 'SSLCOMMERZ':
        return this.sslcommerz;
      default:
        throw new ServiceUnavailableException(
          `Gateway ${gateway} is not supported by automation.`,
        );
    }
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\dto\initialize-gateway-payment.dto.ts" `
        @'
import {
  ApiProperty,
  ApiPropertyOptional,
} from '@nestjs/swagger';
import {
  IsOptional,
  IsString,
  IsUrl,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class InitializeGatewayPaymentDto {
  @ApiProperty()
  @IsUUID()
  invoiceId!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUrl({
    require_tld: false,
  })
  successUrl?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUrl({
    require_tld: false,
  })
  cancelUrl?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUrl({
    require_tld: false,
  })
  failureUrl?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(160)
  customerReference?: string;
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\dto\run-billing-automation.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsInt,
  IsOptional,
  Max,
  Min,
} from 'class-validator';

export class RunBillingAutomationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  asOf?: string;

  @ApiPropertyOptional({ default: 7 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(90)
  dueInDays = 7;

  @ApiPropertyOptional({ default: 50 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  batchSize = 50;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  dryRun = false;
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\dto\reconcile-payments.dto.ts" `
        @'
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  Max,
  Min,
} from 'class-validator';

export class ReconcilePaymentsDto {
  @ApiPropertyOptional({ default: 25 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 25;

  @ApiPropertyOptional({ default: 15 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1440)
  minimumAgeMinutes = 15;
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\services\gateway-payment.service.ts" `
        @'
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  PaymentGateway,
  Prisma,
} from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../../billing/common/billing-access.service';
import { PaymentsService } from '../../billing/payments/payments.service';
import { GatewayRegistryService } from '../adapters/gateway-registry.service';
import { AutomationIdentityService } from '../common/automation-identity.service';
import { GatewaySignatureService } from '../common/gateway-signature.service';
import type {
  AutomatedPaymentGateway,
  GatewayResult,
  GatewayWebhookHeaders,
} from '../common/gateway-types';
import type { InitializeGatewayPaymentDto } from '../dto/initialize-gateway-payment.dto';

const payableInvoiceStatuses = [
  'ISSUED',
  'PARTIALLY_PAID',
  'OVERDUE',
] as const;

@Injectable()
export class GatewayPaymentService {
  private readonly callbackBaseUrl: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly payments: PaymentsService,
    private readonly registry: GatewayRegistryService,
    private readonly identity: AutomationIdentityService,
    private readonly signatures: GatewaySignatureService,
    private readonly auditService: AuditService,
    configService: ConfigService,
  ) {
    this.callbackBaseUrl = (
      configService.get<string>(
        'PAYMENT_CALLBACK_BASE_URL',
      ) ??
      'http://localhost:3000/api/v1/payment-gateways/webhooks'
    ).replace(/\/+$/, '');
  }

  async initialize(
    auth: AuthContext,
    paymentId: string,
    dto: InitializeGatewayPaymentDto,
  ) {
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
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment was not found.');
    }

    if (
      !['INITIATED', 'PENDING'].includes(payment.status)
    ) {
      throw new ConflictException(
        'Only initiated or pending payments can be initialized.',
      );
    }

    const gateway = this.automationGateway(
      payment.paymentGateway,
    );
    const adapter = this.registry.get(gateway);

    const invoice = await this.prisma.invoice.findUnique({
      where: {
        id: dto.invoiceId,
      },
    });

    if (
      !invoice ||
      invoice.customerId !== payment.customerId
    ) {
      throw new BadRequestException(
        'Gateway invoice must belong to the payment customer.',
      );
    }

    if (invoice.currency !== payment.currency) {
      throw new BadRequestException(
        'Gateway payment and invoice currencies must match.',
      );
    }

    if (
      !payableInvoiceStatuses.includes(
        invoice.status as (typeof payableInvoiceStatuses)[number],
      )
    ) {
      throw new ConflictException(
        'Gateway payment requires a payable invoice.',
      );
    }

    if (payment.amount.gt(invoice.outstandingAmount)) {
      throw new BadRequestException(
        'Payment amount exceeds the invoice outstanding amount.',
      );
    }

    const customerName =
      payment.customer.individualProfile?.fullName ??
      payment.customer.organizationProfile?.displayName ??
      payment.customer.customerCode;

    const callbackUrl =
      `${this.callbackBaseUrl}/${gateway}`;

    const initiation = await adapter.initialize({
      paymentId: payment.id,
      paymentNumber: payment.paymentNumber,
      gateway,
      amount: payment.amount.toString(),
      currency: payment.currency,
      customerName,
      customerMobile:
        payment.customer.primaryMobile ?? undefined,
      customerEmail:
        payment.customer.primaryEmail ?? undefined,
      invoiceId: invoice.id,
      invoiceNumber: invoice.invoiceNumber,
      callbackUrl,
      successUrl: dto.successUrl,
      cancelUrl: dto.cancelUrl,
      failureUrl: dto.failureUrl,
    });

    const existingMetadata = this.record(
      payment.metadata,
    );
    const metadata = JSON.parse(
      JSON.stringify({
        ...existingMetadata,
        gatewayAutomation: {
          invoiceId: invoice.id,
          invoiceNumber: invoice.invoiceNumber,
          customerReference:
            dto.customerReference ?? null,
          callbackUrl,
          initializedAt: new Date().toISOString(),
          initiation: initiation.raw,
        },
      }),
    ) as Prisma.InputJsonValue;

    const updated = await this.prisma.payment.update({
      where: {
        id: payment.id,
      },
      data: {
        status: 'PENDING',
        gatewayReference:
          initiation.gatewayReference,
        gatewayTransactionId:
          initiation.gatewayTransactionId,
        metadata,
      },
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'payment-gateway.initialized',
      resourceType: 'Payment',
      resourceId: payment.id,
      scopeType: 'CUSTOMER',
      scopeId: payment.customerId,
      beforeData: payment,
      afterData: updated,
      metadata: {
        gateway,
        invoiceId: invoice.id,
        redirectUrlConfigured:
          Boolean(initiation.redirectUrl),
      },
    });

    return {
      payment: updated,
      gateway,
      gatewayReference:
        initiation.gatewayReference,
      gatewayTransactionId:
        initiation.gatewayTransactionId,
      redirectUrl: initiation.redirectUrl,
    };
  }

  async webhook(
    gatewayValue: string,
    headers: GatewayWebhookHeaders,
    payload: Record<string, unknown>,
  ) {
    const gateway = this.gateway(gatewayValue);
    const adapter = this.registry.get(gateway);
    const verified = await adapter.verifyWebhook(
      headers,
      payload,
    );

    if (!verified) {
      throw new UnauthorizedException(
        'Payment gateway callback verification failed.',
      );
    }

    const result = await adapter.parseWebhook(
      headers,
      payload,
    );

    return this.processResult(
      gateway,
      result,
      payload,
    );
  }

  async reconcile(
    auth: AuthContext,
    paymentId: string,
  ) {
    this.access.assertPlatform(auth);

    const payment = await this.prisma.payment.findUnique({
      where: {
        id: paymentId,
      },
    });

    if (!payment) {
      throw new NotFoundException('Payment was not found.');
    }

    const gateway = this.automationGateway(
      payment.paymentGateway,
    );
    const adapter = this.registry.get(gateway);
    const result = await adapter.query(payment);

    return this.processResult(
      gateway,
      result,
      result.raw,
      `reconcile:${payment.id}:${result.externalEventId}`,
    );
  }

  async retryEvent(
    auth: AuthContext,
    eventId: string,
  ) {
    this.access.assertPlatform(auth);

    const event =
      await this.prisma.paymentGatewayEvent.findUnique({
        where: {
          id: eventId,
        },
      });

    if (!event) {
      throw new NotFoundException(
        'Payment gateway event was not found.',
      );
    }

    if (event.status !== 'FAILED') {
      throw new ConflictException(
        'Only failed gateway events can be retried.',
      );
    }

    const payload = this.record(event.payload);
    const gateway = this.automationGateway(
      event.gateway,
    );
    const adapter = this.registry.get(gateway);
    const result = await adapter.parseWebhook(
      {
        eventId: event.externalEventId,
      },
      payload,
    );

    await this.prisma.paymentGatewayEvent.update({
      where: {
        id: event.id,
      },
      data: {
        status: 'RECEIVED',
        errorMessage: null,
        processedAt: null,
      },
    });

    return this.processExistingEvent(
      event.id,
      gateway,
      result,
    );
  }

  private async processResult(
    gateway: AutomatedPaymentGateway,
    result: GatewayResult,
    payload: Record<string, unknown>,
    externalEventId = result.externalEventId,
  ) {
    const systemAuth =
      await this.identity.platformAuth();
    const event = await this.payments.gatewayEvent(
      systemAuth,
      {
        gateway,
        externalEventId,
        eventType: result.eventType,
        payload,
      },
    );

    if (
      ['PROCESSED', 'IGNORED'].includes(event.status)
    ) {
      return {
        event,
        idempotent: true,
      };
    }

    return this.processExistingEvent(
      event.id,
      gateway,
      result,
    );
  }

  private async processExistingEvent(
    eventId: string,
    gateway: AutomatedPaymentGateway,
    result: GatewayResult,
  ) {
    const claim =
      await this.prisma.paymentGatewayEvent.updateMany({
        where: {
          id: eventId,
          status: {
            in: ['RECEIVED', 'FAILED'],
          },
        },
        data: {
          status: 'PROCESSING',
          errorMessage: null,
        },
      });

    if (claim.count === 0) {
      return {
        event:
          await this.prisma.paymentGatewayEvent.findUnique({
            where: {
              id: eventId,
            },
          }),
        idempotent: true,
      };
    }

    try {
      const payment = await this.findPayment(
        gateway,
        result,
      );

      if (!payment) {
        const ignored =
          await this.prisma.paymentGatewayEvent.update({
            where: {
              id: eventId,
            },
            data: {
              status: 'IGNORED',
              processedAt: new Date(),
              errorMessage:
                'No matching payment was found.',
            },
          });

        return {
          event: ignored,
          payment: null,
        };
      }

      await this.validateResult(payment, result);
      const systemAuth =
        await this.identity.platformAuth();

      if (result.status === 'SUCCEEDED') {
        if (
          ![
            'SUCCEEDED',
            'PARTIALLY_REFUNDED',
            'REFUNDED',
          ].includes(payment.status)
        ) {
          const invoiceId =
            await this.resolveInvoiceId(payment);
          await this.payments.confirm(
            systemAuth,
            payment.id,
            {
              gatewayTransactionId:
                result.gatewayTransactionId,
              gatewayReference:
                result.gatewayReference ??
                result.paymentReference,
              allocations: [
                {
                  invoiceId,
                  amount: payment.amount.toString(),
                },
              ],
            },
          );
        }
      } else if (
        result.status === 'FAILED' ||
        result.status === 'CANCELLED'
      ) {
        if (
          ['INITIATED', 'PENDING'].includes(
            payment.status,
          )
        ) {
          await this.payments.fail(
            systemAuth,
            payment.id,
            {
              reason:
                result.failureReason ??
                `Gateway reported ${result.status}.`,
            },
          );
        }
      }

      const processed =
        await this.prisma.paymentGatewayEvent.update({
          where: {
            id: eventId,
          },
          data: {
            paymentId: payment.id,
            status: 'PROCESSED',
            processedAt: new Date(),
            errorMessage: null,
          },
        });

      return {
        event: processed,
        payment:
          await this.prisma.payment.findUnique({
            where: {
              id: payment.id,
            },
            include: {
              allocations: true,
              refunds: true,
              commissionEntries: true,
            },
          }),
      };
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : 'Unknown gateway processing error.';

      await this.prisma.paymentGatewayEvent.update({
        where: {
          id: eventId,
        },
        data: {
          status: 'FAILED',
          errorMessage: message,
        },
      });

      throw error;
    }
  }

  private async findPayment(
    gateway: PaymentGateway,
    result: GatewayResult,
  ) {
    const conditions: Prisma.PaymentWhereInput[] = [
      {
        paymentNumber: result.paymentReference,
      },
      {
        gatewayReference: result.paymentReference,
      },
    ];

    if (result.gatewayReference) {
      conditions.push({
        gatewayReference: result.gatewayReference,
      });
    }

    if (result.gatewayTransactionId) {
      conditions.push({
        gatewayTransactionId:
          result.gatewayTransactionId,
      });
    }

    return this.prisma.payment.findFirst({
      where: {
        paymentGateway: gateway,
        OR: conditions,
      },
    });
  }

  private async validateResult(
    payment: {
      amount: Prisma.Decimal;
      currency: string;
    },
    result: GatewayResult,
  ): Promise<void> {
    if (
      result.currency &&
      result.currency.toUpperCase() !==
        payment.currency.toUpperCase()
    ) {
      throw new BadRequestException(
        'Gateway callback currency does not match the payment.',
      );
    }

    if (
      result.amount &&
      !new Prisma.Decimal(result.amount).eq(
        payment.amount,
      )
    ) {
      throw new BadRequestException(
        'Gateway callback amount does not match the payment.',
      );
    }
  }

  private async resolveInvoiceId(payment: {
    id: string;
    customerId: string;
    amount: Prisma.Decimal;
    currency: string;
    metadata: Prisma.JsonValue | null;
  }): Promise<string> {
    const metadata = this.record(payment.metadata);
    const automation = this.record(
      metadata.gatewayAutomation,
    );
    const configuredInvoiceId =
      typeof automation.invoiceId === 'string'
        ? automation.invoiceId
        : undefined;

    if (configuredInvoiceId) {
      const invoice =
        await this.prisma.invoice.findFirst({
          where: {
            id: configuredInvoiceId,
            customerId: payment.customerId,
            currency: payment.currency,
            status: {
              in: [...payableInvoiceStatuses],
            },
          },
        });

      if (
        invoice &&
        payment.amount.lte(invoice.outstandingAmount)
      ) {
        return invoice.id;
      }
    }

    const fallback =
      await this.prisma.invoice.findFirst({
        where: {
          customerId: payment.customerId,
          currency: payment.currency,
          status: {
            in: [...payableInvoiceStatuses],
          },
          outstandingAmount: {
            gte: payment.amount,
          },
        },
        orderBy: [
          {
            dueDate: 'asc',
          },
          {
            createdAt: 'asc',
          },
        ],
      });

    if (!fallback) {
      throw new BadRequestException(
        'No payable invoice can receive this payment.',
      );
    }

    return fallback.id;
  }

  private automationGateway(
    gateway: PaymentGateway,
  ): AutomatedPaymentGateway {
    return this.gateway(gateway);
  }

  private gateway(value: string): AutomatedPaymentGateway {
    const normalized = value.trim().toUpperCase();

    if (
      ![
        'OTHER',
        'BKASH',
        'NAGAD',
        'SSLCOMMERZ',
      ].includes(normalized)
    ) {
      throw new BadRequestException(
        'Unsupported payment gateway callback.',
      );
    }

    return normalized as AutomatedPaymentGateway;
  }

  private record(
    value: unknown,
  ): Record<string, unknown> {
    return value !== null &&
      typeof value === 'object' &&
      !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\services\recurring-billing.service.ts" `
        @'
import {
  ConflictException,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '../../generated/prisma/client';
import { PrismaService } from '../../database/prisma.service';
import { AuditService } from '../../identity/audit/audit.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../../billing/common/billing-access.service';
import { BillingDateService } from '../../billing/common/billing-date.service';
import { InvoicesService } from '../../billing/invoices/invoices.service';
import { AutomationIdentityService } from '../common/automation-identity.service';
import { AutomationRunKeyService } from '../common/automation-run-key.service';
import { GatewaySignatureService } from '../common/gateway-signature.service';
import type { RunBillingAutomationDto } from '../dto/run-billing-automation.dto';

@Injectable()
export class RecurringBillingService
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(
    RecurringBillingService.name,
  );
  private readonly enabled: boolean;
  private readonly intervalMs: number;
  private readonly defaultBatchSize: number;
  private readonly defaultDueInDays: number;
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly dates: BillingDateService,
    private readonly invoices: InvoicesService,
    private readonly identity: AutomationIdentityService,
    private readonly runKeys: AutomationRunKeyService,
    private readonly signatures: GatewaySignatureService,
    private readonly auditService: AuditService,
    configService: ConfigService,
  ) {
    this.enabled = this.boolean(
      configService.get(
        'PAYMENT_AUTOMATION_ENABLED',
        false,
      ),
    );
    this.intervalMs = Math.max(
      configService.get<number>(
        'PAYMENT_AUTOMATION_INTERVAL_MS',
        60000,
      ),
      60000,
    );
    this.defaultBatchSize = configService.get<number>(
      'PAYMENT_AUTOMATION_BATCH_SIZE',
      50,
    );
    this.defaultDueInDays = configService.get<number>(
      'PAYMENT_AUTOMATION_DUE_IN_DAYS',
      7,
    );
  }

  onModuleInit(): void {
    if (!this.enabled) {
      return;
    }

    this.timer = setInterval(() => {
      void this.runScheduled();
    }, this.intervalMs);

    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  async run(
    auth: AuthContext,
    dto: RunBillingAutomationDto,
  ) {
    this.access.assertPlatform(auth);

    return this.execute(auth, {
      asOf: dto.asOf
        ? new Date(dto.asOf)
        : new Date(),
      dueInDays: dto.dueInDays,
      batchSize: dto.batchSize,
      dryRun: dto.dryRun,
      source: 'MANUAL',
    });
  }

  async status() {
    const recentRuns =
      await this.prisma.paymentGatewayEvent.findMany({
        where: {
          gateway: 'OTHER',
          eventType: 'BILLING_AUTOMATION_RUN',
        },
        orderBy: {
          receivedAt: 'desc',
        },
        take: 10,
      });

    const dueSubscriptions =
      await this.prisma.subscription.count({
        where: {
          autoRenew: true,
          status: {
            in: [
              'TRIALING',
              'ACTIVE',
              'PAST_DUE',
            ],
          },
          nextBillingAt: {
            lte: new Date(),
          },
        },
      });

    return {
      enabled: this.enabled,
      intervalMs: this.intervalMs,
      defaultBatchSize: this.defaultBatchSize,
      defaultDueInDays: this.defaultDueInDays,
      dueSubscriptions,
      recentRuns,
    };
  }

  private async runScheduled(): Promise<void> {
    try {
      const auth =
        await this.identity.platformAuth();

      await this.execute(auth, {
        asOf: new Date(),
        dueInDays: this.defaultDueInDays,
        batchSize: this.defaultBatchSize,
        dryRun: false,
        source: 'SCHEDULED',
      });
    } catch (error) {
      this.logger.error(
        error instanceof Error
          ? error.message
          : 'Unknown scheduled billing error.',
      );
    }
  }

  private async execute(
    auth: AuthContext,
    input: {
      asOf: Date;
      dueInDays: number;
      batchSize: number;
      dryRun: boolean;
      source: 'MANUAL' | 'SCHEDULED';
    },
  ) {
    const dueSubscriptions =
      await this.prisma.subscription.findMany({
        where: {
          autoRenew: true,
          status: {
            in: [
              'TRIALING',
              'ACTIVE',
              'PAST_DUE',
            ],
          },
          nextBillingAt: {
            lte: input.asOf,
          },
        },
        orderBy: {
          nextBillingAt: 'asc',
        },
        take: input.batchSize,
        include: {
          servicePlan: true,
        },
      });

    if (input.dryRun) {
      return {
        dryRun: true,
        asOf: input.asOf,
        dueSubscriptionIds:
          dueSubscriptions.map(
            (subscription) => subscription.id,
          ),
      };
    }

    const runKey = this.runKeys.key(
      input.asOf,
      this.intervalMs,
    );
    const runPayload: Prisma.InputJsonValue = {
      source: input.source,
      asOf: input.asOf.toISOString(),
      dueInDays: input.dueInDays,
      batchSize: input.batchSize,
    };

    let runEvent;

    try {
      runEvent =
        await this.prisma.paymentGatewayEvent.create({
          data: {
            gateway: 'OTHER',
            externalEventId: runKey,
            eventType: 'BILLING_AUTOMATION_RUN',
            payload: runPayload,
            payloadHash:
              this.signatures.hash(runPayload),
            status: 'PROCESSING',
          },
        });
    } catch (error) {
      if (
        error instanceof
          Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        return {
          idempotent: true,
          runKey,
          message:
            'This billing automation interval has already been claimed.',
        };
      }

      throw error;
    }

    const results: Array<Record<string, unknown>> = [];

    try {
      for (const subscription of dueSubscriptions) {
        try {
          results.push(
            await this.processSubscription(
              auth,
              subscription.id,
              input.dueInDays,
            ),
          );
        } catch (error) {
          results.push({
            subscriptionId: subscription.id,
            status: 'FAILED',
            error:
              error instanceof Error
                ? error.message
                : 'Unknown subscription billing error.',
          });
        }
      }

      const overdue =
        await this.markOverdueInvoices(input.asOf);
      const summary = {
        runKey,
        processed: results.length,
        succeeded: results.filter(
          (item) => item.status === 'SUCCEEDED',
        ).length,
        failed: results.filter(
          (item) => item.status === 'FAILED',
        ).length,
        overdueInvoices: overdue.invoiceCount,
        pastDueSubscriptions:
          overdue.subscriptionCount,
        results,
      };

      await this.prisma.paymentGatewayEvent.update({
        where: {
          id: runEvent.id,
        },
        data: {
          status: 'PROCESSED',
          processedAt: new Date(),
          payload: JSON.parse(
            JSON.stringify({
              ...this.record(runPayload),
              summary,
            }),
          ) as Prisma.InputJsonValue,
        },
      });

      await this.auditService.record({
        actorUserId: auth.userId,
        actorOrganizationId:
          this.access.actorOrganizationId(auth),
        action: 'billing-automation.completed',
        resourceType: 'BillingAutomationRun',
        resourceId: runEvent.id,
        scopeType: 'PLATFORM',
        afterData: summary,
      });

      return summary;
    } catch (error) {
      await this.prisma.paymentGatewayEvent.update({
        where: {
          id: runEvent.id,
        },
        data: {
          status: 'FAILED',
          errorMessage:
            error instanceof Error
              ? error.message
              : 'Unknown billing automation error.',
        },
      });

      throw error;
    }
  }

  private async processSubscription(
    auth: AuthContext,
    subscriptionId: string,
    dueInDays: number,
  ): Promise<Record<string, unknown>> {
    const subscription =
      await this.prisma.subscription.findUnique({
        where: {
          id: subscriptionId,
        },
        include: {
          servicePlan: true,
        },
      });

    if (!subscription) {
      throw new ConflictException(
        'Subscription disappeared during billing.',
      );
    }

    const periodStart =
      subscription.currentPeriodStart ??
      subscription.nextBillingAt ??
      new Date();
    const periodEnd =
      subscription.currentPeriodEnd ??
      this.dates.addInterval(
        periodStart,
        subscription.servicePlan.billingIntervalUnit,
        subscription.servicePlan.billingIntervalCount,
      );

    let invoice =
      await this.prisma.invoice.findFirst({
        where: {
          subscriptionId,
          billingPeriodStart: periodStart,
          billingPeriodEnd: periodEnd,
          status: {
            not: 'VOID',
          },
        },
      });

    if (!invoice) {
      invoice =
        await this.invoices.createFromSubscription(
          auth,
          subscriptionId,
          dueInDays,
        );
    }

    if (invoice.status === 'DRAFT') {
      invoice = await this.invoices.issue(
        auth,
        invoice.id,
        {},
      );
    }

    const nextPeriodStart = periodEnd;
    const nextPeriodEnd = this.dates.addInterval(
      nextPeriodStart,
      subscription.servicePlan.billingIntervalUnit,
      subscription.servicePlan.billingIntervalCount,
    );

    const updatedSubscription =
      await this.prisma.subscription.update({
        where: {
          id: subscription.id,
        },
        data: {
          status: 'ACTIVE',
          currentPeriodStart: nextPeriodStart,
          currentPeriodEnd: nextPeriodEnd,
          nextBillingAt: nextPeriodEnd,
          trialEndsAt: null,
        },
      });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId:
        this.access.actorOrganizationId(auth),
      action: 'subscription.period-advanced',
      resourceType: 'Subscription',
      resourceId: subscription.id,
      scopeType: 'CUSTOMER',
      scopeId: subscription.customerId,
      beforeData: subscription,
      afterData: updatedSubscription,
      metadata: {
        invoiceId: invoice.id,
      },
    });

    return {
      subscriptionId: subscription.id,
      invoiceId: invoice.id,
      invoiceNumber: invoice.invoiceNumber,
      status: 'SUCCEEDED',
      nextBillingAt:
        updatedSubscription.nextBillingAt,
    };
  }

  private async markOverdueInvoices(
    asOf: Date,
  ): Promise<{
    invoiceCount: number;
    subscriptionCount: number;
  }> {
    const dateBoundary = new Date(
      Date.UTC(
        asOf.getUTCFullYear(),
        asOf.getUTCMonth(),
        asOf.getUTCDate(),
      ),
    );
    const overdueInvoices =
      await this.prisma.invoice.findMany({
        where: {
          dueDate: {
            lt: dateBoundary,
          },
          status: {
            in: ['ISSUED', 'PARTIALLY_PAID'],
          },
        },
        select: {
          id: true,
          subscriptionId: true,
        },
      });

    if (overdueInvoices.length === 0) {
      return {
        invoiceCount: 0,
        subscriptionCount: 0,
      };
    }

    await this.prisma.invoice.updateMany({
      where: {
        id: {
          in: overdueInvoices.map(
            (invoice) => invoice.id,
          ),
        },
      },
      data: {
        status: 'OVERDUE',
      },
    });

    const subscriptionIds = Array.from(
      new Set(
        overdueInvoices
          .map((invoice) => invoice.subscriptionId)
          .filter(
            (value): value is string =>
              Boolean(value),
          ),
      ),
    );

    if (subscriptionIds.length > 0) {
      await this.prisma.subscription.updateMany({
        where: {
          id: {
            in: subscriptionIds,
          },
          status: 'ACTIVE',
        },
        data: {
          status: 'PAST_DUE',
        },
      });
    }

    return {
      invoiceCount: overdueInvoices.length,
      subscriptionCount: subscriptionIds.length,
    };
  }

  private boolean(value: unknown): boolean {
    return value === true ||
      String(value).toLowerCase() === 'true';
  }

  private record(
    value: unknown,
  ): Record<string, unknown> {
    return value !== null &&
      typeof value === 'object' &&
      !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\services\payment-reconciliation.service.ts" `
        @'
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import type { AuthContext } from '../../identity/common/auth-context';
import { BillingAccessService } from '../../billing/common/billing-access.service';
import type { ReconcilePaymentsDto } from '../dto/reconcile-payments.dto';
import { GatewayPaymentService } from './gateway-payment.service';

@Injectable()
export class PaymentReconciliationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: BillingAccessService,
    private readonly gateways: GatewayPaymentService,
  ) {}

  async batch(
    auth: AuthContext,
    dto: ReconcilePaymentsDto,
  ) {
    this.access.assertPlatform(auth);

    const cutoff = new Date(
      Date.now() -
        dto.minimumAgeMinutes * 60 * 1000,
    );
    const payments = await this.prisma.payment.findMany({
      where: {
        paymentGateway: {
          in: [
            'OTHER',
            'BKASH',
            'NAGAD',
            'SSLCOMMERZ',
          ],
        },
        status: {
          in: ['INITIATED', 'PENDING'],
        },
        initiatedAt: {
          lte: cutoff,
        },
      },
      orderBy: {
        initiatedAt: 'asc',
      },
      take: dto.limit,
      select: {
        id: true,
      },
    });

    const results: Array<Record<string, unknown>> = [];

    for (const payment of payments) {
      try {
        results.push({
          paymentId: payment.id,
          status: 'SUCCEEDED',
          result: await this.gateways.reconcile(
            auth,
            payment.id,
          ),
        });
      } catch (error) {
        results.push({
          paymentId: payment.id,
          status: 'FAILED',
          error:
            error instanceof Error
              ? error.message
              : 'Unknown reconciliation error.',
        });
      }
    }

    return {
      attempted: results.length,
      succeeded: results.filter(
        (result) => result.status === 'SUCCEEDED',
      ).length,
      failed: results.filter(
        (result) => result.status === 'FAILED',
      ).length,
      results,
    };
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\controllers\payment-gateway.controller.ts" `
        @'
import {
  Body,
  Controller,
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
import { InitializeGatewayPaymentDto } from '../dto/initialize-gateway-payment.dto';
import { ReconcilePaymentsDto } from '../dto/reconcile-payments.dto';
import { GatewayPaymentService } from '../services/gateway-payment.service';
import { PaymentReconciliationService } from '../services/payment-reconciliation.service';

@ApiTags('Payment Gateway Operations')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller()
export class PaymentGatewayController {
  constructor(
    private readonly gateways: GatewayPaymentService,
    private readonly reconciliation: PaymentReconciliationService,
  ) {}

  @Post('payments/:paymentId/gateway/initialize')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary:
      'Initialize an existing pending payment with its configured gateway',
  })
  initialize(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', ParseUUIDPipe)
    paymentId: string,
    @Body() dto: InitializeGatewayPaymentDto,
  ) {
    return this.gateways.initialize(
      auth,
      paymentId,
      dto,
    );
  }

  @Post('payments/:paymentId/gateway/reconcile')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary:
      'Reconcile one pending gateway payment',
  })
  reconcile(
    @CurrentAuth() auth: AuthContext,
    @Param('paymentId', ParseUUIDPipe)
    paymentId: string,
  ) {
    return this.gateways.reconcile(
      auth,
      paymentId,
    );
  }

  @Post('payment-gateway-events/:eventId/retry')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary:
      'Retry one failed, previously verified gateway event',
  })
  retry(
    @CurrentAuth() auth: AuthContext,
    @Param('eventId', ParseUUIDPipe)
    eventId: string,
  ) {
    return this.gateways.retryEvent(
      auth,
      eventId,
    );
  }

  @Post('payment-gateways/reconcile')
  @RequirePermissions('payment.view')
  @ApiOperation({
    summary:
      'Reconcile a bounded batch of pending gateway payments',
  })
  reconcileBatch(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: ReconcilePaymentsDto,
  ) {
    return this.reconciliation.batch(auth, dto);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\controllers\payment-gateway-webhook.controller.ts" `
        @'
import {
  Body,
  Controller,
  Headers,
  Param,
  Post,
} from '@nestjs/common';
import {
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { GatewayPaymentService } from '../services/gateway-payment.service';

@ApiTags('Payment Gateway Webhooks')
@Controller('payment-gateways/webhooks')
export class PaymentGatewayWebhookController {
  constructor(
    private readonly gateways: GatewayPaymentService,
  ) {}

  @Post(':gateway')
  @ApiOperation({
    summary:
      'Receive a verified and idempotent payment gateway callback',
  })
  webhook(
    @Param('gateway') gateway: string,
    @Headers('x-solid-signature')
    signature: string | undefined,
    @Headers('x-solid-event-id')
    eventId: string | undefined,
    @Headers('authorization')
    authorization: string | undefined,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.gateways.webhook(
      gateway,
      {
        signature,
        eventId,
        authorization,
      },
      payload,
    );
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\controllers\billing-automation.controller.ts" `
        @'
import {
  Body,
  Controller,
  Get,
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
import { RunBillingAutomationDto } from '../dto/run-billing-automation.dto';
import { RecurringBillingService } from '../services/recurring-billing.service';

@ApiTags('Billing Automation')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('billing-automation')
export class BillingAutomationController {
  constructor(
    private readonly recurringBilling: RecurringBillingService,
  ) {}

  @Get('status')
  @RequirePermissions('subscription.view')
  @ApiOperation({
    summary:
      'Inspect recurring billing worker configuration and recent runs',
  })
  status() {
    return this.recurringBilling.status();
  }

  @Post('run')
  @RequirePermissions('subscription.create')
  @ApiOperation({
    summary:
      'Run one idempotent recurring invoice and overdue cycle',
  })
  run(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: RunBillingAutomationDto,
  ) {
    return this.recurringBilling.run(auth, dto);
  }
}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\payment-gateway-automation.module.ts" `
        @'
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { BillingApiModule } from '../billing/billing-api.module';
import { AccessControlModule } from '../identity/access-control/access-control.module';
import { AuditModule } from '../identity/audit/audit.module';
import { BkashGatewayAdapter } from './adapters/bkash-gateway.adapter';
import { GatewayRegistryService } from './adapters/gateway-registry.service';
import { NagadGatewayAdapter } from './adapters/nagad-gateway.adapter';
import { SandboxGatewayAdapter } from './adapters/sandbox-gateway.adapter';
import { SignedProxyClientService } from './adapters/signed-proxy-client.service';
import { SslCommerzGatewayAdapter } from './adapters/sslcommerz-gateway.adapter';
import { AutomationIdentityService } from './common/automation-identity.service';
import { AutomationRunKeyService } from './common/automation-run-key.service';
import { GatewayHttpService } from './common/gateway-http.service';
import { GatewaySignatureService } from './common/gateway-signature.service';
import { BillingAutomationController } from './controllers/billing-automation.controller';
import { PaymentGatewayWebhookController } from './controllers/payment-gateway-webhook.controller';
import { PaymentGatewayController } from './controllers/payment-gateway.controller';
import { GatewayPaymentService } from './services/gateway-payment.service';
import { PaymentReconciliationService } from './services/payment-reconciliation.service';
import { RecurringBillingService } from './services/recurring-billing.service';

@Module({
  imports: [
    ConfigModule,
    BillingApiModule,
    AccessControlModule,
    AuditModule,
  ],
  controllers: [
    PaymentGatewayController,
    PaymentGatewayWebhookController,
    BillingAutomationController,
  ],
  providers: [
    GatewaySignatureService,
    GatewayHttpService,
    AutomationRunKeyService,
    AutomationIdentityService,
    SignedProxyClientService,
    SandboxGatewayAdapter,
    BkashGatewayAdapter,
    NagadGatewayAdapter,
    SslCommerzGatewayAdapter,
    GatewayRegistryService,
    GatewayPaymentService,
    PaymentReconciliationService,
    RecurringBillingService,
  ],
})
export class PaymentGatewayAutomationModule {}
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\common\gateway-signature.service.spec.ts" `
        @'
import { GatewaySignatureService } from './gateway-signature.service';

describe('GatewaySignatureService', () => {
  const service = new GatewaySignatureService();

  it('creates stable signatures regardless of object key order', () => {
    const secret =
      '12345678901234567890123456789012';
    const left = {
      status: 'SUCCEEDED',
      nested: {
        amount: '500.00',
        currency: 'BDT',
      },
    };
    const right = {
      nested: {
        currency: 'BDT',
        amount: '500.00',
      },
      status: 'SUCCEEDED',
    };

    const signature = service.sign(secret, left);

    expect(service.sign(secret, right)).toBe(
      signature,
    );
    expect(
      service.verify(secret, right, signature),
    ).toBe(true);
    expect(
      service.verify(
        secret,
        right,
        `${signature.slice(0, -1)}0`,
      ),
    ).toBe(false);
  });
});
'@

    Write-Utf8File `
        "services\backend-api\src\payment-automation\common\automation-run-key.service.spec.ts" `
        @'
import { AutomationRunKeyService } from './automation-run-key.service';

describe('AutomationRunKeyService', () => {
  const service = new AutomationRunKeyService();

  it('returns the same durable key within one interval', () => {
    const first = new Date('2026-07-14T12:00:10.000Z');
    const second = new Date('2026-07-14T12:00:50.000Z');

    expect(service.key(first, 60000)).toBe(
      service.key(second, 60000),
    );
  });

  it('returns a different key for the next interval', () => {
    const first = new Date('2026-07-14T12:00:10.000Z');
    const second = new Date('2026-07-14T12:01:10.000Z');

    expect(service.key(first, 60000)).not.toBe(
      service.key(second, 60000),
    );
  });
});
'@

    Write-Utf8File `
        "services\backend-api\test\payment-gateway-automation.e2e-spec.ts" `
        @'
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { TestingModule } from '@nestjs/testing';
import {
  randomInt,
  randomUUID,
} from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApplication } from '../src/bootstrap/app.setup';
import { PrismaService } from '../src/database/prisma.service';
import { PasswordService } from '../src/identity/common/password.service';
import { GatewaySignatureService } from '../src/payment-automation/common/gateway-signature.service';

describe('Payment gateway and recurring billing automation (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let signatures: GatewaySignatureService;
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

  const numericSuffix = randomInt(
    10_000_000,
    100_000_000,
  ).toString();
  const codeSuffix = randomUUID()
    .replace(/-/g, '')
    .slice(0, 10)
    .toUpperCase();
  const mobileNumber = `+88015${numericSuffix}`;
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
    signatures = app.get(GatewaySignatureService);
    const passwordService = app.get(PasswordService);
    const passwordHash =
      await passwordService.hash(password);

    const platformOrganization =
      await prisma.organization.findUniqueOrThrow({
        where: {
          code: 'ORG-PLATFORM',
        },
      });
    const superAdminRole =
      await prisma.role.findUniqueOrThrow({
        where: {
          code: 'PLATFORM_SUPER_ADMIN',
        },
      });
    const user = await prisma.user.create({
      data: {
        userCode: `USR-PAY-${codeSuffix}`,
        fullName:
          'Payment Automation E2E Administrator',
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

    const assignment =
      await prisma.roleAssignment.create({
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

    const loginResponse =
      await request(app.getHttpServer())
        .post('/api/v1/auth/login')
        .send({
          mobileNumber,
          password,
          platform: 'WEB',
          deviceName:
            'Payment Automation E2E',
          appVersion: 'test',
        })
        .expect(200);

    accessToken =
      loginResponse.body.accessToken as string;
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

  it('generates a recurring invoice and confirms it through an idempotent signed callback', async () => {
    const dealerResponse =
      await request(app.getHttpServer())
        .post('/api/v1/dealers')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          name:
            `Gateway E2E Dealer ${codeSuffix}`,
          contactMobile: `017${numericSuffix}`,
        })
        .expect(201);

    dealerId = dealerResponse.body.id as string;

    const customerResponse =
      await request(app.getHttpServer())
        .post('/api/v1/customers/individual')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          managingDealerId: dealerId,
          fullName:
            `Gateway E2E Customer ${codeSuffix}`,
          primaryMobile: `016${numericSuffix}`,
        })
        .expect(201);

    customerId = customerResponse.body.id as string;

    const vehicleResponse =
      await request(app.getHttpServer())
        .post('/api/v1/vehicles')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          customerId,
          vehicleType: 'CAR',
          registrationNumber:
            `PAY-E2E-${codeSuffix}`,
          manufacturer: 'Solid Tracker Test',
          modelName: 'Automation Car',
          manufacturingYear: 2026,
        })
        .expect(201);

    vehicleId = vehicleResponse.body.id as string;

    const effectiveFrom = new Date(
      Date.now() - 24 * 60 * 60 * 1000,
    ).toISOString();

    const planResponse =
      await request(app.getHttpServer())
        .post('/api/v1/service-plans')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          planFamilyCode:
            `AUTO_${codeSuffix}`,
          name:
            `Automated Monthly ${codeSuffix}`,
          billingIntervalUnit: 'MONTH',
          billingIntervalCount: 1,
          basePrice: '500.00',
          currency: 'BDT',
          taxBehavior: 'NONE',
          trialDays: 0,
          effectiveFrom,
        })
        .expect(201);

    planId = planResponse.body.id as string;

    await request(app.getHttpServer())
      .post(
        `/api/v1/service-plans/${planId}/activate`,
      )
      .set(
        'Authorization',
        `Bearer ${accessToken}`,
      )
      .send({})
      .expect(201);

    const subscriptionResponse =
      await request(app.getHttpServer())
        .post('/api/v1/subscriptions')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          customerId,
          vehicleId,
          servicePlanId: planId,
          autoRenew: true,
        })
        .expect(201);

    subscriptionId =
      subscriptionResponse.body.id as string;

    await request(app.getHttpServer())
      .post(
        `/api/v1/subscriptions/${subscriptionId}/activate`,
      )
      .set(
        'Authorization',
        `Bearer ${accessToken}`,
      )
      .send({})
      .expect(201);

    const periodStart = new Date(
      Date.now() - 40 * 24 * 60 * 60 * 1000,
    );
    const periodEnd = new Date(
      Date.now() - 10 * 24 * 60 * 60 * 1000,
    );

    await prisma.subscription.update({
      where: {
        id: subscriptionId,
      },
      data: {
        status: 'ACTIVE',
        currentPeriodStart: periodStart,
        currentPeriodEnd: periodEnd,
        nextBillingAt: periodEnd,
      },
    });

    const asOf = new Date(
      Date.now() +
        randomInt(2, 120) * 60 * 1000,
    );

    const automationResponse =
      await request(app.getHttpServer())
        .post('/api/v1/billing-automation/run')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          asOf: asOf.toISOString(),
          dueInDays: 7,
          batchSize: 10,
          dryRun: false,
        })
        .expect(201);

    expect(automationResponse.body.succeeded).toBe(1);

    const invoice =
      await prisma.invoice.findFirstOrThrow({
        where: {
          subscriptionId,
          status: 'ISSUED',
        },
        orderBy: {
          createdAt: 'desc',
        },
      });

    invoiceId = invoice.id;

    const paymentResponse =
      await request(app.getHttpServer())
        .post('/api/v1/payments')
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          customerId,
          amount: invoice.totalAmount.toString(),
          currency: invoice.currency,
          paymentMethod: 'CARD',
          paymentGateway: 'OTHER',
        })
        .expect(201);

    paymentId = paymentResponse.body.id as string;

    const initializationResponse =
      await request(app.getHttpServer())
        .post(
          `/api/v1/payments/${paymentId}/gateway/initialize`,
        )
        .set(
          'Authorization',
          `Bearer ${accessToken}`,
        )
        .send({
          invoiceId,
          successUrl:
            'http://localhost/payment/success',
          cancelUrl:
            'http://localhost/payment/cancel',
          failureUrl:
            'http://localhost/payment/failure',
        })
        .expect(201);

    const gatewayReference =
      initializationResponse.body
        .gatewayReference as string;
    const eventId =
      `E2E-${codeSuffix}-${randomUUID()}`;
    const payload = {
      eventId,
      paymentReference: gatewayReference,
      transactionId:
        `SANDBOX-TXN-${codeSuffix}`,
      status: 'SUCCEEDED',
      amount: invoice.totalAmount.toString(),
      currency: invoice.currency,
    };
    const secret =
      process.env.PAYMENT_SANDBOX_WEBHOOK_SECRET;

    expect(secret).toBeDefined();

    const signature = signatures.sign(
      secret as string,
      payload,
    );

    const callbackResponse =
      await request(app.getHttpServer())
        .post(
          '/api/v1/payment-gateways/webhooks/OTHER',
        )
        .set('x-solid-signature', signature)
        .set('x-solid-event-id', eventId)
        .send(payload)
        .expect(201);

    expect(
      callbackResponse.body.payment.status,
    ).toBe('SUCCEEDED');

    const repeatedCallback =
      await request(app.getHttpServer())
        .post(
          '/api/v1/payment-gateways/webhooks/OTHER',
        )
        .set('x-solid-signature', signature)
        .set('x-solid-event-id', eventId)
        .send(payload)
        .expect(201);

    expect(repeatedCallback.body.idempotent).toBe(
      true,
    );

    const storedPayment =
      await prisma.payment.findUniqueOrThrow({
        where: {
          id: paymentId,
        },
        include: {
          allocations: true,
        },
      });
    const storedInvoice =
      await prisma.invoice.findUniqueOrThrow({
        where: {
          id: invoiceId,
        },
      });
    const storedEvent =
      await prisma.paymentGatewayEvent.findUniqueOrThrow({
        where: {
          gateway_externalEventId: {
            gateway: 'OTHER',
            externalEventId: eventId,
          },
        },
      });

    expect(storedPayment.status).toBe('SUCCEEDED');
    expect(storedPayment.allocations).toHaveLength(1);
    expect(storedInvoice.status).toBe('PAID');
    expect(storedEvent.status).toBe('PROCESSED');
  });
});
'@


    Write-Step 5 9 "Exporting billing services and registering the automation module"

    $billingModulePath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\billing\billing-api.module.ts"

    $billingModuleContent = [System.IO.File]::ReadAllText(
        $billingModulePath
    ).Replace("`r`n", "`n")

    if (-not $billingModuleContent.Contains("exports: [")) {
        $exportsBlock = @'
  exports: [
    BillingAccessService,
    BillingCodeService,
    BillingDateService,
    BillingMoneyService,
    CommissionEngineService,
    InvoicesService,
    PaymentsService,
  ],
'@

        $closingMarker = "`n})`nexport class BillingApiModule {}"
        $closingIndex = $billingModuleContent.LastIndexOf(
            $closingMarker,
            [System.StringComparison]::Ordinal
        )

        if ($closingIndex -lt 0) {
            throw "Could not locate the BillingApiModule closing marker."
        }

        $billingModuleContent = (
            $billingModuleContent.Substring(0, $closingIndex) +
            "`n" +
            $exportsBlock +
            $billingModuleContent.Substring($closingIndex)
        )

        [System.IO.File]::WriteAllText(
            $billingModulePath,
            $billingModuleContent,
            $script:Utf8NoBom
        )

        Write-Host (
            "[UPDATED] services\backend-api\src\billing\billing-api.module.ts"
        ) -ForegroundColor Green
    }

    $appModulePath = Join-Path `
        $script:RootPath `
        "services\backend-api\src\app.module.ts"

    $appModuleContent = [System.IO.File]::ReadAllText(
        $appModulePath
    )

    $automationImport =
        "import { PaymentGatewayAutomationModule } from './payment-automation/payment-gateway-automation.module';"

    if (-not $appModuleContent.Contains($automationImport)) {
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
            $automationImport +
            $appModuleContent.Substring(
                $moduleMatch.Index + $moduleMatch.Length
            )
        )
    }

    if (
        -not $appModuleContent.Contains(
            "PaymentGatewayAutomationModule,"
        )
    ) {
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
            "PaymentGatewayAutomationModule," +
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

    Write-Host (
        "[UPDATED] services\backend-api\src\app.module.ts"
    ) -ForegroundColor Green

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

    Write-Step 7 9 "Verifying billing and gateway invariants"

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
    FROM pg_index AS index_metadata
    INNER JOIN pg_class AS table_record
      ON table_record.oid = index_metadata.indrelid
    INNER JOIN pg_namespace AS namespace_record
      ON namespace_record.oid = table_record.relnamespace
    WHERE namespace_record.nspname = 'public'
      AND table_record.relname = 'payment_gateway_events'
      AND index_metadata.indisunique
      AND (
        SELECT string_agg(
          attribute_record.attname,
          ',' ORDER BY key_record.ordinality
        )
        FROM unnest(index_metadata.indkey)
          WITH ORDINALITY AS key_record(attnum, ordinality)
        INNER JOIN pg_attribute AS attribute_record
          ON attribute_record.attrelid = table_record.oid
         AND attribute_record.attnum = key_record.attnum
      ) = 'gateway,externalEventId'
  ) AS gateway_event_idempotency_index_count,
  (
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
        'subscriptions_one_current_per_vehicle',
        'dealer_payout_accounts_one_default_per_dealer'
      )
  ) AS billing_invariant_index_count;
'@

    $verificationOutput = $databaseVerification |
        docker compose `
            --env-file .env `
            exec -T postgres `
            sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At'

    if ($LASTEXITCODE -ne 0) {
        throw "Gateway database verification failed."
    }

    $verificationLine = ($verificationOutput | Out-String).Trim()
    $parts = $verificationLine.Split("|")

    if ($parts.Count -ne 5) {
        throw "Unexpected verification result: $verificationLine"
    }

    $publicTableCount = [int]$parts[0]
    $appliedMigrationCount = [int]$parts[1]
    $permissionCount = [int]$parts[2]
    $gatewayIndexCount = [int]$parts[3]
    $billingIndexCount = [int]$parts[4]

    if ($publicTableCount -lt 50) {
        throw "Expected at least 50 public tables."
    }

    if ($appliedMigrationCount -ne 5) {
        throw "Expected exactly 5 applied migrations."
    }

    if ($permissionCount -ne 7) {
        throw "Expected 7 active billing permissions."
    }

    if ($gatewayIndexCount -lt 1) {
        throw "Gateway event idempotency index was not found."
    }

    if ($billingIndexCount -ne 2) {
        throw "Expected 2 billing invariant indexes."
    }

    Write-Host "Public tables:          $publicTableCount" -ForegroundColor Green
    Write-Host "Applied migrations:     $appliedMigrationCount" -ForegroundColor Green
    Write-Host "Billing permissions:    $permissionCount" -ForegroundColor Green
    Write-Host "Gateway idempotency:    verified" -ForegroundColor Green
    Write-Host "Billing invariants:     $billingIndexCount indexes" -ForegroundColor Green

    Write-Step 8 9 "Writing payment automation architecture documentation"

    Write-Utf8File `
        "docs/architecture/payment-gateway-automation.md" `
        @'
# Payment Gateway and Recurring Billing Automation

## Scope

This stage adds a provider-neutral payment gateway boundary and recurring billing operations without introducing a Prisma migration.

It implements:

- initialization of pending payments against a selected gateway;
- canonical payload hashing and HMAC verification;
- idempotent callback storage using `payment_gateway_events`;
- amount, currency, payment, customer, and invoice validation;
- automatic payment confirmation and invoice allocation;
- automatic dealer commission through the existing commission engine;
- callback retry and payment reconciliation operations;
- recurring invoice generation and period advancement;
- overdue invoice and past-due subscription transitions;
- a durable interval claim based on the gateway-event unique key;
- bounded manual and scheduled processing;
- sandbox callback E2E coverage.

## Gateway adapters

### Sandbox

The `OTHER` gateway is used as a deterministic signed sandbox adapter for local development and E2E tests.

### SSLCOMMERZ

The SSLCOMMERZ adapter creates a hosted checkout session and validates callback data through the provider validation boundary before changing payment state.

### bKash and Nagad

The bKash and Nagad adapters use a signed merchant-integration proxy contract. This keeps provider credentials and provider-specific certification logic outside the application process while preserving Solid Tracker's common initiation, callback, idempotency, reconciliation, and accounting contract.

Live activation requires merchant credentials, approved callback URLs, and provider acceptance testing.

## Recurring billing

The worker selects auto-renewing subscriptions whose `nextBillingAt` is due. It creates and issues one invoice for the current billing period, advances the period, and records an audit event.

A run claims a unique minute bucket in `payment_gateway_events`. Concurrent instances attempting the same interval receive the existing unique-key conflict and skip duplicate work.

The worker is disabled by default for local development:

```text
PAYMENT_AUTOMATION_ENABLED=false
```

Production deployment should enable it on a controlled worker instance or invoke the authenticated manual-run endpoint from the platform scheduler.

## Callback flow

```text
gateway callback
→ provider verification
→ gateway event upsert
→ atomic processing claim
→ payment lookup
→ amount and currency validation
→ payment confirmation or failure
→ invoice allocation
→ commission calculation
→ event completion
```

Repeated callbacks return the previously processed event without repeating the financial transaction.

## Security

Secrets remain in the runtime environment. `.env.example` contains placeholders only. The API never returns gateway secrets.

The callback endpoint has no user bearer token. It relies on adapter-specific verification and durable event idempotency.
'@

    Write-Step 9 9 "Committing the payment gateway automation stage"

    git add -- `
        ".env.example" `
        "docs/architecture/payment-gateway-automation.md" `
        "scripts/solid-tracker-payment-gateway-automation.ps1" `
        "services/backend-api/src/app.module.ts" `
        "services/backend-api/src/config/environment.validation.ts" `
        "services/backend-api/src/billing/billing-api.module.ts" `
        "services/backend-api/src/payment-automation" `
        "services/backend-api/test/payment-gateway-automation.e2e-spec.ts"

    git commit `
        -m "feat(payments): establish gateway adapters and billing automation"

    if ($LASTEXITCODE -ne 0) {
        throw "Payment gateway automation commit failed."
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Payment Gateway and Billing Automation Ready" -ForegroundColor Cyan
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
        "Outbound notification providers, background delivery workers, " +
        "observability, rate controls, and production deployment hardening"
    ) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "PAYMENT GATEWAY AUTOMATION FAILED" -ForegroundColor Red
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
