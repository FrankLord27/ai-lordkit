# NestJS — Testing

## Setup (viene incluido con nest new)

```bash
pnpm run test           # unit tests
pnpm run test:watch     # watch mode
pnpm run test:cov       # con coverage
pnpm run test:e2e       # end-to-end
```

## 1. Unit Tests — Services

```typescript
// cats/cats.service.spec.ts
import { Test, TestingModule } from "@nestjs/testing";
import { CatsService } from "./cats.service";
import { getRepositoryToken } from "@nestjs/typeorm";
import { Cat } from "./entities/cat.entity";
import { NotFoundException } from "@nestjs/common";

describe("CatsService", () => {
  let service: CatsService;

  const mockRepository = {
    find: jest.fn(),
    findOneBy: jest.fn(),
    create: jest.fn(),
    save: jest.fn(),
    remove: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        CatsService,
        {
          provide: getRepositoryToken(Cat),
          useValue: mockRepository,
        },
      ],
    }).compile();

    service = module.get<CatsService>(CatsService);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe("findAll", () => {
    it("should return an array of cats", async () => {
      const cats = [{ id: "1", name: "Tom" }];
      mockRepository.find.mockResolvedValue(cats);

      const result = await service.findAll();

      expect(result).toEqual(cats);
      expect(mockRepository.find).toHaveBeenCalledTimes(1);
    });
  });

  describe("findOne", () => {
    it("should return a cat by id", async () => {
      const cat = { id: "1", name: "Tom" };
      mockRepository.findOneBy.mockResolvedValue(cat);

      expect(await service.findOne("1")).toEqual(cat);
    });

    it("should throw NotFoundException if cat not found", async () => {
      mockRepository.findOneBy.mockResolvedValue(null);

      await expect(service.findOne("999")).rejects.toThrow(NotFoundException);
    });
  });

  describe("create", () => {
    it("should create and return a cat", async () => {
      const dto = { name: "Tom", age: 3 };
      const cat = { id: "1", ...dto };
      mockRepository.create.mockReturnValue(cat);
      mockRepository.save.mockResolvedValue(cat);

      expect(await service.create(dto)).toEqual(cat);
      expect(mockRepository.create).toHaveBeenCalledWith(dto);
    });
  });
});
```

## 2. Unit Tests — Controllers

```typescript
// cats/cats.controller.spec.ts
import { Test, TestingModule } from "@nestjs/testing";
import { CatsController } from "./cats.controller";
import { CatsService } from "./cats.service";

describe("CatsController", () => {
  let controller: CatsController;
  let service: CatsService;

  const mockCatsService = {
    findAll: jest.fn(),
    findOne: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    remove: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [CatsController],
      providers: [{ provide: CatsService, useValue: mockCatsService }],
    }).compile();

    controller = module.get<CatsController>(CatsController);
    service = module.get<CatsService>(CatsService);
  });

  it("should call service.findAll", async () => {
    const cats = [{ id: "1" }];
    mockCatsService.findAll.mockResolvedValue(cats);

    const result = await controller.findAll();
    expect(result).toEqual(cats);
    expect(mockCatsService.findAll).toHaveBeenCalled();
  });
});
```

## 3. Testing con Prisma (mock)

```typescript
import { PrismaService } from "../prisma/prisma.service";
import { DeepMockProxy, mockDeep } from "jest-mock-extended";

// jest-mock-extended permite mockear métodos profundos de Prisma
// pnpm add -D jest-mock-extended

describe("CarsService with Prisma", () => {
  let service: CarsService;
  let prisma: DeepMockProxy<PrismaService>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        CarsService,
        { provide: PrismaService, useValue: mockDeep<PrismaService>() },
      ],
    }).compile();

    service = module.get(CarsService);
    prisma = module.get(PrismaService);
  });

  it("should create a car", async () => {
    const carData = { title: "Toyota", pricePerDay: 50 };
    prisma.car.create.mockResolvedValue({ id: "1", ...carData } as any);

    const result = await service.create(carData as any, "user-1");
    expect(prisma.car.create).toHaveBeenCalledWith({
      data: { ...carData, ownerId: "user-1" },
      include: expect.any(Object),
    });
  });
});
```

## 4. E2E Tests

```typescript
// test/cats.e2e-spec.ts
import { Test, TestingModule } from "@nestjs/testing";
import { INestApplication, ValidationPipe } from "@nestjs/common";
import * as request from "supertest";
import { AppModule } from "../src/app.module";

describe("CatsController (e2e)", () => {
  let app: INestApplication;
  let authToken: string;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true }),
    );
    app.setGlobalPrefix("api/v1");
    await app.init();

    // Login para obtener token
    const loginRes = await request(app.getHttpServer())
      .post("/api/v1/auth/login")
      .send({ email: "test@test.com", password: "password123" });
    authToken = loginRes.body.accessToken;
  });

  afterAll(async () => {
    await app.close();
  });

  describe("GET /api/v1/cats", () => {
    it("should return 200 with cats array", () => {
      return request(app.getHttpServer())
        .get("/api/v1/cats")
        .set("Authorization", `Bearer ${authToken}`)
        .expect(200)
        .expect((res) => {
          expect(res.body).toHaveProperty("data");
          expect(Array.isArray(res.body.data)).toBe(true);
        });
    });

    it("should return 401 without token", () => {
      return request(app.getHttpServer()).get("/api/v1/cats").expect(401);
    });
  });

  describe("POST /api/v1/cats", () => {
    it("should create a cat and return 201", () => {
      return request(app.getHttpServer())
        .post("/api/v1/cats")
        .set("Authorization", `Bearer ${authToken}`)
        .send({ name: "Tom", age: 3, breed: "Siamese" })
        .expect(201)
        .expect((res) => {
          expect(res.body).toHaveProperty("id");
          expect(res.body.name).toBe("Tom");
        });
    });

    it("should return 400 for invalid data", () => {
      return request(app.getHttpServer())
        .post("/api/v1/cats")
        .set("Authorization", `Bearer ${authToken}`)
        .send({ name: "" }) // inválido
        .expect(400);
    });
  });
});
```

## 5. Configuración Jest (jest.config.ts)

```typescript
// jest.config.ts
export default {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: 'src',
  testRegex: '.*\\.spec\\.ts$',
  transform: { '^.+\\.(t|j)s$': 'ts-jest' },
  collectCoverageFrom: ['**/*.(t|j)s'],
  coverageDirectory: '../coverage',
  testEnvironment: 'node',
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/$1',
  },
};

// Para E2E (test/jest-e2e.json):
{
  "moduleFileExtensions": ["js", "json", "ts"],
  "rootDir": ".",
  "testEnvironment": "node",
  "testRegex": ".e2e-spec.ts$",
  "transform": { "^.+\\.(t|j)s$": "ts-jest" }
}
```

## 6. Mocking Guards en tests

```typescript
// Mockear JwtAuthGuard en E2E para tests sin autenticación:
const moduleFixture = await Test.createTestingModule({
  imports: [AppModule],
})
  .overrideGuard(JwtAuthGuard)
  .useValue({ canActivate: () => true })
  .compile();
```
