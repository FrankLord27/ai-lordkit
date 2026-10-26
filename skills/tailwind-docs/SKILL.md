---
name: tailwind-docs
description: >
  Referencia completa de Tailwind CSS v4, el sistema de estilos del estándar `fullstack`.
  Úsala SIEMPRE que estiles la web y necesites:
  clases de utilidad, configuración (tailwind.config.ts o CSS-first con @theme),
  responsive design (breakpoints, containers), dark mode, animaciones, custom
  properties, plugins, o cuando debas decidir entre Tailwind y CSS custom.
  NO usar en proyectos legados con Sass + CSS Modules + BEM.
  Activa automáticamente cuando el proyecto tenga tailwind.config.ts o @import
  "tailwindcss" en el CSS principal.
---

# Tailwind CSS v4 — Referencia Completa

## Documentación oficial (Context7)

Para la doc oficial y actualizada de Tailwind CSS v4, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

## Tailwind v4 — Diferencias clave vs v3

```css
/* v4: configuración en CSS, no en JS */
@import "tailwindcss";

@theme {
  --color-brand: #6366f1;
  --font-sans: "Inter", sans-serif;
  --spacing-18: 4.5rem;
}
```

## Reglas no negociables

- **Proyectos legados con Sass/BEM** siguen su convención (ver `fullstack/references/legacy-sass-bem.md`)
- **No inline styles** — si no existe la utilidad, extender el theme
- **`cn()` helper** para clases condicionales: `import { cn } from '@/lib/utils'`
- **Responsive mobile-first**: `sm:`, `md:`, `lg:`, `xl:`, `2xl:`
- **Dark mode**: `dark:` prefix con `class` strategy
- **Extraer componente** cuando se repitan más de 3 clases en 3+ lugares
