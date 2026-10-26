# LEGADO — Frontend con Sass + CSS Modules + BEM

> Solo para proyectos que YA usan Sass/BEM (`*.module.scss`). En ellos se sigue la convención existente; no se migra a Tailwind sin que el usuario lo pida. Proyectos nuevos: `stack-frontend.md` (Tailwind v4).

---

## Next.js 16 — App Router

### Estructura de carpetas estándar

```
apps/web/src/
├── app/
│   ├── layout.tsx              ← Server Component. Providers globales aquí.
│   ├── page.tsx                ← Server Component. Fetch inicial de datos.
│   ├── (auth)/                 ← Grupo de rutas sin layout compartido
│   │   ├── login/page.tsx
│   │   └── register/page.tsx
│   └── (main)/                 ← Rutas protegidas
│       ├── layout.tsx          ← Verifica sesión, muestra nav
│       └── [feature]/page.tsx
├── components/
│   └── ui/                     ← Componentes genéricos: Button, Input, Modal
├── features/
│   └── [dominio]/              ← Todo lo relacionado a un dominio aquí
│       ├── api/                ← Hooks TanStack Query
│       │   ├── query-keys.ts
│       │   ├── use-[entidad].ts
│       │   └── use-create-[entidad].ts
│       ├── components/         ← Componentes específicos del dominio
│       └── stores/             ← Zustand stores del dominio
├── lib/
│   ├── api-client.ts           ← fetch wrapper tipado
│   └── query-client.ts         ← Configuración TanStack Query
└── styles/
    ├── _variables.scss
    ├── _mixins.scss
    ├── _reset.scss
    └── globals.scss
```

### Server vs Client Components

**Server Component (default — sin `'use client'`):**

- Fetch de datos iniciales
- Layouts y páginas sin interactividad
- Acceso a variables de entorno privadas

```tsx
// app/(main)/items/page.tsx — Server Component
// Fetch directo sin TanStack Query en el servidor
async function ItemsPage() {
  const items = await fetch(`${process.env.API_URL}/api/v1/items`).then((r) =>
    r.json(),
  );
  return <ItemsList initialData={items} />;
}
```

**Client Component (`'use client'` solo cuando es necesario):**

- useState, useEffect, event handlers
- TanStack Query hooks
- Librerías que usan el DOM

```tsx
"use client";
// Recibe datos iniciales del Server Component — sin loading inicial
export function ItemsList({ initialData }: { initialData: Item[] }) {
  const { data } = useItems({ initialData }); // TanStack Query hidrata con initialData
  return (
    <div>
      {data?.map((item) => (
        <ItemCard key={item.id} item={item} />
      ))}
    </div>
  );
}
```

**Buena práctica — pasar datos del Server al Client:**

```tsx
// Server Component pasa initialData → no hay spinner en el primer render
async function Page() {
  const data = await fetchItems();
  return <ClientComponent initialData={data} />;
}
```

---

## TanStack Query

### Configuración global

```typescript
// lib/query-client.ts
import { QueryClient } from "@tanstack/react-query";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 min — no refetch si data es reciente
      retry: 1, // 1 reintento en error
      refetchOnWindowFocus: false, // No refetch al cambiar de tab
    },
  },
});
```

```tsx
// app/layout.tsx
"use client";
import { QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import { queryClient } from "@/lib/query-client";

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html>
      <body>
        <QueryClientProvider client={queryClient}>
          {children}
          <ReactQueryDevtools initialIsOpen={false} />
        </QueryClientProvider>
      </body>
    </html>
  );
}
```

### Query Keys — siempre como constantes

```typescript
// features/items/api/query-keys.ts
export const itemKeys = {
  all: ["items"] as const,
  lists: () => [...itemKeys.all, "list"] as const,
  search: (filters: SearchFilters) => [...itemKeys.lists(), filters] as const,
  detail: (id: string) => [...itemKeys.all, "detail", id] as const,
};
// Uso: queryClient.invalidateQueries({ queryKey: itemKeys.lists() })
```

### Hook de query estándar

```typescript
// features/items/api/use-items.ts
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "@/lib/api-client";
import { itemKeys } from "./query-keys";

export const useSearchItems = (filters: SearchFilters) => {
  return useQuery({
    queryKey: itemKeys.search(filters),
    queryFn: () => apiClient.post<SearchResponse>("/items/search", filters),
    staleTime: 1000 * 60 * 5,
    enabled: !!filters.locationId, // Solo ejecuta si hay datos necesarios
  });
};

export const useItemDetail = (id: string) => {
  return useQuery({
    queryKey: itemKeys.detail(id),
    queryFn: () => apiClient.get<Item>(`/items/${id}`),
    enabled: !!id,
  });
};
```

### Mutación con invalidación de cache

```typescript
// features/items/api/use-create-item.ts
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "@/lib/api-client";
import { itemKeys } from "./query-keys";

export const useCreateItem = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateItemInput) => apiClient.post<Item>("/items", data),
    onSuccess: () => {
      // Invalida la lista completa → se refetchea automáticamente
      queryClient.invalidateQueries({ queryKey: itemKeys.lists() });
    },
    onError: (error) => {
      console.error("Error creando item:", error);
    },
  });
};
```

### API Client tipado

```typescript
// lib/api-client.ts
const BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001/api/v1";

class ApiClientError extends Error {
  constructor(
    public override message: string,
    public statusCode: number,
  ) {
    super(message);
    this.name = "ApiClientError";
  }
}

async function apiFetch<T>(
  endpoint: string,
  options?: RequestInit,
): Promise<T> {
  const response = await fetch(`${BASE_URL}${endpoint}`, {
    ...options,
    headers: { "Content-Type": "application/json", ...options?.headers },
    credentials: "include", // Cookies JWT httpOnly
  });

  if (!response.ok) {
    const error = await response.json();
    throw new ApiClientError(error.message, error.statusCode);
  }

  // El backend envuelve en { data } — extraemos aquí
  const result = await response.json();
  return result.data ?? result;
}

export const apiClient = {
  get: <T>(url: string, options?: RequestInit) =>
    apiFetch<T>(url, { ...options, method: "GET" }),
  post: <T>(url: string, body: unknown, options?: RequestInit) =>
    apiFetch<T>(url, {
      ...options,
      method: "POST",
      body: JSON.stringify(body),
    }),
  put: <T>(url: string, body: unknown, options?: RequestInit) =>
    apiFetch<T>(url, { ...options, method: "PUT", body: JSON.stringify(body) }),
  patch: <T>(url: string, body: unknown, options?: RequestInit) =>
    apiFetch<T>(url, {
      ...options,
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  delete: <T>(url: string, options?: RequestInit) =>
    apiFetch<T>(url, { ...options, method: "DELETE" }),
};
```

---

## Zustand

### Cuándo usar

| Usar Zustand                      | No usar Zustand                          |
| --------------------------------- | ---------------------------------------- |
| Filtros activos de la UI          | Datos del servidor → TanStack Query      |
| Paso actual de un wizard          | Estado local de un componente → useState |
| Carrito de compras                |                                          |
| Preferencias de UI (tema, idioma) |                                          |

### Patrón — un store por dominio, pequeño y enfocado

```typescript
// features/booking/stores/use-booking-store.ts
import { create } from "zustand";

interface BookingStore {
  // Estado
  step: number;
  selectedItemId: string | null;
  // Acciones
  setStep: (step: number) => void;
  selectItem: (id: string) => void;
  reset: () => void;
}

const initialState = { step: 1, selectedItemId: null };

export const useBookingStore = create<BookingStore>((set) => ({
  ...initialState,
  setStep: (step) => set({ step }),
  selectItem: (id) => set({ selectedItemId: id }),
  reset: () => set(initialState), // Siempre tener un reset
}));
```

### Con persistencia (carrito, preferencias)

```typescript
import { create } from "zustand";
import { persist } from "zustand/middleware";

export const useCartStore = create<CartStore>()(
  persist(
    (set, get) => ({
      items: [],
      addItem: (item) => set({ items: [...get().items, item] }),
      removeItem: (id) =>
        set({ items: get().items.filter((i) => i.id !== id) }),
      clear: () => set({ items: [] }),
    }),
    { name: "cart-storage" }, // localStorage key
  ),
);
```

---

## React Hook Form + Zod

### Regla clave

El schema Zod siempre viene de `shared-types`. El mismo schema valida frontend y backend.

```typescript
// packages/shared-types/src/schemas/item.schema.ts
import { z } from "zod";

export const CreateItemSchema = z.object({
  name: z.string().min(2, "Mínimo 2 caracteres"),
  price: z.number().min(0, "El precio no puede ser negativo"),
  categoryId: z.string().uuid("ID de categoría inválido"),
});

export type CreateItemInput = z.infer<typeof CreateItemSchema>;
```

```tsx
// Uso en componente
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { CreateItemSchema, CreateItemInput } from "@mystack/shared-types";
import { useCreateItem } from "../api/use-create-item";

export function CreateItemForm() {
  const createItem = useCreateItem();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<CreateItemInput>({
    resolver: zodResolver(CreateItemSchema),
  });

  const onSubmit = async (data: CreateItemInput) => {
    await createItem.mutateAsync(data);
    reset();
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <div>
        <input {...register("name")} placeholder="Nombre" />
        {errors.name && (
          <span className={styles.error}>{errors.name.message}</span>
        )}
      </div>
      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? "Guardando..." : "Crear"}
      </button>
    </form>
  );
}
```

---

## Sass + CSS Modules

### Variables y design tokens

```scss
// styles/_variables.scss
:root {
  // Colores
  --color-primary: #2563eb;
  --color-primary-hover: #1d4ed8;
  --color-danger: #dc2626;
  --color-text: #111827;
  --color-text-muted: #6b7280;
  --color-bg: #ffffff;
  --color-border: #e5e7eb;

  // Espaciado
  --spacing-xs: 0.25rem;
  --spacing-sm: 0.5rem;
  --spacing-md: 1rem;
  --spacing-lg: 1.5rem;
  --spacing-xl: 2rem;

  // Tipografía
  --font-size-sm: 0.875rem;
  --font-size-base: 1rem;
  --font-size-lg: 1.125rem;
  --font-size-xl: 1.25rem;

  // Bordes
  --radius-sm: 0.25rem;
  --radius-md: 0.5rem;
  --radius-lg: 0.75rem;

  // Sombras
  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
  --shadow-md: 0 4px 6px rgba(0, 0, 0, 0.07);
}
```

```scss
// styles/_mixins.scss
@mixin flex-center {
  display: flex;
  align-items: center;
  justify-content: center;
}

@mixin breakpoint($size) {
  @if $size == sm {
    @media (min-width: 640px) {
      @content;
    }
  }
  @if $size == md {
    @media (min-width: 768px) {
      @content;
    }
  }
  @if $size == lg {
    @media (min-width: 1024px) {
      @content;
    }
  }
  @if $size == xl {
    @media (min-width: 1280px) {
      @content;
    }
  }
}

@mixin text-ellipsis {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
```

### Componente con CSS Module

```scss
// components/ui/Button/Button.module.scss
.button {
  display: inline-flex;
  align-items: center;
  gap: var(--spacing-sm);
  padding: var(--spacing-sm) var(--spacing-md);
  border-radius: var(--radius-md);
  font-size: var(--font-size-base);
  font-weight: 500;
  cursor: pointer;
  transition: opacity 0.15s ease;
  border: none;

  &:hover:not(:disabled) {
    opacity: 0.88;
  }
  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  // Variantes con BEM modifier
  &--primary {
    background: var(--color-primary);
    color: white;
  }

  &--secondary {
    background: transparent;
    color: var(--color-primary);
    border: 1px solid var(--color-primary);
  }

  &--danger {
    background: var(--color-danger);
    color: white;
  }

  // Tamaños
  &--sm {
    padding: var(--spacing-xs) var(--spacing-sm);
    font-size: var(--font-size-sm);
  }
  &--lg {
    padding: var(--spacing-md) var(--spacing-lg);
    font-size: var(--font-size-lg);
  }
}
```

```tsx
// components/ui/Button/Button.tsx
import styles from "./Button.module.scss";

type ButtonVariant = "primary" | "secondary" | "danger";
type ButtonSize = "sm" | "md" | "lg";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

export function Button({
  variant = "primary",
  size = "md",
  className,
  children,
  ...props
}: ButtonProps) {
  const classes = [
    styles.button,
    styles[`button--${variant}`],
    size !== "md" && styles[`button--${size}`],
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <button className={classes} {...props}>
      {children}
    </button>
  );
}
```

---

## Buenas prácticas Frontend

- **Nunca `any`** — si TypeScript no puede inferir el tipo, hay un problema de diseño.
- **Server Component por defecto** — agrega `'use client'` solo cuando es necesario.
- **`enabled` en queries** — siempre usar `enabled: !!requiredParam` para evitar queries vacías.
- **Query keys como constantes** — nunca strings inline.
- **Un store Zustand por dominio** — stores pequeños y enfocados, no un store global gigante.
- **Siempre `reset()` en stores** — facilita limpiar estado al salir de un flujo.
- **Schemas Zod de `shared-types`** — nunca duplicar validaciones entre frontend y backend.
- **Error boundaries** — usar `error.tsx` por segmento en App Router.
- **Loading states** — usar `loading.tsx` por segmento o estados de `isLoading` del query.
- **Manejo de errores integrado** — ver `references/error-handling.md` para el sistema completo de errores TanStack + Next.js + NestJS.
