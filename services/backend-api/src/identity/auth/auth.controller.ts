import { Body, Controller, Get, HttpCode, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { AuthService, RequestMetadata } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';

@ApiTags('Authentication')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  @HttpCode(200)
  @ApiOperation({ summary: 'Authenticate with mobile number and password' })
  login(@Body() dto: LoginDto, @Req() request: Request) {
    return this.authService.login(dto, this.getMetadata(request));
  }

  @Post('refresh')
  @HttpCode(200)
  @ApiOperation({ summary: 'Rotate a refresh token and issue a new session' })
  refresh(@Body() dto: RefreshTokenDto, @Req() request: Request) {
    return this.authService.refresh(dto.refreshToken, this.getMetadata(request));
  }

  @Get('me')
  @ApiBearerAuth()
  @UseGuards(AccessTokenGuard)
  @ApiOperation({ summary: 'Return the authenticated access context' })
  me(@CurrentAuth() auth: AuthContext) {
    return this.authService.getMe(auth);
  }

  @Post('logout')
  @HttpCode(204)
  @ApiBearerAuth()
  @UseGuards(AccessTokenGuard)
  @ApiOperation({ summary: 'Revoke the current session' })
  async logout(@CurrentAuth() auth: AuthContext, @Req() request: Request): Promise<void> {
    await this.authService.logout(auth, this.getMetadata(request));
  }

  @Post('logout-all')
  @HttpCode(200)
  @ApiBearerAuth()
  @UseGuards(AccessTokenGuard)
  @ApiOperation({ summary: 'Revoke every active session for the user' })
  async logoutAll(
    @CurrentAuth() auth: AuthContext,
    @Req() request: Request,
  ): Promise<{ revokedSessionCount: number }> {
    return {
      revokedSessionCount: await this.authService.logoutAll(auth, this.getMetadata(request)),
    };
  }

  private getMetadata(request: Request): RequestMetadata {
    const userAgentHeader = request.headers['user-agent'];

    return {
      ipAddress: request.ip || request.socket.remoteAddress || 'unknown',
      userAgent: Array.isArray(userAgentHeader) ? userAgentHeader.join(' ') : userAgentHeader,
    };
  }
}
