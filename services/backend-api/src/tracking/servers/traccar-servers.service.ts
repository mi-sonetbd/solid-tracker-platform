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

  async create(auth: AuthContext, dto: CreateTraccarServerDto) {
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
      throw new ConflictException('A Traccar server with this base URL already exists.');
    }

    const encryptedCredentialReference = this.credentialCrypto.encrypt({
      username: dto.username?.trim(),
      password: dto.password,
      token: dto.token,
    });

    const server = await this.prisma.$transaction(async (transaction) => {
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
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
      action: 'tracking.traccar-server.created',
      resourceType: 'TraccarServer',
      resourceId: server.id,
      scopeType: 'PLATFORM',
      afterData: this.sanitize(server),
    });

    return this.sanitize(server);
  }

  async update(auth: AuthContext, serverId: string, dto: UpdateTraccarServerDto) {
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

    if (dto.isDefault === true && effectiveStatus !== 'ACTIVE') {
      throw new BadRequestException('Only an active Traccar server may be the default.');
    }

    if (dto.status === 'ARCHIVED' && before.isDefault && dto.isDefault !== false) {
      throw new BadRequestException('Clear the default flag before archiving the server.');
    }

    const credentialFieldsProvided =
      dto.username !== undefined || dto.password !== undefined || dto.token !== undefined;

    if (credentialFieldsProvided) {
      this.assertCredentialInput(dto);
    }

    const updated = await this.prisma.$transaction(async (transaction) => {
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
          baseUrl: dto.baseUrl !== undefined ? this.normalizeBaseUrl(dto.baseUrl) : undefined,
          apiUsernameReference: credentialFieldsProvided ? dto.username?.trim() || null : undefined,
          encryptedCredentialReference: credentialFieldsProvided
            ? this.credentialCrypto.encrypt({
                username: dto.username?.trim(),
                password: dto.password,
                token: dto.token,
              })
            : undefined,
          status: dto.status,
          isDefault: dto.status === 'ARCHIVED' ? false : dto.isDefault,
          archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
        },
      });
    });

    await this.auditService.record({
      actorUserId: auth.userId,
      actorOrganizationId: this.access.actorOrganizationId(auth),
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
          status: server.status === 'DEGRADED' ? 'ACTIVE' : server.status,
        },
      });

      return {
        server: this.sanitize(updated),
        health: response,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown Traccar health error';

      await this.prisma.traccarServer.update({
        where: {
          id: serverId,
        },
        data: {
          lastHealthCheckAt: checkedAt,
          lastHealthStatus: 'DOWN',
          lastHealthError: message,
          status: server.status === 'ACTIVE' ? 'DEGRADED' : server.status,
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
      throw new NotFoundException('An active default Traccar server is not configured.');
    }

    return server;
  }

  private assertCredentialInput(input: {
    username?: string;
    password?: string;
    token?: string;
  }): void {
    const hasToken = Boolean(input.token?.trim());
    const hasBasic = Boolean(input.username?.trim()) && input.password !== undefined;

    if (!hasToken && !hasBasic) {
      throw new BadRequestException('Provide either a token or username and password.');
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

  private sanitize<
    T extends {
      encryptedCredentialReference: string;
    },
  >(
    server: T,
  ): Omit<T, 'encryptedCredentialReference'> & {
    credentialConfigured: true;
  } {
    const { encryptedCredentialReference, ...safe } = server;

    void encryptedCredentialReference;

    return {
      ...safe,
      credentialConfigured: true,
    };
  }
}
