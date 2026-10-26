# Prisma 7 — Testing

Estrategias para testear código que usa Prisma: mocking, test containers, y fixtures.

---

## Estrategias de testing

| Tipo             | Velocidad  | Confianza | Cuándo usar                 |
| ---------------- | ---------- | --------- | --------------------------- |
| Mock completo    | Muy rápida | Baja      | Tests unitarios de services |
| SQLite in-memory | Rápida     | Media     | Tests simples de queries    |
| Test container   | Lenta      | Alta      | Tests de integración        |
| DB de test       | Media      | Alta      | E2E tests                   |

---

## 1. Mock completo (tests unitarios)

Para tests unitarios donde solo quieres verificar la lógica del service:

```typescript
// __mocks__/prisma.mock.ts
import { PrismaClient } from "../src/generated/prisma/client.js";
import { mockDeep, DeepMockProxy } from "jest-mock-extended";

export type MockPrismaClient = DeepMockProxy<PrismaClient>;

export const createMockPrisma = (): MockPrismaClient => {
  return mockDeep<PrismaClient>();
};
```

### Test con mock

```typescript
// users/users.service.spec.ts
import { Test } from "@nestjs/testing";
import { UsersService } from "./users.service";
import { PrismaService } from "../prisma/prisma.service";
import { createMockPrisma, MockPrismaClient } from "../__mocks__/prisma.mock";

describe("UsersService", () => {
  let service: UsersService;
  let prisma: MockPrismaClient;

  beforeEach(async () => {
    prisma = createMockPrisma();

    const module = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: PrismaService, useValue: { client: prisma } },
      ],
    }).compile();

    service = module.get(UsersService);
  });

  describe("findOne", () => {
    it("should return user when found", async () => {
      const mockUser = {
        id: "123",
        email: "test@example.com",
        name: "Test User",
        createdAt: new Date(),
        updatedAt: new Date(),
        deletedAt: null,
      };

      prisma.user.findUnique.mockResolvedValue(mockUser);

      const result = await service.findOne("123");

      expect(result).toEqual(mockUser);
      expect(prisma.user.findUnique).toHaveBeenCalledWith({
        where: { id: "123" },
      });
    });

    it("should throw NotFoundException when user not found", async () => {
      prisma.user.findUnique.mockResolvedValue(null);

      await expect(service.findOne("999")).rejects.toThrow(NotFoundException);
    });
  });

  describe("create", () => {
    it("should create user with hashed password", async () => {
      const dto = { email: "new@example.com", name: "New", password: "secret" };
      const mockCreated = { id: "456", ...dto, createdAt: new Date() };

      prisma.user.create.mockResolvedValue(mockCreated);

      const result = await service.create(dto);

      expect(result.id).toBe("456");
      expect(prisma.user.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          email: dto.email,
          name: dto.name,
          password: expect.not.stringMatching(dto.password), // hashed
        }),
      });
    });
  });
});
```

---

## 2. Test Containers (tests de integración)

Base de datos PostgreSQL real en Docker, creada y destruida por test:

```bash
pnpm add -D @testcontainers/postgresql testcontainers
```

### Setup global

```typescript
// test/setup/test-db.ts
import {
  PostgreSqlContainer,
  StartedPostgreSqlContainer,
} from "@testcontainers/postgresql";
import { execSync } from "child_process";

let container: StartedPostgreSqlContainer;

export async function setupTestDatabase() {
  container = await new PostgreSqlContainer("postgres:16")
    .withDatabase("test_db")
    .withUsername("test")
    .withPassword("test")
    .start();

  const databaseUrl = container.getConnectionUri();
  process.env.DATABASE_URL = databaseUrl;

  // Aplicar migraciones
  execSync("npx prisma migrate deploy", {
    env: { ...process.env, DATABASE_URL: databaseUrl },
  });

  return container;
}

export async function teardownTestDatabase() {
  if (container) {
    await container.stop();
  }
}

export function getTestDatabaseUrl(): string {
  return container.getConnectionUri();
}
```

### Jest config

```typescript
// jest.integration.config.ts
export default {
  moduleFileExtensions: ["js", "json", "ts"],
  rootDir: ".",
  testRegex: ".*\\.integration\\.spec\\.ts$",
  transform: { "^.+\\.(t|j)s$": "ts-jest" },
  globalSetup: "./test/setup/global-setup.ts",
  globalTeardown: "./test/setup/global-teardown.ts",
  setupFilesAfterEnv: ["./test/setup/setup-after-env.ts"],
  testTimeout: 30000,
};
```

```typescript
// test/setup/global-setup.ts
import { setupTestDatabase } from "./test-db";

export default async () => {
  await setupTestDatabase();
};
```

```typescript
// test/setup/global-teardown.ts
import { teardownTestDatabase } from "./test-db";

export default async () => {
  await teardownTestDatabase();
};
```

### Test de integración

```typescript
// users/users.integration.spec.ts
import { Test } from "@nestjs/testing";
import { INestApplication } from "@nestjs/common";
import * as request from "supertest";
import { AppModule } from "../app.module";
import { PrismaService } from "../prisma/prisma.service";

describe("Users Integration", () => {
  let app: INestApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = module.createNestApplication();
    prisma = module.get(PrismaService);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(async () => {
    // Limpiar datos entre tests
    await prisma.client.user.deleteMany();
  });

  describe("POST /users", () => {
    it("should create user", async () => {
      const response = await request(app.getHttpServer())
        .post("/users")
        .send({
          email: "test@example.com",
          name: "Test",
          password: "secret123",
        })
        .expect(201);

      expect(response.body.email).toBe("test@example.com");
      expect(response.body.password).toBeUndefined(); // No exponer password

      // Verificar en DB
      const dbUser = await prisma.client.user.findUnique({
        where: { email: "test@example.com" },
      });
      expect(dbUser).not.toBeNull();
    });

    it("should fail with duplicate email", async () => {
      // Crear usuario primero
      await prisma.client.user.create({
        data: {
          email: "existing@example.com",
          name: "Existing",
          password: "hash",
        },
      });

      await request(app.getHttpServer())
        .post("/users")
        .send({
          email: "existing@example.com",
          name: "Duplicate",
          password: "secret",
        })
        .expect(409); // Conflict
    });
  });
});
```

---

## 3. Factories y Fixtures

```typescript
// test/factories/user.factory.ts
import { faker } from "@faker-js/faker";
import { PrismaClient, User, Prisma } from "../src/generated/prisma/client.js";

export class UserFactory {
  constructor(private readonly prisma: PrismaClient) {}

  // Datos por defecto
  private defaultData(): Prisma.UserCreateInput {
    return {
      email: faker.internet.email().toLowerCase(),
      name: faker.person.fullName(),
      password: "$2b$12$hashedpassword", // bcrypt hash de "password123"
      role: "USER",
    };
  }

  // Crear un usuario
  async create(overrides: Partial<Prisma.UserCreateInput> = {}): Promise<User> {
    return this.prisma.user.create({
      data: { ...this.defaultData(), ...overrides },
    });
  }

  // Crear múltiples usuarios
  async createMany(
    count: number,
    overrides: Partial<Prisma.UserCreateInput> = {},
  ): Promise<User[]> {
    const users: User[] = [];
    for (let i = 0; i < count; i++) {
      users.push(await this.create(overrides));
    }
    return users;
  }

  // Crear admin
  async createAdmin(
    overrides: Partial<Prisma.UserCreateInput> = {},
  ): Promise<User> {
    return this.create({ ...overrides, role: "ADMIN" });
  }

  // Build sin guardar (para mocks)
  build(
    overrides: Partial<Prisma.UserCreateInput> = {},
  ): Prisma.UserCreateInput {
    return { ...this.defaultData(), ...overrides };
  }
}

// Uso:
const userFactory = new UserFactory(prisma);
const user = await userFactory.create({ name: "Custom Name" });
const admins = await userFactory.createMany(3, { role: "ADMIN" });
```

### Factory con relaciones

```typescript
// test/factories/post.factory.ts
export class PostFactory {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly userFactory: UserFactory,
  ) {}

  async create(overrides: Partial<Prisma.PostCreateInput> = {}): Promise<Post> {
    // Si no se provee autor, crear uno
    if (!overrides.author) {
      const author = await this.userFactory.create();
      overrides.author = { connect: { id: author.id } };
    }

    return this.prisma.post.create({
      data: {
        title: faker.lorem.sentence(),
        content: faker.lorem.paragraphs(3),
        published: faker.datatype.boolean(),
        ...overrides,
      },
    });
  }
}
```

---

## 4. Helper para limpiar DB entre tests

```typescript
// test/helpers/db-cleaner.ts
import { PrismaClient } from "../src/generated/prisma/client.js";

export async function cleanDatabase(prisma: PrismaClient) {
  // Orden importa por foreign keys
  const tablenames = await prisma.$queryRaw<Array<{ tablename: string }>>`
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  `;

  // Desactivar constraints temporalmente
  await prisma.$executeRaw`SET session_replication_role = 'replica'`;

  for (const { tablename } of tablenames) {
    if (tablename !== "_prisma_migrations") {
      await prisma.$executeRawUnsafe(`TRUNCATE TABLE "${tablename}" CASCADE`);
    }
  }

  // Reactivar constraints
  await prisma.$executeRaw`SET session_replication_role = 'origin'`;
}

// Uso en tests:
beforeEach(async () => {
  await cleanDatabase(prisma);
});
```

---

## 5. Testing de transacciones

```typescript
describe("OrderService.createOrder", () => {
  it("should rollback if payment fails", async () => {
    const user = await userFactory.create();
    const product = await productFactory.create({ stock: 10 });

    // Mock de payment que falla
    paymentService.charge.mockRejectedValue(new Error("Payment failed"));

    await expect(
      orderService.createOrder(user.id, [
        { productId: product.id, quantity: 2 },
      ]),
    ).rejects.toThrow("Payment failed");

    // Verificar que el stock NO se redujo (rollback)
    const updatedProduct = await prisma.product.findUnique({
      where: { id: product.id },
    });
    expect(updatedProduct.stock).toBe(10);

    // Verificar que NO se creó orden
    const orders = await prisma.order.findMany({ where: { userId: user.id } });
    expect(orders).toHaveLength(0);
  });
});
```

---

## 6. Testing de soft delete

```typescript
describe("Soft delete behavior", () => {
  it("findMany should not return deleted records", async () => {
    const user1 = await userFactory.create();
    const user2 = await userFactory.create();

    // Soft delete user1
    await prisma.user.update({
      where: { id: user1.id },
      data: { deletedAt: new Date() },
    });

    const users = await service.findAll();

    expect(users).toHaveLength(1);
    expect(users[0].id).toBe(user2.id);
  });

  it("findOne should throw for deleted records", async () => {
    const user = await userFactory.create();
    await prisma.user.update({
      where: { id: user.id },
      data: { deletedAt: new Date() },
    });

    await expect(service.findOne(user.id)).rejects.toThrow(NotFoundException);
  });
});
```

---

## package.json scripts

```json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:integration": "jest --config jest.integration.config.ts",
    "test:e2e": "jest --config jest.e2e.config.ts"
  }
}
```

---

## Checklist

- [ ] Decidir estrategia por tipo de test (mock vs container)
- [ ] Configurar test containers para integración
- [ ] Crear factories para cada modelo principal
- [ ] Helper para limpiar DB entre tests
- [ ] Separar configs de Jest (unit, integration, e2e)
- [ ] CI ejecuta tests con PostgreSQL real (GitHub Actions + services)
