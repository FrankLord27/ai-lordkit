# Testing en NestJS — Jest

---

## Configuración inicial

```bash
# NestJS ya incluye Jest. Instalar dependencias adicionales:
pnpm add -D @nestjs/testing jest @types/jest ts-jest
pnpm add -D @faker-js/faker   # Generación de datos de prueba
```

```typescript
// apps/api/jest.config.ts
import type { Config } from "jest";

const config: Config = {
  moduleFileExtensions: ["js", "json", "ts"],
  rootDir: "src",
  testRegex: ".*\\.spec\\.ts$",
  transform: { "^.+\\.(t|j)s$": "ts-jest" },
  collectCoverageFrom: ["**/*.(t|j)s"],
  // Excluir archivos que no necesitan cobertura
  coveragePathIgnorePatterns: ["main.ts", ".module.ts", ".dto.ts", "index.ts"],
  coverageDirectory: "../coverage",
  testEnvironment: "node",
  // Separar configs para unit vs integration
  projects: [
    {
      displayName: "unit",
      testMatch: ["<rootDir>/**/*.spec.ts"],
      testPathIgnorePatterns: ["integration"],
    },
    {
      displayName: "integration",
      testMatch: ["<rootDir>/**/*.integration.spec.ts"],
    },
  ],
};

export default config;
```

```json
// package.json scripts
{
  "scripts": {
    "test": "jest --config jest.config.ts",
    "test:unit": "jest --config jest.config.ts --selectProjects unit",
    "test:integration": "jest --config jest.config.ts --selectProjects integration",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage"
  }
}
```

---

## Tests unitarios de Services

El Service es donde vive la lógica de negocio. Es lo más importante de testear.
Se mockean todas las dependencias externas (Repository, Redis, etc.).

```typescript
// modules/rent/services/search-cars.service.spec.ts
import { Test, TestingModule } from "@nestjs/testing";
import { SearchCarsService } from "./search-cars.service";
import { CarRepository } from "../repositories/car.repository";
import { RedisService } from "../../../redis/redis.service";
import { faker } from "@faker-js/faker";

// Factory — genera datos de test consistentes
const makeSearchDto = (overrides = {}) => ({
  locationId: faker.string.uuid(),
  pickupDate: "2025-03-20T10:00:00Z",
  returnDate: "2025-03-25T10:00:00Z",
  ...overrides,
});

const makeCar = (overrides = {}) => ({
  id: faker.string.uuid(),
  model: faker.vehicle.model(),
  brand: faker.vehicle.manufacturer(),
  dailyRate: faker.number.float({ min: 50, max: 200, fractionDigits: 2 }),
  category: "ECONOMY",
  status: "AVAILABLE",
  ...overrides,
});

describe("SearchCarsService", () => {
  let service: SearchCarsService;
  let carRepository: jest.Mocked<CarRepository>;
  let redisService: jest.Mocked<RedisService>;

  beforeEach(async () => {
    // Crear mocks tipados de cada dependencia
    const mockCarRepository: jest.Mocked<Partial<CarRepository>> = {
      findAvailable: jest.fn(),
    };

    const mockRedisService: jest.Mocked<Partial<RedisService>> = {
      get: jest.fn(),
      set: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SearchCarsService,
        { provide: CarRepository, useValue: mockCarRepository },
        { provide: RedisService, useValue: mockRedisService },
      ],
    }).compile();

    service = module.get<SearchCarsService>(SearchCarsService);
    carRepository = module.get(CarRepository);
    redisService = module.get(RedisService);
  });

  afterEach(() => {
    jest.clearAllMocks(); // Limpiar mocks entre tests
  });

  describe("execute", () => {
    it("retorna autos mapeados cuando no hay cache", async () => {
      const dto = makeSearchDto();
      const cars = [makeCar(), makeCar()];

      redisService.get.mockResolvedValue(null); // Cache miss
      carRepository.findAvailable.mockResolvedValue(cars);
      redisService.set.mockResolvedValue(undefined);

      const result = await service.execute(dto);

      expect(result.cars).toHaveLength(2);
      expect(result.totalCount).toBe(2);
      expect(carRepository.findAvailable).toHaveBeenCalledWith(dto);
      expect(carRepository.findAvailable).toHaveBeenCalledTimes(1);
    });

    it("usa cache de Redis cuando existe y no consulta la DB", async () => {
      const dto = makeSearchDto();
      const cachedResult = { cars: [makeCar()], totalCount: 1 };

      redisService.get.mockResolvedValue(cachedResult); // Cache hit

      const result = await service.execute(dto);

      expect(result).toEqual(cachedResult);
      // La clave: no debe llamar al repository si hay cache
      expect(carRepository.findAvailable).not.toHaveBeenCalled();
    });

    it("guarda resultado en Redis con TTL de 300 segundos", async () => {
      const dto = makeSearchDto();
      redisService.get.mockResolvedValue(null);
      carRepository.findAvailable.mockResolvedValue([makeCar()]);

      await service.execute(dto);

      expect(redisService.set).toHaveBeenCalledWith(
        expect.stringContaining("search:cars:"),
        expect.any(Object),
        300,
      );
    });

    it("retorna priceRange correcto con múltiples autos", async () => {
      const dto = makeSearchDto();
      redisService.get.mockResolvedValue(null);
      carRepository.findAvailable.mockResolvedValue([
        makeCar({ dailyRate: 50 }),
        makeCar({ dailyRate: 150 }),
        makeCar({ dailyRate: 100 }),
      ]);

      const result = await service.execute(dto);

      expect(result.priceRange).toEqual({ min: 50, max: 150 });
    });

    it("retorna priceRange en cero cuando no hay autos disponibles", async () => {
      const dto = makeSearchDto();
      redisService.get.mockResolvedValue(null);
      carRepository.findAvailable.mockResolvedValue([]);

      const result = await service.execute(dto);

      expect(result.priceRange).toEqual({ min: 0, max: 0 });
      expect(result.totalCount).toBe(0);
    });
  });
});
```

---

## Tests de integración con Prisma

Los tests de integración usan una base de datos PostgreSQL real de test.
No mockean Prisma — prueban que las queries funcionan correctamente.

### Setup de base de datos de test

```bash
# .env.test
DATABASE_URL=postgresql://devuser:devpassword@localhost:5432/myapp_test
```

```typescript
// test/setup/database.ts — helper compartido para tests de integración
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient({
  datasources: { db: { url: process.env.DATABASE_URL } },
});

// Limpiar todas las tablas antes de cada test
// El orden importa por las foreign keys
export async function cleanDatabase() {
  const tablenames = await prisma.$queryRaw<{ tablename: string }[]>`
    SELECT tablename FROM pg_tables WHERE schemaname='public'
  `;

  const tables = tablenames
    .map(({ tablename }) => tablename)
    .filter((name) => name !== "_prisma_migrations")
    .map((name) => `"public"."${name}"`)
    .join(", ");

  await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${tables} CASCADE;`);
}

export { prisma };
```

```typescript
// modules/rent/repositories/car.repository.integration.spec.ts
import { Test } from "@nestjs/testing";
import { CarRepository } from "./car.repository";
import { PrismaService } from "../../../prisma/prisma.service";
import { cleanDatabase, prisma } from "../../../../test/setup/database";
import { faker } from "@faker-js/faker";

describe("CarRepository (Integration)", () => {
  let repository: CarRepository;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      providers: [CarRepository, PrismaService],
    }).compile();

    repository = module.get<CarRepository>(CarRepository);
  });

  beforeEach(async () => {
    await cleanDatabase(); // Cada test empieza con DB limpia
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  describe("findAvailable", () => {
    it("retorna solo autos con status AVAILABLE", async () => {
      // Arrange — crear datos en la DB real
      const location = await prisma.location.create({
        data: { name: "Aeropuerto", city: "Santo Domingo", country: "DO" },
      });

      await prisma.car.createMany({
        data: [
          {
            model: "Corolla",
            brand: "Toyota",
            category: "ECONOMY",
            transmission: "automatic",
            passengers: 5,
            dailyRate: 80,
            status: "AVAILABLE",
            locationId: location.id,
          },
          {
            model: "Civic",
            brand: "Honda",
            category: "ECONOMY",
            transmission: "automatic",
            passengers: 5,
            dailyRate: 90,
            status: "MAINTENANCE",
            locationId: location.id,
          }, // No debe aparecer
        ],
      });

      // Act
      const result = await repository.findAvailable({
        locationId: location.id,
        pickupDate: "2025-03-20T10:00:00Z",
        returnDate: "2025-03-25T10:00:00Z",
      });

      // Assert
      expect(result).toHaveLength(1);
      expect(result[0].model).toBe("Corolla");
      expect(result[0].status).toBe("AVAILABLE");
    });

    it("excluye autos con reservas solapadas", async () => {
      const location = await prisma.location.create({
        data: { name: "Centro", city: "Santo Domingo", country: "DO" },
      });
      const user = await prisma.user.create({
        data: { email: faker.internet.email(), password: "hash", name: "Test" },
      });
      const car = await prisma.car.create({
        data: {
          model: "Rav4",
          brand: "Toyota",
          category: "SUV",
          transmission: "automatic",
          passengers: 5,
          dailyRate: 120,
          status: "AVAILABLE",
          locationId: location.id,
        },
      });

      // Crear reserva que solapa con las fechas de búsqueda
      await prisma.booking.create({
        data: {
          userId: user.id,
          carId: car.id,
          pickupDate: new Date("2025-03-18"),
          returnDate: new Date("2025-03-22"), // Solapa con 20-25
          totalPrice: 480,
          status: "CONFIRMED",
        },
      });

      const result = await repository.findAvailable({
        locationId: location.id,
        pickupDate: "2025-03-20T10:00:00Z",
        returnDate: "2025-03-25T10:00:00Z",
      });

      // El auto tiene reserva que solapa — no debe aparecer
      expect(result).toHaveLength(0);
    });
  });
});
```

---

## Tests de Guards

```typescript
// common/guards/jwt-auth.guard.spec.ts
import { JwtAuthGuard } from "./jwt-auth.guard";
import { ExecutionContext } from "@nestjs/common";
import { UnauthorizedException } from "@nestjs/common";

describe("JwtAuthGuard", () => {
  let guard: JwtAuthGuard;

  beforeEach(() => {
    guard = new JwtAuthGuard();
  });

  it("permite el acceso cuando el token es válido", () => {
    const mockContext = {
      switchToHttp: () => ({
        getRequest: () => ({
          headers: { authorization: "Bearer valid.jwt.token" },
          user: { sub: "user-id", email: "test@test.com", role: "user" },
        }),
      }),
    } as ExecutionContext;

    // JwtAuthGuard extiende AuthGuard('jwt') — mockear el método padre
    jest.spyOn(guard, "canActivate").mockReturnValue(true);
    expect(guard.canActivate(mockContext)).toBe(true);
  });

  it("lanza UnauthorizedException cuando no hay token", () => {
    const mockContext = {
      switchToHttp: () => ({
        getRequest: () => ({ headers: {} }),
      }),
    } as ExecutionContext;

    jest.spyOn(guard, "canActivate").mockImplementation(() => {
      throw new UnauthorizedException();
    });

    expect(() => guard.canActivate(mockContext)).toThrow(UnauthorizedException);
  });
});
```

---

## Tests de DTOs — validación

```typescript
// modules/rent/dto/search-cars.dto.spec.ts
import { validate } from "class-validator";
import { plainToInstance } from "class-transformer";
import { SearchCarsDto } from "./search-cars.dto";

describe("SearchCarsDto", () => {
  const validDto = {
    locationId: "uuid-location-id",
    pickupDate: "2025-03-20T10:00:00Z",
    returnDate: "2025-03-25T10:00:00Z",
  };

  it("es válido con datos correctos", async () => {
    const dto = plainToInstance(SearchCarsDto, validDto);
    const errors = await validate(dto);
    expect(errors).toHaveLength(0);
  });

  it("falla cuando falta locationId", async () => {
    const dto = plainToInstance(SearchCarsDto, {
      ...validDto,
      locationId: undefined,
    });
    const errors = await validate(dto);
    expect(errors.some((e) => e.property === "locationId")).toBe(true);
  });

  it("falla cuando pickupDate no es una fecha válida", async () => {
    const dto = plainToInstance(SearchCarsDto, {
      ...validDto,
      pickupDate: "no-es-fecha",
    });
    const errors = await validate(dto);
    expect(errors.some((e) => e.property === "pickupDate")).toBe(true);
  });

  it("falla cuando maxPrice es negativo", async () => {
    const dto = plainToInstance(SearchCarsDto, { ...validDto, maxPrice: -50 });
    const errors = await validate(dto);
    expect(errors.some((e) => e.property === "maxPrice")).toBe(true);
  });

  it("es válido cuando maxPrice es opcional y no se envía", async () => {
    const dto = plainToInstance(SearchCarsDto, validDto); // Sin maxPrice
    const errors = await validate(dto);
    expect(errors).toHaveLength(0);
  });
});
```

---

## Mocks — qué mockear y cómo

### Qué mockear siempre

```typescript
// ✅ Mockear: infraestructura externa
jest.mock("ioredis"); // Redis
jest.mock("@sendgrid/mail"); // Email
jest.mock("stripe"); // Pagos

// ✅ Mockear: repositorios en tests unitarios de services
const mockRepo = { findAvailable: jest.fn(), create: jest.fn() };

// ❌ Nunca mockear: la lógica que estás probando
// Si mockeas el SearchCarsService para testear el SearchCarsService,
// no estás probando nada real.
```

### Mock de fecha — tests deterministas

```typescript
describe("TokenService", () => {
  beforeEach(() => {
    // Fijar la fecha en todos los tests de este bloque
    jest.useFakeTimers();
    jest.setSystemTime(new Date("2025-01-15T12:00:00Z"));
  });

  afterEach(() => {
    jest.useRealTimers(); // Restaurar tiempo real
  });

  it("genera token con expiración correcta", () => {
    const token = tokenService.generate("user-id");
    const decoded = tokenService.decode(token);
    // Con fecha fija, la expiración es predecible
    expect(decoded.exp).toBe(new Date("2025-01-15T12:15:00Z").getTime() / 1000);
  });
});
```

### Spy — verificar llamadas sin reemplazar implementación

```typescript
it("loguea el error cuando Redis falla", async () => {
  const loggerSpy = jest.spyOn(service["logger"], "error");
  redisService.get.mockRejectedValue(new Error("Redis connection failed"));

  // El service debe manejar el error gracefully y continuar
  await service.execute(dto);

  expect(loggerSpy).toHaveBeenCalledWith(
    expect.stringContaining("Redis"),
    expect.any(Error),
  );
});
```
