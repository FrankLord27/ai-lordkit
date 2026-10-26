# NestJS — Guards

**Fuente:** https://docs.nestjs.com/guards

## Concepto

Un Guard es una clase `@Injectable()` que implementa `CanActivate`. Tienen **una sola responsabilidad**: determinar si una request puede acceder al route handler (autorización/autenticación).

**Se ejecutan:** DESPUÉS de middleware, ANTES de interceptors y pipes.

## Diferencia con Middleware

|                               | Middleware         | Guard                     |
| ----------------------------- | ------------------ | ------------------------- |
| Sabe qué handler se ejecutará | ❌                 | ✅ (via ExecutionContext) |
| Acceso a metadata del handler | ❌                 | ✅ (via Reflector)        |
| Detiene la request            | Solo con res.end() | Retornando false          |

## Guard básico

```typescript
import { Injectable, CanActivate, ExecutionContext } from "@nestjs/common";
import { Observable } from "rxjs";

@Injectable()
export class AuthGuard implements CanActivate {
  canActivate(
    context: ExecutionContext,
  ): boolean | Promise<boolean> | Observable<boolean> {
    const request = context.switchToHttp().getRequest();
    return this.validateRequest(request);
  }

  private validateRequest(request: any): boolean {
    return !!request.user; // ejemplo simple
  }
}
```

## ExecutionContext

```typescript
canActivate(context: ExecutionContext): boolean {
  // HTTP
  const request = context.switchToHttp().getRequest<Request>();
  const response = context.switchToHttp().getResponse<Response>();

  // Información del handler
  const handler = context.getHandler();   // método del controller
  const className = context.getClass();   // clase del controller
  const type = context.getType();         // 'http' | 'ws' | 'rpc'

  return true;
}
```

## Guard con JWT (patrón real)

```typescript
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
} from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { Request } from "express";

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private jwtService: JwtService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const token = this.extractTokenFromHeader(request);
    if (!token) throw new UnauthorizedException();

    try {
      const payload = await this.jwtService.verifyAsync(token, {
        secret: process.env.JWT_SECRET,
      });
      request["user"] = payload; // attach al request
    } catch {
      throw new UnauthorizedException();
    }
    return true;
  }

  private extractTokenFromHeader(request: Request): string | undefined {
    const [type, token] = request.headers.authorization?.split(" ") ?? [];
    return type === "Bearer" ? token : undefined;
  }
}
```

## Role-based Guard con Reflector y Metadata

```typescript
// roles.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const Roles = (...roles: string[]) => SetMetadata('roles', roles);

// roles.guard.ts
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<string[]>('roles', [
      context.getHandler(),   // metadata del método
      context.getClass(),     // metadata del controller
    ]);

    if (!requiredRoles) return true; // sin restricción = acceso libre

    const { user } = context.switchToHttp().getRequest();
    return requiredRoles.some(role => user?.roles?.includes(role));
  }
}

// controller:
@Roles('admin')
@Get('admin-only')
adminRoute() {}
```

## Binding Guards

```typescript
// En método
@UseGuards(AuthGuard)
@Get('profile')
getProfile() {}

// En controller (aplica a todos los métodos)
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('cats')
export class CatsController {}

// Global (main.ts) — sin DI support
app.useGlobalGuards(new AuthGuard());

// Global con DI support (app.module.ts) — RECOMENDADO
@Module({
  providers: [
    {
      provide: APP_GUARD,
      useClass: JwtAuthGuard,
    },
  ],
})
export class AppModule {}
```

## Rutas públicas (saltarse guard global)

```typescript
// public.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

// jwt-auth.guard.ts
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private jwtService: JwtService,
    private reflector: Reflector,
  ) {}

  canActivate(context: ExecutionContext): boolean | Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true; // saltarse verificación

    return this.validateJwt(context);
  }
}

// En controller:
@Public()
@Post('login')
signIn(@Body() signInDto: SignInDto) {}
```

## Cuándo lanza ForbiddenException vs UnauthorizedException

```typescript
// Guard retorna false → Nest lanza automáticamente ForbiddenException (403)
// Para 401 (no autenticado) → lanzar UnauthorizedException explícitamente
throw new UnauthorizedException("Token missing or invalid");
```
