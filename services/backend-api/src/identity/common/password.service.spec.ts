import { PasswordService } from './password.service';

describe('PasswordService', () => {
  const service = new PasswordService();

  it('hashes and verifies a strong password', async () => {
    const hash = await service.hash('SolidTracker123!');

    expect(hash).not.toContain('SolidTracker123!');
    await expect(service.verify('SolidTracker123!', hash)).resolves.toBe(true);
    await expect(service.verify('WrongPassword123!', hash)).resolves.toBe(false);
  });

  it('rejects weak passwords', async () => {
    await expect(service.hash('password')).rejects.toThrow(
      'Password must contain at least 12 characters',
    );
  });
});
