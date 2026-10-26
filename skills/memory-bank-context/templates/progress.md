# Progress

> **Cómo usar esta plantilla:** bitácora histórica. APPEND-ONLY en la sección
> "Completado". Mover de "En curso" → "Completado" al cerrar tareas.
> Mover de "Backlog" → "En curso" al empezar.

---

## Completado

> Cada entrada con fecha ISO. La más reciente arriba.

- **2026-05-21** [Ej. ERD del módulo accounting finalizado. Migración Prisma
  inicial aplicada con Account, JournalEntry, JournalLine.]
- **2026-05-19** [Ej. Setup inicial del monorepo: Turborepo + NestJS 11 +
  Next.js 15 + Prisma 7 funcionando. CI con dependency-cruiser.]
- **2026-05-18** [Ej. Memory Bank inicializado. projectbrief.md y
  productContext.md validados con stakeholder.]

## En Curso

> Tareas activas. Una por persona o por sub-agente.

- **[P1]** [Tarea con prioridad. Ej.: Implementar PostJournalEntryUseCase con TDD.]
- **[P1]** [Migración SQL de triggers de inmutabilidad para JournalEntry/JournalLine.]
- **[P2]** [Setup de Bull Board para monitoreo de colas.]

## Backlog priorizado

> Próximas tareas. Mantener ordenadas por prioridad y dependencia.

### Sprint actual

- **[P1]** Módulo `pos`: terminar sesión de caja con cierre ciego.
- **[P1]** Módulo `fiscal-dgii`: generación de XML de e-CF E32 con firma XAdES.
- **[P2]** Endpoint para reporte 607 mensual.

### Próximo sprint

- **[P1]** Módulo `inventory`: ajustes de stock con asientos contables automáticos.
- **[P2]** Dashboard admin con saldos en tiempo real.
- **[P3]** Sincronización offline → online con resolución de conflictos.

### Futuro / Sin fecha

- Integración con pasarela de pagos [nombre].
- App móvil para cajeros.
- Multi-currency con conversión histórica.

## Bugs conocidos

| ID      | Severidad | Descripción                                                             | ETA           |
| ------- | --------- | ----------------------------------------------------------------------- | ------------- |
| BUG-001 | P2        | [Ej. El cálculo de ITBIS descuenta 1 centavo en redondeos específicos.] | Sprint actual |
| BUG-002 | P3        | [Ej. Bull Board no carga en Safari.]                                    | Backlog       |

## Decisiones pospuestas

- **2026-05-20** Diferida la integración con [X] hasta validar volumen real
  de transacciones en el piloto.
- **2026-05-18** Diferido el soporte multi-currency hasta v2.

## Hitos / Milestones

- [ ] **MVP funcional** (target: [fecha])
  - [x] Setup monorepo
  - [x] Módulo accounting ERD
  - [ ] Módulo POS funcional
  - [ ] Módulo fiscal-DGII en sandbox
  - [ ] Cierre ciego validado en pruebas
- [ ] **Beta piloto** (target: [fecha])
- [ ] **Producción** (target: [fecha])

## Métricas a fecha

- **Coverage:** [X%]
- **Tests pasando:** [N/M]
- **Tiempo de build:** [Xs]
- **Architecture score:** [X/100]
- **Módulos completados:** [N]

---

_Última actualización: [YYYY-MM-DD]_
