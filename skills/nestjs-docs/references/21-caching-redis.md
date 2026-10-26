# Caching con Redis — @nestjs/cache-manager

## Instalación

```bash
pnpm add @nestjs/cache-manager cache-manager cache-manager-redis-yet redis
```

---

## Configuración del módulo

```typescript
// app.module.ts
import { Module } from "@nestjs/common";
import { CacheModule } from "@nestjs/cache-manager";
import { redisStore } from "cache-manager-redis-yet";

@Module({
  imports: [
    CacheModule.registerAsync({
      isGlobal: true, // Disponible en todos los módulos sin importar
      useFactory: async () => ({
        store: await redisStore({
          socket: {
            host: process.env.REDIS_HOST ?? "localhost",
            port: parseInt(process.env.REDIS_PORT ?? "6379"),
          },
          password: process.env.REDIS_PASSWORD,
          ttl: 60 * 1000, // TTL default: 60 segundos (en ms)
        }),
      }),
    }),
  ],
})
export class AppModule {}
```

---

## Uso básico con decorador @Cacheable (automático)

El `CacheInterceptor` cachea automáticamente las respuestas GET.

```typescript
// products/products.controller.ts
import { Controller, Get, UseInterceptors } from "@nestjs/common";
import { CacheInterceptor, CacheTTL, CacheKey } from "@nestjs/cache-manager";

@Controller("products")
@UseInterceptors(CacheInterceptor) // Aplica a todos los GET del controller
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  @Get()
  @CacheTTL(300000) // 5 minutos en ms
  @CacheKey("all-products") // Key explícita (opcional)
  findAll() {
    // Esta query solo se ejecuta si el cache está vacío o expiró
    return this.productsService.findAll();
  }

  @Get(":id")
  @CacheTTL(60000) // 1 minuto
  findOne(@Param("id") id: string) {
    // Key automática: GET_/products/:id
    return this.productsService.findOne(id);
  }
}
```

**Problema del CacheInterceptor**: La key automática es la URL, así que `/products?page=1` y `/products?page=2` tienen la misma key. Para queries con parámetros, usa `@CacheKey()` dinámico o el patrón manual.

---

## Uso manual en Services (recomendado para control)

```typescript
// products/products.service.ts
import { Injectable, Inject } from "@nestjs/common";
import { CACHE_MANAGER } from "@nestjs/cache-manager";
import { Cache } from "cache-manager";

@Injectable()
export class ProductsService {
  constructor(
    @Inject(CACHE_MANAGER) private readonly cache: Cache,
    private readonly prisma: PrismaService,
  ) {}

  async findAll(filters: ProductFiltersDto): Promise<Product[]> {
    // Generar key única basada en los filtros
    const cacheKey = `products:${JSON.stringify(filters)}`;

    // Intentar obtener del cache
    const cached = await this.cache.get<Product[]>(cacheKey);
    if (cached) {
      return cached; // Cache HIT
    }

    // Cache MISS: ir a la base de datos
    const products = await this.prisma.product.findMany({
      where: {
        categoryId: filters.categoryId,
        isActive: true,
      },
      orderBy: { createdAt: "desc" },
    });

    // Guardar en cache con TTL de 5 minutos
    await this.cache.set(cacheKey, products, 5 * 60 * 1000);

    return products;
  }

  async findOne(id: string): Promise<Product | null> {
    const cacheKey = `product:${id}`;
    const cached = await this.cache.get<Product>(cacheKey);
    if (cached) return cached;

    const product = await this.prisma.product.findUnique({ where: { id } });
    if (product) {
      await this.cache.set(cacheKey, product, 60 * 1000); // 1 minuto
    }

    return product;
  }
}
```

---

## Invalidación de cache

La parte más importante y más olvidada. Cuando los datos cambian, el cache debe invalidarse.

```typescript
// products/products.service.ts
@Injectable()
export class ProductsService {
  constructor(
    @Inject(CACHE_MANAGER) private readonly cache: Cache,
    private readonly prisma: PrismaService,
  ) {}

  async create(dto: CreateProductDto): Promise<Product> {
    const product = await this.prisma.product.create({ data: dto });

    // Invalidar cache de lista (cualquier combinación de filtros)
    await this.invalidateProductsCache();

    return product;
  }

  async update(id: string, dto: UpdateProductDto): Promise<Product> {
    const product = await this.prisma.product.update({
      where: { id },
      data: dto,
    });

    // Invalidar cache específico del producto
    await this.cache.del(`product:${id}`);

    // Invalidar cache de lista
    await this.invalidateProductsCache();

    return product;
  }

  async remove(id: string): Promise<void> {
    await this.prisma.product.delete({ where: { id } });
    await this.cache.del(`product:${id}`);
    await this.invalidateProductsCache();
  }

  // Invalidar todas las keys que empiezan con "products:"
  private async invalidateProductsCache(): Promise<void> {
    // cache-manager-redis-yet permite usar el cliente Redis directamente
    const client = (this.cache.store as any).client;
    const keys = await client.keys("products:*");
    if (keys.length > 0) {
      await client.del(keys);
    }
  }
}
```

---

## Patrón Cache-Aside con helper reutilizable

```typescript
// common/cache/cache.helper.ts
import { Inject, Injectable } from '@nestjs/common';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Cache } from 'cache-manager';

@Injectable()
export class CacheHelper {
  constructor(@Inject(CACHE_MANAGER) private readonly cache: Cache) {}

  /**
   * Obtiene del cache o ejecuta la función y guarda el resultado
   */
  async getOrSet<T>(
    key: string,
    fetcher: () => Promise<T>,
    ttlMs: number = 60000,
  ): Promise<T> {
    const cached = await this.cache.get<T>(key);
    if (cached !== undefined && cached !== null) {
      return cached;
    }

    const fresh = await fetcher();
    if (fresh !== undefined && fresh !== null) {
      await this.cache.set(key, fresh, ttlMs);
    }

    return fresh;
  }

  /**
   * Invalida múltiples keys por patrón
   */
  async invalidateByPattern(pattern: string): Promise<number> {
    const client = (this.cache.store as any).client;
    const keys = await client.keys(pattern);
    if (keys.length > 0) {
      await client.del(keys);
    }
    return keys.length;
  }

  /**
   * Invalida múltiples keys específicas
   */
  async invalidateMany(keys: string[]): Promise<void> {
    await Promise.all(keys.map((key) => this.cache.del(key)));
  }
}

// Uso en service:
async findAll(filters: ProductFiltersDto): Promise<Product[]> {
  return this.cacheHelper.getOrSet(
    `products:${JSON.stringify(filters)}`,
    () => this.prisma.product.findMany({ where: filters }),
    5 * 60 * 1000,  // 5 minutos
  );
}
```

---

## TTL recomendados por tipo de dato

| Tipo de dato                   | TTL            | Razón                               |
| ------------------------------ | -------------- | ----------------------------------- |
| Catálogos (categorías, países) | 1-24 horas     | Casi nunca cambian                  |
| Listas de productos            | 5-15 minutos   | Cambian moderadamente               |
| Detalle de producto            | 1-5 minutos    | Puede cambiar por stock             |
| Usuario autenticado            | 5 minutos      | Balance seguridad/performance       |
| Configuración del tenant       | 1 hora         | Cambia raramente                    |
| Resultados de búsqueda         | 1-5 minutos    | Depende de la frecuencia de updates |
| Datos en tiempo real           | 0 (no cachear) | Siempre frescos                     |

---

## Cache en multi-tenant

```typescript
// Siempre incluir tenantId en la cache key
const cacheKey = `tenant:${tenantId}:products:${JSON.stringify(filters)}`;

// Invalidar todo el cache de un tenant específico
await this.cacheHelper.invalidateByPattern(`tenant:${tenantId}:*`);
```

---

## Testing con cache mockeado

```typescript
// products.service.spec.ts
describe("ProductsService", () => {
  let service: ProductsService;
  let cacheManager: Cache;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        ProductsService,
        {
          provide: CACHE_MANAGER,
          useValue: {
            get: jest.fn(),
            set: jest.fn(),
            del: jest.fn(),
            store: { client: { keys: jest.fn(), del: jest.fn() } },
          },
        },
        // ... otros providers
      ],
    }).compile();

    service = module.get(ProductsService);
    cacheManager = module.get(CACHE_MANAGER);
  });

  it("should return cached data on cache hit", async () => {
    const cachedProducts = [{ id: "1", name: "Product" }];
    jest.spyOn(cacheManager, "get").mockResolvedValue(cachedProducts);

    const result = await service.findAll({});

    expect(result).toEqual(cachedProducts);
    expect(cacheManager.get).toHaveBeenCalledWith("products:{}");
  });

  it("should fetch from DB and cache on cache miss", async () => {
    jest.spyOn(cacheManager, "get").mockResolvedValue(null);
    // ... mock prisma

    await service.findAll({});

    expect(cacheManager.set).toHaveBeenCalled();
  });
});
```

---

## Errores comunes y soluciones

| Error                         | Causa                                     | Solución                                                              |
| ----------------------------- | ----------------------------------------- | --------------------------------------------------------------------- |
| Cache nunca expira            | TTL en segundos en vez de ms              | Usar milisegundos: `60 * 1000`                                        |
| Datos stale después de update | No invalidaste el cache                   | Llamar `cache.del()` en create/update/delete                          |
| Memory leak en Redis          | Keys sin TTL                              | Siempre pasar TTL, nunca `cache.set(key, value)` sin tercer parámetro |
| Cache key collision           | Keys muy genéricas                        | Incluir entidad, tenantId, y filtros en la key                        |
| Thundering herd               | Muchos requests simultáneos cuando expira | Usar lock distribuido o stale-while-revalidate                        |

---

## Checklist de implementación

- [ ] Instalar dependencias: `@nestjs/cache-manager`, `cache-manager-redis-yet`
- [ ] Configurar `CacheModule.registerAsync()` con Redis
- [ ] Crear `CacheHelper` para patrón cache-aside
- [ ] Definir TTLs por tipo de dato
- [ ] Implementar invalidación en create/update/delete
- [ ] Incluir `tenantId` en keys para multi-tenant
- [ ] Agregar tests con cache mockeado
- [ ] Monitorear hit rate en producción
