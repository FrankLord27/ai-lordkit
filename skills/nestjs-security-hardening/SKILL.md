---
name: nestjs-security-hardening
description: Usar al crear o revisar un backend NestJS: aplica una base de seguridad igual o superior a la de Laravel (auth, validación, CSRF, cifrado, multi-tenant, logs).
---

# NestJS Security Hardening

Objetivo: que todo backend NestJS salga con una base de seguridad **igual o superior a Laravel de fábrica**. Laravel trae casi todo incluido; en Nest hay que montarlo. Esta skill cierra esa brecha y añade capas que Laravel no impone por defecto (deny-by-default, validación fail-fast del entorno, aislamiento multi-tenant, rotación de refresh con detección de reuso, redacción de logs).

Stack asumido: NestJS 11 + Express, TypeScript strict, Prisma 7 + PostgreSQL, Redis, validación con Zod vía `nestjs-zod` (nunca class-validator en código nuevo). Si el proyecto usa otro ORM o Fastify, adapta los equivalentes sin bajar el nivel.

## Modos de uso

1. **Proyecto nuevo**: aplicar todas las secciones en orden.
2. **Módulo nuevo**: aplicar secciones 6, 7, 8, 9 y 10 al módulo.
3. **Revisión/auditoría**: recorrer el checklist final y reportar cada punto como OK / FALTA / RIESGO, con archivo y línea.

Nunca bajar un control para "que funcione". Si algo choca, explicar el riesgo y proponer la alternativa segura.

## Mapa Laravel → NestJS

| Laravel (de fábrica) | Equivalente en Nest (obligatorio) |
|---|---|
| `.env` + `APP_DEBUG=false` | `ConfigModule` + validación Zod fail-fast; filtro global que oculta errores 500 |
| CSRF middleware | Cookies `SameSite=Strict` + `OriginGuard` (sección 5) |
| Form Requests | `ZodValidationPipe` global + schemas Zod `.strict()` |
| `$fillable` / `$guarded` | DTOs estrictos + asignación explícita de campos en Prisma |
| Eloquent (queries parametrizadas) | Prisma; `$queryRawUnsafe` prohibido |
| `Hash::make` (bcrypt/argon2) | `argon2id` |
| Auth (Breeze/Sanctum) | JWT corto + refresh opaco rotado (en Redis) en cookie httpOnly |
| Gates / Policies | `JwtAuthGuard` global (deny-by-default) + `RolesGuard` + chequeo de propiedad en servicio |
| `RateLimiter` / `throttle` | `@nestjs/throttler` global + límites estrictos en auth |
| `Crypt` (APP_KEY) | `CryptoService` AES-256-GCM |
| `URL::signedRoute` | `SignedUrlService` HMAC con expiración |
| Password reset con token que expira | Token aleatorio, guardado como hash SHA-256, 60 min, un solo uso |
| Escape en Blade | API JSON + Helmet (CSP) + el frontend escapa |
| Encrypted cookies | `cookie-parser` firmado + flags `Secure`, `HttpOnly`, `SameSite` |

## Dependencias

```bash
pnpm add helmet cookie-parser @nestjs/config zod nestjs-zod @nestjs/throttler argon2 @nestjs/passport passport passport-jwt @nestjs/jwt nestjs-pino pino-http @nestjs/terminus ioredis
pnpm add -D @types/cookie-parser @types/passport-jwt pino-pretty
```

Varias instancias detrás de un balanceador: añadir `@nest-lab/throttler-storage-redis` para compartir el rate limit.

## 1. Entorno validado (fail-fast)

La app NO arranca si falta o es débil un secreto.

```ts
// src/config/env.schema.ts
import { z } from 'zod';

export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(32),
  APP_KEY: z
    .string()
    .refine((v) => Buffer.from(v, 'base64').length === 32, 'APP_KEY debe ser 32 bytes en base64'),
  COOKIE_SECRET: z.string().min(32),
  CORS_ORIGINS: z.string().min(1),
  REDIS_URL: z.string().url().optional(),
});

export type Env = z.infer<typeof envSchema>;
```

```ts
// en AppModule imports
ConfigModule.forRoot({ isGlobal: true, validate: (env) => envSchema.parse(env) }),
```

Generar secretos: `openssl rand -base64 32`. Nunca commitear `.env`; mantener `.env.example` sin valores reales.

## 2. Bootstrap endurecido

```ts
// src/main.ts
import { NestFactory } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: true });
  const config = app.get(ConfigService);

  app.useLogger(app.get(Logger));
  app.set('trust proxy', 1); // detrás de Nginx/Cloudflare: IP real para el throttler
  app.disable('x-powered-by');

  app.use(helmet());
  app.use(cookieParser(config.getOrThrow<string>('COOKIE_SECRET')));
  app.useBodyParser('json', { limit: '1mb' });
  app.useBodyParser('urlencoded', { extended: true, limit: '1mb' });

  app.enableCors({
    origin: config.getOrThrow<string>('CORS_ORIGINS').split(',').map((o) => o.trim()),
    credentials: true,
  });

  app.useGlobalFilters(new AllExceptionsFilter());
  app.enableShutdownHooks();

  await app.listen(config.getOrThrow<number>('PORT'));
}
bootstrap();
```

La validación global va en `AppModule` (así aplica también en tests e2e):

```ts
// AppModule providers
{ provide: APP_PIPE, useClass: ZodValidationPipe }, // import { ZodValidationPipe } from 'nestjs-zod'
```

Nunca usar `origin: '*'` con `credentials: true`. Swagger (`/docs`) solo en dev/staging o detrás de auth.

## 3. Filtro global de errores (equivale a APP_DEBUG=false)

```ts
// src/common/filters/all-exceptions.filter.ts
import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Request, Response } from 'express';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('Exceptions');

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request>();
    const status =
      exception instanceof HttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;

    if (status >= 500) this.logger.error({ err: exception, method: req.method, path: req.url });

    const body =
      exception instanceof HttpException && status < 500
        ? exception.getResponse()
        : { statusCode: status, message: 'Error interno del servidor' };

    res.status(status).json(body);
  }
}
```

Regla: jamás devolver stack traces, mensajes de Prisma ni SQL al cliente.

## 4. Rate limiting

```ts
// AppModule imports
ThrottlerModule.forRoot([{ name: 'default', ttl: 60_000, limit: 100 }]),
```

```ts
// En login, registro, reset de contraseña y verificación de OTP
@Throttle({ default: { limit: 5, ttl: 60_000 } })
@Post('login')
```

## 5. CSRF (solo si la auth viaja en cookies)

Bearer tokens en header no son vulnerables a CSRF. Con cookies: `SameSite=Strict` + este guard.

```ts
// src/common/guards/origin.guard.ts
import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Request } from 'express';

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

@Injectable()
export class OriginGuard implements CanActivate {
  private readonly allowed: Set<string>;

  constructor(config: ConfigService) {
    this.allowed = new Set(
      config.getOrThrow<string>('CORS_ORIGINS').split(',').map((o) => o.trim()),
    );
  }

  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest<Request>();
    if (SAFE_METHODS.has(req.method)) return true;
    if (req.headers.authorization?.startsWith('Bearer ')) return true;

    let origin = req.headers.origin;
    if (!origin && req.headers.referer) {
      try {
        origin = new URL(req.headers.referer).origin;
      } catch {
        origin = undefined;
      }
    }
    if (!origin || !this.allowed.has(origin)) throw new ForbiddenException('Origen no permitido');
    return true;
  }
}
```

## 6. Autenticación deny-by-default

Todo endpoint exige auth salvo que se marque `@Public()` explícitamente. Laravel no impone esto; aquí sí.

```ts
// src/common/decorators/public.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
```

```ts
// src/auth/guards/jwt-auth.guard.ts
import { ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { IS_PUBLIC_KEY } from '../../common/decorators/public.decorator';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly reflector: Reflector) {
    super();
  }

  canActivate(ctx: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (isPublic) return true;
    return super.canActivate(ctx);
  }
}
```

```ts
// src/auth/strategies/jwt.strategy.ts
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

export interface JwtPayload {
  sub: string;
  tenantId: string;
  roles: string[];
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: config.getOrThrow<string>('JWT_ACCESS_SECRET'),
      algorithms: ['HS256'],
      ignoreExpiration: false,
    });
  }

  validate(payload: JwtPayload) {
    return { userId: payload.sub, tenantId: payload.tenantId, roles: payload.roles };
  }
}
```

Access token: 15 minutos máximo. Firmar con `{ expiresIn: '15m' }`.

Registro global (orden importa: throttler → origen → auth → roles):

```ts
// AppModule providers
{ provide: APP_GUARD, useClass: ThrottlerGuard },
{ provide: APP_GUARD, useClass: OriginGuard },
{ provide: APP_GUARD, useClass: JwtAuthGuard },
{ provide: APP_GUARD, useClass: RolesGuard },
```

## 7. Autorización (Gates/Policies)

```ts
// src/common/guards/roles.guard.ts
import { CanActivate, ExecutionContext, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<string[]>(ROLES_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (!required?.length) return true;
    const { user } = ctx.switchToHttp().getRequest();
    return required.some((r) => user?.roles?.includes(r));
  }
}
```

Roles no bastan. Contra IDOR, todo acceso por id filtra por dueño y tenant en el `where`:

```ts
const ticket = await this.prisma.ticket.findFirst({
  where: { id, tenantId: user.tenantId, ...(isAdmin ? {} : { ownerId: user.userId }) },
});
if (!ticket) throw new NotFoundException(); // 404, no 403: no revelar que existe
```

## 8. Contraseñas, refresh tokens y resets

```ts
import * as argon2 from 'argon2';
import { createHash, randomBytes } from 'crypto';

export const hashPassword = (pw: string) => argon2.hash(pw, { type: argon2.argon2id });
export const sha256 = (v: string) => createHash('sha256').update(v).digest('hex');

// Login resistente a timing: verificar siempre, exista o no el usuario
const DUMMY_HASH = await hashPassword(randomBytes(16).toString('hex')); // calcular una vez al iniciar
const user = await this.prisma.user.findUnique({ where: { email } });
const ok = await argon2.verify(user?.passwordHash ?? DUMMY_HASH, password);
if (!user || !ok) throw new UnauthorizedException('Credenciales inválidas');
```

Refresh token opaco en Redis, guardado como hash, rotado en cada uso, con detección de reuso:

```ts
// src/auth/refresh-token.service.ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { randomBytes, randomUUID } from 'crypto';
import Redis from 'ioredis';
import { sha256 } from './crypto.util';

const TTL = 7 * 24 * 60 * 60; // segundos

@Injectable()
export class RefreshTokenService {
  constructor(private readonly redis: Redis) {}

  async issue(userId: string, familyId: string = randomUUID()): Promise<string> {
    const raw = randomBytes(32).toString('base64url');
    const hash = sha256(raw);
    await this.redis
      .multi()
      .set(`rt:${hash}`, JSON.stringify({ userId, familyId }), 'EX', TTL)
      .sadd(`rt:family:${familyId}`, hash)
      .expire(`rt:family:${familyId}`, TTL)
      .sadd(`rt:user:${userId}`, familyId)
      .expire(`rt:user:${userId}`, TTL)
      .exec();
    return raw;
  }

  async rotate(raw: string): Promise<{ userId: string; refreshToken: string }> {
    const hash = sha256(raw);
    const data = await this.redis.getdel(`rt:${hash}`); // atómico: un token se usa una sola vez
    if (!data) {
      const reusedFamily = await this.redis.get(`rt:used:${hash}`);
      if (reusedFamily) await this.revokeFamily(reusedFamily); // reuso = robo probable
      throw new UnauthorizedException('Sesión inválida');
    }
    const { userId, familyId } = JSON.parse(data) as { userId: string; familyId: string };
    await this.redis.set(`rt:used:${hash}`, familyId, 'EX', TTL);
    return { userId, refreshToken: await this.issue(userId, familyId) };
  }

  async revokeFamily(familyId: string): Promise<void> {
    const hashes = await this.redis.smembers(`rt:family:${familyId}`);
    const tx = this.redis.multi().del(`rt:family:${familyId}`);
    for (const h of hashes) tx.del(`rt:${h}`);
    await tx.exec();
  }

  // Al cambiar contraseña o al "cerrar todas las sesiones"
  async revokeAllForUser(userId: string): Promise<void> {
    const families = await this.redis.smembers(`rt:user:${userId}`);
    for (const f of families) await this.revokeFamily(f);
    await this.redis.del(`rt:user:${userId}`);
  }
}
```

`getdel` requiere Redis ≥ 6.2. Redis con `requirepass` y sin exponer el puerto fuera de la red interna.

Cookie del refresh:

```ts
res.cookie('refresh_token', refreshToken, {
  httpOnly: true,
  secure: true,
  sameSite: 'strict',
  path: '/auth/refresh',
  maxAge: 7 * 24 * 60 * 60 * 1000,
});
```

Reset de contraseña: `randomBytes(32)` → enviar el token por correo, guardar solo `sha256(token)`, expira en 60 min, se marca usado al consumirlo, y al cambiar la contraseña se llama a `revokeAllForUser`. La respuesta de "olvidé mi contraseña" es idéntica exista o no el correo.

## 9. Validación y mass assignment

- Todo input entra por un schema Zod (en `packages/shared-types`) convertido con `createZodDto`. Sin schema, no hay endpoint.
- Schemas de entrada con `.strict()`: un campo no declarado es error 400, no se ignora en silencio.
- Nunca `data: dto` ni `...dto` hacia Prisma en updates sensibles; asignar campos explícitos.
- Campos como `role`, `tenantId`, `isAdmin`, `ownerId` jamás vienen del body; salen del JWT o de la lógica del servidor.
- Respuestas: usar `select` explícito en Prisma; nunca devolver `passwordHash`, tokens ni campos internos.

```ts
// packages/shared-types/src/user.ts
import { z } from 'zod';

export const UpdateProfileSchema = z
  .object({
    name: z.string().trim().min(2).max(80),
    phone: z.string().regex(/^\+1(809|829|849)\d{7}$/).optional(),
  })
  .strict();

// apps/api/src/users/dto/update-profile.dto.ts
import { createZodDto } from 'nestjs-zod';
import { UpdateProfileSchema } from '@repo/shared-types';
export class UpdateProfileDto extends createZodDto(UpdateProfileSchema) {}

// en el servicio
await this.prisma.user.update({
  where: { id: user.userId },
  data: { name: dto.name, phone: dto.phone },
  select: { id: true, name: true, phone: true, email: true },
});
```

## 10. SQL injection

- Permitido: métodos de Prisma y `$queryRaw` con template tag (parametriza solo).
- **Prohibido**: `$queryRawUnsafe`, `$executeRawUnsafe` y concatenar strings en SQL.
- `orderBy` o columnas dinámicas: validar contra una lista blanca con `z.enum([...])`.

## 11. Multi-tenant (capa extra que Laravel no trae)

Primera capa: `tenantId` en todo `where` (sección 7). Segunda capa en PostgreSQL con Row Level Security:

```sql
ALTER TABLE "Ticket" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Ticket" FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON "Ticket"
  USING ("tenantId" = current_setting('app.tenant_id', true));
```

```ts
return this.prisma.$transaction(async (tx) => {
  await tx.$executeRaw`SELECT set_config('app.tenant_id', ${tenantId}, true)`;
  return tx.ticket.findMany();
});
```

El usuario de BD de la app no puede ser superusuario (bypassa RLS). Migraciones con un usuario distinto.

## 12. Cifrado de datos sensibles (equivale a Crypt)

```ts
// src/common/crypto/crypto.service.ts
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

@Injectable()
export class CryptoService {
  private readonly key: Buffer;

  constructor(config: ConfigService) {
    this.key = Buffer.from(config.getOrThrow<string>('APP_KEY'), 'base64');
  }

  encrypt(plain: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const enc = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), enc]).toString('base64');
  }

  decrypt(payload: string): string {
    const buf = Buffer.from(payload, 'base64');
    const decipher = createDecipheriv('aes-256-gcm', this.key, buf.subarray(0, 12));
    decipher.setAuthTag(buf.subarray(12, 28));
    return Buffer.concat([decipher.update(buf.subarray(28)), decipher.final()]).toString('utf8');
  }
}
```

Usar para: cédulas, tokens de terceros, API keys de clientes, datos fiscales.

## 13. URLs firmadas (equivale a signedRoute)

```ts
import { createHmac, timingSafeEqual } from 'crypto';

sign(path: string, ttlSeconds: number): string {
  const expires = Math.floor(Date.now() / 1000) + ttlSeconds;
  const sig = createHmac('sha256', this.key).update(`${path}:${expires}`).digest('base64url');
  return `${path}?expires=${expires}&signature=${sig}`;
}

verify(path: string, expires: string, signature: string): boolean {
  if (Number(expires) < Math.floor(Date.now() / 1000)) return false;
  const expected = createHmac('sha256', this.key).update(`${path}:${expires}`).digest();
  const given = Buffer.from(signature, 'base64url');
  return given.length === expected.length && timingSafeEqual(given, expected);
}
```

## 14. Subida de archivos

```ts
@Post('avatar')
@UseInterceptors(FileInterceptor('file', { limits: { fileSize: 2 * 1024 * 1024, files: 1 } }))
upload(
  @UploadedFile(
    new ParseFilePipe({
      validators: [
        new MaxFileSizeValidator({ maxSize: 2 * 1024 * 1024 }),
        new FileTypeValidator({ fileType: /^image\/(png|jpeg|webp)$/ }),
      ],
    }),
  )
  file: Express.Multer.File,
) {}
```

- Nombre del archivo guardado: UUID, nunca el original.
- Guardar fuera de carpetas públicas (MinIO/S3 privado) y servir con URL firmada.
- Jamás ejecutar ni descomprimir archivos subidos sin límites.

## 15. Logs y auditoría

```ts
// AppModule imports
LoggerModule.forRoot({
  pinoHttp: {
    level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
    redact: {
      paths: ['req.headers.authorization', 'req.headers.cookie', '*.password', '*.token', '*.refreshToken'],
      censor: '[REDACTED]',
    },
  },
}),
```

- Auditar acciones sensibles (login, cambio de rol, borrados, exportaciones) en una tabla `AuditLog` con usuario, tenant, acción, recurso, IP y fecha.
- Nunca loguear contraseñas, tokens completos ni datos cifrados en claro.

## 16. Operación

- `pnpm install --frozen-lockfile` en CI, `pnpm audit --prod` como paso obligatorio y Renovate/Dependabot activo.
- `@nestjs/terminus` para `/health` (público, sin datos internos).
- HTTPS obligatorio; HSTS lo pone Helmet.
- Contenedor con usuario no root y `NODE_ENV=production`.

## Checklist de revisión

Reportar cada punto como OK / FALTA / RIESGO:

1. Entorno validado con Zod; app no arranca con secretos débiles.
2. Helmet, `x-powered-by` desactivado, límite de body, `trust proxy` correcto.
3. CORS con lista blanca; nunca `*` con credenciales.
4. `ZodValidationPipe` global; schemas de entrada `.strict()`; cero DTOs nuevos con class-validator.
5. Filtro global que oculta errores 500.
6. Throttler global + límite estricto en endpoints de auth.
7. `JwtAuthGuard` global; cada `@Public()` está justificado.
8. Chequeo de dueño y tenant en todo acceso por id (sin IDOR).
9. argon2id; login resistente a timing; mensajes genéricos.
10. Access token ≤ 15 min; refresh opaco en Redis, rotado con detección de reuso, en cookie httpOnly/Secure/Strict.
11. CSRF cubierto si hay auth por cookies.
12. Sin `$queryRawUnsafe` ni SQL concatenado.
13. Sin mass assignment; respuestas con `select` explícito.
14. RLS activo en tablas multi-tenant; usuario de BD sin superusuario.
15. Datos sensibles cifrados con AES-256-GCM.
16. Archivos validados por tamaño y tipo real, nombres UUID, almacenamiento privado.
17. Logs con redacción; auditoría de acciones sensibles.
18. `pnpm audit --prod` limpio.
