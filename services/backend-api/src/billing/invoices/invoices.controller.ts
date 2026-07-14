import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
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
import { InvoiceQueryDto } from '../common/billing-query.dto';
import { CreateInvoiceDto } from './dto/create-invoice.dto';
import { IssueInvoiceDto, VoidInvoiceDto } from './dto/invoice-action.dto';
import { InvoicesService } from './invoices.service';

@ApiTags('Invoices')
@ApiBearerAuth()
@UseGuards(AccessTokenGuard, PermissionsGuard)
@Controller('invoices')
export class InvoicesController {
  constructor(private readonly invoicesService: InvoicesService) {}

  @Get()
  @RequirePermissions('invoice.view')
  @ApiOperation({ summary: 'List invoices within effective scope' })
  list(@CurrentAuth() auth: AuthContext, @Query() query: InvoiceQueryDto) {
    return this.invoicesService.list(auth, query);
  }

  @Post()
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Create a manual draft invoice' })
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateInvoiceDto) {
    return this.invoicesService.create(auth, dto);
  }

  @Get(':invoiceId')
  @RequirePermissions('invoice.view')
  @ApiOperation({ summary: 'Read one invoice with financial history' })
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('invoiceId', new ParseUUIDPipe()) invoiceId: string,
  ) {
    return this.invoicesService.get(auth, invoiceId);
  }

  @Post(':invoiceId/issue')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Issue a draft invoice' })
  issue(
    @CurrentAuth() auth: AuthContext,
    @Param('invoiceId', new ParseUUIDPipe()) invoiceId: string,
    @Body() dto: IssueInvoiceDto,
  ) {
    return this.invoicesService.issue(auth, invoiceId, dto);
  }

  @Post(':invoiceId/void')
  @RequirePermissions('subscription.create')
  @ApiOperation({ summary: 'Void an unpaid invoice' })
  void(
    @CurrentAuth() auth: AuthContext,
    @Param('invoiceId', new ParseUUIDPipe()) invoiceId: string,
    @Body() dto: VoidInvoiceDto,
  ) {
    return this.invoicesService.void(auth, invoiceId, dto);
  }
}
