# 06 - Monorepo (Turborepo) with NestJS + Prisma

## Recommended Structure

```
apps/
  api/
    src/generated/prisma/   <- gitignored
    src/prisma/
      prisma.service.ts
      prisma.module.ts
    prisma/schema.prisma
    package.json

packages/
  database/                 <- Optional shared schema
    prisma/schema.prisma
    src/index.ts
    package.json

turbo.json
package.json
```

## Option A: Prisma per-app (simplest)

Each app owns its schema.prisma. Use the new generator with output path:

```prisma
generator client {
  provider   = "prisma-client"
  output     = "../src/generated/prisma"
  engineType = "client"
}
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
```

## Option B: Shared database package

packages/database/package.json:

```json
{
  "name": "@repo/database",
  "scripts": {
    "generate": "prisma generate",
    "migrate": "prisma migrate dev"
  },
  "dependencies": { "@prisma/adapter-pg": "*", "@prisma/client": "*" },
  "devDependencies": { "prisma": "*" }
}
```

packages/database/src/index.ts:

```typescript
export * from "./generated/prisma/client.js";
```

apps/api/src/prisma/prisma.service.ts (using shared package):

```typescript
import { Injectable } from "@nestjs/common";
import { PrismaClient } from "@repo/database";
import { PrismaPg } from "@prisma/adapter-pg";

@Injectable()
export class PrismaService extends PrismaClient {
  constructor() {
    super({
      adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL! }),
    });
  }
}
```

## turbo.json

```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["generate", "^build"],
      "outputs": ["dist/**", "src/generated/**"]
    },
    "generate": {
      "cache": false,
      "inputs": ["prisma/schema.prisma"]
    },
    "dev": {
      "cache": false,
      "persistent": true,
      "dependsOn": ["generate"]
    }
  }
}
```

## Postinstall Hook (ensures client generated on install)

```json
{
  "scripts": {
    "postinstall": "prisma generate"
  }
}
```

## Common Monorepo Issues

1. Multiple PrismaClient instances: Use @Global() PrismaModule to ensure singleton
2. Missing generated types: Always run generate before build
3. ESM/CJS conflicts: Be consistent with "type": "module" across packages
4. TypeScript path resolution: Each app needs its own tsconfig.json with baseUrl
5. The new prisma-client generator avoids the node_modules conflicts common in monorepos
