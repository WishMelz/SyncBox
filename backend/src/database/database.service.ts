import { Injectable } from '@nestjs/common';
import { DataSource, type EntityManager } from 'typeorm';
import { ConfigService } from '@nestjs/config';
import { createReadStream, mkdirSync, readdirSync, statSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { BadRequestException } from '@nestjs/common';

// SQLite uses one connection. Serialize application queries with transactions so
// concurrent requests cannot accidentally join or roll back another transaction.
@Injectable()
export class DatabaseService {
  private pending: Promise<unknown> = Promise.resolve();
  constructor(private readonly source: DataSource, private readonly config: ConfigService) {}

  async createBackup() {
    const configured = this.config.getOrThrow<string>('DATABASE_PATH');
    if (configured === ':memory:') throw new BadRequestException('内存数据库不能创建备份');
    const database = resolve(configured);
    const directory = join(dirname(database), 'backups');
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    const name = `syncbox-${new Date().toISOString().replace(/[:.]/g, '-')}-${randomUUID()}.sqlite`;
    const path = join(directory, name);
    try {
      // VACUUM INTO creates a consistent snapshot including the current WAL state.
      const escapedPath = path.replaceAll("'", "''");
      await this.query(`VACUUM INTO '${escapedPath}'`);
    } catch (error) {
      try { unlinkSync(path); } catch { /* the snapshot was not created */ }
      throw error;
    }
    for (const old of readdirSync(directory).filter((file) => file.startsWith('syncbox-') && file.endsWith('.sqlite')).sort().slice(0, -10)) {
      try { unlinkSync(join(directory, old)); } catch { /* a concurrent download may still hold it */ }
    }
    const sha256 = await new Promise<string>((resolveHash, reject) => {
      const hash = createHash('sha256');
      const stream = createReadStream(path);
      stream.on('data', (chunk) => hash.update(chunk));
      stream.once('error', reject);
      stream.once('end', () => resolveHash(hash.digest('hex')));
    });
    return { path, name, size: statSync(path).size, sha256, createdAt: new Date().toISOString() };
  }

  private enqueue<T>(work: () => Promise<T>): Promise<T> {
    const result = this.pending.then(work);
    this.pending = result.catch(() => undefined);
    return result;
  }

  query<T = any>(sql: string, parameters: unknown[] = []): Promise<T> {
    return this.enqueue(() => this.source.query(sql, parameters));
  }

  transaction<T>(work: (manager: EntityManager) => Promise<T>): Promise<T> {
    return this.enqueue(() => this.source.transaction(work));
  }
}
