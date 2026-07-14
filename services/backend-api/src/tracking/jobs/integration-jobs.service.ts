import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
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
      throw new NotFoundException('Integration job was not found.');
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
      throw new NotFoundException('Integration job was not found.');
    }

    if (!['FAILED', 'DEAD_LETTER'].includes(job.status)) {
      throw new BadRequestException('Only failed or dead-letter jobs may be retried.');
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
      throw new NotFoundException('Integration job was not found.');
    }

    if (['SUCCEEDED', 'CANCELLED', 'DEAD_LETTER'].includes(job.status)) {
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
      const existing = await this.prisma.integrationJob.findUnique({
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
    const message = error instanceof Error ? error.message : 'Unknown integration error';
    const deadLetter = job.attemptCount >= job.maximumAttempts;

    return this.prisma.integrationJob.update({
      where: {
        id: jobId,
      },
      data: {
        status: deadLetter ? 'DEAD_LETTER' : 'FAILED',
        lockedAt: null,
        failedAt: new Date(),
        lastError: message,
        nextAttemptAt: deadLetter ? null : new Date(Date.now() + 60_000),
      },
    });
  }
}
