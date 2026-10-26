# NestJS — CLI y Estructura de Proyecto

## Instalación CLI

```bash
pnpm install -g @nestjs/cli
nest new project-name
nest new project-name --strict   # con TypeScript strict mode
```

## Comandos CLI esenciales

```bash
# Generar recursos completos (CRUD)
nest generate resource cars          # genera módulo + controller + service + DTOs + entities
nest g resource cars --no-spec       # sin archivos de test

# Generar piezas individuales
nest g module cars
nest g controller cars
nest g service cars
nest g guard auth/jwt-auth
nest g interceptor common/logging
nest g filter common/http-exception
nest g pipe common/parse-uuid
nest g decorator common/current-user
nest g middleware common/logger
nest g class cars/dto/create-car     # clase simple

# Aliases
nest g mo / nest g co / nest g s / nest g gu / nest g int / nest g f / nest g pi

# Información del proyecto
nest info       # versiones de NestJS y Node
nest build      # compilar
nest start --watch   # desarrollo con hot reload
```

## Estructura de proyecto recomendada

```
src/
├── main.ts                          # bootstrap de la app
├── app.module.ts                    # módulo raíz
├── app.controller.ts                # health check, root
│
├── auth/                            # módulo de autenticación
│   ├── auth.module.ts
│   ├── auth.controller.ts
│   ├── auth.service.ts
│   ├── strategies/
│   │   ├── jwt.strategy.ts
│   │   └── local.strategy.ts
│   ├── guards/
│   │   ├── jwt-auth.guard.ts
│   │   └── roles.guard.ts
│   └── dto/
│       ├── login.dto.ts
│       └── register.dto.ts
│
├── users/
│   ├── users.module.ts
│   ├── users.controller.ts
│   ├── users.service.ts
│   ├── dto/
│   │   ├── create-user.dto.ts
│   │   └── update-user.dto.ts
│   └── entities/
│       └── user.entity.ts           # Para TypeORM
│
├── cars/
│   ├── cars.module.ts
│   ├── cars.controller.ts
│   ├── cars.service.ts
│   ├── dto/
│   └── entities/
│
├── prisma/                          # Si usas Prisma
│   ├── prisma.module.ts
│   └── prisma.service.ts
│
└── common/                          # Código compartido
    ├── decorators/
    │   ├── current-user.decorator.ts
    │   ├── public.decorator.ts
    │   └── roles.decorator.ts
    ├── filters/
    │   ├── http-exception.filter.ts
    │   └── prisma-exception.filter.ts
    ├── guards/
    ├── interceptors/
    │   ├── logging.interceptor.ts
    │   └── transform.interceptor.ts
    ├── pipes/
    ├── interfaces/
    │   ├── paginated-result.interface.ts
    │   └── jwt-payload.interface.ts
    ├── enums/
    │   └── role.enum.ts
    └── dto/
        └── pagination.dto.ts
```

## tsconfig.json recomendado

```json
{
  "compilerOptions": {
    "module": "commonjs",
    "declaration": true,
    "removeComments": true,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "allowSyntheticDefaultImports": true,
    "target": "ES2021",
    "sourceMap": true,
    "outDir": "./dist",
    "baseUrl": "./",
    "incremental": true,
    "skipLibCheck": true,
    "strictNullChecks": true,
    "noImplicitAny": true,
    "strictBindCallApply": true,
    "forceConsistentCasingInFileNames": true,
    "noFallthroughCasesInSwitch": true,
    "paths": {
      "@/*": ["src/*"]
    }
  }
}
```

## nest-cli.json con Swagger plugin

```json
{
  "$schema": "https://json.schemastore.org/nest-cli",
  "collection": "@nestjs/schematics",
  "sourceRoot": "src",
  "compilerOptions": {
    "deleteOutDir": true,
    "plugins": [
      {
        "name": "@nestjs/swagger",
        "options": {
          "classValidatorShim": true,
          "introspectComments": true
        }
      }
    ]
  }
}
```

## package.json scripts

```json
{
  "scripts": {
    "build": "nest build",
    "start": "node dist/main",
    "start:dev": "nest start --watch",
    "start:debug": "nest start --debug --watch",
    "start:prod": "node dist/main",
    "lint": "eslint \"{src,apps,libs,test}/**/*.ts\"",
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:e2e": "jest --config ./test/jest-e2e.json",
    "prisma:migrate": "prisma migrate dev",
    "prisma:generate": "prisma generate",
    "prisma:seed": "ts-node prisma/seed.ts"
  }
}
```

## Monorepo con Turborepo (estructura apps/)

```
apps/
├── api/          ← NestJS app
│   └── src/
├── web/          ← Next.js app
└── ...
packages/
└── shared-types/ ← DTOs compartidos

# nest-cli.json en apps/api
# El sourceRoot ya está en ./src por defecto
```
