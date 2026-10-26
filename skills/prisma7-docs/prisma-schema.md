# 02 - Prisma Schema and Migrations (Prisma 7)

## Schema Template

```prisma
generator client {
  provider = "prisma-client"
  output   = "../src/generated/prisma"
}

datasource db {
  provider = "postgresql"
  // url is configured in prisma.config.ts in Prisma 7 (deprecated in schema)
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String?
  role      Role     @default(USER)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  posts     Post[]
  profile   Profile?
  @@index([email])
}

model Post {
  id         Int        @id @default(autoincrement())
  title      String
  content    String?
  published  Boolean    @default(false)
  createdAt  DateTime   @default(now())
  updatedAt  DateTime   @updatedAt
  author     User       @relation(fields: [authorId], references: [id])
  authorId   Int
  categories Category[]
  @@index([authorId])
}

model Profile {
  id     Int     @id @default(autoincrement())
  bio    String?
  user   User    @relation(fields: [userId], references: [id])
  userId Int     @unique
}

model Category {
  id    Int    @id @default(autoincrement())
  name  String @unique
  posts Post[]
}

enum Role { USER ADMIN }
```

## BREAKING CHANGES still relevant in v7 (from v6)

- Bytes fields: use Uint8Array NOT Buffer
- NotFoundError removed: catch PrismaClientKnownRequestError code P2025
- Model names: async, await, using are reserved, cannot be model names
- PostgreSQL fulltext: flag renamed fullTextSearch -> fullTextSearchPostgres

## Field Types

String=TEXT, Int=INTEGER, BigInt=BIGINT, Float=DOUBLE PRECISION, Boolean=BOOLEAN,
DateTime=TIMESTAMP, Json=JSONB, Bytes=BYTEA (Uint8Array in TypeScript)

## Attributes

```prisma
@id @default(autoincrement())  // Auto-increment PK
@default(uuid())               // UUID PK
@default(cuid())               // CUID PK
@default(now())                // Timestamp
@unique                        // Unique
@updatedAt                     // Auto-update
@@index([f1, f2])              // Composite index
@@unique([f1, f2])             // Composite unique
@@map("table_name")            // Custom table name
@map("column_name")            // Custom column name
```

## Relation Patterns

```prisma
// One-to-Many
model User { posts Post[] }
model Post {
  author   User @relation(fields: [authorId], references: [id])
  authorId Int
}

// One-to-One
model User { profile Profile? }
model Profile {
  user   User @relation(fields: [userId], references: [id])
  userId Int  @unique
}

// Many-to-Many Implicit (Prisma manages join table)
model Post { categories Category[] }
model Category { posts Post[] }

// Many-to-Many Explicit
model PostTag {
  post   Post @relation(fields: [postId], references: [id])
  postId Int
  tag    Tag  @relation(fields: [tagId], references: [id])
  tagId  Int
  @@id([postId, tagId])
}
```

## Migration Commands (Prisma 7)

```bash
npx prisma migrate dev --name init   # Dev: create + apply
npx prisma migrate deploy            # Prod: apply pending
npx prisma migrate status            # Check status
npx prisma migrate reset             # Dev only, destructive
npx prisma db push                   # Push without history (prototyping)
npx prisma db pull                   # Pull from existing DB
npx prisma generate                  # Regen client (NOT auto in v7!)
npx prisma db seed                   # Seed (NOT auto in v7!)
npx prisma studio                    # Visual browser

# migrate diff (v7 syntax uses prisma.config.ts)
npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script
```

## Seeding (Prisma 7)

prisma.config.ts configures the seed script path:

```typescript
migrations: {
  seed: "tsx prisma/seed.ts";
}
```

```typescript
// prisma/seed.ts
import "dotenv/config";
import { PrismaClient } from "../src/generated/prisma/client.js";
import { PrismaPg } from "@prisma/adapter-pg";

const prisma = new PrismaClient({
  adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL! }),
});

async function main() {
  await prisma.user.upsert({
    where: { email: "admin@example.com" },
    update: {},
    create: { email: "admin@example.com", name: "Admin", role: "ADMIN" },
  });
}
main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
```

Run: npx prisma db seed
