import { ConfigService } from '@nestjs/config';
import { TrackingCredentialCryptoService } from './tracking-credential-crypto.service';

describe('TrackingCredentialCryptoService', () => {
  it('encrypts and decrypts Traccar credentials', () => {
    const config = {
      getOrThrow: () => 'solid-tracker-test-tracking-encryption-key-123456789',
    } as unknown as ConfigService;
    const service = new TrackingCredentialCryptoService(config);
    const encrypted = service.encrypt({
      username: 'api-user',
      password: 'api-password',
    });

    expect(encrypted).not.toContain('api-password');
    expect(service.decrypt(encrypted)).toEqual({
      username: 'api-user',
      password: 'api-password',
    });
  });
});
