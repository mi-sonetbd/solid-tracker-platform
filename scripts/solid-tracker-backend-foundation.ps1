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

function New-Text {
    param(
        [AllowEmptyCollection()]
        [object[]]$Lines
    )

    $stringLines = @($Lines | ForEach-Object { [string]$_ })
    return (($stringLines -join "`n") + "`n")
}

function Write-ManagedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $fullPath = Join-Path $script:RootPath $RelativePath
    $parentPath = Split-Path -Parent $fullPath
    $normalizedExpected = $Content.Replace("`r`n", "`n")

    if (
        -not [string]::IsNullOrWhiteSpace($parentPath) -and
        -not (Test-Path -LiteralPath $parentPath)
    ) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    if (Test-Path -LiteralPath $fullPath) {
        $current = [System.IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")

        if ($current -eq $normalizedExpected) {
            Write-Host "[PRESERVED] $RelativePath" -ForegroundColor DarkYellow
            return
        }

        throw "Refusing to overwrite an existing modified file: $RelativePath"
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $normalizedExpected,
        $script:Utf8NoBom
    )

    Write-Host "[CREATED]   $RelativePath" -ForegroundColor Green
}

function Add-EnvironmentLineIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$VariableName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "Environment file not found: $FilePath"
    }

    $lines = @(Get-Content -LiteralPath $FilePath)

    if ($lines -match ("^{0}=" -f [regex]::Escape($VariableName))) {
        return
    }

    Add-Content `
        -LiteralPath $FilePath `
        -Value ("{0}={1}" -f $VariableName, $Value) `
        -Encoding UTF8
}

function Invoke-Pnpm {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & pnpm.cmd @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "pnpm command failed: pnpm $($Arguments -join ' ')"
    }
}

function Get-EnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $pattern = "^{0}=(.*)$" -f [regex]::Escape($Name)
    $line = Get-Content -LiteralPath $FilePath |
        Where-Object { $_ -match $pattern } |
        Select-Object -First 1

    if ($null -eq $line) {
        return $null
    }

    return ([regex]::Match($line, $pattern)).Groups[1].Value
}

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " Solid Tracker - NestJS Backend Foundation" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    Set-Location -LiteralPath $RepositoryPath
    $script:RootPath = (Get-Location).Path
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Git repository was not found in $script:RootPath"
    }

    $currentBranch = (git branch --show-current).Trim()

    if ($currentBranch -ne "feat/backend-foundation") {
        throw "Expected branch feat/backend-foundation, but current branch is $currentBranch"
    }

    Write-Step 1 10 "Validating repository and infrastructure"

    foreach ($requiredFile in @(
        "package.json",
        "pnpm-workspace.yaml",
        ".env",
        ".env.example",
        "compose.yaml"
    )) {
        if (-not (Test-Path -LiteralPath $requiredFile)) {
            throw "Required file is missing: $requiredFile"
        }
    }

    docker compose --env-file .env ps --status running *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose services are not running."
    }

    $postgresHealth = (
        docker inspect `
            --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
            solid-tracker-postgres
    ).Trim()

    $redisHealth = (
        docker inspect `
            --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" `
            solid-tracker-redis
    ).Trim()

    if ($postgresHealth -ne "healthy" -or $redisHealth -ne "healthy") {
        throw "PostgreSQL and Redis must both be healthy before backend setup."
    }

    Write-Host "PostgreSQL: $postgresHealth" -ForegroundColor Green
    Write-Host "Redis:      $redisHealth" -ForegroundColor Green

    Write-Step 2 10 "Preparing backend service directory"

    $backendPath = Join-Path $script:RootPath "services\backend-api"
    New-Item -ItemType Directory -Path $backendPath -Force | Out-Null

    $gitKeepPath = Join-Path $backendPath ".gitkeep"

    if (Test-Path -LiteralPath $gitKeepPath) {
        Remove-Item -LiteralPath $gitKeepPath -Force
        Write-Host "[REMOVED]   services\backend-api\.gitkeep" -ForegroundColor Green
    }

    $directories = @(
        "services\backend-api\src\bootstrap",
        "services\backend-api\src\config",
        "services\backend-api\src\database",
        "services\backend-api\src\health",
        "services\backend-api\src\redis",
        "services\backend-api\test"
    )

    foreach ($directory in $directories) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Write-Step 3 10 "Creating NestJS project configuration"

    Write-ManagedFile "services\backend-api\package.json" (New-Text @(
        "{",
        '  "name": "@solid-tracker/backend-api",',
        '  "version": "0.1.0",',
        '  "private": true,',
        '  "description": "Solid Tracker backend REST API",',
        '  "license": "UNLICENSED",',
        '  "scripts": {',
        '    "build": "nest build",',
        '    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\"",',
        '    "start": "nest start",',
        '    "start:dev": "nest start --watch",',
        '    "start:debug": "nest start --debug --watch",',
        '    "start:prod": "node dist/main.js",',
        '    "lint": "eslint \"{src,test}/**/*.ts\"",',
        '    "lint:fix": "eslint \"{src,test}/**/*.ts\" --fix",',
        '    "typecheck": "tsc --noEmit",',
        '    "test": "jest",',
        '    "test:watch": "jest --watch",',
        '    "test:cov": "jest --coverage",',
        '    "test:e2e": "jest --config ./test/jest-e2e.json"',
        "  },",
        '  "jest": {',
        '    "moduleFileExtensions": ["js", "json", "ts"],',
        '    "rootDir": "src",',
        '    "testRegex": ".*\\.spec\\.ts$",',
        '    "transform": {',
        '      "^.+\\.(t|j)s$": "ts-jest"',
        "    },",
        '    "collectCoverageFrom": ["**/*.(t|j)s"],',
        '    "coverageDirectory": "../coverage",',
        '    "testEnvironment": "node"',
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\nest-cli.json" (New-Text @(
        "{",
        '  "$schema": "https://json.schemastore.org/nest-cli",',
        '  "collection": "@nestjs/schematics",',
        '  "sourceRoot": "src",',
        '  "compilerOptions": {',
        '    "deleteOutDir": true',
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\tsconfig.json" (New-Text @(
        "{",
        '  "compilerOptions": {',
        '    "module": "nodenext",',
        '    "moduleResolution": "nodenext",',
        '    "resolvePackageJsonExports": true,',
        '    "esModuleInterop": true,',
        '    "isolatedModules": true,',
        '    "declaration": true,',
        '    "removeComments": true,',
        '    "emitDecoratorMetadata": true,',
        '    "experimentalDecorators": true,',
        '    "allowSyntheticDefaultImports": true,',
        '    "target": "ES2023",',
        '    "sourceMap": true,',
        '    "outDir": "./dist",',
        '    "baseUrl": "./",',
        '    "incremental": true,',
        '    "skipLibCheck": true,',
        '    "strict": true,',
        '    "strictNullChecks": true,',
        '    "forceConsistentCasingInFileNames": true,',
        '    "noImplicitAny": true,',
        '    "noFallthroughCasesInSwitch": true',
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\tsconfig.build.json" (New-Text @(
        "{",
        '  "extends": "./tsconfig.json",',
        '  "exclude": ["node_modules", "test", "dist", "**/*spec.ts"]',
        "}"
    ))

    Write-ManagedFile "services\backend-api\.prettierrc" (New-Text @(
        "{",
        '  "singleQuote": true,',
        '  "trailingComma": "all",',
        '  "printWidth": 100',
        "}"
    ))

    Write-ManagedFile "services\backend-api\eslint.config.mjs" (New-Text @(
        "import eslint from '@eslint/js';",
        "import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended';",
        "import globals from 'globals';",
        "import tseslint from 'typescript-eslint';",
        "",
        "export default tseslint.config(",
        "  {",
        "    ignores: ['dist/**', 'coverage/**'],",
        "  },",
        "  eslint.configs.recommended,",
        "  ...tseslint.configs.recommended,",
        "  eslintPluginPrettierRecommended,",
        "  {",
        "    languageOptions: {",
        "      globals: {",
        "        ...globals.node,",
        "        ...globals.jest,",
        "      },",
        "      parserOptions: {",
        "        sourceType: 'module',",
        "      },",
        "    },",
        "    rules: {",
        "      '@typescript-eslint/explicit-function-return-type': 'off',",
        "      '@typescript-eslint/explicit-module-boundary-types': 'off',",
        "    },",
        "  },",
        ");"
    ))

    Write-Step 4 10 "Creating application source files"

    Write-ManagedFile "services\backend-api\src\config\environment.validation.ts" (New-Text @(
        "import * as Joi from 'joi';",
        "",
        "export const environmentValidationSchema = Joi.object({",
        "  NODE_ENV: Joi.string()",
        "    .valid('development', 'test', 'production')",
        "    .default('development'),",
        "  APP_PORT: Joi.number().port().default(3000),",
        "  DATABASE_URL: Joi.string()",
        "    .uri({ scheme: ['postgres', 'postgresql'] })",
        "    .required(),",
        "  REDIS_URL: Joi.string().uri({ scheme: ['redis', 'rediss'] }).required(),",
        "  CORS_ORIGINS: Joi.string().allow('').default(''),",
        "  TRACCAR_BASE_URL: Joi.string().uri().required(),",
        "  TRACCAR_USERNAME: Joi.string().allow('').default(''),",
        "  TRACCAR_PASSWORD: Joi.string().allow('').default(''),",
        "});"
    ))

    Write-ManagedFile "services\backend-api\src\database\database.service.ts" (New-Text @(
        "import { Injectable, OnModuleDestroy } from '@nestjs/common';",
        "import { ConfigService } from '@nestjs/config';",
        "import { Pool, QueryResult, QueryResultRow } from 'pg';",
        "",
        "@Injectable()",
        "export class DatabaseService implements OnModuleDestroy {",
        "  private readonly pool: Pool;",
        "",
        "  constructor(private readonly configService: ConfigService) {",
        "    this.pool = new Pool({",
        "      connectionString: this.configService.getOrThrow<string>('DATABASE_URL'),",
        "      max: 10,",
        "      idleTimeoutMillis: 30_000,",
        "      connectionTimeoutMillis: 5_000,",
        "    });",
        "  }",
        "",
        "  query<T extends QueryResultRow = QueryResultRow>(",
        "    text: string,",
        "    values: readonly unknown[] = [],",
        "  ): Promise<QueryResult<T>> {",
        "    return this.pool.query<T>(text, [...values]);",
        "  }",
        "",
        "  async ping(): Promise<void> {",
        "    await this.pool.query('SELECT 1');",
        "  }",
        "",
        "  async onModuleDestroy(): Promise<void> {",
        "    await this.pool.end();",
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\src\database\database.module.ts" (New-Text @(
        "import { Global, Module } from '@nestjs/common';",
        "import { DatabaseService } from './database.service';",
        "",
        "@Global()",
        "@Module({",
        "  providers: [DatabaseService],",
        "  exports: [DatabaseService],",
        "})",
        "export class DatabaseModule {}"
    ))

    Write-ManagedFile "services\backend-api\src\redis\redis.service.ts" (New-Text @(
        "import { Injectable, OnModuleDestroy } from '@nestjs/common';",
        "import { ConfigService } from '@nestjs/config';",
        "import Redis from 'ioredis';",
        "",
        "@Injectable()",
        "export class RedisService implements OnModuleDestroy {",
        "  private readonly client: Redis;",
        "",
        "  constructor(private readonly configService: ConfigService) {",
        "    this.client = new Redis(this.configService.getOrThrow<string>('REDIS_URL'), {",
        "      lazyConnect: true,",
        "      maxRetriesPerRequest: 2,",
        "      enableReadyCheck: true,",
        "    });",
        "  }",
        "",
        "  private async ensureConnected(): Promise<void> {",
        "    if (this.client.status === 'wait') {",
        "      await this.client.connect();",
        "    }",
        "  }",
        "",
        "  async ping(): Promise<void> {",
        "    await this.ensureConnected();",
        "    const response = await this.client.ping();",
        "",
        "    if (response !== 'PONG') {",
        "      throw new Error('Unexpected Redis response: ' + response);",
        "    }",
        "  }",
        "",
        "  async onModuleDestroy(): Promise<void> {",
        "    if (this.client.status !== 'end') {",
        "      await this.client.quit();",
        "    }",
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\src\redis\redis.module.ts" (New-Text @(
        "import { Global, Module } from '@nestjs/common';",
        "import { RedisService } from './redis.service';",
        "",
        "@Global()",
        "@Module({",
        "  providers: [RedisService],",
        "  exports: [RedisService],",
        "})",
        "export class RedisModule {}"
    ))

    Write-ManagedFile "services\backend-api\src\health\database.health.ts" (New-Text @(
        "import { Injectable } from '@nestjs/common';",
        "import { HealthIndicatorService } from '@nestjs/terminus';",
        "import { DatabaseService } from '../database/database.service';",
        "",
        "@Injectable()",
        "export class DatabaseHealthIndicator {",
        "  constructor(",
        "    private readonly databaseService: DatabaseService,",
        "    private readonly healthIndicatorService: HealthIndicatorService,",
        "  ) {}",
        "",
        "  async isHealthy(key: string) {",
        "    const indicator = this.healthIndicatorService.check(key);",
        "    const startedAt = Date.now();",
        "",
        "    try {",
        "      await this.databaseService.ping();",
        "      return indicator.up({ latencyMs: Date.now() - startedAt });",
        "    } catch (error: unknown) {",
        "      return indicator.down({",
        "        latencyMs: Date.now() - startedAt,",
        "        message: error instanceof Error ? error.message : 'Unknown database error',",
        "      });",
        "    }",
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\src\health\redis.health.ts" (New-Text @(
        "import { Injectable } from '@nestjs/common';",
        "import { HealthIndicatorService } from '@nestjs/terminus';",
        "import { RedisService } from '../redis/redis.service';",
        "",
        "@Injectable()",
        "export class RedisHealthIndicator {",
        "  constructor(",
        "    private readonly redisService: RedisService,",
        "    private readonly healthIndicatorService: HealthIndicatorService,",
        "  ) {}",
        "",
        "  async isHealthy(key: string) {",
        "    const indicator = this.healthIndicatorService.check(key);",
        "    const startedAt = Date.now();",
        "",
        "    try {",
        "      await this.redisService.ping();",
        "      return indicator.up({ latencyMs: Date.now() - startedAt });",
        "    } catch (error: unknown) {",
        "      return indicator.down({",
        "        latencyMs: Date.now() - startedAt,",
        "        message: error instanceof Error ? error.message : 'Unknown Redis error',",
        "      });",
        "    }",
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\src\health\health.controller.ts" (New-Text @(
        "import { Controller, Get } from '@nestjs/common';",
        "import { ApiOperation, ApiTags } from '@nestjs/swagger';",
        "import { HealthCheck, HealthCheckService } from '@nestjs/terminus';",
        "import { DatabaseHealthIndicator } from './database.health';",
        "import { RedisHealthIndicator } from './redis.health';",
        "",
        "@ApiTags('Health')",
        "@Controller('health')",
        "export class HealthController {",
        "  constructor(",
        "    private readonly healthCheckService: HealthCheckService,",
        "    private readonly databaseHealthIndicator: DatabaseHealthIndicator,",
        "    private readonly redisHealthIndicator: RedisHealthIndicator,",
        "  ) {}",
        "",
        "  @Get('live')",
        "  @ApiOperation({ summary: 'Check whether the API process is alive' })",
        "  live() {",
        "    return {",
        "      status: 'ok',",
        "      service: 'solid-tracker-backend-api',",
        "      uptimeSeconds: Math.floor(process.uptime()),",
        "      timestamp: new Date().toISOString(),",
        "    };",
        "  }",
        "",
        "  @Get('ready')",
        "  @HealthCheck()",
        "  @ApiOperation({ summary: 'Check PostgreSQL and Redis readiness' })",
        "  ready() {",
        "    return this.healthCheckService.check([",
        "      () => this.databaseHealthIndicator.isHealthy('postgresql'),",
        "      () => this.redisHealthIndicator.isHealthy('redis'),",
        "    ]);",
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\src\health\health.module.ts" (New-Text @(
        "import { Module } from '@nestjs/common';",
        "import { TerminusModule } from '@nestjs/terminus';",
        "import { DatabaseHealthIndicator } from './database.health';",
        "import { HealthController } from './health.controller';",
        "import { RedisHealthIndicator } from './redis.health';",
        "",
        "@Module({",
        "  imports: [TerminusModule],",
        "  controllers: [HealthController],",
        "  providers: [DatabaseHealthIndicator, RedisHealthIndicator],",
        "})",
        "export class HealthModule {}"
    ))

    Write-ManagedFile "services\backend-api\src\app.service.ts" (New-Text @(
        "import { Injectable } from '@nestjs/common';",
        "",
        "@Injectable()",
        "export class AppService {",
        "  getServiceInformation() {",
        "    return {",
        "      name: 'Solid Tracker Backend API',",
        "      version: '0.1.0',",
        "      status: 'running',",
        "      documentation: '/docs',",
        "      health: {",
        "        liveness: '/api/v1/health/live',",
        "        readiness: '/api/v1/health/ready',",
        "      },",
        "    };",
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\src\app.controller.ts" (New-Text @(
        "import { Controller, Get } from '@nestjs/common';",
        "import { ApiOperation, ApiTags } from '@nestjs/swagger';",
        "import { AppService } from './app.service';",
        "",
        "@ApiTags('System')",
        "@Controller()",
        "export class AppController {",
        "  constructor(private readonly appService: AppService) {}",
        "",
        "  @Get()",
        "  @ApiOperation({ summary: 'Return API service information' })",
        "  getServiceInformation() {",
        "    return this.appService.getServiceInformation();",
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\src\app.module.ts" (New-Text @(
        "import { Module } from '@nestjs/common';",
        "import { ConfigModule } from '@nestjs/config';",
        "import { AppController } from './app.controller';",
        "import { AppService } from './app.service';",
        "import { environmentValidationSchema } from './config/environment.validation';",
        "import { DatabaseModule } from './database/database.module';",
        "import { HealthModule } from './health/health.module';",
        "import { RedisModule } from './redis/redis.module';",
        "",
        "@Module({",
        "  imports: [",
        "    ConfigModule.forRoot({",
        "      isGlobal: true,",
        "      cache: true,",
        "      envFilePath: ['../../.env', '.env'],",
        "      validationSchema: environmentValidationSchema,",
        "      validationOptions: {",
        "        abortEarly: false,",
        "      },",
        "    }),",
        "    DatabaseModule,",
        "    RedisModule,",
        "    HealthModule,",
        "  ],",
        "  controllers: [AppController],",
        "  providers: [AppService],",
        "})",
        "export class AppModule {}"
    ))

    Write-ManagedFile "services\backend-api\src\bootstrap\app.setup.ts" (New-Text @(
        "import { INestApplication, ValidationPipe } from '@nestjs/common';",
        "import { ConfigService } from '@nestjs/config';",
        "import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';",
        "import helmet from 'helmet';",
        "",
        "export function configureApplication(app: INestApplication): void {",
        "  const configService = app.get(ConfigService);",
        "  const configuredOrigins = configService.get<string>('CORS_ORIGINS', '');",
        "  const origins = configuredOrigins",
        "    .split(',')",
        "    .map((origin) => origin.trim())",
        "    .filter(Boolean);",
        "",
        "  app.use(helmet());",
        "  app.enableCors({",
        "    origin: origins.length > 0 ? origins : false,",
        "    credentials: true,",
        "  });",
        "  app.setGlobalPrefix('api/v1');",
        "  app.useGlobalPipes(",
        "    new ValidationPipe({",
        "      whitelist: true,",
        "      forbidNonWhitelisted: true,",
        "      transform: true,",
        "    }),",
        "  );",
        "  app.enableShutdownHooks();",
        "",
        "  const swaggerConfig = new DocumentBuilder()",
        "    .setTitle('Solid Tracker API')",
        "    .setDescription('Solid Tracker GPS tracking platform backend API')",
        "    .setVersion('0.1.0')",
        "    .addBearerAuth()",
        "    .build();",
        "",
        "  const swaggerDocument = SwaggerModule.createDocument(app, swaggerConfig);",
        "  SwaggerModule.setup('docs', app, swaggerDocument, {",
        "    swaggerOptions: {",
        "      persistAuthorization: true,",
        "    },",
        "  });",
        "}"
    ))

    Write-ManagedFile "services\backend-api\src\main.ts" (New-Text @(
        "import { Logger } from '@nestjs/common';",
        "import { ConfigService } from '@nestjs/config';",
        "import { NestFactory } from '@nestjs/core';",
        "import { AppModule } from './app.module';",
        "import { configureApplication } from './bootstrap/app.setup';",
        "",
        "async function bootstrap(): Promise<void> {",
        "  const app = await NestFactory.create(AppModule, {",
        "    bufferLogs: true,",
        "  });",
        "",
        "  configureApplication(app);",
        "",
        "  const configService = app.get(ConfigService);",
        "  const port = configService.get<number>('APP_PORT', 3000);",
        "",
        "  await app.listen(port, '0.0.0.0');",
        "",
        "  const logger = new Logger('Bootstrap');",
        "  logger.log('Solid Tracker API is running at http://localhost:' + port + '/api/v1');",
        "  logger.log('Swagger documentation: http://localhost:' + port + '/docs');",
        "}",
        "",
        "bootstrap().catch((error: unknown) => {",
        "  const logger = new Logger('Bootstrap');",
        "  logger.error(error instanceof Error ? error.stack : error);",
        "  process.exit(1);",
        "});"
    ))

    Write-Step 5 10 "Creating tests and backend documentation"

    Write-ManagedFile "services\backend-api\src\app.service.spec.ts" (New-Text @(
        "import { AppService } from './app.service';",
        "",
        "describe('AppService', () => {",
        "  it('returns Solid Tracker service information', () => {",
        "    const service = new AppService();",
        "    const result = service.getServiceInformation();",
        "",
        "    expect(result.name).toBe('Solid Tracker Backend API');",
        "    expect(result.status).toBe('running');",
        "    expect(result.health.readiness).toBe('/api/v1/health/ready');",
        "  });",
        "});"
    ))

    Write-ManagedFile "services\backend-api\test\app.e2e-spec.ts" (New-Text @(
        "import { INestApplication } from '@nestjs/common';",
        "import { Test, TestingModule } from '@nestjs/testing';",
        "import request from 'supertest';",
        "import { AppModule } from '../src/app.module';",
        "import { configureApplication } from '../src/bootstrap/app.setup';",
        "",
        "describe('Solid Tracker API (e2e)', () => {",
        "  let app: INestApplication;",
        "",
        "  beforeAll(async () => {",
        "    const moduleFixture: TestingModule = await Test.createTestingModule({",
        "      imports: [AppModule],",
        "    }).compile();",
        "",
        "    app = moduleFixture.createNestApplication();",
        "    configureApplication(app);",
        "    await app.init();",
        "  });",
        "",
        "  afterAll(async () => {",
        "    await app.close();",
        "  });",
        "",
        "  it('GET /api/v1', async () => {",
        "    const response = await request(app.getHttpServer()).get('/api/v1').expect(200);",
        "",
        "    expect(response.body.name).toBe('Solid Tracker Backend API');",
        "  });",
        "",
        "  it('GET /api/v1/health/live', async () => {",
        "    const response = await request(app.getHttpServer())",
        "      .get('/api/v1/health/live')",
        "      .expect(200);",
        "",
        "    expect(response.body.status).toBe('ok');",
        "  });",
        "",
        "  it('GET /api/v1/health/ready', async () => {",
        "    const response = await request(app.getHttpServer())",
        "      .get('/api/v1/health/ready')",
        "      .expect(200);",
        "",
        "    expect(response.body.status).toBe('ok');",
        "    expect(response.body.info.postgresql.status).toBe('up');",
        "    expect(response.body.info.redis.status).toBe('up');",
        "  });",
        "});"
    ))

    Write-ManagedFile "services\backend-api\test\jest-e2e.json" (New-Text @(
        "{",
        '  "moduleFileExtensions": ["js", "json", "ts"],',
        '  "rootDir": ".",',
        '  "testEnvironment": "node",',
        '  "testRegex": ".e2e-spec.ts$",',
        '  "transform": {',
        '    "^.+\\.(t|j)s$": "ts-jest"',
        "  }",
        "}"
    ))

    Write-ManagedFile "services\backend-api\README.md" (New-Text @(
        "# Solid Tracker Backend API",
        "",
        "This service provides the REST API for the Solid Tracker platform.",
        "",
        "## Current foundation",
        "",
        "- NestJS and TypeScript",
        "- Environment validation",
        "- PostgreSQL connection pool",
        "- Redis connection",
        "- Liveness and readiness endpoints",
        "- Swagger/OpenAPI documentation",
        "- Global request validation",
        "- Security headers",
        "- Unit and end-to-end tests",
        "",
        "## Local endpoints",
        "",
        "- API root: http://localhost:3000/api/v1",
        "- Liveness: http://localhost:3000/api/v1/health/live",
        "- Readiness: http://localhost:3000/api/v1/health/ready",
        "- Swagger: http://localhost:3000/docs",
        "",
        "## Commands",
        "",
        "From the repository root:",
        "",
        "    pnpm api:start:dev",
        "    pnpm api:build",
        "    pnpm api:lint",
        "    pnpm api:typecheck",
        "    pnpm api:test",
        "    pnpm api:test:e2e",
        "",
        "Business database models are intentionally not defined in this foundation.",
        "The Prisma schema will be created after the Solid Tracker domain model and ERD are reviewed."
    ))

    Write-Step 6 10 "Updating root scripts and environment settings"

    $rootPackagePath = Join-Path $script:RootPath "package.json"
    $rootPackage = Get-Content -LiteralPath $rootPackagePath -Raw | ConvertFrom-Json

    if ($null -eq $rootPackage.scripts) {
        $rootPackage | Add-Member -MemberType NoteProperty -Name scripts -Value ([pscustomobject]@{})
    }

    $rootScripts = [ordered]@{}

    foreach ($property in $rootPackage.scripts.PSObject.Properties) {
        $rootScripts[$property.Name] = $property.Value
    }

    $rootScripts["api:build"] = "pnpm --filter @solid-tracker/backend-api build"
    $rootScripts["api:start"] = "pnpm --filter @solid-tracker/backend-api start"
    $rootScripts["api:start:dev"] = "pnpm --filter @solid-tracker/backend-api start:dev"
    $rootScripts["api:start:prod"] = "pnpm --filter @solid-tracker/backend-api start:prod"
    $rootScripts["api:format"] = "pnpm --filter @solid-tracker/backend-api format"
    $rootScripts["api:lint"] = "pnpm --filter @solid-tracker/backend-api lint"
    $rootScripts["api:lint:fix"] = "pnpm --filter @solid-tracker/backend-api lint:fix"
    $rootScripts["api:typecheck"] = "pnpm --filter @solid-tracker/backend-api typecheck"
    $rootScripts["api:test"] = "pnpm --filter @solid-tracker/backend-api test"
    $rootScripts["api:test:e2e"] = "pnpm --filter @solid-tracker/backend-api test:e2e"

    $rootPackage.scripts = [pscustomobject]$rootScripts

    [System.IO.File]::WriteAllText(
        $rootPackagePath,
        (($rootPackage | ConvertTo-Json -Depth 20) + "`n"),
        $script:Utf8NoBom
    )

    Add-EnvironmentLineIfMissing `
        -FilePath (Join-Path $script:RootPath ".env") `
        -VariableName "CORS_ORIGINS" `
        -Value "http://localhost:3001,http://localhost:5173"

    Add-EnvironmentLineIfMissing `
        -FilePath (Join-Path $script:RootPath ".env.example") `
        -VariableName "CORS_ORIGINS" `
        -Value "http://localhost:3001,http://localhost:5173"

    Write-Step 7 10 "Installing NestJS dependencies"

    Invoke-Pnpm @(
        "--filter",
        "@solid-tracker/backend-api",
        "add",
        "@nestjs/common",
        "@nestjs/config",
        "@nestjs/core",
        "@nestjs/platform-express",
        "@nestjs/swagger",
        "@nestjs/terminus",
        "class-transformer",
        "class-validator",
        "helmet",
        "ioredis",
        "joi",
        "pg",
        "reflect-metadata",
        "rxjs"
    )

    Invoke-Pnpm @(
        "--filter",
        "@solid-tracker/backend-api",
        "add",
        "--save-dev",
        "@nestjs/cli",
        "@nestjs/schematics",
        "@nestjs/testing",
        "@eslint/js",
        "@types/express",
        "@types/jest",
        "@types/node",
        "@types/pg",
        "@types/supertest",
        "eslint",
        "eslint-config-prettier",
        "eslint-plugin-prettier",
        "globals",
        "jest",
        "prettier",
        "source-map-support",
        "supertest",
        "ts-jest",
        "ts-loader",
        "ts-node",
        "tsconfig-paths",
        "typescript@5.9.3",
        "typescript-eslint"
    )

    Write-Step 8 10 "Formatting, linting, testing and building"

    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "format")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "lint")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "typecheck")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "test", "--runInBand")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "test:e2e", "--runInBand")
    Invoke-Pnpm @("--filter", "@solid-tracker/backend-api", "build")

    Write-Step 9 10 "Running API smoke test"

    $envPath = Join-Path $script:RootPath ".env"
    $appPort = Get-EnvValue -FilePath $envPath -Name "APP_PORT"

    if ([string]::IsNullOrWhiteSpace($appPort)) {
        $appPort = "3000"
    }

    $logsDirectory = Join-Path $script:RootPath "temp\backend-smoke-test"
    New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null

    $stdoutPath = Join-Path $logsDirectory "stdout.log"
    $stderrPath = Join-Path $logsDirectory "stderr.log"

    $apiProcess = Start-Process `
        -FilePath "node.exe" `
        -ArgumentList "services/backend-api/dist/main.js" `
        -WorkingDirectory $script:RootPath `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru

    try {
        $deadline = (Get-Date).AddSeconds(60)
        $ready = $false

        do {
            Start-Sleep -Seconds 2

            if ($apiProcess.HasExited) {
                $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { "" }
                $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }

                throw "API process exited during smoke test.`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
            }

            try {
                $readiness = Invoke-RestMethod `
                    -Uri ("http://127.0.0.1:{0}/api/v1/health/ready" -f $appPort) `
                    -Method Get `
                    -TimeoutSec 5

                if ($readiness.status -eq "ok") {
                    $ready = $true
                }
            }
            catch {
                # Continue until the deadline while NestJS initializes.
            }
        }
        while (-not $ready -and (Get-Date) -lt $deadline)

        if (-not $ready) {
            throw "API readiness endpoint did not become healthy within 60 seconds."
        }

        $serviceInfo = Invoke-RestMethod `
            -Uri ("http://127.0.0.1:{0}/api/v1" -f $appPort) `
            -Method Get `
            -TimeoutSec 5

        if ($serviceInfo.name -ne "Solid Tracker Backend API") {
            throw "API root endpoint returned an unexpected response."
        }

        Write-Host "API root:      healthy" -ForegroundColor Green
        Write-Host "PostgreSQL:    healthy" -ForegroundColor Green
        Write-Host "Redis:         healthy" -ForegroundColor Green
        Write-Host "Swagger route: http://localhost:$appPort/docs" -ForegroundColor Green
    }
    finally {
        if ($null -ne $apiProcess -and -not $apiProcess.HasExited) {
            Stop-Process -Id $apiProcess.Id -Force
            $apiProcess.WaitForExit()
        }
    }

    Write-Step 10 10 "Committing backend foundation"

    $filesToStage = @(
        ".env.example",
        "package.json",
        "pnpm-lock.yaml",
        "services/backend-api",
        "scripts/solid-tracker-backend-foundation.ps1"
    )

    foreach ($file in $filesToStage) {
        if (Test-Path -LiteralPath $file) {
            git add -- $file
        }
    }

    $stagedChanges = @(git diff --cached --name-only)

    if ($stagedChanges.Count -gt 0) {
        git commit -m "feat(api): establish NestJS backend foundation"

        if ($LASTEXITCODE -ne 0) {
            throw "Git commit failed."
        }
    }
    else {
        Write-Host "No new backend changes require a commit." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " NestJS Backend Foundation Ready" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "Current branch:" -ForegroundColor Yellow
    git branch --show-current

    Write-Host ""
    Write-Host "Latest commit:" -ForegroundColor Yellow
    git log -1 --oneline --decorate

    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short

    Write-Host ""
    Write-Host "Development command:" -ForegroundColor Yellow
    Write-Host "pnpm api:start:dev"

    Write-Host ""
    Write-Host "Local endpoints:" -ForegroundColor Yellow
    Write-Host "http://localhost:$appPort/api/v1"
    Write-Host "http://localhost:$appPort/api/v1/health/live"
    Write-Host "http://localhost:$appPort/api/v1/health/ready"
    Write-Host "http://localhost:$appPort/docs"

    Write-Host ""
    Write-Host "Solid Tracker NestJS backend foundation is ready." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "SETUP FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    Write-Host ""
    Write-Host "Repository status:" -ForegroundColor Yellow
    git status --short 2>$null

    exit 1
}
