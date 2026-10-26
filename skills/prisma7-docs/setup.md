# 01 - Full Project Setup: NestJS + Prisma 7

## Requirements

- Node.js 20.19+ (22.x recommended), TypeScript 5.4+
- MongoDB is NOT supported in Prisma 7

## 1. Create NestJS Project + ESM config

nest new my-app && cd my-app

package.json: { "type": "module" }

tsconfig.json compilerOptions:
"module": "ESNext", "moduleResolution": "bundler", "target": "ES2023"

## 2. Install Dependencies

pnpm add -D prisma@7
pnpm add @prisma/client@7 @prisma/adapter-pg pg dotenv @nestjs/config
pnpm add -D @types/pg

Other adapters: @prisma/adapter-mariadb (MySQL), @prisma/adapter-better-sqlite3 (SQLite)

## 3. Initialize

npx prisma init
Creates: prisma/schema.prisma, prisma.config.ts (at root), .env

## 4. prisma/schema.prisma

generator client {
provider = "prisma-client"
output = "../src/generated/prisma"
}

datasource db {
provider = "postgresql"
// url is now in prisma.config.ts in v7
}

## 5. prisma.config.ts (REQUIRED at project root in Prisma 7)

import 'dotenv/config';
import { defineConfig, env } from 'prisma/config';

export default defineConfig({
schema: 'prisma/schema.prisma',
migrations: {
path: 'prisma/migrations',
seed: 'tsx prisma/seed.ts',
},
datasource: {
url: env('DATABASE_URL'),
},
});

## 6. .env

DATABASE_URL="postgresql://USER:PASSWORD@HOST:5432/DBNAME?schema=public"

## 7. app.module.ts

import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

@Module({
imports: [ConfigModule.forRoot({ isGlobal: true })],
})
export class AppModule {}

## 8. Migrate, Generate, Seed (ALL manual in v7 — none are automatic)

npx prisma migrate dev --name init
npx prisma generate # NOT automatic anymore in v7
npx prisma db seed # NOT automatic anymore in v7

## 9. tsconfig.json — include prisma.config.ts

Add to "include": ["src", "prisma.config.ts"]

## 10. .gitignore

src/generated/
.env

## Project Structure

my-app/
prisma/
schema.prisma
migrations/
seed.ts
src/
generated/prisma/ <- gitignored
prisma/
prisma.service.ts
prisma.module.ts
users/
users.service.ts
users.controller.ts
users.module.ts
prisma.config.ts <- REQUIRED at root, same level as package.json
package.json
tsconfig.json
.env
