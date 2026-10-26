# NestJS — Seguridad Web (Helmet, CORS, Rate Limiting, CSRF)

**Fuente:** https://docs.nestjs.com/security/helmet | cors | csrf | rate-limiting

## Helmet (headers de seguridad)

```bash
pnpm add helmet
```

```typescript
// main.ts
import helmet from "helmet";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.use(helmet()); // aplica antes de todo
  await app.listen(3000);
}
```

Helmet configura headers como:

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `Strict-Transport-Security` (HSTS)
- `X-XSS-Protection`
- `Content-Security-Policy`

## CORS

```typescript
// main.ts — habilitación simple
app.enableCors();

// Configuración completa
app.enableCors({
  origin: ["https://myapp.com", "https://admin.myapp.com"],
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE"],
  allowedHeaders: ["Content-Type", "Authorization", "X-Request-Id"],
  credentials: true, // para cookies/auth headers
  maxAge: 86400, // pre-flight cache en segundos
});

// Función dinámica
app.enableCors({
  origin: (origin, callback) => {
    const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(",") ?? [];
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error("Not allowed by CORS"));
    }
  },
});
```

## Rate Limiting (@nestjs/throttler)

```bash
pnpm add @nestjs/throttler
```

```typescript
// app.module.ts
import { ThrottlerModule, ThrottlerGuard } from "@nestjs/throttler";
import { APP_GUARD } from "@nestjs/core";

@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        name: "short",
        ttl: 1000, // 1 segundo
        limit: 3, // máx 3 requests
      },
      {
        name: "long",
        ttl: 60000, // 1 minuto
        limit: 100, // máx 100 requests
      },
    ]),
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}
```

### Personalizar por ruta

```typescript
// Saltarse el throttle global
@SkipThrottle()
@Get('health')
healthCheck() {}

// Throttle específico para una ruta
@Throttle({ default: { limit: 5, ttl: 60000 } })
@Post('login')
signIn() {}
```

### Con Redis (distribuido)

```bash
pnpm add @nestjs/throttler @nestjs-throttler-storage-redis ioredis
```

```typescript
import { ThrottlerStorageRedisService } from "@nestjs-throttler-storage-redis";

ThrottlerModule.forRootAsync({
  useFactory: (config: ConfigService) => ({
    throttlers: [{ ttl: 60000, limit: 100 }],
    storage: new ThrottlerStorageRedisService({
      host: config.get("REDIS_HOST"),
      port: config.get("REDIS_PORT"),
    }),
  }),
  inject: [ConfigService],
});
```

## CSRF Protection

```bash
pnpm add csurf
pnpm add @types/csurf
```

```typescript
// main.ts — para apps con sesiones/cookies
import * as csurf from "csurf";
import * as cookieParser from "cookie-parser";

const app = await NestFactory.create(AppModule);
app.use(cookieParser());
app.use(csurf({ cookie: true }));
```

> 📝 CSRF es relevante para apps con sesiones de cookies (SSR/MVC). Para APIs REST stateless con JWT en headers, CSRF no aplica.

## Encryption and Hashing

```bash
pnpm add bcrypt
pnpm add -D @types/bcrypt
```

```typescript
import * as bcrypt from "bcrypt";

// Hash de password
const saltRounds = 10;
const hashedPassword = await bcrypt.hash(plainPassword, saltRounds);

// Verificar password
const isMatch = await bcrypt.compare(plainPassword, hashedPassword);

// Generar salt manualmente
const salt = await bcrypt.genSalt(12);
const hash = await bcrypt.hash(password, salt);
```

### Cifrado simétrico (AES)

```typescript
import { createCipheriv, createDecipheriv, randomBytes, scrypt } from "crypto";
import { promisify } from "util";

const scryptAsync = promisify(scrypt);

async function encrypt(text: string, password: string): Promise<string> {
  const iv = randomBytes(16);
  const key = (await scryptAsync(password, "salt", 32)) as Buffer;
  const cipher = createCipheriv("aes-256-ctr", key, iv);
  const encryptedText = Buffer.concat([cipher.update(text), cipher.final()]);
  return `${iv.toString("hex")}:${encryptedText.toString("hex")}`;
}

async function decrypt(encrypted: string, password: string): Promise<string> {
  const [ivHex, encryptedHex] = encrypted.split(":");
  const iv = Buffer.from(ivHex, "hex");
  const key = (await scryptAsync(password, "salt", 32)) as Buffer;
  const decipher = createDecipheriv("aes-256-ctr", key, iv);
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedHex, "hex")),
    decipher.final(),
  ]).toString();
}
```

## Configuración main.ts completa (producción)

```typescript
async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Seguridad
  app.use(helmet());

  // CORS
  app.enableCors({
    origin: process.env.ALLOWED_ORIGINS?.split(","),
    credentials: true,
  });

  // Prefijo global
  app.setGlobalPrefix("api/v1");

  // Validación global
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // Serialización global
  app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));

  const port = app.get(ConfigService).get("PORT", 3000);
  await app.listen(port);
  Logger.log(`🚀 App running on port ${port}`, "Bootstrap");
}
```
