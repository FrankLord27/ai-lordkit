---
name: typescript-docs
description: >
  Referencia completa de TypeScript en modo strict para desarrollo fullstack con
  NestJS y Next.js. Úsala cuando trabajes con: tipos avanzados (generics, conditional
  types, mapped types, template literal types), utility types (Partial, Required,
  Pick, Omit, ReturnType, Awaited), decoradores, declaration files, configuración
  de tsconfig.json, module augmentation, type guards, discriminated unions, o cuando
  necesites tipar correctamente DTOs, entidades de dominio, respuestas de API,
  estados de Zustand o queries de TanStack Query. También activa cuando el compilador
  dé errores de tipos que no sean evidentes.
---

# TypeScript — Referencia Completa (Strict Mode)

## Documentación oficial (Context7)

Para la doc oficial y actualizada de TypeScript, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

## Configuración obligatoria (tsconfig.json)

```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true
  }
}
```

## Utility types más usados en el stack

```typescript
// Partial — todos los campos opcionales (para DTOs de update)
type UpdateUserDto = Partial<User>;

// Pick — solo ciertos campos
type UserPublic = Pick<User, "id" | "name" | "email">;

// Omit — excluir campos
type UserWithoutPassword = Omit<User, "password">;

// ReturnType — extraer tipo de retorno
type QueryResult = ReturnType<typeof findUser>;

// Awaited — desenvolver Promise
type ResolvedUser = Awaited<ReturnType<typeof fetchUser>>;

// Record — objeto con claves tipadas
type RolePermissions = Record<Role, Permission[]>;
```

## Reglas no negociables

- **`any` está prohibido** — usar `unknown` + type guard, o definir el tipo correcto
- **`as Tipo`** solo cuando sea absolutamente necesario y con comentario de por qué
- **`!` non-null assertion** evitar — mejor narrowing o optional chaining
- **Discriminated unions** para modelar estados: `{ status: 'success', data: T } | { status: 'error', error: string }`
- **`satisfies`** para validar tipos sin widening: `const config = { ... } satisfies Config`
