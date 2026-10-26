# NestJS — Testing

**Fuente:** https://docs.nestjs.com/fundamentals/testing

## Unit Testing con Jest

```typescript
// cats.service.spec.ts
import { Test, TestingModule } from "@nestjs/testing";
import { CatsService } from "./cats.service";
import { PrismaService } from "../prisma/prisma.service";

describe("CatsService", () => {
  let service: CatsService;
  let prisma: PrismaService;

  const mockPrismaService = {
    cat: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        CatsService,
        { provide: PrismaService, useValue: mockPrismaService },
      ],
    }).compile();

    service = module.get<CatsService>(CatsService);
    prisma = module.get<PrismaService>(PrismaService);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe("findAll", () => {
    it("should return array of cats", async () => {
      const cats = [{ id: "1", name: "Whiskers" }];
      mockPrismaService.cat.findMany.mockResolvedValue(cats);

      const result = await service.findAll();

      expect(result).toEqual(cats);
      expect(prisma.cat.findMany).toHaveBeenCalledTimes(1);
    });
  });

  describe("findOne", () => {
    it("should throw NotFoundException when cat not found", async () => {
      mockPrismaService.cat.findUnique.mockResolvedValue(null);

      await expect(service.findOne("nonexistent-id")).rejects.toThrow(
        NotFoundException,
      );
    });
  });
});
```

## Testing con Mock de dependencias externas

```typescript
// auth.service.spec.ts
import { JwtService } from "@nestjs/jwt";
import * as bcrypt from "bcrypt";

jest.mock("bcrypt");

describe("AuthService", () => {
  let service: AuthService;

  const mockJwtService = {
    signAsync: jest.fn().mockResolvedValue("mock.jwt.token"),
    verifyAsync: jest.fn(),
  };

  const mockUsersService = {
    findByEmail: jest.fn(),
    create: jest.fn(),
  };

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: JwtService, useValue: mockJwtService },
        { provide: UsersService, useValue: mockUsersService },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it("should sign in successfully", async () => {
    mockUsersService.findByEmail.mockResolvedValue({
      id: "1",
      email: "test@test.com",
      password: "hashed",
    });
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);

    const result = await service.signIn("test@test.com", "password");

    expect(result.access_token).toBe("mock.jwt.token");
  });
});
```

## Integration Testing (supertest)

```typescript
// cats.controller.spec.ts
import * as request from "supertest";
import { INestApplication, ValidationPipe } from "@nestjs/common";

describe("CatsController (e2e)", () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule], // módulo real (con DB de test)
    }).compile();

    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true }),
    );
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  describe("POST /cats", () => {
    it("should create a cat", () => {
      return request(app.getHttpServer())
        .post("/cats")
        .set("Authorization", `Bearer ${testToken}`)
        .send({ name: "Whiskers", age: 3 })
        .expect(201)
        .expect((res) => {
          expect(res.body.name).toBe("Whiskers");
          expect(res.body.id).toBeDefined();
        });
    });

    it("should return 400 on invalid data", () => {
      return request(app.getHttpServer())
        .post("/cats")
        .set("Authorization", `Bearer ${testToken}`)
        .send({ name: "", age: -1 })
        .expect(400);
    });
  });
});
```

## Testing con mock de guards/pipes globales

```typescript
const moduleRef = await Test.createTestingModule({
  imports: [CatsModule],
})
  .overrideGuard(JwtAuthGuard)
  .useValue({ canActivate: () => true }) // siempre permite
  .overridePipe(ValidationPipe)
  .useValue(new ValidationPipe({ whitelist: true }))
  .overrideProvider(CatsService)
  .useValue(mockCatsService)
  .compile();
```

## Testing de Guards

```typescript
describe("JwtAuthGuard", () => {
  let guard: JwtAuthGuard;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        JwtAuthGuard,
        { provide: JwtService, useValue: { verifyAsync: jest.fn() } },
        { provide: ConfigService, useValue: { get: () => "secret" } },
        { provide: Reflector, useValue: { getAllAndOverride: () => false } },
      ],
    }).compile();

    guard = module.get<JwtAuthGuard>(JwtAuthGuard);
  });

  it("should deny access without token", async () => {
    const context = createMockExecutionContext({ headers: {} });
    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });
});

function createMockExecutionContext(requestMock: any) {
  return {
    switchToHttp: () => ({ getRequest: () => requestMock }),
    getHandler: () => ({}),
    getClass: () => ({}),
  } as ExecutionContext;
}
```

## Configuración jest.config.js

```javascript
module.exports = {
  moduleFileExtensions: ["js", "json", "ts"],
  rootDir: "src",
  testRegex: ".*\\.spec\\.ts$",
  transform: { "^.+\\.(t|j)s$": "ts-jest" },
  collectCoverageFrom: ["**/*.(t|j)s"],
  coverageDirectory: "../coverage",
  testEnvironment: "node",
  moduleNameMapper: {
    "^@/(.*)$": "<rootDir>/$1",
  },
};
```

## Scripts package.json

```json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:e2e": "jest --config ./test/jest-e2e.json"
  }
}
```
