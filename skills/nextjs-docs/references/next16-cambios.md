# Next.js 16 — Cambios importantes vs Next.js 15

> Fuente: blog y guía de upgrade oficiales de Vercel (nextjs.org/blog/next-16, nextjs.org/docs/app/guides/upgrading/version-16). Este archivo manda sobre el espejo de docs v15.

## Breaking changes (invalidan patrones de Next 15)

### 1. Request APIs solo asíncronas — ELIMINADO el acceso síncrono

En 15 estaba deprecado con warning; en 16 **no compila/falla en runtime**.

```tsx
// ❌ Next 15 (ya no funciona en 16)
export default function Page({ params }: { params: { id: string } }) {
  const { id } = params;
}

// ✅ Next 16
export default async function Page({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
}
```

Aplica a: `params` y `searchParams` (page/layout/route/generateMetadata), `cookies()`, `headers()`, `draftMode()`. En Client Components, `params` se consume con `use(params)`.

### 2. Turbopack es el bundler por defecto (dev Y build)

- `next dev` y `next build` usan Turbopack sin flags. Elimina `--turbopack`/`--turbo` de los scripts.
- **Si hay config custom de webpack en `next.config.ts`, `next build` FALLA a propósito** para evitar builds mal configurados. Opciones: migrar la config a Turbopack (`turbopack` ahora es clave top-level de `nextConfig`, ya no `experimental.turbopack`) o escape temporal con `next build --webpack`.
- Números oficiales: ~87% dev startup más rápido, ~75% Fast Refresh más rápido, ~2.5x build de producción.

### 3. React 19.2 mínimo obligatorio

`react` y `react-dom` deben ser `^19.2.0`. Actualízalos en el mismo PR del upgrade.

### 4. `middleware.ts` → `proxy.ts` (Next 16.2+)

El archivo `middleware.ts` se renombra a `proxy.ts` (misma API de intercepción de requests, nombre que refleja lo que realmente hace). Revisa la versión exacta del proyecto: en 16.0/16.1 middleware.ts sigue funcionando.

## Novedades que conviene adoptar

- **`"use cache"` / Cache Components**: caching explícito y componible a nivel de función/componente — el modelo de caching implícito de fetch queda como legado. Para lógica nueva de cache, preferir `"use cache"` cuando el proyecto lo tenga habilitado.
- **`turbopack` top-level en `next.config.ts`** para aliases/reglas de loader.
- Mejoras de PPR (Partial Prerendering) y streaming.

## Checklist de upgrade 15 → 16 (por proyecto)

- [ ] `pnpm add next@16 react@^19.2.0 react-dom@^19.2.0` (+ types)
- [ ] Codemod oficial: `npx @next/codemod@latest upgrade latest`
- [ ] Buscar TODOS los usos síncronos: `grep -rn "params\." src/app | grep -v await` y tipos `params: {` sin `Promise<`
- [ ] Quitar `--turbopack` de scripts en package.json
- [ ] Revisar config webpack custom → migrar a `turbopack` top-level o `--webpack` temporal
- [ ] Si 16.2+: renombrar `middleware.ts` → `proxy.ts`
- [ ] Correr build + suite E2E completa antes de mergear

## Proyectos que siguen en v15

Antes de tocar el frontend, revisa la versión de `next` en el `package.json` del proyecto. Si sigue en v15, no introduzcas patrones de v16 hasta hacer el upgrade con el checklist de arriba.
