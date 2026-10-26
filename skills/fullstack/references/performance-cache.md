# Estrategias de Cache con Redis

---

## Cache-Aside — el patrón estándar

El patrón más usado. La app gestiona el cache manualmente.

```
READ:  App → Redis (hit?) → sí: retornar | no: DB → guardar en Redis → retornar
WRITE: App → DB → invalidar cache de Redis
```

```typescript
// El patrón completo en un Service
@Injectable()
export class ItemsService {
  constructor(
    private readonly repo: ItemRepository,
    private readonly redis: RedisService,
    private readonly logger: Logger,
  ) {}

  async findById(id: string): Promise<ItemDto> {
    const cacheKey = `item:${id}`;

    // 1. Intentar cache
    const cached = await this.redis.get<ItemDto>(cacheKey);
    if (cached) {
      this.logger.debug(`Cache hit: ${cacheKey}`);
      return cached;
    }

    // 2. Cache miss — ir a la DB
    this.logger.debug(`Cache miss: ${cacheKey}`);
    const item = await this.repo.findById(id);

    if (!item) throw new NotFoundException("Item no encontrado");

    // 3. Guardar en cache
    await this.redis.set(cacheKey, ItemMapper.toDto(item), 600); // 10 min

    return ItemMapper.toDto(item);
  }

  async update(id: string, dto: UpdateItemDto): Promise<ItemDto> {
    const item = await this.repo.update(id, dto);

    // Invalidar cache del item específico
    await this.redis.del(`item:${id}`);

    // Si el item aparece en listas cacheadas, invalidarlas también
    await this.redis.delByPattern("items:list:*");

    return ItemMapper.toDto(item);
  }

  async delete(id: string): Promise<void> {
    await this.repo.delete(id);
    await this.redis.del(`item:${id}`);
    await this.redis.delByPattern("items:list:*");
  }
}
```

---

## Nomenclatura de keys — consistente y predecible

```typescript
// Patrón: entidad:identificador:variante
// Separador: : (dos puntos)

// ✅ Keys bien nombradas
`item:${id}` // Item específico
`items:list:page:${page}:${limit}` // Página de listado
`items:search:${hash(filters)}` // Resultado de búsqueda
`user:${id}:profile` // Perfil de usuario
`user:${id}:bookings` // Bookings del usuario
`session:${token}` // Sesión
`refresh:${userId}:${token}` // Refresh token
// ❌ Keys mal nombradas
`data_${id}` // Ambiguo — ¿qué tipo de dato?
`cache_search_result` // Sin identificador — sobrescribe siempre
`user123profile`; // Sin separadores — difícil de parsear y limpiar
```

```typescript
// Helper para generar cache keys de búsquedas — hash del objeto de filtros
import { createHash } from "crypto";

export function hashFilters(filters: object): string {
  // Ordenar las keys para que el mismo objeto en diferente orden
  // genere el mismo hash
  const sorted = JSON.stringify(filters, Object.keys(filters).sort());
  return createHash("md5").update(sorted).digest("hex").slice(0, 8);
}

// Uso
const cacheKey = `items:search:${hashFilters(filters)}`;
```

---

## TTL correcto por tipo de dato

```typescript
// Constantes de TTL — definir en un archivo centralizado
export const CACHE_TTL = {
  // Datos que cambian con cada acción del usuario
  USER_PROFILE: 60, // 1 minuto
  USER_BOOKINGS: 30, // 30 segundos

  // Búsquedas y listados
  SEARCH_RESULTS: 300, // 5 minutos
  ITEM_LIST: 300, // 5 minutos
  ITEM_DETAIL: 600, // 10 minutos

  // Datos de referencia — cambian raramente
  LOCATIONS: 3600, // 1 hora
  CATEGORIES: 3600, // 1 hora
  CONFIGURATION: 86400, // 24 horas

  // Sesiones y tokens
  REFRESH_TOKEN: 604800, // 7 días
  SESSION: 3600, // 1 hora
} as const;
```

---

## Invalidación de cache — los patrones correctos

### Por key exacta — para items específicos

```typescript
// Al actualizar un item: invalidar solo ese item
await this.redis.del(`item:${id}`);
```

### Por patrón — para listas y búsquedas

```typescript
// Al crear/modificar/eliminar un item:
// todas las páginas de lista y búsquedas quedan obsoletas
await this.redis.delByPattern('items:list:*');
await this.redis.delByPattern('items:search:*');

// RedisService — implementación de delByPattern
async delByPattern(pattern: string): Promise<void> {
  // SCAN es mejor que KEYS en producción — no bloquea Redis
  let cursor = '0';
  do {
    const [nextCursor, keys] = await this.client.scan(
      cursor,
      'MATCH', pattern,
      'COUNT', 100,
    );
    cursor = nextCursor;
    if (keys.length > 0) {
      await this.client.del(...keys);
    }
  } while (cursor !== '0');
}
```

### Tags de cache — para invalidación semántica

```typescript
// Estrategia avanzada: guardar qué keys pertenecen a cada "tag"
// Útil cuando un objeto afecta múltiples tipos de cache

async setWithTags(key: string, value: unknown, ttl: number, tags: string[]) {
  await this.redis.set(key, value, ttl);

  // Guardar la key en cada conjunto de tags
  for (const tag of tags) {
    await this.client.sadd(`tag:${tag}`, key);
    await this.client.expire(`tag:${tag}`, ttl);
  }
}

async invalidateTag(tag: string) {
  // Obtener todas las keys con este tag e invalidarlas
  const keys = await this.client.smembers(`tag:${tag}`);
  if (keys.length > 0) {
    await this.client.del(...keys, `tag:${tag}`);
  }
}

// Uso
await this.setWithTags(
  `item:${id}`,
  itemData,
  600,
  ['items', `location:${locationId}`],
);

// Al cambiar algo de una location, invalida todo lo relacionado
await this.invalidateTag(`location:${locationId}`);
```

---

## Thundering Herd — cuando el cache expira y todos piden a la vez

El problema: el cache expira, y 100 requests llegan al mismo tiempo.
Todos van a la DB simultáneamente. La DB se satura.

```typescript
// Solución: mutex con Redis — solo uno accede a la DB, el resto espera
import { Mutex } from "async-mutex";

@Injectable()
export class ItemsService {
  private mutexes = new Map<string, Mutex>();

  private getMutex(key: string): Mutex {
    if (!this.mutexes.has(key)) {
      this.mutexes.set(key, new Mutex());
    }
    return this.mutexes.get(key);
  }

  async findById(id: string) {
    const cacheKey = `item:${id}`;
    const cached = await this.redis.get(cacheKey);
    if (cached) return cached;

    // Solo un proceso entra a buscar en DB — los demás esperan
    const mutex = this.getMutex(cacheKey);
    return mutex.runExclusive(async () => {
      // Verificar cache de nuevo — puede que ya lo haya cargado otro proceso
      const cachedAfterLock = await this.redis.get(cacheKey);
      if (cachedAfterLock) return cachedAfterLock;

      // Ahora sí ir a la DB
      const item = await this.repo.findById(id);
      await this.redis.set(cacheKey, item, 600);
      return item;
    });
  }
}
```

### Solución más simple: staggered TTL

```typescript
// Añadir jitter al TTL — los items no expiran todos al mismo tiempo
function ttlWithJitter(baseTtl: number, jitterPercent = 0.1): number {
  const jitter = baseTtl * jitterPercent;
  return Math.floor(baseTtl + (Math.random() * jitter * 2 - jitter));
}

// 5 minutos ± 30 segundos — los items expiran en momentos distintos
await this.redis.set(key, value, ttlWithJitter(300));
```

---

## Cache warming — precalentar antes de que los usuarios lleguen

```typescript
// Calentar el cache de datos críticos al iniciar la app
// O como job programado antes de hora pico

@Injectable()
export class CacheWarmingService implements OnModuleInit {
  async onModuleInit() {
    if (process.env.NODE_ENV !== "production") return;

    this.logger.log("Calentando cache...");

    await Promise.all([
      this.warmLocations(),
      this.warmCategories(),
      this.warmFeaturedItems(),
    ]);

    this.logger.log("Cache calentado");
  }

  private async warmLocations() {
    const locations = await this.prisma.location.findMany();
    await this.redis.set("locations:all", locations, CACHE_TTL.LOCATIONS);
  }

  private async warmFeaturedItems() {
    const items = await this.prisma.item.findMany({
      where: { featured: true },
      take: 20,
    });
    await this.redis.set("items:featured", items, CACHE_TTL.ITEM_LIST);
  }
}
```

---

## Qué NO cachear

```
❌ Nunca cachear:
  - Contraseñas (ni hasheadas)
  - Tokens de acceso completos
  - Datos médicos o información personal sensible
  - Resultados de búsquedas personalizadas con datos de otros usuarios
  - Datos que deben ser exactos en tiempo real (saldos de cuenta, inventario crítico)

⚠️ Cachear con cuidado:
  - Datos del usuario autenticado — TTL corto (< 60s), invalidar en logout
  - Precios — TTL muy corto si cambian frecuentemente
  - Disponibilidad — considerar si la precisión importa más que la velocidad
```

---

## Métricas de cache — saber si el cache está funcionando

```typescript
// Instrumentar el RedisService para medir hit rate
@Injectable()
export class RedisService {
  private hits = 0;
  private misses = 0;

  async get<T>(key: string): Promise<T | null> {
    const value = await this.client.get(key);

    if (value) {
      this.hits++;
    } else {
      this.misses++;
    }

    return value ? JSON.parse(value) : null;
  }

  // Endpoint de métricas — llamar periódicamente
  getStats() {
    const total = this.hits + this.misses;
    return {
      hits: this.hits,
      misses: this.misses,
      hitRate: total > 0 ? ((this.hits / total) * 100).toFixed(1) + "%" : "0%",
    };
  }
}

// Hit rate objetivo: > 80%
// Si es < 50%: el cache no está ayudando — revisar TTL y qué se cachea
// Si es > 95%: puede que el TTL sea demasiado largo — datos pueden ser stale
```
