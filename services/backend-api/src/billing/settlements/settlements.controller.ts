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
import { SettlementQueryDto } from '../common/billing-query.dto';
import { CreatePayoutAccountDto } from './dto/create-payout-account.dto';
import { CreateSettlementDto } from './dto/create-settlement.dto';
import { CompleteSettlementDto, FailSettlementDto } from './dto/settlement-action.dto';
import { UpdatePayoutAccountDto } from './dto/update-payout-account.dto';
import { VerifyPayoutAccountDto } from './dto/verify-payout-account.dto';
import { PayoutAccountsService } from './payout-accounts.service';
import { SettlementsService } from './settlements.service';

@ApiTags('Dealer Settlements')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller()
export class SettlementsController {
  constructor(
    private readonly payoutAccountsService: PayoutAccountsService,
    private readonly settlementsService: SettlementsService,
  ) {}

  @Get('dealers/:dealerId/payout-accounts')
  @RequirePermissions('settlement.create')
  @ApiOperation({ summary: 'List masked dealer payout accounts' })
  listPayoutAccounts(
    @CurrentAuth() auth: AuthContext,
    @Param('dealerId', new ParseUUIDPipe()) dealerId: string,
  ) {
    return this.payoutAccountsService.list(auth, dealerId);
  }

  @Post('dealer-payout-accounts')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Create an encrypted dealer payout account',
  })
  createPayoutAccount(@CurrentAuth() auth: AuthContext, @Body() dto: CreatePayoutAccountDto) {
    return this.payoutAccountsService.create(auth, dto);
  }

  @Patch('dealer-payout-accounts/:payoutAccountId')
  @RequirePermissions('settlement.create')
  @ApiOperation({ summary: 'Update a dealer payout account' })
  updatePayoutAccount(
    @CurrentAuth() auth: AuthContext,
    @Param('payoutAccountId', new ParseUUIDPipe())
    payoutAccountId: string,
    @Body() dto: UpdatePayoutAccountDto,
  ) {
    return this.payoutAccountsService.update(auth, payoutAccountId, dto);
  }

  @Post('dealer-payout-accounts/:payoutAccountId/verify')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Verify or reject a payout account as platform',
  })
  verifyPayoutAccount(
    @CurrentAuth() auth: AuthContext,
    @Param('payoutAccountId', new ParseUUIDPipe())
    payoutAccountId: string,
    @Body() dto: VerifyPayoutAccountDto,
  ) {
    return this.payoutAccountsService.verify(auth, payoutAccountId, dto);
  }

  @Get('settlements')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'List settlements within scope' })
  listSettlements(@CurrentAuth() auth: AuthContext, @Query() query: SettlementQueryDto) {
    return this.settlementsService.list(auth, query);
  }

  @Post('settlements')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Create a draft settlement from available commission',
  })
  createSettlement(@CurrentAuth() auth: AuthContext, @Body() dto: CreateSettlementDto) {
    return this.settlementsService.create(auth, dto);
  }

  @Get('settlements/:settlementId')
  @RequirePermissions('commission.view')
  @ApiOperation({ summary: 'Read settlement details' })
  getSettlement(
    @CurrentAuth() auth: AuthContext,
    @Param('settlementId', new ParseUUIDPipe())
    settlementId: string,
  ) {
    return this.settlementsService.get(auth, settlementId);
  }

  @Post('settlements/:settlementId/submit')
  @RequirePermissions('settlement.create')
  @ApiOperation({ summary: 'Submit a draft settlement' })
  submitSettlement(
    @CurrentAuth() auth: AuthContext,
    @Param('settlementId', new ParseUUIDPipe())
    settlementId: string,
  ) {
    return this.settlementsService.submit(auth, settlementId);
  }

  @Post('settlements/:settlementId/complete')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Complete a settlement and append ledger debits',
  })
  completeSettlement(
    @CurrentAuth() auth: AuthContext,
    @Param('settlementId', new ParseUUIDPipe())
    settlementId: string,
    @Body() dto: CompleteSettlementDto,
  ) {
    return this.settlementsService.complete(auth, settlementId, dto);
  }

  @Post('settlements/:settlementId/fail')
  @RequirePermissions('settlement.create')
  @ApiOperation({
    summary: 'Fail a settlement and release commission entries',
  })
  failSettlement(
    @CurrentAuth() auth: AuthContext,
    @Param('settlementId', new ParseUUIDPipe())
    settlementId: string,
    @Body() dto: FailSettlementDto,
  ) {
    return this.settlementsService.fail(auth, settlementId, dto);
  }
}
