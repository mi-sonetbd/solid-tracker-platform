import { Module } from '@nestjs/common';
import { DeviceModelsModule } from './device-models/device-models.module';
import { DevicesModule } from './devices/devices.module';
import { VehiclesModule } from './vehicles/vehicles.module';

@Module({
  imports: [VehiclesModule, DeviceModelsModule, DevicesModule],
})
export class AssetManagementModule {}
