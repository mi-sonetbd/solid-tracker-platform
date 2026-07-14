import { BadRequestException } from '@nestjs/common';
import { NotificationTemplateRendererService } from './notification-template-renderer.service';

describe('NotificationTemplateRendererService', () => {
  const service = new NotificationTemplateRendererService();

  it('renders nested variables', () => {
    expect(
      service.render('Vehicle {{vehicle.name}} entered {{geofence}}.', {
        vehicle: { name: 'Dhaka-01' },
        geofence: 'Warehouse',
      }),
    ).toBe('Vehicle Dhaka-01 entered Warehouse.');
  });

  it('rejects missing variables', () => {
    expect(() => service.render('Hello {{name}}', {})).toThrow(BadRequestException);
  });
});
