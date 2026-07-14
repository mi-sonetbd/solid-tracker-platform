import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthRateLimitService } from './auth-rate-limit.service';
import { PasswordService } from './password.service';
import { TokenService } from './token.service';

@Module({
  imports: [JwtModule.register({})],
  providers: [PasswordService, TokenService, AuthRateLimitService],
  exports: [JwtModule, PasswordService, TokenService, AuthRateLimitService],
})
export class SecurityModule {}
