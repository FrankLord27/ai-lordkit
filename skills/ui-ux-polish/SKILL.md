---
name: ui-ux-polish
description: >
  Convierte interfaces planas, aburridas o "guacala" en experiencias con profundidad,
  jerarquía visual, micro-interacciones y movimiento, dentro del stack fullstack
  (Next.js 16 App Router + React 19 + TypeScript strict + Tailwind CSS v4). Úsala SIEMPRE
  que el usuario diga que algo "se ve plano", "muy básico", "soso", "aburrido", "sin vida",
  "guacala", "le falta diseño", "mejorar el UI/UX", "darle profundidad", "agregar animaciones",
  o cuando pida pulir/rediseñar una vista, pantalla, card, formulario, dashboard o landing.
  También aplica al revisar un componente que solo tiene fondos planos, bordes duros, cero
  sombras o cero transiciones. NO uses SCSS, BEM ni styled-components: todo es Tailwind v4.
---

# UI/UX Polish — fullstack (Tailwind v4)

Rol: Ingeniero Frontend senior, experto en UI/UX y diseño de sistemas. Tu trabajo es
**despancar** interfaces: quitar la planitud, crear capas, dirigir la vista hacia los CTAs
y dar sensación de calidad sin caer en exceso ni romper el rendimiento del App Router.

## Reglas duras del stack

- **Framework:** Next.js 16 (App Router) + React 19 + TypeScript `strict`. Prohibido `any` sin justificación.
- **Estilos:** Tailwind CSS v4 (CSS-first, `@theme`). Prohibido SCSS, BEM, styled-components.
- **Server-first:** mantené los componentes como Server Components por defecto. Solo pasás a
  `"use client"` cuando hay estado, eventos o Motion. Un fade de entrada NO justifica `"use client"`.
- **Valores arbitrarios:** evitá `[14px]`, `[#1a1a1a]` sueltos. Definí tokens en `@theme` y usá la utilidad.

## Diagnóstico (qué hace que se vea "plano")

Antes de tocar código, identificá cuáles de estos síntomas aplican. En la salida los listás en 2-3 viñetas.

1. **Cero profundidad:** todo al mismo plano — sin sombras, sin niveles de superficie, bordes duros `#000`.
2. **Sin jerarquía:** mismo tamaño/peso/color en todo; el ojo no sabe dónde mirar; el CTA no resalta.
3. **Estático:** sin transiciones en hover/focus, sin animación de entrada; la carga es un "flash" seco.
4. **Layout apretado o desordenado:** falta whitespace, agrupación ilógica, sin ritmo de espaciado.
5. **Color sin intención:** grises planos, contraste pobre, estados (hover/active/disabled) inexistentes.

## Los 5 ejes de mejora

### 1. Profundidad por capas (elevation)

No uses una sombra cualquiera. Definí **niveles de superficie** y sombras multicapa suaves.
Una sombra de calidad usa 2 capas (una corta y dura + una larga y difusa), no un blur gris fuerte.

En `globals.css`:

```css
@import "tailwindcss";
@import "tw-animate-css"; /* enter/exit utilities, reemplaza tailwindcss-animate (v4-native) */

@theme {
  /* superficies: cada nivel "sube" un escalón */
  --color-surface-0: #0a0b0d;   /* fondo base */
  --color-surface-1: #111317;   /* cards */
  --color-surface-2: #181b21;   /* elementos elevados / hover */
  --color-border-subtle: #ffffff14;  /* borde tenue, no negro duro */

  /* sombras multicapa (clave para no verse plano) */
  --shadow-card: 0 1px 2px #0000004d, 0 4px 12px #00000033;
  --shadow-elevated: 0 2px 4px #0000005c, 0 12px 32px #00000040;
  --shadow-glow: 0 0 0 1px var(--color-border-subtle), 0 8px 24px #22d3ee1f;
}
```

Reglas:
- Cada nivel jerárquico sube de superficie **y** de sombra. Card = `surface-1` + `shadow-card`; al hover sube a `surface-2` + `shadow-elevated`.
- Bordes siempre tenues (`border-border-subtle`), nunca `#000` puro.
- Para overlays/modales/glassmorphism: `bg-surface-1/70 backdrop-blur-md` (úsalo con criterio, mata rendimiento si abusás).

### 2. Jerarquía (tipografía + espaciado)

- Escala tipográfica con saltos claros: título `text-2xl font-semibold tracking-tight`, body `text-sm text-white/70`, label `text-xs uppercase tracking-wide text-white/50`.
- Ritmo de espaciado consistente (`gap-2 / gap-4 / gap-6`, no números al azar). Agrupá con whitespace: más aire **entre** grupos que **dentro** del grupo.
- El CTA debe ganar por contraste y peso, no por gritar. Un solo CTA primario por vista.

### 3. Interactividad (estados)

Todo elemento interactivo lleva transición y los 3 estados. **Usá `focus-visible`, no `focus`** (accesibilidad por teclado sin molestar al mouse).

```tsx
<button
  className="
    inline-flex items-center gap-2 rounded-lg px-4 py-2.5
    bg-cyan-500 text-surface-0 font-medium
    shadow-card transition-all duration-200 ease-out
    hover:bg-cyan-400 hover:shadow-elevated hover:-translate-y-0.5
    active:translate-y-0 active:scale-[0.98]
    focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400/60
    disabled:opacity-50 disabled:pointer-events-none
  "
>
  Continuar
</button>
```

Duraciones: micro-interacciones `150–200ms`, entradas `250–400ms`, easing `ease-out` (entra rápido, frena suave).

### 4. Movimiento — la regla CSS-first vs Motion

Decisión por defecto: **CSS/Tailwind primero, Motion solo cuando CSS no llega.**

| Caso | Herramienta |
|------|-------------|
| Entrada al montar (fade/slide/zoom-in) | `tw-animate-css`: `animate-in fade-in slide-in-from-bottom-4 duration-300` |
| Hover / focus / active | `transition-* hover:*` (CSS puro) |
| Keyframes propios (pulse, shimmer, float) | `@theme { --animate-*: ... ; @keyframes ... }` |
| **Salida al desmontar** (modal/drawer/toast) | **Motion** `AnimatePresence` (CSS no puede animar un unmount) |
| **Layout / shared element** (reordenar lista, expandir) | **Motion** `layout` / `layoutId` |
| **Orquestación / stagger** complejo, gestos, drag | **Motion** |
| Scroll-linked / reveal al entrar al viewport | `tw-animate-css` `timeline-view` o Motion `whileInView` según complejidad |

Regla de oro: si el efecto obliga `"use client"`, que valga la pena. Un fade de entrada se hace con `tw-animate-css` y queda en Server Component.

**Animación custom en `@theme`** (sin plugin, tree-shakeable):

```css
@theme {
  --animate-shimmer: shimmer 1.4s linear infinite;
  @keyframes shimmer {
    from { background-position: -200% 0; }
    to   { background-position: 200% 0; }
  }
}
/* uso: class="animate-shimmer ..." para skeletons */
```

**Motion** (solo cuando la tabla lo pide). Paquete `motion` (antes `framer-motion`), import `motion/react`, React 19 OK:

```tsx
"use client";
import { AnimatePresence, motion } from "motion/react";

export function Toast({ open, children }: { open: boolean; children: React.ReactNode }) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          initial={{ opacity: 0, y: 12, scale: 0.96 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 12, scale: 0.96 }}
          transition={{ duration: 0.2, ease: "easeOut" }}
          className="rounded-lg bg-surface-2 px-4 py-3 shadow-elevated"
        >
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
```

### 5. Layout y whitespace

- **Grid** para estructuras 2D (dashboards, galerías): `grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6`.
- **Flex** para ejes simples (toolbars, filas): `flex items-center justify-between gap-4`.
- Contenedor con respiro: `mx-auto max-w-6xl px-4 sm:px-6 lg:px-8`.
- Whitespace dirige la vista: aislá el CTA con espacio; no lo amontones con texto secundario.

## Accesibilidad (no negociable)

- Respetá `prefers-reduced-motion`: prefijá animaciones no esenciales con `motion-safe:` (ej. `motion-safe:animate-in`). `tw-animate-css` y Tailwind ya exponen `motion-safe:` / `motion-reduce:`.
- `focus-visible:ring-*` en todo lo interactivo. Nunca `outline-none` sin un reemplazo visible.
- Contraste mínimo AA: texto body `text-white/70` sobre superficies oscuras está OK; `text-white/40` solo para deshabilitado/decorativo.

## Anti-patrones (NO hacer)

- Sombra única gris fuerte (`shadow-2xl` en todo) → se ve barato. Usá tokens multicapa.
- Animar **todo** → ruido. Animá lo que comunica (entrada de contenido, feedback de acción, transición de estado).
- `transition-all` en componentes con muchos hijos pesados → animá props concretas (`transition-[transform,box-shadow,background-color]`).
- Meter `"use client"` solo para un fade. Usá `tw-animate-css`.
- Valores arbitrarios regados. Tokenizá en `@theme`.
- Glassmorphism (`backdrop-blur`) en listas largas/scroll → caída de FPS.

## Formato de salida

1. **Diagnóstico:** 2-3 viñetas con los problemas de UX detectados (referenciá los síntomas del Diagnóstico).
2. **Setup (si aplica):** los tokens nuevos para `@theme` en `globals.css`.
3. **Código refactorizado completo:** los `.tsx` listos para copiar y pegar, con responsabilidades divididas en componentes pequeños (ej. `Card`, `CardHeader`, `CardActions`). Server por defecto; `"use client"` solo donde corresponda y marcado.
4. Sin explicaciones largas. Directo, en español, copy-paste-ready.

## Dependencias

```bash
pnpm add motion        # solo si la vista necesita salida/layout/gestos
pnpm add tw-animate-css
```
`tw-animate-css` se importa en CSS (`@import "tw-animate-css";`), no es plugin JS.
