# Performance en Next.js — Frontend

---

## Core Web Vitals — las métricas que importan

Google usa estas métricas para SEO y UX. Medirlas con Lighthouse en Chrome DevTools.

| Métrica                               | Qué mide                            | Objetivo | Malo si |
| ------------------------------------- | ----------------------------------- | -------- | ------- |
| **LCP** Largest Contentful Paint      | Cuándo carga el elemento más grande | < 2.5s   | > 4s    |
| **CLS** Cumulative Layout Shift       | Cuánto se mueve el layout al cargar | < 0.1    | > 0.25  |
| **FID/INP** Interaction to Next Paint | Respuesta a la primera interacción  | < 100ms  | > 300ms |

```bash
# Medir con Lighthouse en CLI
npx lighthouse https://tudominio.com \
  --output html \
  --output-path ./lighthouse-report.html \
  --preset=perf \
  --emulated-form-factor=mobile  # ← Medir en mobile siempre — es el caso peor
```

---

## LCP — mejorar el tiempo de carga del elemento principal

El LCP suele ser la imagen hero o el título principal de la página.

```tsx
// ✅ Imagen hero con priority — carga inmediatamente sin lazy loading
import Image from "next/image";

export function HeroSection() {
  return (
    <Image
      src="/hero.webp"
      alt="Hero"
      width={1200}
      height={600}
      priority // ← Precarga con <link rel="preload">
      quality={85} // 85% calidad — buen balance tamaño/calidad
      sizes="100vw" // Ocupa el 100% del viewport
    />
  );
}

// ✅ Fuentes con preload — evita FOUT (Flash of Unstyled Text)
import { Inter } from "next/font/google";

const inter = Inter({
  subsets: ["latin"],
  display: "swap", // Muestra texto del sistema mientras carga la fuente
  preload: true, // Precarga la fuente
  variable: "--font-inter",
});
```

---

## CLS — evitar saltos de layout

```tsx
// ❌ Causa CLS — el contenedor cambia de tamaño cuando carga la imagen
<img src="/photo.jpg" alt="Photo" />

// ✅ Sin CLS — dimensiones fijas reservan el espacio antes de cargar
<Image src="/photo.jpg" alt="Photo" width={800} height={600} />

// ❌ Causa CLS — el banner de cookies aparece y empuja el contenido
// ✅ Usar position: fixed para elementos que aparecen dinámicamente

// ❌ Causa CLS — skeleton que tiene diferente tamaño que el contenido real
<div className={styles.skeleton} style={{ height: 200 }} />
// ✅ El skeleton debe tener EXACTAMENTE el mismo tamaño que el contenido
```

---

## Imágenes — next/image siempre

```tsx
import Image from 'next/image';

// ✅ Imagen con tamaños responsive
<Image
  src={car.imageUrl}
  alt={`${car.brand} ${car.model}`}
  width={800}
  height={500}
  sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
  // ↑ Le dice al browser qué tamaño tiene la imagen en cada breakpoint
  // Next.js genera automáticamente los srcset con WebP
/>

// ✅ Imagen de fondo con fill
<div style={{ position: 'relative', height: 400 }}>
  <Image
    src={hero.src}
    alt={hero.alt}
    fill
    style={{ objectFit: 'cover' }}
    priority
    sizes="100vw"
  />
</div>
```

```javascript
// next.config.js — dominios de imágenes externos
const nextConfig = {
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "res.cloudinary.com",
        pathname: "/tu-cuenta/**",
      },
    ],
    // Formatos en orden de preferencia
    formats: ["image/avif", "image/webp"],
    // Tamaños de dispositivo para srcset
    deviceSizes: [640, 768, 1024, 1280, 1920],
  },
};
```

---

## Fuentes — next/font siempre

```tsx
// app/layout.tsx — configuración de fuentes
import { Inter, Poppins } from "next/font/google";
import localFont from "next/font/local";

// Google Fonts — descarga en build time, sin petición externa en runtime
const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

// Fuente local — más rápido aún
const myFont = localFont({
  src: "../fonts/MyFont.woff2",
  display: "swap",
  variable: "--font-custom",
});

export default function RootLayout({ children }) {
  return (
    <html className={`${inter.variable} ${myFont.variable}`}>
      <body>{children}</body>
    </html>
  );
}
```

```scss
// styles/_variables.scss
body {
  font-family: var(--font-inter), system-ui, sans-serif;
}
```

---

## Bundle analysis — detectar qué hace grande el bundle

```bash
# Analizar el bundle de Next.js
pnpm add -D @next/bundle-analyzer

# next.config.js
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
});
module.exports = withBundleAnalyzer(nextConfig);

# Ejecutar el análisis
ANALYZE=true pnpm build
# Abre automáticamente el reporte en el browser
```

### Qué buscar en el bundle analyzer

```
🔴 Señales de problema:
  - Una dependencia que ocupa > 100KB — buscar alternativa más ligera
  - La misma librería incluida dos veces (versiones diferentes)
  - Código de Node.js en el bundle del cliente
  - moment.js — reemplazar con date-fns o dayjs (10x más pequeño)
  - lodash completo — usar lodash-es o importar solo la función necesaria

✅ Imports correctos:
  import { format } from 'date-fns';         // ✅ Solo la función
  import format from 'date-fns/format';      // ✅ También correcto
  import * as dateFns from 'date-fns';       // ❌ Importa todo — no tree-shakeable
  import _ from 'lodash';                    // ❌ Importa lodash completo (~70KB)
  import { debounce } from 'lodash-es';      // ✅ Tree-shakeable
```

---

## Code splitting — cargar solo lo necesario

```tsx
// ✅ Dynamic import — componentes pesados que no se necesitan al inicio
import dynamic from "next/dynamic";

// El mapa solo carga cuando el usuario navega a esa sección
const MapComponent = dynamic(() => import("@/components/Map"), {
  loading: () => <div className={styles.mapSkeleton} />,
  ssr: false, // El mapa usa APIs del browser — no renderizar en servidor
});

// El editor de texto enriquecido es pesado — cargar solo cuando se necesita
const RichTextEditor = dynamic(() => import("@/components/RichTextEditor"), {
  loading: () => <textarea placeholder="Cargando editor..." />,
  ssr: false,
});

// Modal — no necesita estar en el bundle inicial
const ConfirmModal = dynamic(() => import("@/components/ConfirmModal"));
```

---

## Server Components — aprovechar el rendering en servidor

```tsx
// ✅ Server Component — fetch en el servidor, 0 JS enviado al cliente
// El HTML llega completo al browser — LCP mejora significativamente
async function CarsList({ locationId }: { locationId: string }) {
  // Fetch directo, sin TanStack Query, sin estado, sin useEffect
  const response = await fetch(
    `${process.env.API_URL}/api/v1/cars?locationId=${locationId}`,
    { next: { revalidate: 300 } }, // Cache de Next.js: revalidar cada 5 min
  );
  const { data: cars } = await response.json();

  return (
    <div>
      {cars.map((car) => (
        <CarCard key={car.id} car={car} />
      ))}
    </div>
  );
}

// ✅ Combinar Server Components con Client Components
// Server Component hace el fetch inicial → pasa datos al Client Component
async function SearchPage() {
  const locations = await fetchLocations(); // En el servidor

  return (
    <>
      <h1>Buscar autos</h1>
      {/* El formulario de búsqueda necesita interactividad → Client Component */}
      <SearchForm locations={locations} />
      {/* Suspense muestra skeleton mientras carga el servidor */}
      <Suspense fallback={<CarsSkeleton />}>
        <CarsList locationId="default" />
      </Suspense>
    </>
  );
}
```

---

## Caché de Next.js — los niveles de caché

```tsx
// NIVEL 1: Request memoization — automático, dura un render
// Si llamas fetch() con la misma URL en el mismo render → solo una petición real
async function Page() {
  // Ambos llaman a la misma URL — Next.js solo hace 1 petición real
  const car = await getCar("123"); // fetch('/api/cars/123')
  const relatedCar = await getRelated("123"); // fetch('/api/cars/123') → usa el memoizado
}

// NIVEL 2: Data Cache — persiste entre requests, controlado con next.cache
fetch(url, {
  next: {
    revalidate: 3600, // Revalidar cada hora
    tags: ["cars"], // Tag para invalidación manual
  },
});

// Invalidar manualmente desde Server Action o API Route
import { revalidateTag } from "next/cache";
revalidateTag("cars"); // Invalida todo lo tageado con 'cars'

// NIVEL 3: Full Route Cache — cachea el HTML estático de la página
// Automático para páginas estáticas (sin cookies, sin headers dinámicos)

// NIVEL 4: Router Cache — en el browser, cachea páginas ya visitadas
// Automático, dura la sesión del browser
```

---

## Prefetching — cargar antes de que el usuario necesite

```tsx
// Next.js Link hace prefetch automático de páginas cuando entran al viewport
import Link from 'next/link';

// ✅ Prefetch automático — la página /cars/[id] se precarga al ver el link
<Link href={`/cars/${car.id}`}>
  <CarCard car={car} />
</Link>

// Desactivar prefetch para links que no se van a visitar frecuentemente
<Link href="/terms" prefetch={false}>
  Términos y condiciones
</Link>
```

```typescript
// TanStack Query — prefetch en el servidor para datos críticos
// Elimina el spinner inicial en el cliente

// app/cars/page.tsx (Server Component)
import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query';

async function CarsPage() {
  const queryClient = new QueryClient();

  // Prefetch los datos en el servidor — el cliente los recibe hidratados
  await queryClient.prefetchQuery({
    queryKey: ['cars', 'featured'],
    queryFn: () => fetchFeaturedCars(),
  });

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <CarsClient /> {/* Ya tiene los datos — sin spinner inicial */}
    </HydrationBoundary>
  );
}
```
