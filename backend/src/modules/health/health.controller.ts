import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Controller('health')
export class HealthController {
  constructor(private readonly database: DataSource) {}

  @Get()
  async check() {
    try {
      await this.database.query('SELECT 1');
    } catch {
      throw new ServiceUnavailableException('数据库暂时不可用');
    }
    return { status: 'ok', service: 'syncbox-backend', database: 'up' };
  }
}
