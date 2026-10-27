---
description: Arranca un proyecto nuevo con el estándar fullstack: pregunta tipo, nombre y si lleva app móvil, y configura todo
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Comando: `/new-project`

Por defecto, todo proyecto nuevo usa la skill `fullstack` (Next.js 16 + Tailwind v4, NestJS 11, Prisma 7, PostgreSQL, Redis, Zod compartido). Si el usuario no sabe qué arquitectura o herramientas usar, o pide escoger, primero pasa por la skill `crear-app` (selector interactivo) y usa lo que escoja: no repitas aquí las preguntas que ya contestó.

## Paso 1 — Preguntar (en un solo mensaje)

```
1. Nombre del proyecto (kebab-case, ej. mi-erp-dgii):
2. Tipo:
   a. SaaS multi-tenant (helpdesk, CRM, ERP)
   b. Marketplace (proveedores + clientes + comisiones)
   c. POS / facturación
   d. Sitio público + admin
   e. API standalone
   f. Otro (describe en una línea)
3. ¿Lleva app móvil (Expo)? [s/N]
```

Modo no interactivo: `/new-project mi-app saas movil` salta las preguntas.

## Paso 2 — Crear el `CLAUDE.md` del proyecto

En la raíz del proyecto, crea `CLAUDE.md` empezando con este bloque (los agents lo leen automáticamente en cada sesión):

```markdown
# <nombre>

## Proyecto

- Tipo: <saas | marketplace | pos | public-admin | api | other>
- Arquitectura y herramientas: <lo de docs/METODO.md, o "estándar del kit">
- App móvil: <sí | no>
- Estándar: skill `fullstack`. Seguridad: skill `nestjs-security-hardening`.

## Reglas de negocio

<!-- Las reglas inviolables de ESTE proyecto (roles, comisiones, estados, tenant). -->
```

Si ya existe un `CLAUDE.md`, pregunta antes de tocarlo y, si el usuario acepta, agrega solo la sección `## Proyecto`.

## Paso 3 — Fijar runtime y seguridad de dependencias (obligatorio, sin preguntar)

1. `package.json` raíz con:

```json
{
  "packageManager": "pnpm@<versión instalada, obtenla con pnpm --version>",
  "engines": { "node": ">=24" }
}
```

2. `.npmrc` con `engine-strict=true`.
3. Verifica con `node --version` que el entorno corre Node 24. Si no, DETENTE y avisa antes de continuar.
4. Solo pnpm en este proyecto: nunca npm ni yarn.

## Paso 4 — README

Invoca al agent `readme-writer` para el `README.md` inicial según el tipo.

## Paso 5 — Skills del proyecto

Anuncia qué skills aplican:

- Siempre → `fullstack` + `nestjs-security-hardening` + `memory-bank-context`
- Tipo saas, marketplace o con reglas financieras → `erp-saas-core`
- Tipo pos → `erp-saas-core` + `skills-bundle`
- App móvil → además, el plugin oficial de Expo. Si no está instalado, dile al usuario que lo instale desde `/plugin` antes de tocar la app.

## Paso 6 — Resumen

```
✓ Proyecto <nombre> configurado:
  Tipo:       <descripción>
  App móvil:  <sí | no>
  CLAUDE.md:  creado con la sección Proyecto
  README:     generado por readme-writer
  Skills:     <lista>
```

Después del resumen, sigue con la skill `elegir-metodo` (si `crear-app` ya escribió `docs/METODO.md`, léelo y no preguntes de nuevo) y arranca el Bloque 0 de `desarrollo-por-etapas`.
