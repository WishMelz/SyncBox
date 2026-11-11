import 'reflect-metadata';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { NestFactory } from '@nestjs/core';
import { ExpressAdapter, type NestExpressApplication } from '@nestjs/platform-express';
import { ConfigService } from '@nestjs/config';
import { AppModule } from './app.module';
import { configureApp } from './app.setup';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, new ExpressAdapter());
  configureApp(app);
  const config = app.get(ConfigService);
  const staticDir = config.get<string>('STATIC_DIR');
  if (staticDir) {
    app.useStaticAssets(staticDir, { index: false });
  }

  // Initialize Nest before adding the SPA fallback so API routes keep priority.
  await app.init();
  const indexPath = staticDir ? join(staticDir, 'index.html') : '';
  if (indexPath && existsSync(indexPath)) {
    const httpServer = app.getHttpAdapter().getInstance();
    httpServer.use(
      (
        request: { method?: string; path?: string },
        response: { sendFile: (path: string) => void },
        next: () => void,
      ) => {
        if (
          request.method !== 'GET' ||
          request.path === '/api' ||
          request.path?.startsWith('/api/')
        ) {
          next();
          return;
        }
        response.sendFile(indexPath);
      },
    );
  }

  await app.listen(config.getOrThrow<number>('PORT'), config.getOrThrow<string>('HOST'));
}

void bootstrap().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
