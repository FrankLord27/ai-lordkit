# 07 — Offline-First en POS

## Por qué

Un POS físico no puede detener ventas porque cayó el WiFi del local. La caída de internet promedio en R.D. es minutos, no horas, pero suficiente para perder ventas y enojar clientes.

---

## Estrategia general

```
[Cajero] → [PWA Next.js + IndexedDB] → [TanStack Query 5] ↔ [API NestJS]
                  ↑                            ↑
        Cache de productos                Cola de mutaciones
        Cache de cliente                  Sincroniza al volver
        Bloque pre-asignado de NCF
```

---

## 1. PWA: que cargue sin red

```typescript
// next.config.js
const withPWA = require("@ducanh2912/next-pwa").default({
  dest: "public",
  cacheOnFrontEndNav: true,
  aggressiveFrontEndNavCaching: true,
  reloadOnOnline: true,
  workboxOptions: {
    runtimeCaching: [
      {
        urlPattern: /^https:\/\/api\.miPos\.com\/products/,
        handler: "StaleWhileRevalidate",
        options: {
          cacheName: "api-products",
          expiration: { maxAgeSeconds: 60 * 60 * 24 },
        },
      },
      {
        urlPattern: /^https:\/\/api\.miPos\.com\//,
        handler: "NetworkFirst",
        options: { cacheName: "api-other", networkTimeoutSeconds: 3 },
      },
    ],
  },
});

module.exports = withPWA({
  /* next config */
});
```

```json
// public/manifest.json
{
  "name": "POS",
  "short_name": "POS",
  "start_url": "/pos",
  "display": "standalone",
  "background_color": "#0a0a0a",
  "theme_color": "#0a0a0a",
  "icons": [
    /* ... */
  ]
}
```

---

## 2. TanStack Query con persistencia

```typescript
// lib/query-client.ts
import { QueryClient } from "@tanstack/react-query";
import { persistQueryClient } from "@tanstack/react-query-persist-client";
import { createSyncStoragePersister } from "@tanstack/query-sync-storage-persister";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      networkMode: "offlineFirst",
      staleTime: 1000 * 60 * 5, // 5 min antes de refetch
      gcTime: 1000 * 60 * 60 * 24, // 24h en caché
      retry: (failureCount, error: any) => {
        if (error?.response?.status === 401) return false;
        return failureCount < 3;
      },
    },
    mutations: {
      networkMode: "offlineFirst", // ★ encola mutaciones offline
      retry: 3,
      retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 30_000),
    },
  },
});

if (typeof window !== "undefined") {
  const persister = createSyncStoragePersister({
    storage: window.localStorage,
    throttleTime: 1000,
  });

  persistQueryClient({
    queryClient,
    persister,
    maxAge: 1000 * 60 * 60 * 24,
    buster: "v1", // bump para invalidar todo cuando cambia el schema
  });
}
```

> Para datasets grandes (catálogo de 10k+ productos), reemplazá `localStorage` por IndexedDB con `idb-keyval`:
>
> ```typescript
> import { get, set, del } from "idb-keyval";
> const persister = createAsyncStoragePersister({
>   storage: { getItem: get, setItem: set, removeItem: del },
> });
> ```

---

## 3. Encolar mutaciones offline

TanStack Query 5 + `networkMode: 'offlineFirst'` encola las mutations automáticamente cuando `navigator.onLine === false`.

```typescript
// hooks/useCompleteSale.ts
export function useCompleteSale() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationKey: ["sales", "complete"], // ★ para resume
    mutationFn: async (payload: SalePayload) => {
      const idempotencyKey = payload.localId; // usa local ID como key
      return api.post("/sales", payload, {
        headers: { "X-Idempotency-Key": idempotencyKey },
      });
    },
    onMutate: async (payload) => {
      // Optimistic update: el cajero ve "venta registrada" aunque esté offline
      const optimistic = { ...payload, status: "PENDING_SYNC" };
      queryClient.setQueryData(["sales", payload.localId], optimistic);
      return { optimistic };
    },
    onSuccess: (server, payload) => {
      queryClient.setQueryData(["sales", payload.localId], {
        ...server,
        status: "SYNCED",
      });
    },
  });
}
```

Resume mutations al recuperar conexión:

```typescript
// app/providers.tsx
useEffect(() => {
  const onlineHandler = () => queryClient.resumePausedMutations();
  window.addEventListener("online", onlineHandler);
  return () => window.removeEventListener("online", onlineHandler);
}, []);
```

---

## 4. NCF pre-asignados: el problema fiscal de operar offline

En R.D., el NCF debe ser único y secuencial por tenant. Si lo asigna el backend, no podés facturar offline porque no sabés el siguiente número.

### Solución: bloque pre-asignado por caja

Al abrir la sesión de caja (online), el backend reserva un rango:

```typescript
// POST /pos/sessions/open
async openSession(cmd: OpenSessionCommand) {
  return this.prisma.$transaction(async (tx) => {
    // Lock secuencia para asignar rango
    const sequence = await tx.$queryRaw<Array<{ from: number; to: number }>>`
      UPDATE "NcfSequence"
      SET "currentValue" = "currentValue" + 50
      WHERE "tenantId" = ${cmd.tenantId} AND "type" = 'B02'
      RETURNING "currentValue" - 49 AS "from", "currentValue" AS "to"
    `;

    const session = await tx.posSession.create({
      data: {
        tenantId: cmd.tenantId,
        cashRegisterId: cmd.cashRegisterId,
        userId: cmd.userId,
        ncfBlockFrom: sequence[0].from,
        ncfBlockTo: sequence[0].to,
        ncfBlockCurrent: sequence[0].from - 1,
        // ...
      },
    });

    return session;
  }, { isolationLevel: 'Serializable' });
}
```

El frontend recibe el rango y lo guarda en `localStorage`:

```typescript
const session = await openSession();
localStorage.setItem(
  "pos:session",
  JSON.stringify({
    id: session.id,
    ncfRange: { from: session.ncfBlockFrom, to: session.ncfBlockTo },
    ncfUsed: [],
  }),
);
```

Al facturar offline, el frontend asigna el siguiente NCF del rango:

```typescript
function getNextLocalNcf(): string {
  const session = JSON.parse(localStorage.getItem("pos:session"));
  const nextNumber = session.ncfRange.from + session.ncfUsed.length;
  if (nextNumber > session.ncfRange.to) {
    throw new Error("NCF block exhausted — go online to refill");
  }
  session.ncfUsed.push(nextNumber);
  localStorage.setItem("pos:session", JSON.stringify(session));
  return formatNcf("B02", nextNumber);
}
```

Al volver online, las ventas pendientes se sincronizan con su NCF ya asignado. El backend valida que el NCF está dentro del rango de esa sesión.

---

## 5. Conflictos al sincronizar

Posibles conflictos:

| Conflicto                            | Detección               | Resolución                                      |
| ------------------------------------ | ----------------------- | ----------------------------------------------- |
| Stock insuficiente (otro POS vendió) | Backend rechaza el item | Marcar venta como "sin stock", notificar cajero |
| Producto eliminado                   | Backend rechaza         | Marcar venta para revisión manual               |
| Cliente eliminado                    | Backend rechaza         | Cambiar a "consumidor final" automático         |
| Sesión ya cerrada                    | Backend rechaza         | Reabrir sesión o crear nueva                    |
| NCF fuera de rango                   | Backend rechaza         | Error fatal: requiere intervención              |

```typescript
// hooks/useSyncStatus.ts
export function useSyncStatus() {
  const isOnline = useOnlineStatus();
  const isFetching = useIsFetching();
  const isMutating = useIsMutating();
  const pending = useMutationState({ filters: { status: "pending" } });

  return {
    isOnline,
    pendingSyncCount: pending.length,
    isSyncing: isMutating > 0,
  };
}
```

Mostrar en la UI siempre: badge verde "Online — Sincronizado" o amarillo "Offline — 5 ventas pendientes".

---

## 6. Stock optimista vs realidad

Cuando estás offline, no sabés si otro POS vendió el último item. Estrategias:

1. **Permitir vender sin validar stock offline.** Al sincronizar, si hay sobreventa, generar nota de crédito automática y notificar.
2. **Reserva de stock por POS.** Al abrir sesión, reservás N unidades de los SKUs top. Riesgo: mercancía "fantasma" si la sesión no cierra.
3. **Bloqueo total: prohibir ventas offline de productos con stock < 5.**

Recomendación: opción 1 + un campo `offlineSold` en producto para auditar. La mayoría de tiendas físicas tienen mucho más stock que sobreventas potenciales.

---

## Tests offline-first

```typescript
describe("Offline mode", () => {
  beforeEach(() => {
    Object.defineProperty(navigator, "onLine", {
      value: false,
      writable: true,
    });
  });

  it("completes a sale offline and queues it", async () => {
    const { result } = renderHook(() => useCompleteSale(), { wrapper });
    await act(() => result.current.mutate(salePayload));
    expect(result.current.status).toBe("pending");
    expect(queryClient.getMutationCache().getAll()).toHaveLength(1);
  });

  it("resumes paused mutations when online returns", async () => {
    // ... mutate offline
    Object.defineProperty(navigator, "onLine", { value: true });
    window.dispatchEvent(new Event("online"));
    await waitFor(() => expect(result.current.status).toBe("success"));
  });
});
```
