import { Global, Module } from '@nestjs/common';
import { EventBus } from './events.service';

@Global()
@Module({ providers: [EventBus], exports: [EventBus] })
export class EventsModule {}
