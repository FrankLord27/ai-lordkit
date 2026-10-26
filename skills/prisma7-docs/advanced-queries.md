# 05 - Advanced Queries: Relations, Transactions, Raw SQL

## Select with Relations (include / select)

```typescript
// Include: loads full related objects
const user = await this.prisma.user.findUnique({
  where: { id },
  include: {
    posts: true,
    profile: true,
  },
});

// Nested include
const user = await this.prisma.user.findUnique({
  where: { id },
  include: {
    posts: {
      include: { categories: true },
      where: { published: true },
      orderBy: { createdAt: "desc" },
      take: 10,
    },
  },
});

// Select: pick specific fields (more efficient)
const user = await this.prisma.user.findUnique({
  where: { id },
  select: {
    id: true,
    email: true,
    name: true,
    posts: {
      select: { id: true, title: true },
    },
  },
});
```

## Filtering

```typescript
// Basic where
await this.prisma.post.findMany({
  where: {
    published: true,
    authorId: userId,
  },
});

// OR / AND / NOT
await this.prisma.post.findMany({
  where: {
    OR: [
      { title: { contains: search, mode: "insensitive" } },
      { content: { contains: search, mode: "insensitive" } },
    ],
  },
});

// Null check
await this.prisma.user.findMany({ where: { name: { not: null } } });

// Range / comparison
await this.prisma.post.findMany({
  where: {
    createdAt: { gte: startDate, lte: endDate },
  },
});

// In array
await this.prisma.user.findMany({ where: { id: { in: [1, 2, 3] } } });

// Relation filter
await this.prisma.user.findMany({
  where: {
    posts: { some: { published: true } },
  },
});
```

## Ordering and Grouping

```typescript
await this.prisma.post.findMany({
  orderBy: [{ published: "desc" }, { createdAt: "desc" }],
});

// Count related records
const usersWithCount = await this.prisma.user.findMany({
  include: {
    _count: { select: { posts: true } },
  },
});
```

## Transactions

```typescript
// Sequential (interactive) transaction
const result = await this.prisma.$transaction(async (tx) => {
  const user = await tx.user.create({
    data: { email: "new@example.com", name: "New User" },
  });
  const post = await tx.post.create({
    data: { title: "First Post", authorId: user.id },
  });
  return { user, post };
});

// Batch transaction (parallel, more efficient for independent ops)
const [users, posts] = await this.prisma.$transaction([
  this.prisma.user.findMany(),
  this.prisma.post.findMany({ where: { published: true } }),
]);

// Transaction with timeout
await this.prisma.$transaction(
  async (tx) => {
    // ... operations
  },
  {
    maxWait: 5000, // ms to wait to acquire transaction
    timeout: 10000, // ms before transaction times out
  },
);
```

## Raw Queries (TypedSQL recommended over raw string)

```typescript
// $queryRaw - returns typed results
const users = await this.prisma.$queryRaw<User[]>`
  SELECT * FROM "User" WHERE email LIKE ${`%${search}%`}
`;

// $executeRaw - for mutations (UPDATE, DELETE, etc.)
const count = await this.prisma.$executeRaw`
  UPDATE "User" SET "name" = ${name} WHERE "id" = ${id}
`;

// Parameterized queries (safe from SQL injection)
import { Prisma } from "../generated/prisma/client.js";
const result = await this.prisma.$queryRaw(
  Prisma.sql`SELECT * FROM "User" WHERE id = ${id}`,
);
```

## Upsert

```typescript
const user = await this.prisma.user.upsert({
  where: { email: dto.email },
  update: { name: dto.name },
  create: { email: dto.email, name: dto.name },
});
```

## createMany / updateMany / deleteMany

```typescript
// createMany (skipDuplicates available)
await this.prisma.user.createMany({
  data: [{ email: "a@test.com" }, { email: "b@test.com" }],
  skipDuplicates: true,
});

// updateMany
const result = await this.prisma.post.updateMany({
  where: { authorId: userId },
  data: { published: false },
});
// result.count = number of updated records

// deleteMany
await this.prisma.post.deleteMany({
  where: { createdAt: { lt: cutoffDate } },
});
```

## connectOrCreate / connect / disconnect (Relations)

```typescript
// Connect existing related record
await this.prisma.post.create({
  data: {
    title: "Hello",
    author: { connect: { id: authorId } },
    // OR connect by email:
    // author: { connect: { email: authorEmail } },
  },
});

// connectOrCreate
await this.prisma.post.create({
  data: {
    title: "Hello",
    categories: {
      connectOrCreate: {
        where: { name: "Tech" },
        create: { name: "Tech" },
      },
    },
  },
});

// Disconnect from relation (many-to-many)
await this.prisma.post.update({
  where: { id: postId },
  data: {
    categories: { disconnect: { id: categoryId } },
  },
});
```

## Aggregations

```typescript
const stats = await this.prisma.post.aggregate({
  _count: { id: true },
  _avg: { views: true },
  _max: { createdAt: true },
  where: { published: true },
});

// GroupBy
const byAuthor = await this.prisma.post.groupBy({
  by: ["authorId"],
  _count: { id: true },
  orderBy: { _count: { id: "desc" } },
});
```

## Middleware / Extensions

```typescript
// Soft delete extension example
const xprisma = this.prisma.$extends({
  model: {
    user: {
      async softDelete(id: number) {
        return prisma.user.update({
          where: { id },
          data: { deletedAt: new Date() },
        });
      },
    },
  },
});
```
