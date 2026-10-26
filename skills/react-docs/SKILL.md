---
name: react-docs
description: >
  Referencia completa de React 19.2 para componentes de cliente en Next.js 16.
  Úsala cuando trabajes con: hooks (useState, useEffect, useCallback, useMemo,
  useRef, useContext, useReducer, useTransition, useDeferredValue, useOptimistic),
  patrones de estado, composición de componentes, context API, portals, forwardRef,
  concurrent features, React 19.2 Actions, use() hook, o cuando necesites decidir
  entre Server Component y Client Component. También activa para: optimización de
  re-renders, memoización, manejo de formularios sin librerías externas, o errores
  relacionados con el ciclo de vida de componentes React.
---

# React 19.2 — Referencia Completa

## Documentación oficial (Context7)

Para la doc oficial y actualizada de React, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

## Server Component vs Client Component

```
Server Component (por defecto en Next.js App Router)
✅ Acceso a DB, filesystem, secrets
✅ Sin bundle size en el cliente
✅ SEO, performance
❌ No puede usar hooks de estado/efecto
❌ No puede usar event listeners

Client Component ("use client" al inicio)
✅ Interactividad, eventos, animaciones
✅ Hooks de estado (useState, useEffect)
✅ Browser APIs (localStorage, window)
❌ Aumenta bundle del cliente
```

## Hooks de React 19.2 más importantes

```typescript
// useTransition — marcar actualizaciones como no urgentes
const [isPending, startTransition] = useTransition();
startTransition(() => setFilter(newFilter));

// useOptimistic — UI optimista (React 19.2)
const [optimisticItems, addOptimistic] = useOptimistic(items);

// use() — leer recursos en render (React 19.2)
const data = use(fetchPromise);
const theme = use(ThemeContext);

// useDeferredValue — diferir valor para no bloquear UI
const deferredSearch = useDeferredValue(searchQuery);
```

## Reglas no negociables

- **Componentes funcionales** siempre — nunca clases
- **`"use client"`** solo cuando realmente se necesite interactividad
- **Keys únicas** en listas — nunca el índice del array como key
- **No mutar estado directamente** — siempre crear nuevo objeto/array
- **Efectos con cleanup** cuando suscriben a eventos o timers
- **Memoización solo cuando haya problema de performance medido** — no prematuramente
