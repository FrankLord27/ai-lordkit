---
name: zustand-docs
description: >
  Referencia completa de Zustand v5 para manejo de estado global en el cliente
  con Next.js 16. Úsala cuando trabajes con: creación de stores, slices pattern,
  middleware (persist, devtools, immer), uso en Server Components, hidratación SSR,
  stores tipados con TypeScript, o cuando debas decidir entre Zustand, Context API
  o TanStack Query para un problema de estado. También activa para: estado de UI
  (modals, sidebars, notificaciones), estado de sesión del cliente, o carrito de
  compras en sistemas POS/ecommerce.
---

# Zustand v5 — Referencia Completa

## Documentación oficial (Context7)

Para la doc oficial y actualizada de Zustand v5, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

## Cuándo usar Zustand vs otras opciones

```
Zustand
✅ Estado UI compartido entre componentes no relacionados
✅ Estado que persiste entre navegaciones (cliente)
✅ Stores complejos con múltiples acciones

Context API (sin Zustand)
✅ Estado simple que cambia raramente (theme, locale)
✅ Solo necesita propagarse a componentes hijos directos

TanStack Query (no Zustand)
✅ Estado del servidor — datos que vienen de una API
✅ Cache, sincronización, background refetch
```

## Patrones esenciales

```typescript
// Store tipado con TypeScript
interface CartStore {
  items: CartItem[];
  addItem: (item: CartItem) => void;
  removeItem: (id: string) => void;
  clear: () => void;
}

const useCartStore = create<CartStore>()((set) => ({
  items: [],
  addItem: (item) => set((state) => ({ items: [...state.items, item] })),
  removeItem: (id) =>
    set((state) => ({ items: state.items.filter((i) => i.id !== id) })),
  clear: () => set({ items: [] }),
}));

// Con persist middleware
const useAuthStore = create<AuthStore>()(
  persist((set) => ({ user: null, setUser: (user) => set({ user }) }), {
    name: "auth-storage",
  }),
);

// Slices pattern para stores grandes
const useStore = create<StoreState>()((...a) => ({
  ...createCartSlice(...a),
  ...createUISlice(...a),
}));
```

## Reglas no negociables

- **No guardar datos del servidor en Zustand** — eso va en TanStack Query
- **Selectors para evitar re-renders**: `const items = useCartStore(state => state.items)`
- **`devtools` middleware** siempre en desarrollo para debugging
- **SSR con Next.js**: inicializar stores con `createStore` (no `create`) para evitar estado compartido entre requests
