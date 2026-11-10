# Rendimiento desde el desarrollo — checklist (NestJS · Prisma 7 · PostgreSQL · Redis · BullMQ · Next.js 16)

Se aplica al ESCRIBIR el código, no después. Lee solo tu capa. Cada regla dice qué hacer y cómo comprobarlo.
Detalle y ejemplos largos: `performance-database.md`, `performance-cache.md`, `performance-backend.md`, `performance-frontend.md`, `observability.md`.
Orden si hay que priorizar: BD (B1–B5) → B6–B8 → F1–F6 → resto. No optimices a ciegas lo que no esté en esta lista: mide primero.

## Backend y base de datos

- **B1 · Paginar siempre.** Ningún `findMany` sin `take`. `limit` validado con Zod: `z.coerce.number().int().min(1).max(100).default(20)`. Offset para tablas chicas con salto de página; cursor (`cursor` + `take` + `orderBy` estable por `id`) para tablas grandes, feeds e infinite scroll. No hagas `count()` de tablas enormes en cada página.
- **B2 · Solo las columnas necesarias.** `select` explícito en todo listado y en todo `include` anidado. Nunca devuelvas la entidad completa (ni `passwordHash`, ni JSON pesados). En SQL crudo, nunca `SELECT *`.
- **B3 · Cero N+1.** Prohibido `await prisma…` dentro de `for`/`map`. Trae relaciones con `include`/`select` anidado o con una sola consulta `where: { id: { in: ids } }` y agrupa en memoria. Comprobación: con el log de queries activo en dev, un endpoint de listado no debe emitir un número de queries que crezca con las filas.
- **B4 · Índice para cada consulta común.** Toda FK lleva `@@index`. Cada combinación `where` + `orderBy` de un endpoint de listado tiene su índice compuesto, con la columna de igualdad primero: `@@index([tenantId, status, createdAt(sort: Desc)])`. Comprobación: `EXPLAIN (ANALYZE, BUFFERS)` sin `Seq Scan` sobre tablas grandes. En producción, crea índices con `CREATE INDEX CONCURRENTLY` en una migración editada a mano.
- **B5 · Pool de conexiones (Prisma 7).** El pool es el del driver, no el de la URL (`?connection_limit` ya no aplica):
  ```ts
  const adapter = new PrismaPg({
    connectionString: process.env.DATABASE_URL,
    max: 10,                        // por instancia
    connectionTimeoutMillis: 5_000, // pg trae 0 = espera infinita
    idleTimeoutMillis: 30_000,
  });
  ```
  Regla: `instancias × max` (API + workers de BullMQ) ≤ `max_connections` − 10. Con más de 3 instancias, PgBouncer en modo transacción. Un solo `PrismaService` global.
- **B6 · Independiente = en paralelo.** `const [a, b] = await Promise.all([qa(), qb()])` cuando una no depende de la otra. Excepciones: dentro de `prisma.$transaction(async tx => …)` (una sola conexión) y lotes grandes (limita la concurrencia). Usa `Promise.allSettled` si un fallo parcial es aceptable.
- **B7 · Timeout en toda llamada externa.** Ninguna llamada HTTP, SMTP o a un SDK sin límite: `fetch(url, { signal: AbortSignal.timeout(5_000) })`; `HttpModule.register({ timeout: 5_000, maxRedirects: 3 })`. Reintentos con backoff solo si la operación es idempotente. Protege también la BD con `statement_timeout` en el rol de la app y Redis con `commandTimeout`.
- **B8 · Lo lento va a una cola.** Si tarda más de ~300 ms, llama a terceros (correo, pagos, IA en lote, webhooks) o genera archivos (PDF, Excel, imágenes), va a BullMQ: el controller encola y responde `202` con el `jobId`. Job idempotente (`jobId` determinista), `attempts: 3`, `backoff: { type: 'exponential', delay: 1000 }`, `removeOnComplete`/`removeOnFail` con límite. El worker corre en un proceso aparte de la API.
- **B9 · Cache Redis para lo más leído.** Solo lecturas frecuentes y caras, medidas. Cache-aside: clave `app:v1:<entidad>:<id|hash-de-filtros>`, TTL siempre (con ±10 % aleatorio), e invalidación en el mismo servicio que escribe. No se cachea nada por usuario sin el `userId`/`tenantId` en la clave.
- **B10 · Compresión.** En producción la hace el proxy (Nginx/Caddy/Traefik) con Brotli y gzip de respaldo para `text/*`, JSON, JS, CSS, SVG; no el proceso de Node. El middleware `compression` solo si no hay proxy delante. Nunca se comprime un stream SSE ni lo ya comprimido (imágenes, zip).
- **B11 · Streaming de IA token a token.** No esperes la respuesta completa del modelo. NestJS: `@Sse()` que devuelve un `Observable<MessageEvent>` construido desde el stream del SDK; al desuscribirse el cliente, aborta la llamada al proveedor. Cabeceras `Cache-Control: no-cache` y `X-Accel-Buffering: no` (o `proxy_buffering off` en Nginx). En el cliente, pinta cada fragmento al llegar y ofrece "detener".
- **B12 · Trazas desde el primer día.** `instrumentation.ts` con `NodeSDK` + `getNodeAutoInstrumentations()` + `PrismaInstrumentation` (`@prisma/instrumentation`), importado en la PRIMERA línea de `main.ts`. En dev exporta a Jaeger local; en prod, OTLP. Además `log_min_duration_statement = 200` en PostgreSQL. Meta: p95 < 300 ms por endpoint; lo que la supere se abre como tarea con la traza adjunta.
- **B13 · Servidor pegado a la base de datos.** API, workers, PostgreSQL y Redis en la misma región y red privada (misma red de Docker/VPC), nunca por IP pública. Comprobación: `SELECT 1` desde la API en < 2 ms. El servidor de Next llama a la API por la URL interna, no por el dominio público.
- **B14 · Listo para varias instancias.** Nada de estado en memoria del proceso: sesiones, rate limit, locks y adaptador de WebSocket en Redis. `/health/live` y `/health/ready` (Terminus), `app.enableShutdownHooks()` y cierre ordenado. Los cron llevan lock distribuido. Mínimo 2 réplicas detrás del balanceador.
- **B15 · Dependencias sin usar.** Antes de agregar un paquete, justifica por qué no basta lo que ya hay. `knip` como devDependency y `pnpm knip` en CI: una dependencia o export sin usar rompe el build.

## Frontend (Next.js 16 · React 19 · TanStack Query v5)

- **F1 · Servidor primero.** Server Component por defecto; `"use client"` solo en la hoja interactiva. Contenido público o que cambia poco: estático/ISR (`generateStaticParams`, `revalidate` o `"use cache"`). Datos por usuario: SSR con streaming. Una página nunca se queda en blanco esperando un `useEffect`.
- **F2 · Skeleton en todo lo que carga.** `loading.tsx` por segmento y `<Suspense fallback={<Skeleton/>}>` por bloque lento. El skeleton ocupa el mismo alto y ancho que el contenido final (CLS < 0,1). Spinner a pantalla completa: no.
- **F3 · Sin llamadas duplicadas.** Un `queryKey` por recurso, compartido vía una función `xxxQueryOptions()`; `staleTime` explícito (≥ 30 s salvo datos en vivo). En el servidor, envuelve el fetch en `cache()` de React para que layout y página compartan resultado. No pidas lo mismo en un Server Component y en `useQuery` sin hidratar. Botones de envío deshabilitados mientras `isPending`.
- **F4 · Debounce en búsqueda y autocompletado.**
  ```tsx
  const q = useDebouncedValue(term, 300);
  useQuery({
    queryKey: ['search', q],
    queryFn: ({ signal }) => api.search(q, { signal }), // cancela la petición anterior
    enabled: q.length >= 2,
    placeholderData: keepPreviousData,
  });
  ```
- **F5 · Optimistic UI** para acciones baratas y reversibles (toggle, like, reordenar, marcar leído); no para pagos ni formularios largos.
  ```ts
  onMutate: async (v) => {
    await qc.cancelQueries({ queryKey });
    const prev = qc.getQueryData(queryKey);
    qc.setQueryData(queryKey, (old) => apply(old, v));
    return { prev };
  },
  onError: (_e, _v, ctx) => qc.setQueryData(queryKey, ctx?.prev),
  onSettled: () => qc.invalidateQueries({ queryKey }),
  ```
- **F6 · Imágenes.** Siempre `next/image` con `width`/`height` (o `fill`) y `sizes`; `images.formats: ['image/avif', 'image/webp']`. Solo la imagen LCP lleva `preload` (en Next 16 `priority` está deprecado); el resto queda en lazy, que es el valor por defecto: no lo quites. Calidades distintas de 75 se declaran en `images.qualities`. `<img>`, `<iframe>` y `<video>` sueltos: `loading="lazy"` y dimensiones. Subidas de usuarios: un job de BullMQ las convierte con `sharp` a WebP/AVIF y genera tamaños antes de guardarlas en MinIO.
- **F7 · Fuentes.** `next/font` (se sirven desde tu dominio), máximo 2 familias, variable o ≤ 3 grosores, `subsets: ['latin']`, `display: 'swap'`. Ningún `<link>` a Google Fonts.
- **F8 · Scripts de terceros después de la página.** Analítica, chat, mapas y píxeles con `next/script`: `strategy="afterInteractive"` o `"lazyOnload"`; nunca un `<script>` bloqueante en el `<head>`. Embeds pesados se cargan al hacer clic o al entrar en pantalla.
- **F9 · Code splitting.** Las rutas ya se dividen solas; lo pesado y no inicial (gráficas, editor, mapa, modal grande) va con `next/dynamic` y su skeleton. Importa por ruta concreta, no el paquete entero. Presupuesto: < 200 kB de JS inicial por ruta, revisado con `@next/bundle-analyzer`.
- **F10 · Virtualizar listas largas.** Más de ~100 filas en el DOM → `@tanstack/react-virtual`, combinado con `useInfiniteQuery`. Tablas grandes: paginación del servidor (B1), nunca traer todo y filtrar en el cliente.
- **F11 · Re-renders.** Estado lo más cerca posible de donde se usa; selectores en Zustand (`useStore(s => s.x)`); nada que cambie rápido en un Context global; `key` estable. Con React Compiler activo no agregues `useMemo`/`useCallback` a mano; sin él, solo con evidencia del Profiler.
- **F12 · Cache en el navegador y CDN.** Archivos con hash (`/_next/static`, assets versionados): `Cache-Control: public, max-age=31536000, immutable`. HTML y datos privados: `private, no-store`. GET públicos de la API: `public, s-maxage=60, stale-while-revalidate=300`. Estáticos y archivos de MinIO detrás de un CDN (`assetPrefix` en `next.config.ts` o Cloudflare delante de Nginx).
- **F13 · RUM.** Mide a usuarios reales, no solo Lighthouse: componente cliente con `useReportWebVitals` (de `next/web-vitals`) que envía LCP, INP y CLS con `navigator.sendBeacon` a un endpoint propio o a Sentry. Metas en p75: LCP < 2,5 s · INP < 200 ms · CLS < 0,1.
- **F14 · Probar como un celular en red lenta.** Antes de cerrar una pantalla: DevTools con CPU 4× más lenta y red "Slow 4G". En CI, Lighthouse móvil (`@lhci/cli`) con presupuesto que rompe el build. Al menos una pasada en un teléfono Android de gama media real por release.

## Cómo reportar
En el resumen de la tarea: `Rendimiento: B1 ✔ (users.service.ts) · B3 ✔ · B7 n/a · F2 ✔ (loading.tsx) · F4 pendiente: <motivo>`.
