# Los 6 chequeos

Se usan en el cierre de bloque (sobre lo que cambió) y como núcleo de la auditoría completa (sobre todo el proyecto). Los `rg` son el punto de partida, no la prueba: cada coincidencia se sigue por el flujo completo (entrada → servicio → BD → respuesta) antes de llamarla hallazgo, y un hallazgo sin coincidencia de grep también cuenta.

### 1. Validación de inputs

Busca toda entrada del usuario: body, query, params, headers que se usan, cookies, archivos, mensajes de WebSocket, server actions.

Es hallazgo:
- Un `@Body()`, `@Query()` o `@Param()` sin schema, tipado como `any`, `object` o un tipo TS sin validador (TS no valida en runtime).
- Falta el pipe global (`APP_PIPE` con `ZodValidationPipe`) o los schemas no son `.strict()`: entran campos extra → mass assignment (`role`, `tenantId`, `isAdmin`).
- Body pasado directo a Prisma (`data: dto` o `data: req.body`) sin elegir campos.
- `$queryRawUnsafe`, SQL o comandos armados con strings del usuario; rutas de archivo con input del usuario (path traversal).
- IDs sin validar formato (`ParseUUIDPipe` o `z.string().uuid()`).
- Strings y arrays sin largo máximo; números sin rango; uploads sin tamaño y tipo real (magic bytes, no la extensión).
- Validación que solo existe en el frontend (el form de React valida, la API no).
- HTML del usuario renderizado sin escapar: `dangerouslySetInnerHTML`, `v-html`, `innerHTML`, plantillas con `|safe`. Validar no es sanitizar: aquí toca escapar o sanitizar según el contexto de salida.
- Webhooks y datos de servicios externos usados sin validar ni verificar firma.

```bash
rg -n "@(Body|Query|Param)\(\)" --glob '*.ts'
rg -n "data:\s*(dto|body|req\.body|input)\b" --glob '*.ts'
rg -n "queryRawUnsafe|executeRawUnsafe|\beval\(|new Function\(|child_process" --glob '*.ts'
rg -n "dangerouslySetInnerHTML|innerHTML" --glob '*.{tsx,ts,jsx}'
```

Arreglo NestJS: `nestjs-security-hardening` secciones 9 y 10 (Zod con `nestjs-zod`, `createZodDto`, `.strict()`, campos explícitos en Prisma). En código legado con class-validator: `ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true })` global; no migres a Zod sin que te lo pidan.
Next.js: cada route handler y cada server action valida con `schema.safeParse()` antes de usar el dato. Una server action es un endpoint POST público aunque no lo parezca.
Otros stacks: el validador de la casa (Pydantic, FormRequest de Laravel, Bean Validation, `go-playground/validator`) en **todas** las entradas, con lista blanca de campos.

### 2. Rate limiting por usuario y por IP

Es hallazgo:
- No hay rate limit global (crítico si hay login público).
- Login, registro, reset de contraseña, OTP, refresh y endpoints que mandan correo/SMS sin límite estricto propio.
- Límite solo por IP (detrás de un NAT de colegio o empresa, 300 usuarios comparten IP y un atacante con varias IPs lo evade) o solo por usuario (no frena fuerza bruta antes del login).
- `trust proxy` mal puesto detrás de Nginx/Cloudflare: todos los requests cuentan como la IP del proxy, o el cliente falsifica `X-Forwarded-For`.
- Varias instancias con storage en memoria: cada instancia cuenta por su lado.
- Búsquedas, exportaciones y reportes pesados con el mismo límite que un GET simple.

```bash
rg -n "ThrottlerModule|@Throttle|SkipThrottle|trust proxy|rateLimit|ratelimit" --glob '*.ts'
```

Arreglo NestJS (`@nestjs/throttler`, verificado con su doc: cada throttler acepta su propio `getTracker`). Dos contadores a la vez, uno por IP y otro por usuario:

```ts
// app.module.ts
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';

interface TrackedRequest {
  ip?: string;
  user?: { sub?: string };
}

ThrottlerModule.forRoot({
  throttlers: [
    { name: 'ip', ttl: 60_000, limit: 120, getTracker: (req: TrackedRequest) => `ip:${req.ip ?? 'unknown'}` },
    {
      name: 'user',
      ttl: 60_000,
      limit: 60,
      getTracker: (req: TrackedRequest) => (req.user?.sub ? `user:${req.user.sub}` : `ip:${req.ip ?? 'unknown'}`),
    },
  ],
  // varias instancias: storage: new ThrottlerStorageRedisService(redis) de @nest-lab/throttler-storage-redis
}),

// providers: el guard de JWT va ANTES que el throttler para que req.user exista
{ provide: APP_GUARD, useClass: JwtAuthGuard },
{ provide: APP_GUARD, useClass: ThrottlerGuard },
```

```ts
// auth.controller.ts: estricto en login (por IP, porque aún no hay usuario)
@Throttle({ ip: { limit: 5, ttl: 60_000 } })
@Public()
@Post('login')
```

Más `app.set('trust proxy', 1)` (o el número real de proxies) en `main.ts`, como en `nestjs-security-hardening` sección 2. Para fuerza bruta contra una cuenta concreta, además un contador por email en Redis con bloqueo temporal.
Next.js: el límite va en el backend. Si los route handlers son la API, usa un limitador con Redis dentro del handler (clave `user:<id>` e `ip:<ip>`), no solo en `proxy.ts`.
Otros stacks: el limitador estándar del framework (Laravel `RateLimiter`, `slowapi`, `rack-attack`) con las dos claves.

Los números de arriba son un punto de partida, no una verdad: ajústalos al uso real (un profesor que pasa lista a 40 estudiantes hace 40 requests seguidos) y anota en el reporte qué límite pusiste, por qué y qué habría que medir. Bloqueos largos por IP permiten a un atacante dejar fuera a todo un colegio: prefiere ventanas cortas por IP y bloqueo por cuenta. El límite por cuenta nunca usa un id que mande el cliente.
Test: requests normales pasan, el que excede recibe 429, y después de la ventana vuelve a pasar.

### 3. Errores que exponen información sensible

Es hallazgo:
- No hay filtro global de excepciones, o devuelve `exception.message`, `stack`, `error.meta` de Prisma, SQL o rutas internas en respuestas 500.
- `catch (e) { return e }`, `res.json(e)`, `throw new HttpException(e.message, 500)`, `throw new BadRequestException(prismaError)`.
- Mensajes que permiten enumerar usuarios: "el correo no existe" vs "contraseña incorrecta"; reset que dice si el correo está registrado.
- Logs con contraseñas, tokens completos, cookies, headers `authorization` o datos personales sin redactar.
- `catch` vacío que se traga el error, o error a mitad de una operación que deja datos a medias (falta transacción).
- Un 403 o 404 que revela que el recurso ajeno existe ("esa factura es de otro colegio").
- Sin id de correlación: el usuario ve "Error interno" y en el log no hay forma de encontrar cuál fue.
- Swagger o páginas de debug abiertas en producción; `NODE_ENV` no es `production` en el deploy.
- Next.js: `error.message` mostrado en `error.tsx`, o datos del servidor (secrets, campos internos) pasados a un Client Component.

```bash
rg -n "\.stack|error\.meta|err\.message|e\.message|exception\.message" --glob '*.{ts,tsx}'
rg -n "@Catch\(|useGlobalFilters|APP_FILTER|SwaggerModule\.setup" --glob '*.ts'
rg -n "NEXT_PUBLIC_.*(SECRET|KEY|TOKEN|PASSWORD)" --glob '*.{ts,tsx}' --glob '.env.example'
```

Arreglo NestJS: `nestjs-security-hardening` sección 3 (filtro global: el 500 dice "Error interno del servidor" y el detalle va al log) y sección 15 (redacción de logs con pino). Errores de Prisma conocidos (`P2002`, `P2025`) se traducen a 409/404 con mensaje propio. Login con mensaje genérico: sección 8.
Otros stacks: el equivalente a `APP_DEBUG=false` y un manejador global que separa lo que se loguea de lo que se responde.

### 4. Tokens y sesiones: sesiones eternas y suplantación

Dos preguntas que el reporte responde con evidencia: **¿un usuario puede quedarse conectado sin querer?** y **¿alguien puede actuar como otro usuario?**

Es hallazgo:
- JWT sin `expiresIn`, o access token de más de 15 minutos; `ignoreExpiration: true`.
- `jwt.decode()` donde debería ir `verify()`; algoritmo sin fijar (`algorithms: ['HS256']` o el que uses); `issuer`/`audience` sin verificar cuando hay más de un servicio; secreto débil o hardcodeado.
- Tokens en la URL (`?token=`), en logs o en mensajes de error.
- Fijación de sesión: el id de sesión no cambia al iniciar sesión (apps con sesiones de servidor).
- Refresh token que no rota, sin detección de reuso, sin TTL, guardado como JWT largo en vez de opaco en Redis.
- Logout que solo borra la cookie en el cliente y deja el refresh vivo en el servidor.
- Cambio de contraseña, cambio de rol o desactivar la cuenta que no revoca las sesiones abiertas.
- "Recordarme" sin límite absoluto de vida, o sin expiración por inactividad en apps sensibles (notas, dinero, datos de menores).
- Tokens en `localStorage`/`sessionStorage` (cualquier XSS los roba); cookies sin `HttpOnly`, `Secure` y `SameSite`.
- **Suplantación**: el `userId`, `tenantId` o `role` se toma del body, query o header en vez del token (`@Body('userId')`, `req.headers['x-user-id']`).
- Acceso por id sin chequear dueño y tenant (IDOR/BOLA), en lectura **y** en escritura y borrado. Acciones de admin que solo esconde el frontend (BFLA). Un usuario que puede cambiarse el rol a sí mismo.
- Auth por cookies sin protección CSRF.

```bash
rg -n "expiresIn|ignoreExpiration|jwt\.decode|algorithms" --glob '*.ts'
rg -n "localStorage|sessionStorage" --glob '*.{ts,tsx}'
rg -n "httpOnly|sameSite|secure:" --glob '*.ts'
rg -n "(body|query|headers)\.?\[?['\"]?(userId|user_id|tenantId|role|x-user-id)" --glob '*.ts'
rg -n "@Body\(['\"](userId|tenantId|role)['\"]\)" --glob '*.ts'
```

Arreglo NestJS: `nestjs-security-hardening` secciones 5 (CSRF), 6 (guard global deny-by-default), 7 (dueño y tenant en el servicio) y 8 (access ≤ 15 min, refresh opaco rotado en Redis con detección de reuso, cookie httpOnly/Secure/Strict, revocar todo al cambiar contraseña). El id del usuario sale **siempre** de `req.user`, nunca del request.
Next.js: sesión verificada en cada route handler, server action y en la capa de acceso a datos, no solo en `proxy.ts` (antes `middleware.ts`): el proxy es un filtro de conveniencia, no la única barrera.
Otros stacks: mismo criterio (expiración corta, rotación, revocación del lado del servidor, identidad sacada de la sesión).
No cambies el mecanismo de auth (sesiones a JWT o al revés) para arreglar un hallazgo: se arregla dentro del mecanismo que hay. Si de verdad hay que cambiarlo, decide el usuario.
Tests: token expirado → 401; refresh usado dos veces → se revoca la familia; después de logout el refresh no sirve; el usuario A pide el recurso de B → 404 y el body no trae datos de B.

### 5. CORS

Es hallazgo:
- `origin: '*'` o `origin: true` (refleja cualquier origen), sobre todo con `credentials: true`: cualquier web puede leer respuestas con la sesión del usuario (crítico).
- Callback que acepta todo (`callback(null, true)`), regex sin anclar (`/miapp\.com/` deja pasar `miapp.com.atacante.do`), `endsWith('miapp.com')` sin el punto, o el origen `null` permitido.
- Orígenes de desarrollo (`localhost`, IPs) activos en producción; lista escrita en el código en vez de salir de la config.
- Métodos y headers permitidos de más (`allowedHeaders: '*'`), o `exposedHeaders` que deja leer headers internos.
- Una ruta o middleware que pisa la política global con otra más abierta.
- Next.js: `Access-Control-Allow-Origin: *` en route handlers o en `next.config` `headers()` para rutas con sesión.

```bash
rg -n "enableCors|cors\(|Access-Control-Allow|origin:" --glob '*.{ts,js,mjs}'
```

Arreglo NestJS: `nestjs-security-hardening` sección 2: lista blanca desde `CORS_ORIGINS` validada con Zod al arrancar, `credentials: true` solo si la auth va en cookies, nunca `*` con credenciales. Si el front y la API comparten dominio, lo más seguro es no habilitar CORS.
Otros stacks: la misma lista blanca exacta (esquema + host + puerto), sin comodines.
CORS no es autenticación: solo controla qué navegador puede leer la respuesta. Un `curl` pasa igual, así que una ruta sin guard sigue abierta aunque el CORS esté perfecto.
Test: preflight desde el origen legítimo → headers correctos; desde `https://evil.example` → sin `Access-Control-Allow-Origin`.

### 6. Rutas de API sin autenticación o sin validación

Con el inventario de rutas, marca cada una:

| Método | Ruta | Archivo:línea | Auth | Autorización (rol + dueño/tenant) | Validación | Rate limit | Estado |
|---|---|---|---|---|---|---|---|

Estado, uno de cuatro:
- **CONTROLES OK**: auth, autorización sobre el recurso y validación presentes y adecuados. No basta con ver el guard: hay que ver el chequeo de dueño y tenant.
- **VULNERABLE**: falla demostrable (va con su hallazgo).
- **REQUIERE REVISIÓN**: faltan datos o pruebas para confirmarlo.
- **PÚBLICO INTENCIONAL**: sin auth por diseño (login, health, contenido público), con su justificación.

No dependas de una sola búsqueda si el framework registra rutas de forma dinámica (`RouterModule`, prefijo global, versionado): arma la ruta completa.

Es hallazgo:
- No hay guard global y alguna ruta no tiene `@UseGuards` (crítico): en NestJS lo seguro es deny-by-default con `@Public()` explícito.
- `@Public()` en una ruta que no es login, registro, reset, health o contenido público, o sin una línea que justifique por qué.
- Ruta con auth pero sin roles, cuando la matriz de permisos de `docs/METODO.md` dice que solo ciertos roles pueden.
- Ruta que recibe datos sin schema (cruza con el chequeo 1).
- Next.js: `app/**/route.ts` que exporta `GET`/`POST`/… sin verificar sesión; archivos con `'use server'` cuyas funciones no verifican sesión ni validan; rutas que el `matcher` del proxy deja fuera.
- Webhooks sin verificar firma; endpoints de debug, seed, admin o diagnóstico olvidados o abiertos.
- Ruta sensible (exporta datos, manda correos, cobra) sin rate limit propio.

```bash
# NestJS
rg -n "@(Get|Post|Put|Patch|Delete|All)\(" --glob '*.controller.ts'
rg -n "@Public\(\)|@UseGuards|APP_GUARD" --glob '*.ts'
# Next.js
rg --files --glob '**/app/**/route.{ts,js}'
rg -ln "^['\"]use server['\"]" --glob '*.{ts,tsx}'
```

Si Swagger está activo, compara: una ruta del código que no está en `/docs` o al revés también es hallazgo.
Arreglo NestJS: `nestjs-security-hardening` secciones 6 y 7. Test e2e por ruta: sin token → 401, rol equivocado → 403, otro tenant → 404.

