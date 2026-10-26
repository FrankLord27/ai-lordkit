# NestJS — Custom Decorators

**Fuente:** https://docs.nestjs.com/custom-decorators

## Crear decorador de parámetro (User decorator)

```typescript
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const CurrentUser = createParamDecorator(
  (data: unknown, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    return request.user;
  },
);

// Uso en controller:
@Get('profile')
getProfile(@CurrentUser() user: User) {
  return user;
}
```

## Decorador con parámetro

```typescript
export const CurrentUser = createParamDecorator(
  (field: string | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user;
    return field ? user?.[field] : user;
  },
);

// Uso:
@Get('profile')
getProfile(@CurrentUser() user: User) {}            // objeto completo

@Get('name')
getName(@CurrentUser('name') name: string) {}      // solo el campo name
```

## Decorador con Pipes

```typescript
@Get()
async findOne(@User(new ValidationPipe()) userEntity: UserEntity) {}
```

## SetMetadata para guards y reflector

```typescript
import { SetMetadata } from '@nestjs/common';

// Simple
export const Roles = (...roles: string[]) => SetMetadata('roles', roles);
export const Public = () => SetMetadata('isPublic', true);

// Con tipado fuerte
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

// Uso:
@Roles('admin', 'superadmin')
@Post()
create() {}
```

## Leer metadata con Reflector

```typescript
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    // Lee del método, luego del controller (jerarquía)
    const roles = this.reflector.getAllAndOverride<string[]>("roles", [
      context.getHandler(),
      context.getClass(),
    ]);

    // Merge de ambos (método + controller)
    const allRoles = this.reflector.getAllAndMerge<string[]>("roles", [
      context.getHandler(),
      context.getClass(),
    ]);

    if (!roles) return true;
    const { user } = context.switchToHttp().getRequest();
    return roles.some((role) => user.roles?.includes(role));
  }
}
```

## Componer decoradores

```typescript
import { applyDecorators } from '@nestjs/common';

export function Auth(...roles: string[]) {
  return applyDecorators(
    SetMetadata('roles', roles),
    UseGuards(JwtAuthGuard, RolesGuard),
    ApiBearerAuth(),         // swagger
    ApiUnauthorizedResponse({ description: 'Unauthorized' }),
  );
}

// Uso:
@Auth('admin')
@Delete(':id')
remove(@Param('id') id: string) {}
```

## Decorador de clase (class decorator)

```typescript
export function ApiController(path: string, tag: string) {
  return applyDecorators(
    Controller(path),
    ApiTags(tag),
    UseInterceptors(LoggingInterceptor),
    UseGuards(JwtAuthGuard),
  );
}

// Uso:
@ApiController("users", "Users")
export class UsersController {}
```
