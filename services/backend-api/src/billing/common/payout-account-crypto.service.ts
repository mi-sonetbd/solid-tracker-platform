import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createCipheriv, createHash, randomBytes } from 'node:crypto';

@Injectable()
export class PayoutAccountCryptoService {
  private readonly key: Buffer;

  constructor(configService: ConfigService) {
    this.key = createHash('sha256')
      .update(configService.getOrThrow<string>('BILLING_PAYOUT_ENCRYPTION_KEY'))
      .digest();
  }

  encrypt(value: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
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
