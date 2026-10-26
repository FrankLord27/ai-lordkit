---
name: nextjs-docs
description: >
  Documentación de Next.js 16 App Router (con espejo de docs v15 + guía de cambios v16)
  para construir aplicaciones frontend con React Server Components, Server Actions,
  layouts anidados, metadata dinámica, optimización de imágenes y fuentes, Turbopack,
  y despliegue en producción. Úsala SIEMPRE que trabajes con: App Router (carpeta app/),
  Server vs Client Components, layouts, loading/error boundaries, Server Actions,
  fetch con cache, "use cache", next/image, next/font, proxy.ts (ex middleware),
  route handlers, metadata, generateStaticParams, configuración de next.config.ts,
  o cualquier feature de Next.js 15/16. También activa para: upgrade de Next 15 a 16,
  optimización de Core Web Vitals, bundle analysis, code splitting, lazy loading,
  o integración con TanStack Query en SSR/SSG.
---

# Next.js 16 — Referencia Completa (App Router)

> **LEE PRIMERO `references/next16-cambios.md`** si vas a generar código: Next 16 tiene breaking changes que invalidan patrones de Next 15 (params síncronos, middleware.ts, webpack por defecto).

## Reglas no negociables (Next.js 16 + App Router)

- **`params`, `searchParams`, `cookies()`, `headers()` son SIEMPRE async** — `await` obligatorio. El acceso síncrono fue ELIMINADO en 16 (en 15 solo estaba deprecado).
- **Turbopack es el default** en `next dev` y `next build` — no agregues flags `--turbopack`. Si el proyecto tiene config custom de webpack, el build FALLA a propósito: migra la config o usa `--webpack` como escape temporal.
- **React 19.2 mínimo** — Next 16 no arranca con React <19.2.
- **Server Components por defecto** — `"use client"` solo cuando hay eventos/hooks de estado.
- **Server Actions** para mutaciones — no crear route handlers API solo para forms.
- **`next/image`** obligatorio para toda imagen; **`next/font`** para fuentes.
- **Metadata**: `generateMetadata()` dinámica, objeto `metadata` estático.
- **`loading.tsx`** para Suspense automático, **`error.tsx`** para Error Boundaries por segmento.
- Caching explícito: `"use cache"` / Cache Components donde el proyecto lo adopte; `fetch` con `{ next: { revalidate: N } }` para ISR y `{ cache: 'no-store' }` para dinámico.

## Documentación oficial (Context7)

> Nunca uses Pages Router (`pages/`): está prohibido en este stack.

Para la doc oficial y actualizada de Next.js 16, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

## Estructura estándar (App Router)

```
src/
├── app/
│   ├── layout.tsx          ← Root layout
│   ├── page.tsx            ← Home page
│   ├── (auth)/             ← Route group (sin segmento en URL)
│   │   ├── login/page.tsx
│   │   └── register/page.tsx
│   ├── dashboard/
│   │   ├── layout.tsx      ← Nested layout
│   │   ├── page.tsx
│   │   └── loading.tsx
│   └── api/                ← Route Handlers
│       └── webhooks/
│           └── route.ts
├── components/
│   ├── ui/                 ← Componentes genéricos
│   └── features/           ← Componentes de dominio
└── lib/
    ├── actions/            ← Server Actions
    └── queries/            ← Data fetching functions
```

## Orden de lectura recomendado

**Proyecto nuevo**: `references/next16-cambios.md` → routing → data-fetching → rendering → configuring

**Upgrade 15 → 16**: `references/next16-cambios.md` completo antes de tocar código

**Optimización**: optimizing → deploying → architecture (Turbopack)
