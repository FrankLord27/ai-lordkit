# Guía de Implementación — NestJS 11 + Prisma 7

Referencia para la **Fase 3 (Implementación)** del Quality Gate. Este documento
detalla el proceso exacto para implementar un módulo backend desde el contrato
hasta el código ejecutable.

> Para la estructura de carpetas completa, ver la skill `erp-saas-core`.
> Para patrones NestJS avanzados, ver la skill `nestjs-docs`.
> Para Prisma 7 con driver adapters, ver la skill `prisma7-docs`.

---

## Estructura de un módulo

Cada módulo sigue la estructura de Clean Architecture definida en `erp-saas-core`:

```
src/modules/<módulo>/
├── domain/
│   ├── entities/           ← Entidades de dominio (lógica pura, sin framework)
│   ├── value-objects/       ← Money, Email, etc.
│   ├── errors/              ← Errores de dominio tipados
│   ├── repositories/        ← Interfaces (puertos), NO implementaciones
│   └── events/              ← Eventos de dominio
├── application/
│   ├── use-cases/           ← Casos de uso (1 clase = 1 acción)
│   └── services/            ← Servicios de aplicación (orquestación)
├── infrastructure/
│   ├── prisma/              ← Implementación de repositories con Prisma
│   └── queue/               ← Procesadores de BullMQ si aplica
└── presentation/
    ├── controllers/         ← Controllers NestJS (solo routing + validación)
    └── dtos/                ← DTOs generados desde Zod (shared-types)
```

> **Regla inviolable:** `domain/` nunca importa de `infrastructure/`, `presentation/`, ni de NestJS/Prisma.

---

## Paso a paso: implementar un módulo nuevo

### Paso 1 — Schema Prisma

Agregar los modelos al `schema.prisma`. Respetar las convenciones:

```prisma
model Trip {
  id          String   @id @default(uuid())
  tenantId    String   @map("tenant_id")
  driverId    String   @map("driver_id")
  loadMt3     Decimal  @db.Decimal(12, 4) @map("load_mt3")
  distanceKm  Decimal  @db.Decimal(10, 2) @map("distance_km")
  totalAmount Decimal  @db.Decimal(14, 2) @map("total_amount")
  status      TripStatus @default(DRAFT)
  createdAt   DateTime @default(now()) @map("created_at")
  updatedAt   DateTime @updatedAt @map("updated_at")
  deletedAt   DateTime? @map("deleted_at")

  driver      Driver   @relation(fields: [driverId], references: [id])
  tenant      Tenant   @relation(fields: [tenantId], references: [id])

  @@index([tenantId])
  @@index([driverId])
  @@map("trips")
}

enum TripStatus {
  DRAFT
  IN_PROGRESS
  COMPLETED
  CANCELLED
  PAYMENT_PENDING
}
```

**Checklist del schema:**
- [ ] `tenantId` presente y con índice
- [ ] `deletedAt DateTime?` para soft delete
- [ ] Dinero en `@db.Decimal(precision, scale)`, nunca `Float`
- [ ] `@@map` para nombres de tabla en snake_case
- [ ] `@map` para nombres de columna en snake_case
- [ ] Enums para estados con ciclo de vida

### Paso 2 — Migración

```bash
pnpm prisma migrate dev --name add-trip-module
```

Verificar la migración generada en `prisma/migrations/`. Nunca editar migraciones
ya aplicadas en producción.

### Paso 3 — Entidades de dominio

```typescript
// src/modules/trips/domain/entities/trip.entity.ts
import { Decimal } from 'decimal.js';
import { TripStatus } from './trip-status.enum';

export class Trip {
  constructor(
    readonly id: string,
    readonly tenantId: string,
    readonly driverId: string,
    readonly loadMt3: Decimal,
    readonly distanceKm: Decimal,
    readonly ratePerUnit: Decimal,
    private _status: TripStatus,
  ) {
    this.validateLoad();
  }

  get status(): TripStatus { return this._status; }

  get totalAmount(): Decimal {
    return this.loadMt3
      .mul(this.distanceKm)
      .mul(this.ratePerUnit)
      .toDecimalPlaces(2, Decimal.ROUND_HALF_EVEN);
  }

  private validateLoad(): void {
    if (this.loadMt3.lte(0)) {
      throw new InvalidLoadError(this.loadMt3);
    }
  }

  start(): void {
    if (this._status !== TripStatus.DRAFT) {
      throw new InvalidStateTransitionError(this._status, TripStatus.IN_PROGRESS);
    }
    this._status = TripStatus.IN_PROGRESS;
  }
}
```

**Reglas:**
- Toda lógica de negocio vive aquí, no en el controller
- Usa `Decimal` de `decimal.js`, nunca `number` para dinero
- Las validaciones de dominio lanzan errores tipados, no excepciones genéricas
- La entidad es agnóstica de framework — no importa de NestJS ni Prisma

### Paso 4 — Interfaces de repository

```typescript
// src/modules/trips/domain/repositories/trip.repository.ts
export interface TripRepository {
  findById(id: string, tenantId: string): Promise<Trip | null>;
  save(trip: Trip): Promise<Trip>;
  findByDriver(driverId: string, tenantId: string): Promise<Trip[]>;
}
```

### Paso 5 — Implementación del repository con Prisma

```typescript
// src/modules/trips/infrastructure/prisma/trip.prisma-repository.ts
import { Injectable } from '@nestjs/common';
import { PrismaService } from '@shared/infrastructure/prisma/prisma.service';
import { TripRepository } from '../../domain/repositories/trip.repository';
import { TripMapper } from './trip.mapper';

@Injectable()
export class TripPrismaRepository implements TripRepository {
  constructor(private readonly prisma: PrismaService) {}

  async findById(id: string, tenantId: string): Promise<Trip | null> {
    const record = await this.prisma.trip.findFirst({
      where: { id, tenantId, deletedAt: null },
    });
    return record ? TripMapper.toDomain(record) : null;
  }

  async save(trip: Trip): Promise<Trip> {
    const data = TripMapper.toPersistence(trip);
    const record = await this.prisma.trip.upsert({
      where: { id: trip.id },
      create: data,
      update: data,
    });
    return TripMapper.toDomain(record);
  }
}
```

**Importante:** Nunca retornar el record de Prisma directo — siempre pasar por un Mapper.

### Paso 6 — Use cases

```typescript
// src/modules/trips/application/use-cases/create-trip.use-case.ts
@Injectable()
export class CreateTripUseCase {
  constructor(
    @Inject(TRIP_REPOSITORY) private readonly trips: TripRepository,
    @Inject(TRUCK_REPOSITORY) private readonly trucks: TruckRepository,
  ) {}

  async execute(dto: CreateTripDto, tenantId: string): Promise<Trip> {
    const truck = await this.trucks.findById(dto.truckId, tenantId);
    if (!truck) throw new TruckNotFoundError(dto.truckId);

    if (new Decimal(dto.loadMt3).gt(truck.capacityMt3)) {
      throw new OvercapacityError(dto.loadMt3, truck.capacityMt3);
    }

    const trip = new Trip(
      uuid(),
      tenantId,
      dto.driverId,
      new Decimal(dto.loadMt3),
      new Decimal(dto.distanceKm),
      new Decimal(dto.ratePerUnit),
      TripStatus.DRAFT,
    );

    return this.trips.save(trip);
  }
}
```

### Paso 7 — DTOs con Zod (shared-types)

```typescript
// packages/shared-types/src/trips/create-trip.schema.ts
import { z } from 'zod';

export const createTripSchema = z.object({
  truckId: z.string().uuid(),
  driverId: z.string().uuid(),
  loadMt3: z.string().refine(v => new Decimal(v).gt(0), 'Carga debe ser > 0'),
  distanceKm: z.string().refine(v => new Decimal(v).gt(0), 'Distancia debe ser > 0'),
  ratePerUnit: z.string().refine(v => new Decimal(v).gt(0), 'Tarifa debe ser > 0'),
});

export type CreateTripDto = z.infer<typeof createTripSchema>;
```

### Paso 8 — Controller

```typescript
// src/modules/trips/presentation/controllers/trip.controller.ts
@Controller({ path: 'trips', version: '1' })
@UseGuards(JwtAuthGuard)
export class TripController {
  constructor(private readonly createTrip: CreateTripUseCase) {}

  @Post()
  async create(@Body() dto: CreateTripDto, @Req() req: AuthRequest) {
    return this.createTrip.execute(dto, req.user.tenantId);
  }
}
```

**El controller NO tiene lógica de negocio.** Solo recibe, valida y delega.

### Paso 9 — Registrar el módulo

```typescript
@Module({
  controllers: [TripController],
  providers: [
    CreateTripUseCase,
    { provide: TRIP_REPOSITORY, useClass: TripPrismaRepository },
  ],
  exports: [TRIP_REPOSITORY],
})
export class TripsModule {}
```

### Paso 10 — Configurar tests

Ver la siguiente sección.

---

## Setup de testing por módulo

### Estructura de tests

```
test/
├── unit/<módulo>/            ← Reglas de negocio en aislamiento
│   ├── trip-entity.spec.ts
│   └── r1-total-calculation.spec.ts
├── integration/<módulo>/     ← Service + DB real
│   ├── trip-repository.spec.ts
│   └── au-trk-1.spec.ts
└── e2e/<módulo>/             ← Escenario completo HTTP → DB → respuesta
    ├── bsm-trk-001.spec.ts   ← Happy path: viaje completo
    ├── bsm-trk-020.spec.ts   ← Failure: overcapacity
    └── bsm-trk-027.spec.ts   ← Edge: reserva concurrente
```

### Nomenclatura obligatoria

Los tests que validan escenarios de la matrix **deben** llevar el ID del BSM:

```
bsm-<módulo>-<número>.spec.ts
```

Ejemplo: `bsm-trk-001.spec.ts` → BSM-TRK-001 en la Scenario Matrix.

Tests de reglas individuales: `r<número>-<descripción>.spec.ts`
Tests de auditoría: `au-<módulo>-<número>.spec.ts`

### Estructura de un test E2E de escenario

```typescript
// test/e2e/trips/bsm-trk-001.spec.ts
describe('BSM-TRK-001: Viaje completo happy path', () => {
  let app: INestApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    // Usar Testcontainers o DB de test real
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = module.createNestApplication();
    await setupApp(app); // pipes, guards, etc.
    await app.init();
    prisma = module.get(PrismaService);
  });

  afterAll(async () => {
    await app.close();
  });

  it('Paso 1: crear camión con capacidad 30 MT³', async () => { ... });
  it('Paso 2: crear chofer activo', async () => { ... });
  it('Paso 3: solicitar viaje 25 MT³, 22 km, tarifa RD$17', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${token}`)
      .send({ truckId, driverId, loadMt3: '25', distanceKm: '22', ratePerUnit: '17' });

    expect(res.status).toBe(201);
    expect(res.body.data.totalAmount).toBe('9350.00');
    tripId = res.body.data.id;
  });
  it('Paso 4: iniciar viaje', async () => { ... });
  it('Paso 5: finalizar viaje', async () => { ... });
  it('Paso 6: verificar cobro generado', async () => { ... });
  it('Paso 7: registrar pago', async () => { ... });
  it('Paso 8: verificar estado cerrado', async () => { ... });
  it('Paso 9: verificar auditoría completa', async () => {
    const auditRows = await prisma.auditLog.findMany({
      where: { entityId: tripId, tenantId },
    });
    expect(auditRows).toHaveLength(expect.any(Number));
    expect(auditRows.map(r => r.action)).toContain('TRIP_COMPLETED');
  });
});
```

### Base de datos para tests

**Opción recomendada: Testcontainers**

```typescript
// test/setup/test-db.ts
import { PostgreSqlContainer } from '@testcontainers/postgresql';

let container: StartedPostgreSqlContainer;

beforeAll(async () => {
  container = await new PostgreSqlContainer('postgres:16')
    .withDatabase('test_db')
    .start();

  process.env.DATABASE_URL = container.getConnectionUri();
  // Ejecutar migraciones
  execSync('pnpm prisma migrate deploy', { env: process.env });
}, 60_000);

afterAll(async () => {
  await container.stop();
});
```

**Regla:** Nunca mockear Prisma en tests E2E. Los mocks son solo para servicios externos.

---

## Evidencia de ejecución

Cada módulo que pasa por el gate debe tener evidencia en:

```
docs/e2e-evidence/<módulo>/
├── run-log.md           ← Resumen legible por humano
├── junit-results.xml    ← Output XML de Jest/Vitest
└── timing.json          ← Datos de performance
```

### Generar JUnit XML

```json
// jest.config.ts o vitest.config.ts
{
  "reporters": [
    "default",
    ["jest-junit", {
      "outputDirectory": "docs/e2e-evidence/<módulo>",
      "outputName": "junit-results.xml"
    }]
  ]
}
```

### Formato del run-log

```markdown
# Evidencia de ejecución — Módulo: trips

- **Fecha:** 2026-08-16
- **Commit:** abc123
- **Tests ejecutados:** 24
- **Tests pasados:** 24
- **Tests fallidos:** 0
- **Tiempo total:** 12.3s

## Escenarios ejecutados

| BSM ID | Descripción | Resultado | Tiempo |
|--------|-------------|-----------|--------|
| BSM-TRK-001 | Viaje completo happy path | ✅ PASS | 1.2s |
| BSM-TRK-020 | Sobrecapacidad rechazada | ✅ PASS | 0.3s |
| BSM-TRK-027 | Reserva concurrente | ✅ PASS | 2.1s |
```

### Formato del timing.json

```json
{
  "module": "trips",
  "date": "2026-08-16",
  "commit": "abc123",
  "totalTests": 24,
  "passed": 24,
  "failed": 0,
  "totalDurationMs": 12340,
  "scenarios": [
    { "id": "BSM-TRK-001", "durationMs": 1200, "result": "PASS" },
    { "id": "BSM-TRK-020", "durationMs": 300, "result": "PASS" }
  ]
}
```

---

## Referencias cruzadas

| Necesito saber... | Skill / Recurso |
|---|---|
| Patrones NestJS (módulos, guards, pipes, interceptors) | `nestjs-docs` |
| Prisma 7 driver adapters, $extends, transacciones | `prisma7-docs` |
| Reglas financieras, partida doble, Decimal.js, tenantId | `erp-saas-core` |
| Estándares generales del proyecto (lint, git, CI) | `fullstack` |
