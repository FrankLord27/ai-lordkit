# NestJS — Autenticación y Seguridad

## Stack recomendado

- `@nestjs/passport` + `passport-jwt` — estrategia JWT
- `@nestjs/jwt` — generación/verificación de tokens
- `bcrypt` — hash de contraseñas
- `@nestjs/throttler` — rate limiting
- `helmet` — headers de seguridad

```bash
pnpm add @nestjs/passport @nestjs/jwt passport passport-jwt bcrypt
pnpm add -D @types/passport-jwt @types/bcrypt
pnpm add @nestjs/throttler helmet
```

---

## 1. AuthModule completo

```typescript
// auth/auth.module.ts
import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { PassportModule } from "@nestjs/passport";
import { ConfigModule, ConfigService } from "@nestjs/config";
import { AuthService } from "./auth.service";
import { AuthController } from "./auth.controller";
import { JwtStrategy } from "./strategies/jwt.strategy";
import { UsersModule } from "../users/users.module";

@Module({
  imports: [
    UsersModule,
    PassportModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>("JWT_SECRET"),
        signOptions: { expiresIn: config.get<string>("JWT_EXPIRES_IN", "15m") },
      }),
    }),
  ],
  providers: [AuthService, JwtStrategy],
  controllers: [AuthController],
  exports: [AuthService],
})
export class AuthModule {}
```

---

## 2. JWT Strategy

```typescript
// auth/strategies/jwt.strategy.ts
import { Injectable, UnauthorizedException } from "@nestjs/common";
import { PassportStrategy } from "@nestjs/passport";
import { ExtractJwt, Strategy } from "passport-jwt";
import { ConfigService } from "@nestjs/config";
import { UsersService } from "../../users/users.service";

export interface JwtPayload {
  sub: string; // userId
  email: string;
  roles: string[];
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    private config: ConfigService,
    private usersService: UsersService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>("JWT_SECRET"),
    });
  }

  // El resultado se adjunta a request.user
  async validate(payload: JwtPayload) {
    const user = await this.usersService.findById(payload.sub);
    if (!user) throw new UnauthorizedException();
    return user; // request.user = user
  }
}
```

---

## 3. AuthService

```typescript
// auth/auth.service.ts
import {
  Injectable,
  UnauthorizedException,
  ConflictException,
} from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { UsersService } from "../users/users.service";
import * as bcrypt from "bcrypt";

@Injectable()
export class AuthService {
  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
  ) {}

  async register(email: string, password: string) {
    const existing = await this.usersService.findByEmail(email);
    if (existing) throw new ConflictException("Email already exists");

    const hash = await bcrypt.hash(password, 10);
    const user = await this.usersService.create({ email, password: hash });
    return this.generateTokens(user);
  }

  async login(email: string, password: string) {
    const user = await this.usersService.findByEmail(email);
    if (!user) throw new UnauthorizedException("Invalid credentials");

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) throw new UnauthorizedException("Invalid credentials");

    return this.generateTokens(user);
  }

  private generateTokens(user: { id: string; email: string; roles: string[] }) {
    const payload = { sub: user.id, email: user.email, roles: user.roles };
    return {
      accessToken: this.jwtService.sign(payload),
      user: { id: user.id, email: user.email },
    };
  }
}
```

---

## 4. AuthController

```typescript
// auth/auth.controller.ts
import { Controller, Post, Body, Get, UseGuards } from "@nestjs/common";
import { AuthService } from "./auth.service";
import { RegisterDto } from "./dto/register.dto";
import { LoginDto } from "./dto/login.dto";
import { JwtAuthGuard } from "./guards/jwt-auth.guard";
import { CurrentUser } from "../common/decorators/current-user.decorator";
import { Public } from "../common/decorators/public.decorator";

@Controller("auth")
export class AuthController {
  constructor(private authService: AuthService) {}

  @Public()
  @Post("register")
  register(@Body() dto: RegisterDto) {
    return this.authService.register(dto.email, dto.password);
  }

  @Public()
  @Post("login")
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto.email, dto.password);
  }

  @UseGuards(JwtAuthGuard)
  @Get("me")
  getProfile(@CurrentUser() user: any) {
    return user;
  }
}
```

---

## 5. Guard JWT con soporte @Public()

```typescript
// auth/guards/jwt-auth.guard.ts
import { Injectable, ExecutionContext } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Reflector } from "@nestjs/core";
import { IS_PUBLIC_KEY } from "../../common/decorators/public.decorator";

@Injectable()
export class JwtAuthGuard extends AuthGuard("jwt") {
  constructor(private reflector: Reflector) {
    super();
  }

  canActivate(context: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    return super.canActivate(context);
  }
}
```

---

## 6. Refresh Tokens (patrón con Redis)

```typescript
// En AuthService:
async refreshToken(userId: string, refreshToken: string) {
  const stored = await this.redis.get(`refresh:${userId}`);
  if (!stored || stored !== refreshToken) {
    throw new UnauthorizedException('Invalid refresh token');
  }

  const user = await this.usersService.findById(userId);
  return this.generateTokens(user);
}

private async generateTokens(user: User) {
  const payload = { sub: user.id, email: user.email };
  const accessToken = this.jwtService.sign(payload, { expiresIn: '15m' });
  const refreshToken = this.jwtService.sign(payload, { expiresIn: '7d' });

  // Guardar refresh en Redis
  await this.redis.set(`refresh:${user.id}`, refreshToken, 'EX', 7 * 24 * 3600);

  return { accessToken, refreshToken };
}
```

---

## 7. RBAC (Role-Based Access Control)

```typescript
// enums/role.enum.ts
export enum Role { USER = 'user', ADMIN = 'admin', MODERATOR = 'moderator' }

// decorators/roles.decorator.ts
export const ROLES_KEY = 'roles';
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);

// guards/roles.guard.ts
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!requiredRoles?.length) return true;

    const { user } = context.switchToHttp().getRequest();
    return requiredRoles.some((role) => user.roles?.includes(role));
  }
}

// Uso en controller:
@Roles(Role.ADMIN)
@UseGuards(JwtAuthGuard, RolesGuard)
@Delete(':id')
adminDelete(@Param('id') id: string) { ... }
```

---

## 8. Rate Limiting

```typescript
// app.module.ts
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';

@Module({
  imports: [
    ThrottlerModule.forRoot([
      { ttl: 60000, limit: 100 },  // 100 req/minuto por defecto
    ]),
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}

// Override por endpoint:
@Throttle({ default: { ttl: 60000, limit: 5 } })
@Post('login')
login() { ... }

// Saltar throttle:
@SkipThrottle()
@Get('health')
health() { ... }
```

---

## 9. Helmet + CORS

```typescript
// main.ts
import helmet from "helmet";

app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
      },
    },
  }),
);

app.enableCors({
  origin: [process.env.FRONTEND_URL],
  methods: ["GET", "HEAD", "PUT", "PATCH", "POST", "DELETE"],
  allowedHeaders: ["Content-Type", "Authorization"],
  credentials: true,
});
```

---

## 10. DTOs de autenticación

```typescript
// auth/dto/register.dto.ts
import { IsEmail, IsString, MinLength, MaxLength } from "class-validator";

export class RegisterDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password: string;

  @IsString()
  @MinLength(2)
  name: string;
}

// auth/dto/login.dto.ts
export class LoginDto {
  @IsEmail()
  email: string;

  @IsString()
  password: string;
}
```
