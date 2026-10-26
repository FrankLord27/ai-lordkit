# Seguridad en Aplicación Web

---

## OWASP Top 10 — Las vulnerabilidades más críticas

| #   | Vulnerabilidad             | Prevención principal                                   |
| --- | -------------------------- | ------------------------------------------------------ |
| A01 | Broken Access Control      | Verificar permisos en cada request en el servidor      |
| A02 | Cryptographic Failures     | HTTPS siempre, bcrypt para passwords, no MD5/SHA1      |
| A03 | Injection (SQL, XSS, etc.) | Validar y sanitizar todo input, usar ORMs              |
| A04 | Insecure Design            | Threat modeling desde el diseño                        |
| A05 | Security Misconfiguration  | Helmet, CORS estricto, sin defaults inseguros          |
| A06 | Vulnerable Components      | `pnpm audit` en cada deploy                            |
| A07 | Auth Failures              | bcrypt, JWT corto, rate limiting en auth               |
| A08 | Integrity Failures         | Verificar integridad de dependencias                   |
| A09 | Logging Failures           | Logs de seguridad, alertas en anomalías                |
| A10 | SSRF                       | Validar y restringir URLs externas que el server fetch |

---

## Headers HTTP de seguridad

### Con Helmet en NestJS — configuración completa

```typescript
// main.ts
import helmet from "helmet";

app.use(
  helmet({
    // Previene clickjacking — no permite embeder la app en iframes externos
    frameguard: { action: "deny" },

    // Fuerza HTTPS por 1 año — incluye subdominios
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
      preload: true,
    },

    // Previene MIME type sniffing
    noSniff: true,

    // Deshabilita la cabecera X-Powered-By (no revelar tecnología)
    hidePoweredBy: true,

    // Content Security Policy — controla qué recursos puede cargar la página
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"], // Solo scripts del mismo origen
        styleSrc: ["'self'", "'unsafe-inline'"], // Sass genera estilos inline
        imgSrc: ["'self'", "data:", "https:"],
        connectSrc: ["'self'"], // Solo fetch al mismo origen
        fontSrc: ["'self'"],
        objectSrc: ["'none'"], // Bloquea <object>, <embed>, <applet>
        upgradeInsecureRequests: [], // Fuerza HTTPS en recursos
      },
    },

    // Cross-Origin Resource Policy
    crossOriginResourcePolicy: { policy: "same-site" },
    crossOriginOpenerPolicy: { policy: "same-origin" },
  }),
);
```

### Headers que deberías ver en producción

```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Content-Security-Policy: default-src 'self'; ...
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

---

## CORS — configuración correcta

```typescript
// main.ts — CORS estricto en producción
app.enableCors({
  origin: (origin, callback) => {
    const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(",") ?? [];

    // Permitir requests sin origin solo en desarrollo (Postman, curl)
    if (!origin && process.env.NODE_ENV === "development") {
      return callback(null, true);
    }

    if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS bloqueado para origin: ${origin}`));
    }
  },
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE"],
  allowedHeaders: ["Content-Type", "Authorization"],
  credentials: true, // Necesario para cookies httpOnly
  maxAge: 86400, // Cache del preflight por 24 horas
});
```

```env
# .env
ALLOWED_ORIGINS=https://miapp.com,https://www.miapp.com
```

**Errores comunes de CORS:**

- `origin: '*'` con `credentials: true` — imposible y peligroso. El browser rechaza esto.
- `origin: '*'` — nunca en producción. Permite requests desde cualquier dominio.
- No validar el origin en el servidor — el header `Origin` puede ser falsificado en server-to-server.

---

## Rate Limiting

### En NestJS con @nestjs/throttler

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
        limit: 10, // máximo 10 requests por segundo
      },
      {
        name: "medium",
        ttl: 60000, // 1 minuto
        limit: 100, // máximo 100 requests por minuto
      },
    ]),
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard }, // Global
  ],
})
export class AppModule {}
```

```typescript
// Rate limiting agresivo solo en endpoints de auth
import { Throttle, SkipThrottle } from '@nestjs/throttler';

@Controller('auth')
export class AuthController {

  @Post('login')
  @Throttle({ default: { ttl: 900000, limit: 5 } }) // 5 intentos por 15 min
  async login(@Body() dto: LoginDto) { ... }

  @Post('register')
  @Throttle({ default: { ttl: 3600000, limit: 10 } }) // 10 registros por hora
  async register(@Body() dto: RegisterDto) { ... }

  @Get('me')
  @SkipThrottle() // Endpoint interno frecuente — eximir del throttle global
  async me(@CurrentUser() user: UserPayload) { ... }
}
```

---

## Validación de Input — reglas críticas

### Principio: whitelist, nunca blacklist

```typescript
// ❌ Blacklist — intentas bloquear lo malo. Siempre habrá algo que no bloqueaste.
if (input.includes('<script>')) throw new Error('XSS detectado');

// ✅ Whitelist — defines exactamente qué está permitido. Todo lo demás es rechazado.
@IsString()
@Matches(/^[a-zA-Z0-9\s\-_]+$/, { message: 'Solo letras, números y guiones' })
name: string;
```

### ValidationPipe global en NestJS — ya configurado en main.ts

```typescript
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true, // ← Elimina propiedades no declaradas en el DTO
    forbidNonWhitelisted: true, // ← Error 400 si llegan propiedades extra
    transform: true,
  }),
);
```

### Sanitización de HTML — cuando el input permite HTML

Si el usuario puede enviar HTML (editor de texto enriquecido), nunca confiar en el HTML crudo:

```typescript
// pnpm add dompurify jsdom @types/dompurify
import DOMPurify from "dompurify";
import { JSDOM } from "jsdom";

const window = new JSDOM("").window;
const purify = DOMPurify(window);

// Limpia el HTML — elimina scripts, event handlers, atributos peligrosos
const safeHtml = purify.sanitize(userInput, {
  ALLOWED_TAGS: ["p", "br", "strong", "em", "ul", "ol", "li", "a"],
  ALLOWED_ATTR: ["href"], // Solo href en <a>
  FORBID_ATTR: ["style", "class"], // Sin estilos inline ni clases
});
```

### Longitudes máximas siempre

```typescript
export class CreatePostDto {
  @IsString()
  @MaxLength(100) // Sin límite = vector de DoS
  title: string;

  @IsString()
  @MaxLength(10000)
  content: string;
}
```

---

## XSS — Cross-Site Scripting

### Prevención en el frontend (Next.js)

React escapa automáticamente el contenido en JSX. El riesgo aparece cuando usas:

```tsx
// ❌ Peligroso — ejecuta el HTML sin sanitizar
<div dangerouslySetInnerHTML={{ __html: userContent }} />

// ✅ Correcto — sanitizar antes de insertar
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userContent) }} />

// ✅ Mejor — evitar dangerouslySetInnerHTML cuando sea posible
<p>{userContent}</p>  // React escapa automáticamente
```

### CSP como segunda línea de defensa

El Content-Security-Policy configurado en Helmet bloquea la ejecución de scripts
inline aunque el XSS pase la validación. Es la red de seguridad.

---

## CSRF — Cross-Site Request Forgery

En APIs REST con JWT en `Authorization` header, el CSRF no es un problema
porque el browser no envía el header automáticamente desde otro origen.

El CSRF **sí es un problema** cuando usas cookies para auth:

```typescript
// Si usas cookies httpOnly para el JWT, agrega protección CSRF
// pnpm add @nestjs/csrf csurf

// O usa el patrón Double Submit Cookie:
// 1. Generar token CSRF al login, guardarlo en cookie no-httpOnly
// 2. El frontend lee esa cookie y la envía en header X-CSRF-Token
// 3. El backend valida que el header coincide con la cookie

@Post('login')
async login(@Res({ passthrough: true }) res: Response, @Body() dto: LoginDto) {
  const { accessToken, refreshToken, csrfToken } = await this.authService.login(dto);

  // Refresh token — httpOnly, no accesible desde JS
  res.cookie('refresh_token', refreshToken, {
    httpOnly: true,
    secure: true,
    sameSite: 'strict',
    maxAge: 7 * 24 * 60 * 60 * 1000,
  });

  // CSRF token — accesible desde JS para enviarlo en header
  res.cookie('csrf_token', csrfToken, {
    httpOnly: false,   // ← El frontend necesita leerla
    secure: true,
    sameSite: 'strict',
  });

  return { accessToken };
}
```

**`sameSite: 'strict'`** ya mitiga la mayoría de ataques CSRF modernos.

---

## Upload de archivos — vectores de ataque

```typescript
// Validaciones obligatorias en cualquier endpoint de upload
import { FileInterceptor } from '@nestjs/platform-express';
import { Express } from 'express';

@Post('upload')
@UseInterceptors(FileInterceptor('file', {
  limits: {
    fileSize: 5 * 1024 * 1024,  // 5MB máximo — previene DoS
    files: 1,                    // Un solo archivo por request
  },
  fileFilter: (req, file, callback) => {
    // Whitelist de MIME types permitidos — nunca blacklist
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];

    if (!allowed.includes(file.mimetype)) {
      return callback(
        new BadRequestException('Tipo de archivo no permitido'),
        false,
      );
    }
    callback(null, true);
  },
}))
async uploadFile(@UploadedFile() file: Express.Multer.File) {
  // NUNCA usar el nombre original del archivo
  // El usuario puede enviar: "../../etc/passwd", "malware.exe.jpg"
  const safeFilename = `${randomUUID()}.${this.getExtension(file.mimetype)}`;

  // Verificar el magic number — el MIME type puede ser falsificado
  const isValidImage = await this.verifyImageMagicBytes(file.buffer);
  if (!isValidImage) throw new BadRequestException('Archivo inválido');

  // Guardar en S3/Cloudinary, nunca en el servidor directamente
  return this.storageService.upload(file.buffer, safeFilename);
}

private getExtension(mimetype: string): string {
  const map = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
  return map[mimetype] ?? 'bin';
}
```

---

## Gestión de dependencias

```bash
# Auditar antes de cada deploy
pnpm audit

# Solo vulnerabilidades críticas y altas bloquean el deploy
pnpm audit --audit-level=high

# Ver detalles de una vulnerabilidad específica
pnpm audit --json | jq '.advisories'

# Actualizar dependencias con vulnerabilidades conocidas
pnpm update [paquete]
```

**Política recomendada:**

- Vulnerabilidades **críticas** o **altas**: bloquean el deploy. Se parchean inmediatamente.
- Vulnerabilidades **medias**: se parchean en el siguiente sprint.
- Vulnerabilidades **bajas**: se documentan y se parchean cuando hay actualizaciones disponibles.

---

## Variables de entorno y secrets

```typescript
// ❌ Nunca — hardcodeado en el código
const dbPassword = "mi_password_super_secreto";

// ❌ Nunca — en un archivo commiteado
// config.json: { "jwtSecret": "secreto123" }

// ✅ Variables de entorno validadas con Zod al arrancar
const EnvSchema = z.object({
  JWT_SECRET: z.string().min(32, "Mínimo 32 caracteres"),
  DATABASE_URL: z.string().startsWith("postgresql://"),
  REDIS_PASSWORD: z.string().min(16),
});

// ✅ En producción: usar un secrets manager
// AWS Secrets Manager, HashiCorp Vault, Doppler
```

```bash
# Verificar que no hay secrets commiteados
git log --all --full-history -- '*.env'
git grep -r "password\s*=" --include="*.ts"

# Herramienta de detección de secrets
npx @secretlint/secretlint "**/*"
```

**Si un secret se commitea accidentalmente:**

1. Rotarlo inmediatamente — el secret está comprometido aunque borres el commit.
2. Limpiar el historial de git con `git filter-branch` o BFG.
3. Auditar si fue accedido en el tiempo que estuvo expuesto.
