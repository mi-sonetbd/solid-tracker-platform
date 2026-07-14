import { Injectable } from '@nestjs/common';
import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const KEY_LENGTH = 64;
const COST = 32768;
const BLOCK_SIZE = 8;
const PARALLELIZATION = 1;
const MAX_MEMORY = 64 * 1024 * 1024;

@Injectable()
export class PasswordService {
  async hash(password: string): Promise<string> {
    this.assertPasswordPolicy(password);

    const salt = randomBytes(24);
    const derivedKey = await this.deriveKey(
      password,
      salt,
      KEY_LENGTH,
      COST,
      BLOCK_SIZE,
      PARALLELIZATION,
    );

    return [
      'scrypt',
      COST,
      BLOCK_SIZE,
      PARALLELIZATION,
      salt.toString('base64url'),
      derivedKey.toString('base64url'),
    ].join('$');
  }

  async verify(password: string, encodedHash: string): Promise<boolean> {
    const parts = encodedHash.split('$');

    if (parts.length !== 6 || parts[0] !== 'scrypt') {
      return false;
    }

    const cost = Number(parts[1]);
    const blockSize = Number(parts[2]);
    const parallelization = Number(parts[3]);
    const salt = Buffer.from(parts[4], 'base64url');
    const expectedKey = Buffer.from(parts[5], 'base64url');

    if (
      !Number.isInteger(cost) ||
      !Number.isInteger(blockSize) ||
      !Number.isInteger(parallelization) ||
      expectedKey.length !== KEY_LENGTH
    ) {
      return false;
    }

    const actualKey = await this.deriveKey(
      password,
      salt,
      expectedKey.length,
      cost,
      blockSize,
      parallelization,
    );

    return timingSafeEqual(expectedKey, actualKey);
  }

  private deriveKey(
    password: string,
    salt: Buffer,
    keyLength: number,
    cost: number,
    blockSize: number,
    parallelization: number,
  ): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      scrypt(
        password,
        salt,
        keyLength,
        {
          N: cost,
          r: blockSize,
          p: parallelization,
          maxmem: MAX_MEMORY,
        },
        (error, derivedKey) => {
          if (error) {
            reject(error);
            return;
          }

          resolve(derivedKey);
        },
      );
    });
  }

  private assertPasswordPolicy(password: string): void {
    if (
      password.length < 12 ||
      !/[a-z]/.test(password) ||
      !/[A-Z]/.test(password) ||
      !/\d/.test(password)
    ) {
      throw new Error(
        'Password must contain at least 12 characters, uppercase, lowercase, and a number.',
      );
    }
  }
}
