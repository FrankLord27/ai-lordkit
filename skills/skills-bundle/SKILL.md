---
name: skills-bundle
description: >
  Bundle completo que activa simultáneamente erp-saas-core y memory-bank-context.
  Úsalo al inicio de cualquier sesión de trabajo en proyectos complejos con lógica
  financiera, contable o multi-tenant (POS, ERP, SaaS multi-tenant).
  Garantiza que las reglas arquitecturales inmutables (erp-saas-core) y el contexto
  de sesión (memory-bank-context) estén activos desde el primer prompt.
  Actívalo cuando el usuario diga "iniciemos", "continuemos el proyecto", "nueva sesión"
  o empiece a trabajar en un proyecto de ese tipo.
compatibility:
  activates:
    - erp-saas-core
    - memory-bank-context
---

# Skills Bundle — Activación Combinada

Este bundle NO contiene copias propias: activa las dos skills canónicas leyendo directamente sus archivos (así nunca hay versiones divergentes):

- `~/.claude/skills/erp-saas-core/SKILL.md`
- `~/.claude/skills/memory-bank-context/SKILL.md`

Las dos skills complementarias del workflow de proyectos complejos:

## 1. `erp-saas-core`

Reglas arquitecturales inmutables para sistemas ERP/SaaS/POS. Cubre:

- Clean Architecture + DDD + Bounded Contexts
- Contabilidad de partida doble con precisión financiera
- Multi-tenancy estricto (tenantId en toda query)
- Facturación electrónica DGII (NCF, e-CF, 606/607/608)
- TDD para lógica financiera
- Idempotencia y concurrencia en operaciones monetarias

## 2. `memory-bank-context`

Sistema de retención de contexto entre sesiones. Cubre:

- Lectura del Memory Bank al inicio de cada sesión
- Actualización de los 6 archivos canónicos al cerrar
- Prevención de alucinaciones sobre el estado del proyecto

## Flujo de uso

```
1. Usuario inicia sesión
   → Activar skills-bundle
   → memory-bank-context lee los archivos de contexto actuales
   → erp-saas-core carga las reglas del dominio

2. Durante el desarrollo
   → erp-saas-core guía decisiones arquitecturales y financieras
   → memory-bank-context mantiene activeContext.md actualizado

3. Al cerrar sesión
   → memory-bank-context actualiza progress.md y activeContext.md
```
