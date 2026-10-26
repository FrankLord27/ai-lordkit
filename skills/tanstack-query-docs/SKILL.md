---
name: tanstack-query-docs
description: >
  Referencia completa de TanStack Query v5 para data fetching en Next.js 16 con
  React. Úsala SIEMPRE que trabajes con: useQuery, useMutation, useInfiniteQuery,
  QueryClient, QueryClientProvider, cache invalidation, prefetching en Server
  Components, Suspense queries, optimistic updates, deduplication de requests,
  retry logic, background refetch, o cuando debas decidir entre Server Component
  fetch y TanStack Query. También activa para: configuración de staleTime/gcTime,
  integración con Server Actions, o errores relacionados con hidratación y SSR.
---

# TanStack Query v5 — Referencia Completa

## Documentación oficial (Context7)

Para la doc oficial y actualizada de TanStack Query v5, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

## Cuándo usar TanStack Query vs Server Component fetch

```
Server Component fetch (sin TanStack Query)
✅ Datos que no cambian sin interacción del usuario
✅ Initial page load, SEO critical data
✅ No necesitas mostrar loading states en cliente

TanStack Query (en Client Components)
✅ Datos que se actualizan en respuesta a acciones del usuario
✅ Polling, background refetch, optimistic updates
✅ Cache compartido entre componentes
✅ Infinite scroll / pagination
```

## Patrones esenciales v5

```typescript
// Query básica
const { data, isLoading, error } = useQuery({
  queryKey: ["users", filters],
  queryFn: () => fetchUsers(filters),
  staleTime: 5 * 60 * 1000, // 5 minutos
});

// Mutation con invalidación
const mutation = useMutation({
  mutationFn: createUser,
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ["users"] });
  },
});

// Prefetch en Server Component (Next.js 16)
const queryClient = new QueryClient();
await queryClient.prefetchQuery({
  queryKey: ["users"],
  queryFn: fetchUsers,
});
// Pasar dehydratedState al cliente via HydrationBoundary
```

## Reglas no negociables

- **`queryKey` siempre como array** y debe incluir todos los parámetros que afecten el resultado
- **`staleTime`** explícito en cada query — default 0 genera demasiadas peticiones
- **No llamar** al mismo endpoint desde Server Component Y useQuery en el mismo render
- **Invalidar por prefijo** cuando sea posible: `{ queryKey: ['users'] }` invalida todos los keys que empiecen con `'users'`
- **v5 breaking change**: no usar `status === 'loading'` → usar `isLoading` o `isPending`
