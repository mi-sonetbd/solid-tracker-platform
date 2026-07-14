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

  async list(auth: AuthContext, dealerOrganizationId: string) {
    this.access.assertDealer(auth, dealerOrganizationId);

    const accounts = await this.prisma.dealerPayoutAccount.findMany({
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
    this.access.assertDealer(auth, dto.dealerOrganizationId);

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
      throw new BadRequestException('An active dealer organization is required.');
    }

    const encryptedReference = this.crypto.encrypt(dto.accountReference.trim());
    const maskedAccountNumber = this.crypto.mask(dto.accountReference);

    const account = await this.prisma.$transaction(async (transaction) => {
      if (dto.isDefault) {
        await transaction.dealerPayoutAccount.updateMany({
          where: {
            dealerOrganizationId: dto.dealerOrganizationId,
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
          dealerOrganizationId: dto.dealerOrganizationId,
          accountType: dto.accountType,
          provider: dto.provider,
          accountHolderName: dto.accountHolderName.trim(),
          maskedAccountNumber,
          encryptedAccountReference: encryptedReference,
          verificationStatus: 'UNVERIFIED',
          isDefault: dto.isDefault,
          status: 'ACTIVE',
        },
      });
    });

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

  async update(auth: AuthContext, payoutAccountId: string, dto: UpdatePayoutAccountDto) {
    const before = await this.prisma.dealerPayoutAccount.findUnique({
      where: {
        id: payoutAccountId,
      },
    });

    if (!before) {
      throw new NotFoundException('Payout account was not found.');
    }

    this.access.assertDealer(auth, before.dealerOrganizationId);

    if (dto.status === 'ARCHIVED' && before.isDefault) {
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

    const updated = await this.prisma.$transaction(async (transaction) => {
      if (dto.isDefault === true) {
        await transaction.dealerPayoutAccount.updateMany({
          where: {
            dealerOrganizationId: before.dealerOrganizationId,
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
          accountHolderName: dto.accountHolderName?.trim(),
          encryptedAccountReference: encryptedReference,
          maskedAccountNumber,
          verificationStatus: dto.accountReference ? 'UNVERIFIED' : undefined,
          verifiedAt: dto.accountReference ? null : undefined,
          isDefault: dto.isDefault,
          status: dto.status,
          archivedAt: dto.status === 'ARCHIVED' ? new Date() : dto.status ? null : undefined,
        },
      });
    });

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

  async verify(auth: AuthContext, payoutAccountId: string, dto: VerifyPayoutAccountDto) {
    this.access.assertPlatform(auth);

    const before = await this.prisma.dealerPayoutAccount.findUnique({
      where: {
        id: payoutAccountId,
      },
    });

    if (!before) {
      throw new NotFoundException('Payout account was not found.');
    }

    if (before.status !== 'ACTIVE') {
      throw new ConflictException('Only active payout accounts can be verified.');
    }

    const verified = await this.prisma.dealerPayoutAccount.update({
      where: {
        id: payoutAccountId,
      },
      data: {
        verificationStatus: dto.verificationStatus,
        verifiedAt: dto.verificationStatus === 'VERIFIED' ? new Date() : null,
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
      dealerOrganizationId: account.dealerOrganizationId,
      accountType: account.accountType,
      provider: account.provider,
      accountHolderName: account.accountHolderName,
      maskedAccountNumber: account.maskedAccountNumber,
      verificationStatus: account.verificationStatus,
      isDefault: account.isDefault,
      status: account.status,
      verifiedAt: account.verifiedAt,
      createdAt: account.createdAt,
      updatedAt: account.updatedAt,
      archivedAt: account.archivedAt,
    };
  }
}
