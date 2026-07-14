import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RedisService } from '../../redis/redis.service';

@Injectable()
export class AuthRateLimitService {
  constructor(
    private readonly redisService: RedisService,
    private readonly configService: ConfigService,
  ) {}

  async consumeLoginAttempt(ipAddress: string, mobileNumber: string): Promise<void> {
    await Promise.all([
      this.consume(
        `auth:login:ip:${ipAddress}`,
        this.configService.get<number>('AUTH_LOGIN_IP_LIMIT', 20),
        this.configService.get<number>('AUTH_LOGIN_IP_WINDOW_SECONDS', 60),
      ),
      this.consume(
        `auth:login:mobile:${mobileNumber}`,
        this.configService.get<number>('AUTH_LOGIN_MOBILE_LIMIT', 5),
        this.configService.get<number>('AUTH_LOGIN_MOBILE_WINDOW_SECONDS', 300),
      ),
    ]);
  }

  async clearMobileLoginAttempts(mobileNumber: string): Promise<void> {
    await this.redisService.delete(`auth:login:mobile:${mobileNumber}`);
  }

  private async consume(key: string, limit: number, windowSeconds: number): Promise<void> {
    const count = await this.redisService.incrementWithExpiry(key, windowSeconds);

    if (count > limit) {
      throw new HttpException(
        'Too many authentication attempts. Try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }
}
