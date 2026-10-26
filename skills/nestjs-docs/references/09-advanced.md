# NestJS — Conceptos Avanzados

## 1. WebSockets (Gateways)

```bash
pnpm add @nestjs/websockets @nestjs/platform-socket.io
```

```typescript
// chat/chat.gateway.ts
import {
  WebSocketGateway,
  SubscribeMessage,
  MessageBody,
  WebSocketServer,
  ConnectedSocket,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from "@nestjs/websockets";
import { Server, Socket } from "socket.io";
import { UseGuards } from "@nestjs/common";

@WebSocketGateway({
  cors: { origin: process.env.FRONTEND_URL },
  namespace: "/chat",
})
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  handleConnection(client: Socket) {
    console.log(`Client connected: ${client.id}`);
  }

  handleDisconnect(client: Socket) {
    console.log(`Client disconnected: ${client.id}`);
  }

  @SubscribeMessage("joinRoom")
  handleJoinRoom(
    @ConnectedSocket() client: Socket,
    @MessageBody() room: string,
  ) {
    client.join(room);
    this.server.to(room).emit("userJoined", { userId: client.id });
  }

  @SubscribeMessage("sendMessage")
  handleMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { room: string; message: string },
  ) {
    this.server.to(data.room).emit("newMessage", {
      message: data.message,
      userId: client.id,
      timestamp: new Date(),
    });
  }
}
```

---

## 2. Microservicios

```bash
pnpm add @nestjs/microservices
```

### Transporte TCP

```typescript
// main.ts (microservice)
const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
  transport: Transport.TCP,
  options: { host: 'localhost', port: 8877 },
});
await app.listen();

// Controller en microservice:
@Controller()
export class MathController {
  @MessagePattern({ cmd: 'sum' })
  sum(data: number[]): number {
    return data.reduce((a, b) => a + b, 0);
  }
}

// Cliente en otra app:
@Module({
  imports: [
    ClientsModule.register([{
      name: 'MATH_SERVICE',
      transport: Transport.TCP,
      options: { host: 'localhost', port: 8877 },
    }]),
  ],
})

// Uso:
constructor(@Inject('MATH_SERVICE') private client: ClientProxy) {}

// Enviar y esperar respuesta:
const result = await this.client.send<number>({ cmd: 'sum' }, [1, 2, 3]).toPromise();

// Emitir evento (sin respuesta):
this.client.emit('order_created', { orderId: '123' });
```

### Transporte Redis

```typescript
ClientsModule.register([
  {
    name: "EVENTS_SERVICE",
    transport: Transport.REDIS,
    options: { host: "localhost", port: 6379 },
  },
]);
```

---

## 3. Lifecycle Hooks

```typescript
import {
  OnModuleInit,
  OnModuleDestroy,
  OnApplicationBootstrap,
  BeforeApplicationShutdown,
  OnApplicationShutdown,
} from "@nestjs/common";

@Injectable()
export class AppService implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    // Se ejecuta cuando el módulo se inicializa
    await this.warmUpCache();
  }

  async onModuleDestroy() {
    // Se ejecuta al destruir el módulo (cierre de app)
    await this.cleanup();
  }
}

// En main.ts para graceful shutdown:
app.enableShutdownHooks();
```

---

## 4. Módulos Dinámicos (patrón avanzado)

```typescript
export interface MailModuleOptions {
  apiKey: string;
  from: string;
}

@Module({})
export class MailModule {
  static forRoot(options: MailModuleOptions): DynamicModule {
    return {
      module: MailModule,
      providers: [{ provide: "MAIL_OPTIONS", useValue: options }, MailService],
      exports: [MailService],
      global: true,
    };
  }

  static forRootAsync(options: {
    inject: any[];
    useFactory: (...args: any[]) => MailModuleOptions;
  }): DynamicModule {
    return {
      module: MailModule,
      providers: [
        {
          provide: "MAIL_OPTIONS",
          useFactory: options.useFactory,
          inject: options.inject,
        },
        MailService,
      ],
      exports: [MailService],
    };
  }
}

// Uso:
MailModule.forRootAsync({
  inject: [ConfigService],
  useFactory: (config: ConfigService) => ({
    apiKey: config.get("MAIL_API_KEY"),
    from: config.get("MAIL_FROM"),
  }),
});
```

---

## 5. Task Scheduling (Cron Jobs)

```bash
pnpm add @nestjs/schedule
```

```typescript
// app.module.ts
import { ScheduleModule } from '@nestjs/schedule';
@Module({ imports: [ScheduleModule.forRoot()] })

// tasks/tasks.service.ts
import { Injectable } from '@nestjs/common';
import { Cron, CronExpression, Interval, Timeout } from '@nestjs/schedule';

@Injectable()
export class TasksService {
  @Cron(CronExpression.EVERY_DAY_AT_MIDNIGHT)
  async cleanupExpiredSessions() {
    await this.sessionsService.deleteExpired();
  }

  @Cron('0 9 * * 1-5')  // 9am lunes a viernes
  sendDailyReport() { ... }

  @Interval(30000)  // cada 30 segundos
  checkHealthStatus() { ... }

  @Timeout(5000)  // una sola vez después de 5s
  onStartup() { ... }
}
```

---

## 6. Queue (BullMQ)

```bash
pnpm add @nestjs/bullmq bullmq
```

```typescript
// Definir queue:
@Module({
  imports: [
    BullModule.forRoot({ connection: { host: 'localhost', port: 6379 } }),
    BullModule.registerQueue({ name: 'email' }),
  ],
})

// Producir jobs:
constructor(@InjectQueue('email') private emailQueue: Queue) {}

await this.emailQueue.add('send-welcome', { userId, email }, {
  delay: 1000,
  attempts: 3,
  backoff: { type: 'exponential', delay: 1000 },
});

// Consumir (processor):
@Processor('email')
export class EmailProcessor extends WorkerHost {
  @Process('send-welcome')
  async sendWelcome(job: Job<{ userId: string; email: string }>) {
    await this.mailerService.sendWelcome(job.data.email);
  }
}
```

---

## 7. Logging con Winston

```bash
pnpm add winston nest-winston
```

```typescript
import { WinstonModule } from 'nest-winston';
import * as winston from 'winston';

@Module({
  imports: [
    WinstonModule.forRoot({
      transports: [
        new winston.transports.Console({
          format: winston.format.combine(
            winston.format.timestamp(),
            winston.format.colorize(),
            winston.format.simple(),
          ),
        }),
        new winston.transports.File({
          filename: 'logs/error.log',
          level: 'error',
        }),
      ],
    }),
  ],
})

// En services:
constructor(@Inject(WINSTON_MODULE_PROVIDER) private readonly logger: Logger) {}
this.logger.log('info', 'User created', { userId });
this.logger.error('Database error', { error });
```

---

## 8. Circular Dependencies

```typescript
// Evitar con forwardRef:
@Module({
  imports: [forwardRef(() => UsersModule)],
})
export class AuthModule {}

// En constructor:
constructor(
  @Inject(forwardRef(() => UsersService))
  private usersService: UsersService,
) {}
```

---

## 9. CQRS Pattern

```bash
pnpm add @nestjs/cqrs
```

```typescript
// Command:
export class CreateCarCommand { constructor(public readonly dto: CreateCarDto, public readonly userId: string) {} }

// Command Handler:
@CommandHandler(CreateCarCommand)
export class CreateCarHandler implements ICommandHandler<CreateCarCommand> {
  async execute(command: CreateCarCommand) {
    return this.carsRepository.create(command.dto, command.userId);
  }
}

// Query:
export class GetCarsQuery { constructor(public readonly pagination: PaginationDto) {} }

// Dispatch:
constructor(private commandBus: CommandBus, private queryBus: QueryBus) {}
await this.commandBus.execute(new CreateCarCommand(dto, userId));
await this.queryBus.execute(new GetCarsQuery(pagination));
```

---

## 10. Health Checks (Terminus)

```bash
pnpm add @nestjs/terminus
```

```typescript
@Controller("health")
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private db: PrismaHealthIndicator,
    private http: HttpHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      () => this.db.pingCheck("database"),
      () => this.http.pingCheck("api", "http://localhost:3000/api/v1"),
    ]);
  }
}
```
