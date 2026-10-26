# Autenticación y Autorización — Seguridad

---

## Contraseñas — almacenamiento correcto

### bcrypt — el estándar para contraseñas

```typescript
// pnpm add bcrypt @types/bcrypt
import * as bcrypt from 'bcrypt';

const SALT_ROUNDS = 12; // ← Mínimo 12 en producción. 10 es para desarrollo.
                         // Cada incremento duplica el tiempo de cómputo.
                         // 12 = ~300ms por hash. Suficiente para ser lento
                         // para atacantes y aceptable para usuarios.

// Al registrar
async hashPassword(plaintext: string): Promise<string> {
  return bcrypt.hash(plaintext, SALT_ROUNDS);
}

// Al verificar login
async verifyPassword(plaintext: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plaintext, hash);
}
```

### Comparación de tiempo constante — prevenir timing attacks

```typescript
// ❌ Vulnerable a timing attack — la comparación corta en el primer mismatch
if (hash === storedHash) { ... }

// ✅ bcrypt.compare ya usa comparación de tiempo constante internamente
const isValid = await bcrypt.compare(plaintext, storedHash);

// Si necesitas comparar strings directamente
import { timingSafeEqual } from 'crypto';
const isEqual = timingSafeEqual(
  Buffer.from(inputToken),
  Buffer.from(storedToken),
);
```

### Política de contraseñas robusta

```typescript
// packages/shared-types/src/schemas/auth.schema.ts
export const PasswordSchema = z
  .string()
  .min(8, "Mínimo 8 caracteres")
  .max(72, "Máximo 72 caracteres") // ← bcrypt trunca a 72 bytes
  .regex(/[A-Z]/, "Al menos una mayúscula")
  .regex(/[a-z]/, "Al menos una minúscula")
  .regex(/[0-9]/, "Al menos un número")
  .regex(/[^A-Za-z0-9]/, "Al menos un caracter especial");
```

**Nunca almacenar:**

- Contraseña en texto plano
- MD5 o SHA1 del password (reversible con rainbow tables)
- SHA256 o SHA512 sin salt (vulnerable a rainbow tables)

---

## JWT — implementación segura completa

### Estructura de tokens

```
Access Token:  vida corta (15 minutos), viaja en header Authorization
Refresh Token: vida larga (7 días), viaja en cookie httpOnly, guardado en Redis
```

### Generación de tokens

```typescript
// modules/auth/auth.service.ts
import { JwtService } from "@nestjs/jwt";
import { randomBytes } from "crypto";

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly redisService: RedisService,
  ) {}

  async generateTokens(user: User) {
    const payload = {
      sub: user.id, // Subject — ID del usuario
      email: user.email,
      role: user.role,
      // ← NO incluir datos sensibles: password hash, datos bancarios, etc.
    };

    const accessToken = this.jwtService.sign(payload, {
      secret: process.env.JWT_SECRET,
      expiresIn: "15m",
      algorithm: "HS256",
    });

    // Refresh token: string aleatorio opaco, no JWT
    // Si es JWT, alguien con el secret puede forjarlo.
    // Un string aleatorio solo existe si está en Redis.
    const refreshToken = randomBytes(64).toString("hex");

    // Guardar en Redis con TTL
    await this.redisService.set(
      `refresh:${user.id}:${refreshToken}`,
      user.id,
      7 * 24 * 60 * 60, // 7 días
    );

    return { accessToken, refreshToken };
  }

  async refreshAccessToken(refreshToken: string, userId: string) {
    const key = `refresh:${userId}:${refreshToken}`;
    const storedUserId = await this.redisService.get(key);

    if (!storedUserId || storedUserId !== userId) {
      throw new UnauthorizedException("Refresh token inválido o expirado");
    }

    // Rotación: invalidar el token usado, generar uno nuevo
    // Si alguien roba el refresh token y lo usa, el usuario legítimo
    // recibirá un error en su próximo refresh — señal de compromiso.
    await this.redisService.del(key);

    const user = await this.usersService.findById(userId);
    return this.generateTokens(user);
  }

  async logout(refreshToken: string, userId: string) {
    await this.redisService.del(`refresh:${userId}:${refreshToken}`);
  }

  async logoutAllSessions(userId: string) {
    // Invalida TODOS los refresh tokens del usuario
    await this.redisService.delByPattern(`refresh:${userId}:*`);
  }
}
```

### Envío de tokens al cliente

```typescript
@Post('login')
async login(
  @Body() dto: LoginDto,
  @Res({ passthrough: true }) res: Response,
) {
  const { accessToken, refreshToken } = await this.authService.login(dto);

  // Refresh token en cookie httpOnly — no accesible desde JavaScript
  res.cookie('refresh_token', refreshToken, {
    httpOnly: true,      // ← JS no puede leerla. Previene robo por XSS.
    secure: true,        // ← Solo se envía por HTTPS
    sameSite: 'strict',  // ← No se envía en requests cross-site. Previene CSRF.
    maxAge: 7 * 24 * 60 * 60 * 1000, // 7 días en ms
    path: '/api/v1/auth', // ← La cookie solo se envía a rutas de auth
  });

  // Access token en el body — el cliente lo guarda en memoria (no localStorage)
  return { accessToken };
}
```

### Almacenamiento del access token en el frontend

```typescript
// ❌ Nunca en localStorage — vulnerable a XSS
localStorage.setItem("token", accessToken);

// ❌ Nunca en sessionStorage — también vulnerable a XSS
sessionStorage.setItem("token", accessToken);

// ✅ En memoria — desaparece al refrescar la página
// Se mantiene en el store de Zustand (sin persist)
export const useAuthStore = create<AuthStore>((set) => ({
  accessToken: null, // ← Sin persist middleware
  setToken: (token) => set({ accessToken: token }),
  clearToken: () => set({ accessToken: null }),
}));

// Al iniciar la app: intentar refrescar con la cookie httpOnly
// Si la cookie existe y es válida, se obtiene un nuevo access token
// Si no, el usuario está deslogueado.
```

### Interceptor de refresh automático en el frontend

```typescript
// lib/api-client.ts — manejo automático de token expirado
async function apiFetch<T>(
  endpoint: string,
  options?: RequestInit,
): Promise<T> {
  const token = useAuthStore.getState().accessToken;

  const response = await fetch(`${BASE_URL}${endpoint}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options?.headers,
    },
    credentials: "include",
  });

  // Si el token expiró, intentar refresh automático
  if (response.status === 401 && !endpoint.includes("/auth/")) {
    const refreshed = await tryRefreshToken();
    if (refreshed) {
      // Reintentar la request original con el nuevo token
      return apiFetch<T>(endpoint, options);
    }
    // Si el refresh falla, desloguear al usuario
    useAuthStore.getState().clearToken();
    window.location.href = "/login";
  }

  if (!response.ok) {
    const error = await response.json();
    throw new ApiClientError(error.message, error.statusCode);
  }

  return response.json();
}
```

---

## Roles y Permisos — RBAC

```typescript
// common/decorators/roles.decorator.ts
import { SetMetadata } from "@nestjs/common";

export enum Role {
  USER = "user",
  MODERATOR = "moderator",
  ADMIN = "admin",
}

export const Roles = (...roles: Role[]) => SetMetadata("roles", roles);
```

```typescript
// common/guards/roles.guard.ts
import { Injectable, CanActivate, ExecutionContext } from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import { Role } from "../decorators/roles.decorator";

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>("roles", [
      context.getHandler(),
      context.getClass(),
    ]);

    if (!requiredRoles) return true; // Sin roles definidos = cualquiera puede acceder

    const { user } = context.switchToHttp().getRequest();
    return requiredRoles.includes(user.role);
  }
}
```

```typescript
// Uso en controller
@Delete(':id')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN)            // ← Solo admins
async deleteItem(@Param('id') id: string) { ... }

@Patch(':id')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN, Role.MODERATOR)  // ← Admins y moderadores
async updateItem(@Param('id') id: string, @Body() dto: UpdateItemDto) { ... }
```

### Verificación de propiedad de recursos

```typescript
// No basta con estar autenticado — verificar que el recurso pertenece al usuario

@Get(':id')
@UseGuards(JwtAuthGuard)
async getItem(@Param('id') id: string, @CurrentUser() user: UserPayload) {
  const item = await this.itemsService.findById(id);

  if (!item) throw new NotFoundException('Item no encontrado');

  // ← Verificar propiedad. Sin esto, cualquier usuario autenticado
  // puede ver items de otros usuarios (Broken Access Control - OWASP A01)
  if (item.userId !== user.sub && user.role !== Role.ADMIN) {
    throw new ForbiddenException('No tienes acceso a este recurso');
  }

  return item;
}
```

---

## Ataques comunes contra auth — cómo prevenirlos

### Brute Force

```typescript
// Rate limiting agresivo en endpoints de auth — ver web-security.md
// Además: bloqueo progresivo por IP

@Post('login')
@Throttle({ default: { ttl: 900000, limit: 5 } }) // 5 intentos / 15 min
async login(@Body() dto: LoginDto, @Ip() ip: string) {
  // Registrar intento fallido en Redis para auditoría
  const attempts = await this.redisService.get(`login_attempts:${ip}`);
  if (Number(attempts) >= 5) {
    await this.securityService.notifyAdminOfSuspiciousActivity(ip);
  }
}
```

### Credential Stuffing

Ataques con listas de emails/passwords de otros breaches.

```typescript
// Prevención:
// 1. Rate limiting (ya cubierto)
// 2. Verificar passwords contra Have I Been Pwned
import { checkPwnedPassword } from '@xfbs/hibp';

async register(dto: RegisterDto) {
  const isPwned = await checkPwnedPassword(dto.password);
  if (isPwned > 0) {
    throw new BadRequestException(
      'Esta contraseña aparece en brechas de datos conocidas. Elige otra.',
    );
  }
  // ...
}
```

### Account Enumeration

```typescript
// ❌ Revela si el email existe
if (!user) throw new NotFoundException("Usuario no encontrado");
if (!validPassword) throw new UnauthorizedException("Contraseña incorrecta");

// ✅ Mismo mensaje siempre — el atacante no sabe cuál de los dos falló
if (!user || !(await bcrypt.compare(dto.password, user.password))) {
  // Importante: si el usuario no existe, igual ejecutar bcrypt.compare
  // contra un hash falso para que el timing sea idéntico
  if (!user)
    await bcrypt.compare(dto.password, "$2b$12$fakehashfortimingttttttt");
  throw new UnauthorizedException("Credenciales incorrectas");
}
```

### JWT Algorithm Confusion

```typescript
// ❌ Vulnerable — acepta cualquier algoritmo
jwt.verify(token, secret); // Un atacante puede cambiar el algoritmo a 'none'

// ✅ Siempre especificar el algoritmo explícitamente
this.jwtService.verify(token, {
  secret: process.env.JWT_SECRET,
  algorithms: ["HS256"], // ← Solo acepta este algoritmo
});
```

---

## Multi-Factor Authentication (MFA) — implementación básica

```typescript
// pnpm add speakeasy qrcode @types/speakeasy @types/qrcode
import * as speakeasy from "speakeasy";
import * as QRCode from "qrcode";

@Injectable()
export class MfaService {
  // 1. Generar secret y QR para el usuario
  async setupMfa(userId: string, userEmail: string) {
    const secret = speakeasy.generateSecret({
      name: `MiApp (${userEmail})`,
      length: 32,
    });

    // Guardar el secret en DB (cifrado) — aún no activado
    await this.usersService.saveMfaSecret(userId, secret.base32, false);

    // QR para escanear con Google Authenticator / Authy
    const qrDataUrl = await QRCode.toDataURL(secret.otpauth_url);
    return { qrDataUrl, backupCode: secret.base32 };
  }

  // 2. Verificar el código TOTP del usuario
  async verifyTotp(userId: string, token: string): Promise<boolean> {
    const user = await this.usersService.findById(userId);
    if (!user.mfaSecret) return false;

    return speakeasy.totp.verify({
      secret: user.mfaSecret,
      encoding: "base32",
      token,
      window: 1, // ← Acepta el token del período anterior y siguiente
    });
  }
}
```
