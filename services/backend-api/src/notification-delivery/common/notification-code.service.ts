import { Injectable } from '@nestjs/common';
import { randomBytes } from 'node:crypto';

@Injectable()
export class NotificationCodeService {
  template(): string {
    return `NTPL-${this.token(12)}`;
  }

  notification(): string {
    return `NTF-${this.token(16)}`;
  }

  private token(length: number): string {
    return randomBytes(Math.ceil(length / 2))
      .toString('hex')
      .slice(0, length)
      .toUpperCase();
  }
}
