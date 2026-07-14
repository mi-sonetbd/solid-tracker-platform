import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AccessTokenGuard } from '../../identity/access-control/access-token.guard';
import { PermissionsGuard } from '../../identity/access-control/permissions.guard';
import type { AuthContext } from '../../identity/common/auth-context';
import { CurrentAuth } from '../../identity/common/current-auth.decorator';
import { RequirePermissions } from '../../identity/common/permissions.decorator';
import { PaginationQueryDto } from '../../management/common/pagination-query.dto';
import { CommissionQueryDto } from '../common/billing-query.dto';
import { CommissionsService } from './commissions.service';
import { CreateCommissionRuleDto } from './dto/create-commission-rule.dto';
import { ReverseCommissionDto } from './dto/reverse-commission.dto';
import { UpdateCommissionRuleDto } from './dto/update-commission-rule.dto';

@ApiTags('Commissions')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller()
export class CommissionsController {
  constructor(private readonly commissionsService: CommissionsService) {}

  @Get('commission-rules')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'List commission rules within scope' })
  listRules(@CurrentAuth() auth: AuthContext, @Query() query: PaginationQueryDto) {
    return this.commissionsService.listRules(auth, query);
  }

  @Post('commission-rules')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Create a platform commission rule' })
  createRule(@CurrentAuth() auth: AuthContext, @Body() dto: CreateCommissionRuleDto) {
    return this.commissionsService.createRule(auth, dto);
  }

  @Patch('commission-rules/:ruleId')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Update a platform commission rule' })
  updateRule(
    @CurrentAuth() auth: AuthContext,
    @Param('ruleId', new ParseUUIDPipe()) ruleId: string,
    @Body() dto: UpdateCommissionRuleDto,
  ) {
    return this.commissionsService.updateRule(auth, ruleId, dto);
  }

  @Get('commissions')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'List commission entries within scope' })
  listEntries(@CurrentAuth() auth: AuthContext, @Query() query: CommissionQueryDto) {
    return this.commissionsService.listEntries(auth, query);
  }

  @Post('commissions/:commissionEntryId/reverse')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Create an append-only commission reversal' })
  reverseEntry(
    @CurrentAuth() auth: AuthContext,
    @Param('commissionEntryId', new ParseUUIDPipe())
    commissionEntryId: string,
    @Body() dto: ReverseCommissionDto,
  ) {
    return this.commissionsService.reverseEntry(auth, commissionEntryId, dto);
  }

  @Get('dealers/:dealerId/ledger')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Read dealer ledger and balance' })
  ledger(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
    @Query() query: PaginationQueryDto,
  ) {
    return this.commissionsService.ledger(auth, dealerId, query);
  }
}
