import { Module } from '@nestjs/common';
import { CustomerGroupsModule } from './customer-groups/customer-groups.module';
import { CustomersModule } from './customers/customers.module';
import { DealersModule } from './dealers/dealers.module';

@Module({
  imports: [DealersModule, CustomerGroupsModule, CustomersModule],
})
export class DealerCustomerManagementModule {}
