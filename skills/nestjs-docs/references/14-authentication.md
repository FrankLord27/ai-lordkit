# NestJS — Authentication (JWT)

**Fuente:** https://docs.nestjs.com/security/authentication

## Instalación

```bash
pnpm add @nestjs/jwt @nestjs/passport passport passport-jwt bcrypt
pnpm add -D @types/passport-jwt @types/bcrypt
```

## Estructura recomendada

```
src/auth/
├── auth.module.ts
├── auth.controller.ts
├── auth.service.ts
├── guards/
│   ├── jwt-auth.guard.ts
│   └── local-auth.guard.ts
├── strategies/
│   └── jwt.strategy.ts
└── dto/
    ├── sign-in.dto.ts
    └── sign-up.dto.ts
```

## AuthModule

```typescript
import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { ConfigModule, ConfigService } from "@nestjs/config";
import { AuthService } from "./auth.service";
import { AuthController } from "./auth.controller";
import { JwtStrategy } from "./strategies/jwt.strategy";
import { UsersModule } from "../users/users.module";

@Module({
  imports: [
    UsersModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>("JWT_SECRET"),
        signOptions: { expiresIn: config.get("JWT_EXPIRES_IN", "15m") },
      }),
      inject: [ConfigService],
    }),
  ],
  providers: [AuthService, JwtStrategy],
  controllers: [AuthController],
  exports: [AuthService, JwtModule],
})
export class AuthModule {}
```

## AuthService

```typescript
import { Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { UsersService } from "../users/users.service";
import * as bcrypt from "bcrypt";

@Injectable()
export class AuthService {
  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
  ) {}

  async signUp(email: string, password: string) {
    const hashedPassword = await bcrypt.hash(password, 10);
    return this.usersService.create({ email, password: hashedPassword });
  }

  async signIn(email: string, password: string) {
    const user = await this.usersService.findByEmail(email);
    if (!user) throw new UnauthorizedException("Invalid credentials");

    const passwordMatch = await bcrypt.compare(password, user.password);
    if (!passwordMatch) throw new UnauthorizedException("Invalid credentials");

    const payload = { sub: user.id, email: user.email, role: user.role };
    return {
      access_token: await this.jwtService.signAsync(payload),
      user: { id: user.id, email: user.email },
    };
  }

  async verifyToken(token: string) {
    return this.jwtService.verifyAsync(token);
  }
}
```

## JwtAuthGuard (sin Passport — patrón oficial NestJS 10+)

```typescript
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
} from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { ConfigService } from "@nestjs/config";
import { Reflector } from "@nestjs/core";
import { IS_PUBLIC_KEY } from "../decorators/public.decorator";

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private jwtService: JwtService,
    private configService: ConfigService,
    private reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    // Rutas públicas
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest();
    const token = this.extractTokenFromHeader(request);
    if (!token) throw new UnauthorizedException("Token not found");

    try {
      const payload = await this.jwtService.verifyAsync(token, {
        secret: this.configService.get("JWT_SECRET"),
      });
      request["user"] = payload;
    } catch {
      throw new UnauthorizedException("Invalid or expired token");
    }
    return true;
  }

  private extractTokenFromHeader(request: any): string | undefined {
    const [type, token] = request.headers.authorization?.split(" ") ?? [];
    return type === "Bearer" ? token : undefined;
  }
}
```

## JwtStrategy (con Passport)

```typescript
import { Injectable } from "@nestjs/common";
import { PassportStrategy } from "@nestjs/passport";
import { ExtractJwt, Strategy } from "passport-jwt";
import { ConfigService } from "@nestjs/config";

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(configService: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: configService.get<string>("JWT_SECRET"),
    });
  }

  async validate(payload: { sub: string; email: string; role: string }) {
    return { id: payload.sub, email: payload.email, role: payload.role };
  }
}
```

## AuthController

```typescript
@Controller("auth")
export class AuthController {
  constructor(private authService: AuthService) {}

  @Public()
  @Post("register")
  signUp(@Body() dto: SignUpDto) {
    return this.authService.signUp(dto.email, dto.password);
  }

  @Public()
  @Post("login")
  @HttpCode(HttpStatus.OK)
  signIn(@Body() dto: SignInDto) {
    return this.authService.signIn(dto.email, dto.password);
  }

  @Get("profile")
  getProfile(@CurrentUser() user: JwtPayload) {
    return user;
  }
}
```

## Guard global (app.module.ts)

```typescript
import { APP_GUARD } from "@nestjs/core";

@Module({
  providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }],
})
export class AppModule {}
```

## Decoradores de utilidad

```typescript
// public.decorator.ts
export const IS_PUBLIC_KEY = "isPublic";
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

// current-user.decorator.ts
export const CurrentUser = createParamDecorator(
  (field: string | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    return field ? request.user?.[field] : request.user;
  },
);
```

## Refresh tokens (patrón)

```typescript
async refreshTokens(userId: string, refreshToken: string) {
  const user = await this.usersService.findById(userId);
  if (!user?.refreshToken) throw new ForbiddenException();

  const tokenMatch = await bcrypt.compare(refreshToken, user.refreshToken);
  if (!tokenMatch) throw new ForbiddenException();

  const tokens = await this.generateTokens(user.id, user.email);
  await this.updateRefreshToken(user.id, tokens.refresh_token);
  return tokens;
}

private async generateTokens(userId: string, email: string) {
  const [access_token, refresh_token] = await Promise.all([
    this.jwtService.signAsync(
      { sub: userId, email },
      { secret: this.configService.get('JWT_SECRET'), expiresIn: '15m' }
    ),
    this.jwtService.signAsync(
      { sub: userId, email },
      { secret: this.configService.get('JWT_REFRESH_SECRET'), expiresIn: '7d' }
    ),
  ]);
  return { access_token, refresh_token };
}
```
