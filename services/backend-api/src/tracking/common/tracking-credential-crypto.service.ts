import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

export interface TraccarCredentials {
  username?: string;
  password?: string;
  token?: string;
}

@Injectable()
export class TrackingCredentialCryptoService {
  private readonly key: Buffer;

  constructor(configService: ConfigService) {
    const source = configService.getOrThrow<string>('TRACKING_CREDENTIAL_ENCRYPTION_KEY');

    this.key = createHash('sha256').update(source).digest();
  }

  encrypt(credentials: TraccarCredentials): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const plaintext = Buffer.from(JSON.stringify(credentials), 'utf8');
    const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const tag = cipher.getAuthTag();

    return [
      'v1',
      iv.toString('base64url'),
      tag.toString('base64url'),
      encrypted.toString('base64url'),
    ].join('.');
  }

  decrypt(reference: string): TraccarCredentials {
    const [version, ivPart, tagPart, encryptedPart] = reference.split('.');

    if (version !== 'v1' || !ivPart || !tagPart || !encryptedPart) {
      throw new Error('Tracking credential reference is invalid.');
    }

    const decipher = createDecipheriv('aes-256-gcm', this.key, Buffer.from(ivPart, 'base64url'));

    decipher.setAuthTag(Buffer.from(tagPart, 'base64url'));

    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(encryptedPart, 'base64url')),
      decipher.final(),
    ]).toString('utf8');

    return JSON.parse(plaintext) as TraccarCredentials;
  }
}
