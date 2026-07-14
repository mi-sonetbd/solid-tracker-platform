import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { timingSafeEqual } from 'node:crypto';

@Injectable()
export class TrackingWebhookGuard implements CanActivate {
  private readonly expectedSecret: Buffer;

  constructor(configService: ConfigService) {
    this.expectedSecret = Buffer.from(
      configService.getOrThrow<string>('TRACKING_WEBHOOK_SECRET'),
      'utf8',
    );
  }

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<{
      headers: Record<string, string | string[] | undefined>;
    }>();
    const header = request.headers['x-tracking-webhook-secret'];
    const supplied = Array.isArray(header) ? header[0] : header;

    if (!supplied) {
      throw new UnauthorizedException('Tracking webhook secret is required.');
    }

    const actual = Buffer.from(supplied, 'utf8');

    if (
      actual.length !== this.expectedSecret.length ||
      !timingSafeEqual(actual, this.expectedSecret)
    ) {
      throw new UnauthorizedException('Tracking webhook secret is invalid.');
    }

    return true;
  }
}
