# Prisma 7 — Seeding

Crear datos iniciales y fixtures para desarrollo, staging, y tests.

---

## Estructura de seeds

```
apps/api/
├── prisma/
│   ├── schema.prisma
│   ├── seed.ts              ← Archivo principal
│   └── seeds/
│       ├── index.ts
│       ├── users.seed.ts
│       ├── categories.seed.ts
│       ├── products.seed.ts
│       └── fixtures/
│           ├── dev.fixture.ts    ← Datos desarrollo
│           ├── staging.fixture.ts
│           └── demo.fixture.ts   ← Datos para demos
```

---

## Configuración

```json
// package.json
{
  "prisma": {
    "seed": "ts-node --transpile-only prisma/seed.ts"
  }
}
```

---

## Seed principal

```typescript
// prisma/seed.ts
import { PrismaClient } from "../src/generated/prisma/client.js";
import { PrismaPg } from "@prisma/adapter-pg";
import pg from "pg";

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const prisma = new PrismaClient({ adapter: new PrismaPg(pool) });

async function main() {
  const env = process.env.SEED_ENV ?? "dev";
  console.log(`🌱 Seeding database (env: ${env})\n`);

  // Seeds base (siempre se ejecutan)
  await seedRoles();
  await seedCategories();
  await seedAdminUser();

  // Seeds por ambiente
  switch (env) {
    case "dev":
      await seedDevData();
      break;
    case "staging":
      await seedStagingData();
      break;
    case "demo":
      await seedDemoData();
      break;
    case "prod":
      // Solo datos esenciales
      break;
  }

  console.log("\n✅ Seeding completado");
}

main()
  .catch((e) => {
    console.error("❌ Error en seed:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
```

---

## Seeds por dominio

### Roles y permisos

```typescript
// prisma/seeds/roles.seed.ts
import {
  PrismaClient,
  Role,
  Permission,
} from "../src/generated/prisma/client.js";

const ROLES: Array<{ name: Role; permissions: Permission[] }> = [
  {
    name: "ADMIN",
    permissions: ["CREATE", "READ", "UPDATE", "DELETE", "MANAGE_USERS"],
  },
  {
    name: "MANAGER",
    permissions: ["CREATE", "READ", "UPDATE", "DELETE"],
  },
  {
    name: "USER",
    permissions: ["CREATE", "READ", "UPDATE"],
  },
  {
    name: "VIEWER",
    permissions: ["READ"],
  },
];

export async function seedRoles(prisma: PrismaClient) {
  console.log("  → Seeding roles...");

  for (const role of ROLES) {
    await prisma.role.upsert({
      where: { name: role.name },
      update: { permissions: role.permissions },
      create: { name: role.name, permissions: role.permissions },
    });
  }

  console.log(`    ✓ ${ROLES.length} roles`);
}
```

### Categorías (datos estáticos)

```typescript
// prisma/seeds/categories.seed.ts
const CATEGORIES = [
  { name: "Laptops", slug: "laptops" },
  { name: "Desktops", slug: "desktops" },
  { name: "Monitors", slug: "monitors" },
  { name: "Peripherals", slug: "peripherals" },
  { name: "Software", slug: "software" },
];

export async function seedCategories(prisma: PrismaClient) {
  console.log("  → Seeding categories...");

  for (const category of CATEGORIES) {
    await prisma.category.upsert({
      where: { slug: category.slug },
      update: {},
      create: category,
    });
  }

  console.log(`    ✓ ${CATEGORIES.length} categories`);
}
```

### Usuario admin

```typescript
// prisma/seeds/admin.seed.ts
import * as bcrypt from "bcrypt";

export async function seedAdminUser(prisma: PrismaClient) {
  console.log("  → Seeding admin user...");

  const adminEmail = process.env.ADMIN_EMAIL ?? "admin@example.com";
  const adminPassword = process.env.ADMIN_PASSWORD ?? "Admin123!";

  const hashedPassword = await bcrypt.hash(adminPassword, 12);

  await prisma.user.upsert({
    where: { email: adminEmail },
    update: {},
    create: {
      email: adminEmail,
      password: hashedPassword,
      name: "Administrador",
      role: "ADMIN",
      emailVerified: true,
    },
  });

  console.log(`    ✓ Admin: ${adminEmail}`);
}
```

---

## Datos de desarrollo con Faker

```typescript
// prisma/seeds/fixtures/dev.fixture.ts
import { faker } from "@faker-js/faker";
import { PrismaClient } from "../../src/generated/prisma/client.js";
import * as bcrypt from "bcrypt";

export async function seedDevData(prisma: PrismaClient) {
  console.log("\n📦 Seeding development data...");

  const testPassword = await bcrypt.hash("Test123!", 12);

  // Usuario de prueba con credenciales conocidas
  const testUser = await prisma.user.upsert({
    where: { email: "test@example.com" },
    update: {},
    create: {
      email: "test@example.com",
      password: testPassword,
      name: "Usuario de Prueba",
      role: "USER",
      emailVerified: true,
    },
  });
  console.log("  ✓ Test user: test@example.com / Test123!");

  // Usuarios aleatorios
  const users = await createRandomUsers(prisma, 20, testPassword);
  console.log(`  ✓ ${users.length} random users`);

  // Productos aleatorios
  const categories = await prisma.category.findMany();
  const products = await createRandomProducts(prisma, 50, categories);
  console.log(`  ✓ ${products.length} random products`);

  // Órdenes aleatorias
  const orders = await createRandomOrders(prisma, users, products, 100);
  console.log(`  ✓ ${orders.length} random orders`);
}

async function createRandomUsers(
  prisma: PrismaClient,
  count: number,
  password: string,
) {
  const users = [];

  for (let i = 0; i < count; i++) {
    const user = await prisma.user.create({
      data: {
        email: faker.internet.email().toLowerCase(),
        password,
        name: faker.person.fullName(),
        role: faker.helpers.arrayElement(["USER", "MANAGER"]),
        emailVerified: faker.datatype.boolean(),
        phone: faker.phone.number(),
        avatar: faker.image.avatar(),
        createdAt: faker.date.past({ years: 1 }),
      },
    });
    users.push(user);
  }

  return users;
}

async function createRandomProducts(
  prisma: PrismaClient,
  count: number,
  categories: Array<{ id: string }>,
) {
  const products = [];

  for (let i = 0; i < count; i++) {
    const product = await prisma.product.create({
      data: {
        name: faker.commerce.productName(),
        description: faker.commerce.productDescription(),
        price: parseFloat(faker.commerce.price({ min: 10, max: 1000 })),
        stock: faker.number.int({ min: 0, max: 100 }),
        sku: faker.string.alphanumeric(8).toUpperCase(),
        categoryId: faker.helpers.arrayElement(categories).id,
        images: [faker.image.url(), faker.image.url()],
        isActive: faker.datatype.boolean({ probability: 0.9 }),
        createdAt: faker.date.past({ years: 1 }),
      },
    });
    products.push(product);
  }

  return products;
}

async function createRandomOrders(
  prisma: PrismaClient,
  users: Array<{ id: string }>,
  products: Array<{ id: string; price: number }>,
  count: number,
) {
  const orders = [];
  const statuses = [
    "PENDING",
    "PROCESSING",
    "SHIPPED",
    "DELIVERED",
    "CANCELLED",
  ];

  for (let i = 0; i < count; i++) {
    const orderProducts = faker.helpers.arrayElements(products, {
      min: 1,
      max: 5,
    });
    const items = orderProducts.map((p) => ({
      productId: p.id,
      quantity: faker.number.int({ min: 1, max: 3 }),
      price: p.price,
    }));
    const total = items.reduce(
      (sum, item) => sum + item.price * item.quantity,
      0,
    );

    const order = await prisma.order.create({
      data: {
        userId: faker.helpers.arrayElement(users).id,
        status: faker.helpers.arrayElement(statuses),
        total,
        items: {
          create: items,
        },
        createdAt: faker.date.past({ years: 1 }),
      },
    });
    orders.push(order);
  }

  return orders;
}
```

---

## Datos de demo (para presentaciones)

```typescript
// prisma/seeds/fixtures/demo.fixture.ts
export async function seedDemoData(prisma: PrismaClient) {
  console.log("\n🎬 Seeding demo data...");

  // Datos específicos que se ven bien en demos
  // Nombres reales, fotos bonitas, métricas impresionantes

  await prisma.user.createMany({
    data: [
      {
        email: "maria.gonzalez@acme.com",
        name: "María González",
        role: "ADMIN",
      },
      {
        email: "carlos.rodriguez@acme.com",
        name: "Carlos Rodríguez",
        role: "MANAGER",
      },
      { email: "ana.martinez@acme.com", name: "Ana Martínez", role: "USER" },
    ],
    skipDuplicates: true,
  });

  // Dashboard con métricas atractivas
  await prisma.dashboardMetrics.upsert({
    where: { id: "demo" },
    update: {},
    create: {
      id: "demo",
      totalRevenue: 1250000,
      activeUsers: 3500,
      conversionRate: 0.042,
      avgOrderValue: 156.5,
    },
  });
}
```

---

## Reset y re-seed

```bash
# Reset completo: drop + migrate + seed
npx prisma migrate reset

# Solo seed (sin drop)
npx prisma db seed

# Seed con ambiente específico
SEED_ENV=staging npx prisma db seed

# Seed de demo para presentaciones
SEED_ENV=demo npx prisma db seed
```

---

## Script de desarrollo

```bash
#!/bin/bash
# scripts/reset-dev-db.sh

echo "🗑️  Dropping database..."
npx prisma migrate reset --force --skip-seed

echo "🔄 Running migrations..."
npx prisma migrate deploy

echo "🌱 Seeding..."
SEED_ENV=dev npx prisma db seed

echo "✅ Done!"
```

---

## CI/CD: Seed en staging

```yaml
# .github/workflows/deploy-staging.yml
- name: Run migrations
  run: npx prisma migrate deploy
  env:
    DATABASE_URL: ${{ secrets.STAGING_DATABASE_URL }}

- name: Seed staging data
  run: npx prisma db seed
  env:
    DATABASE_URL: ${{ secrets.STAGING_DATABASE_URL }}
    SEED_ENV: staging
```

---

## Checklist

- [ ] Separar seeds base (roles, categorías) de fixtures (usuarios fake)
- [ ] Usar `upsert` para datos que siempre deben existir
- [ ] Variable `SEED_ENV` para diferentes ambientes
- [ ] Usuario de prueba con credenciales conocidas en dev
- [ ] Faker para datos realistas
- [ ] Script de reset rápido para desarrollo
- [ ] No incluir datos sensibles en seeds de staging/demo
