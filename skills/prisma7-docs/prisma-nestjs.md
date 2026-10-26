# 03 - PrismaService and NestJS Integration (Prisma 7)

## PrismaService (Prisma 7 — driver adapter REQUIRED, no default TCP connection)

```typescript
// src/prisma/prisma.service.ts
import { Injectable, OnModuleInit, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient } from "../generated/prisma/client.js";
import { PrismaPg } from "@prisma/adapter-pg";

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor() {
    const adapter = new PrismaPg({
      connectionString: process.env.DATABASE_URL as string,
    });
    super({ adapter }); // adapter is REQUIRED in Prisma 7
  }

  async onModuleInit() {
    await this.$connect();
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

WRONG (v5/v6 patterns — DO NOT USE in Prisma 7):

```typescript
import { PrismaClient } from "@prisma/client"; // ❌ wrong import
const prisma = new PrismaClient(); // ❌ no adapter = error in v7
```

## PrismaService - Legacy (prisma-client-js — deprecated in v7, still works temporarily)

```typescript
// src/prisma/prisma.service.ts
import { Injectable, OnModuleInit } from "@nestjs/common";
import { PrismaClient } from "@prisma/client";

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  async onModuleInit() {
    await this.$connect();
  }
}
```

## PrismaModule (@Global - import once in AppModule)

```typescript
// src/prisma/prisma.module.ts
import { Global, Module } from "@nestjs/common";
import { PrismaService } from "./prisma.service.js";

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

## AppModule

```typescript
// src/app.module.ts
import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { PrismaModule } from "./prisma/prisma.module.js";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule, // Only once due to @Global()
    // ...feature modules
  ],
})
export class AppModule {}
```

## Feature Module (no need to import PrismaModule again)

```typescript
// src/users/users.module.ts
import { Module } from "@nestjs/common";
import { UsersService } from "./users.service.js";
import { UsersController } from "./users.controller.js";

@Module({
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
```

## Using PrismaService in Feature Service

```typescript
// src/users/users.service.ts
import { Injectable } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service.js";
import { User, Prisma } from "../generated/prisma/client.js";

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(): Promise<User[]> {
    return this.prisma.user.findMany();
  }
}
```

## Error Handling - Prisma v6

v6 REMOVED NotFoundError. Use PrismaClientKnownRequestError:

```typescript
import { Prisma } from '../generated/prisma/client.js';
import { NotFoundException, ConflictException } from '@nestjs/common';

// Handle not found (code P2025)
async findOne(id: number): Promise<User> {
  try {
    return await this.prisma.user.findUniqueOrThrow({ where: { id } });
  } catch (error) {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === 'P2025'
    ) {
      throw new NotFoundException(`User ${id} not found`);
    }
    throw error;
  }
}

// Handle duplicate (code P2002)
async create(data: Prisma.UserCreateInput): Promise<User> {
  try {
    return await this.prisma.user.create({ data });
  } catch (error) {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === 'P2002'
    ) {
      throw new ConflictException('Email already exists');
    }
    throw error;
  }
}
```

## Common Error Codes

P2002 - Unique constraint violation
P2003 - Foreign key constraint violation
P2025 - Record not found (replaces removed NotFoundError in v6/v7)
P2016 - Query interpretation error
P2000 - Value too long

## PRISMA 7: Client Middleware ($use) REMOVED

$use() middleware is completely removed in Prisma 7. Use $extends() instead:

```typescript
// ❌ REMOVED in Prisma 7 — this will throw an error:
// prisma.$use(async (params, next) => { ... })

// ✅ Use $extends() query extension instead:
const prisma = new PrismaClient({ adapter }).$extends({
  query: {
    user: {
      async findMany({ args, query }) {
        // custom logic here
        return query(args);
      },
    },
  },
});
```

## Prisma Postgres (Cloud) — Different instantiation

For Prisma Postgres cloud (prisma+postgres:// URL), NO adapter. Use accelerateUrl:

```typescript
import { PrismaClient } from "../generated/prisma/client.js";
import { withAccelerate } from "@prisma/extension-accelerate";

const prisma = new PrismaClient({
  accelerateUrl: process.env.DATABASE_URL, // prisma+postgres:// URL
}).$extends(withAccelerate());
```

prisma.config.ts for Prisma Postgres cloud (no adapter needed at CLI level):

```typescript
import "dotenv/config";
import { defineConfig, env } from "prisma/config";
export default defineConfig({
  schema: "prisma/schema.prisma",
  datasource: { url: env("DATABASE_URL") },
});
```
