# Frontend — Next.js 16 + Tailwind CSS v4 + TanStack Query + RHF + Zod

---

## Estructura de carpetas

```
apps/web/src/
├── app/
│   ├── layout.tsx              ← Server Component. Providers globales.
│   ├── page.tsx                ← Server Component. Fetch inicial.
│   ├── (auth)/
│   │   ├── login/page.tsx
│   │   └── register/page.tsx
│   └── (main)/                 ← Rutas protegidas
│       ├── layout.tsx          ← Verifica sesión, muestra nav
│       └── [feature]/page.tsx
├── components/
│   └── ui/                     ← Button, Input, Modal — genéricos
├── features/
│   └── [dominio]/
│       ├── api/
│       │   ├── query-keys.ts
│       │   ├── use-[entidad].ts
│       │   └── use-create-[entidad].ts
│       └── components/         ← Componentes del dominio
├── lib/
│   ├── api-client.ts
│   └── query-client.ts
└── styles/
    └── globals.css             ← Solo este archivo. Tailwind + tokens.
```

---

## Tailwind CSS v4

### Setup

```bash
pnpm add tailwindcss @tailwindcss/postcss postcss
```

```js
// postcss.config.mjs
export default {
  plugins: { "@tailwindcss/postcss": {} },
};
```

```css
/* styles/globals.css — único archivo CSS del proyecto */
@import "tailwindcss";

@theme {
  /* Design tokens — reemplaza tailwind.config.js extend */
  --color-primary: #2563eb;
  --color-primary-hover: #1d4ed8;
  --color-danger: #dc2626;
  --color-text: #111827;
  --color-text-muted: #6b7280;
  --color-border: #e5e7eb;

  --font-family-sans: "Inter", sans-serif;

  --radius-sm: 0.25rem;
  --radius-md: 0.5rem;
  --radius-lg: 0.75rem;
}
```

```tsx
// app/layout.tsx
import "@/styles/globals.css";
```

### Uso en componentes

```tsx
// components/ui/Button.tsx
type Variant = "primary" | "secondary" | "danger";

const variants: Record<Variant, string> = {
  primary: "bg-primary text-white hover:bg-primary-hover",
  secondary: "border border-primary text-primary bg-transparent",
  danger: "bg-danger text-white",
};

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
}

export function Button({
  variant = "primary",
  className,
  children,
  ...props
}: ButtonProps) {
  return (
    <button
      className={`inline-flex items-center gap-2 px-4 py-2 rounded-md font-medium
        text-sm transition-opacity disabled:opacity-50 disabled:cursor-not-allowed
        ${variants[variant]} ${className ?? ""}`}
      {...props}
    >
      {children}
    </button>
  );
}
```

### Reglas Tailwind

- Nunca escribir CSS custom para lo que Tailwind cubre. Usar utilidades.
- Tokens del proyecto en `@theme`, no hardcodeados en clases.
- Para estilos que se repiten mucho en un componente, extraer a variable local de string.
- No usar `@apply` — derrota el propósito de las utilidades.

---

## Server vs Client Components

**Server Component (default — sin `'use client'`):**

- Fetch de datos iniciales
- Layouts y páginas sin interactividad

```tsx
// app/(main)/items/page.tsx
async function ItemsPage() {
  const items = await fetch(`${process.env.API_URL}/api/v1/items`).then((r) =>
    r.json(),
  );
  return <ItemsList initialData={items} />;
}
```

**Client Component (`'use client'` solo cuando es necesario):**

- useState, event handlers, TanStack Query hooks

```tsx
"use client";
export function ItemsList({ initialData }: { initialData: Item[] }) {
  const { data } = useItems({ initialData }); // hidrata sin spinner
  return (
    <ul>
      {data?.map((item) => (
        <ItemCard key={item.id} item={item} />
      ))}
    </ul>
  );
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
      staleTime: 1000 * 60 * 5, // 5 min
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});
```

```tsx
// app/layout.tsx
"use client";
import { QueryClientProvider } from "@tanstack/react-query";
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
        </QueryClientProvider>
      </body>
    </html>
  );
}
```

### Query Keys — siempre constantes

```typescript
// features/items/api/query-keys.ts
export const itemKeys = {
  all: ["items"] as const,
  lists: () => [...itemKeys.all, "list"] as const,
  search: (filters: SearchFilters) => [...itemKeys.lists(), filters] as const,
  detail: (id: string) => [...itemKeys.all, "detail", id] as const,
};
```

### Hooks estándar

```typescript
// features/items/api/use-items.ts
export const useItems = (filters: SearchFilters) =>
  useQuery({
    queryKey: itemKeys.search(filters),
    queryFn: () => apiClient.post<Item[]>("/items/search", filters),
    enabled: !!filters.locationId,
  });

// features/items/api/use-create-item.ts
export const useCreateItem = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: CreateItemInput) => apiClient.post<Item>("/items", data),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: itemKeys.lists() }),
  });
};
```

---

## API Client

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
  const res = await fetch(`${BASE_URL}${endpoint}`, {
    ...options,
    headers: { "Content-Type": "application/json", ...options?.headers },
    credentials: "include",
  });

  if (!res.ok) {
    const error = await res.json();
    throw new ApiClientError(error.message, error.statusCode);
  }

  const result = await res.json();
  return result.data ?? result;
}

export const apiClient = {
  get: <T>(url: string, opts?: RequestInit) =>
    apiFetch<T>(url, { ...opts, method: "GET" }),
  post: <T>(url: string, body: unknown, opts?: RequestInit) =>
    apiFetch<T>(url, { ...opts, method: "POST", body: JSON.stringify(body) }),
  put: <T>(url: string, body: unknown, opts?: RequestInit) =>
    apiFetch<T>(url, { ...opts, method: "PUT", body: JSON.stringify(body) }),
  patch: <T>(url: string, body: unknown, opts?: RequestInit) =>
    apiFetch<T>(url, { ...opts, method: "PATCH", body: JSON.stringify(body) }),
  delete: <T>(url: string, opts?: RequestInit) =>
    apiFetch<T>(url, { ...opts, method: "DELETE" }),
};
```

---

## React Hook Form + Zod

### Schema compartido en `shared-types`

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

### Uso en componente

```tsx
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { CreateItemSchema, type CreateItemInput } from "@mystack/shared-types";

export function CreateItemForm() {
  const createItem = useCreateItem();
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<CreateItemInput>({ resolver: zodResolver(CreateItemSchema) });

  const onSubmit = async (data: CreateItemInput) => {
    await createItem.mutateAsync(data);
    reset();
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
      <div>
        <input
          {...register("name")}
          placeholder="Nombre"
          className="w-full border border-border rounded-md px-3 py-2 text-sm"
        />
        {errors.name && (
          <p className="text-danger text-xs mt-1">{errors.name.message}</p>
        )}
      </div>
      <Button type="submit" disabled={isSubmitting}>
        {isSubmitting ? "Guardando..." : "Crear"}
      </Button>
    </form>
  );
}
```

---

## Zustand — opcional

Solo se agrega cuando hay estado UI compartido entre componentes no relacionados.

**Cuándo agregar Zustand:**

- Wizard multi-paso donde varios componentes leen el paso actual
- Carrito de compras global
- Preferencias de UI persistidas (tema, idioma)

**Cuándo NO usar Zustand:**

- Estado local de un componente → `useState`
- Filtros de búsqueda en la URL → `useSearchParams`
- Datos del servidor → TanStack Query

```typescript
// Solo si el proyecto lo justifica:
// features/[dominio]/stores/use-[dominio]-store.ts
import { create } from "zustand";

interface WizardStore {
  step: number;
  setStep: (step: number) => void;
  reset: () => void;
}

export const useWizardStore = create<WizardStore>((set) => ({
  step: 1,
  setStep: (step) => set({ step }),
  reset: () => set({ step: 1 }),
}));
```

---

## Buenas prácticas

- Server Component por defecto. `'use client'` solo cuando es necesario.
- `enabled: !!param` en queries para evitar fetches vacíos.
- Query keys como constantes. Nunca strings inline.
- Schemas Zod de `shared-types`. Nunca duplicar validaciones.
- Tokens del proyecto en `@theme`. Nunca colores hardcodeados en clases.
- `error.tsx` por segmento para error boundaries.
- `loading.tsx` por segmento o `isLoading` del query para estados de carga.
