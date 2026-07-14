import { Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../access-control/access-token.guard';
import type { AuthContext } from '../common/auth-context';
import { CurrentAuth } from '../common/current-auth.decorator';
import { SessionsService } from './sessions.service';

@ApiTags('Sessions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard)
@Controller('sessions')
export class SessionsController {
  constructor(private readonly sessionsService: SessionsService) {}

  @Get()
  @ApiOperation({ summary: 'List the current user sessions' })
  list(@CurrentAuth() auth: AuthContext) {
    return this.sessionsService.list(auth);
  }

  @Delete(':sessionId')
  @HttpCode(204)
  @ApiOperation({ summary: 'Revoke one session owned by the user' })
  async revoke(
    @CurrentAuth() auth: AuthContext,
    @Param('sessionId', new ParseUUIDPipe()) sessionId: string,
  ): Promise<void> {
    await this.sessionsService.revoke(auth, sessionId);
  }
}
