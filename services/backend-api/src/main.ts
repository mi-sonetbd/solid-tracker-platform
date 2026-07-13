import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { configureApplication } from './bootstrap/app.setup';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true,
  });

  configureApplication(app);

  const configService = app.get(ConfigService);
  const port = configService.get<number>('APP_PORT', 3000);

  await app.listen(port, '0.0.0.0');

  const logger = new Logger('Bootstrap');
  logger.log('Solid Tracker API is running at http://localhost:' + port + '/api/v1');
  logger.log('Swagger documentation: http://localhost:' + port + '/docs');
}

bootstrap().catch((error: unknown) => {
  const logger = new Logger('Bootstrap');
  logger.error(error instanceof Error ? error.stack : error);
  process.exit(1);
});
