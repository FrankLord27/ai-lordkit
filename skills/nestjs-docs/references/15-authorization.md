# NestJS — Authorization (RBAC / CASL)

**Fuente:** https://docs.nestjs.com/security/authorization

## RBAC básico con decoradores y Reflector

```typescript
// roles.enum.ts
export enum Role {
  USER = "user",
  ADMIN = "admin",
  SUPER_ADMIN = "super_admin",
}

// roles.decorator.ts
import { SetMetadata } from "@nestjs/common";
import { Role } from "./roles.enum";
export const ROLES_KEY = "roles";
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);

// roles.guard.ts
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
    return requiredRoles.some((role) => user?.role === role);
  }
}

// Uso en controller:
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("admin")
export class AdminController {
  @Roles(Role.ADMIN, Role.SUPER_ADMIN)
  @Get("users")
  getAllUsers() {}

  @Roles(Role.SUPER_ADMIN)
  @Delete("users/:id")
  deleteUser() {}
}
```

## CASL (Claims-Based Access Control)

```bash
pnpm add @casl/ability
```

```typescript
// ability.factory.ts
import { Ability, AbilityBuilder, AbilityClass, ExtractSubjectType, InferSubjects } from '@casl/ability';
import { Article } from './article.entity';
import { User } from './user.entity';

type Subjects = InferSubjects<typeof Article | typeof User> | 'all';
export type AppAbility = Ability<[Action, Subjects]>;
export enum Action { Manage = 'manage', Create = 'create', Read = 'read', Update = 'update', Delete = 'delete' }

@Injectable()
export class CaslAbilityFactory {
  createForUser(user: User) {
    const { can, cannot, build } = new AbilityBuilder<AppAbility>(
      Ability as AbilityClass<AppAbility>
    );

    if (user.role === Role.ADMIN) {
      can(Action.Manage, 'all');  // admin puede hacer todo
    } else {
      can(Action.Read, 'all');    // lectura pública
      can(Action.Create, Article);
      can(Action.Update, Article, { authorId: user.id });   // solo sus artículos
      can(Action.Delete, Article, { authorId: user.id });
      cannot(Action.Delete, Article, { published: true });  // no borrar publicados
    }

    return build({
      detectSubjectType: (item) =>
        item.constructor as ExtractSubjectType<Subjects>,
    });
  }
}

// policies.guard.ts
export interface IPolicyHandler {
  handle(ability: AppAbility): boolean;
}

type PolicyHandlerCallback = (ability: AppAbility) => boolean;

export const CHECK_POLICIES_KEY = 'check_policy';
export const CheckPolicies = (...handlers: PolicyHandlerCallback[]) =>
  SetMetadata(CHECK_POLICIES_KEY, handlers);

@Injectable()
export class PoliciesGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private caslAbilityFactory: CaslAbilityFactory,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const policyHandlers = this.reflector.get<PolicyHandlerCallback[]>(
      CHECK_POLICIES_KEY,
      context.getHandler(),
    ) ?? [];

    const { user } = context.switchToHttp().getRequest();
    const ability = this.caslAbilityFactory.createForUser(user);

    return policyHandlers.every(handler => handler(ability));
  }
}

// Uso:
@CheckPolicies(ability => ability.can(Action.Read, Article))
@Get()
findAll() {}
```

## Combinar JWT + Roles en un solo decorador

```typescript
// auth.decorator.ts
import { applyDecorators, UseGuards } from '@nestjs/common';

export function Auth(...roles: Role[]) {
  return applyDecorators(
    roles.length ? Roles(...roles) : (() => {}),
    UseGuards(JwtAuthGuard, RolesGuard),
    ApiBearerAuth(),
    ApiUnauthorizedResponse({ description: 'Unauthorized' }),
    ApiForbiddenResponse({ description: 'Forbidden' }),
  );
}

// Uso limpio:
@Auth(Role.ADMIN)
@Delete(':id')
remove(@Param('id') id: string) {}

@Auth()  // solo autenticado, sin rol específico
@Get('profile')
profile() {}
```

## Guard jerárquico de roles

```typescript
const roleHierarchy = {
  [Role.SUPER_ADMIN]: [Role.ADMIN, Role.USER],
  [Role.ADMIN]: [Role.USER],
  [Role.USER]: [],
};

function hasRole(userRole: Role, requiredRole: Role): boolean {
  if (userRole === requiredRole) return true;
  const inheritance = roleHierarchy[userRole] ?? [];
  return (
    inheritance.includes(requiredRole) ||
    inheritance.some((r) => hasRole(r, requiredRole))
  );
}
```
