# 10 — Diagramas Mínimos Antes de Programar

## Filosofía: documentar lo justo, no todo

Generar los 8 diagramas formales por cada módulo es sobre-ingeniería. TypeScript estricto + Clean Architecture ya documentan implícitamente gran parte del comportamiento.

---

## Priorización real

### Innegociables (hacer SIEMPRE)

| Diagrama                      | Cuándo                                            | Herramienta                        |
| ----------------------------- | ------------------------------------------------- | ---------------------------------- |
| **ERD** (Entidad-Relación)    | Antes del `schema.prisma` de cada Bounded Context | Mermaid `erDiagram` o dbdiagram.io |
| **C4 Contenedores** (Nivel 2) | Una vez por proyecto, actualizar al sumar infra   | Mermaid `flowchart` o Structurizr  |

### Situacionales (solo si la complejidad lo justifica)

| Diagrama                  | Cuándo justificarlo                                                      |
| ------------------------- | ------------------------------------------------------------------------ |
| **Diagrama de Secuencia** | Flujos asíncronos críticos con varios actores (DGII e-CF, login con SSO) |
| **Diagrama de Estados**   | Entidad con ciclo de vida no trivial (factura, pedido, sesión de caja)   |
| **Diagrama de Actividad** | Lógica condicional densa antes de programarla                            |

### Omitir en el día a día

| Diagrama                 | Por qué                                  |
| ------------------------ | ---------------------------------------- |
| C4 Contexto (Nivel 1)    | Útil para stakeholders, no para devs     |
| C4 Componentes (Nivel 3) | Clean Architecture ya lo dicta           |
| Despliegue               | Solo al setup inicial y cambios de infra |

---

## Plantilla: ERD en Mermaid

```mermaid
erDiagram
    TENANT ||--o{ USER : has
    TENANT ||--o{ ACCOUNT : owns
    TENANT ||--o{ JOURNAL_ENTRY : posts

    ACCOUNT ||--o{ ACCOUNT : parent_of
    ACCOUNT ||--o{ JOURNAL_LINE : receives

    JOURNAL_ENTRY ||--|{ JOURNAL_LINE : contains
    JOURNAL_ENTRY }o--|| FISCAL_PERIOD : in

    TENANT {
        uuid id PK
        string name
        string rnc
        datetime created_at
    }
    ACCOUNT {
        uuid id PK
        uuid tenant_id FK
        string code
        string name
        enum type "ASSET|LIABILITY|EQUITY|INCOME|EXPENSE"
        uuid parent_id FK
        boolean is_leaf
    }
    JOURNAL_ENTRY {
        uuid id PK
        uuid tenant_id FK
        string entry_number
        datetime entry_date
        string description
        string source_module
        uuid source_entity_id
        string idempotency_key UK
        uuid reversed_by_id FK
    }
    JOURNAL_LINE {
        uuid id PK
        uuid tenant_id FK
        uuid entry_id FK
        uuid account_id FK
        decimal amount "signed: + debit, - credit"
        string currency
        int line_order
    }
    FISCAL_PERIOD {
        uuid id PK
        uuid tenant_id FK
        int year
        int month
        enum status "OPEN|CLOSED"
        datetime closed_at
    }
```

> Reglas para tu ERD:
>
> - Cada entidad tenant-aware debe tener `tenant_id` y aparece en `@@unique` o `@@index`.
> - Marcar `UK` (unique) en campos como `idempotency_key`.
> - Mostrar tipo de dato (`decimal`, `enum`) para campos críticos.
> - Comentar campos no obvios (ej. `amount "signed: + debit, - credit"`).

---

## Plantilla: C4 Contenedores

```mermaid
flowchart TB
    user[/"Usuario<br/>(cajero, admin, cliente)"\]
    dgii[(DGII<br/>e-CF API)]
    bank[(Pasarela<br/>de Pago)]

    subgraph monorepo["Monorepo (Turborepo)"]
        subgraph web["apps/web — Next.js 15"]
            ui[UI POS / Admin<br/>React 19 + TanStack Query + Zustand]
        end
        subgraph api["apps/api — NestJS 11"]
            rest[REST Controllers]
            domain[Domain + Application]
            workers[BullMQ Workers]
        end
        pkg[("packages/*<br/>ui, types, config, database")]
    end

    pg[(PostgreSQL 16+<br/>libro mayor inmutable<br/>RLS opcional)]
    redis[(Redis<br/>cache + colas BullMQ)]
    minio[(MinIO / S3<br/>XMLs, PDFs, comprobantes)]

    user -->|HTTPS| ui
    ui -->|JSON / Idempotency-Key| rest
    rest --> domain
    domain --> pg
    domain --> redis
    workers -->|consume| redis
    workers --> pg
    workers -->|XML firmado| dgii
    workers -->|webhooks| bank
    domain --> minio
    web -.->|tipos compartidos| pkg
    api -.-> pkg
```

---

## Plantilla: Diagrama de Secuencia (e-CF a DGII)

```mermaid
sequenceDiagram
    actor C as Cajero
    participant W as Web (Next.js)
    participant A as API (NestJS)
    participant DB as PostgreSQL
    participant Q as BullMQ
    participant P as FiscalProcessor
    participant D as DGII

    C->>W: Confirmar venta
    W->>A: POST /sales (Idempotency-Key)
    A->>DB: BEGIN tx
    A->>DB: INSERT Sale + Payments
    A->>DB: assign e-NCF (SELECT FOR UPDATE)
    A->>DB: INSERT ECF (status=PENDING)
    A->>DB: INSERT OutboxEvent
    A->>DB: COMMIT
    A-->>W: 201 + saleId + eNCF
    W-->>C: Ticket impreso

    Note over Q,P: Async (no bloquea al cajero)
    Q->>P: job: SendECF
    P->>P: build XML + sign (XAdES)
    P->>D: POST /recepcion/ecf
    D-->>P: 202 trackId
    P->>DB: UPDATE ECF status=IN_QUEUE
    loop poll cada 3s
        P->>D: GET /respuesta/{trackId}
        D-->>P: ACEPTADO | RECHAZADO | PENDING
    end
    P->>DB: UPDATE ECF status=ACCEPTED
    P->>Q: job: NotifyCustomer
```

---

## Plantilla: Diagrama de Estados (Sesión de caja)

```mermaid
stateDiagram-v2
    [*] --> OPEN: openSession (declara denominaciones)
    OPEN --> OPEN: addSale / cashIn / cashOut
    OPEN --> CLOSING: requestClose (cierre ciego)
    CLOSING --> CLOSED: confirmClose (calcula discrepancy)
    CLOSED --> RESOLVED: resolveDiscrepancy (admin)
    CLOSED --> [*]: no discrepancy
    RESOLVED --> [*]
```

---

## Plantilla: Diagrama de Estados (Factura E31)

```mermaid
stateDiagram-v2
    [*] --> DRAFT: createDraft
    DRAFT --> ISSUED: confirm (assign eNCF)
    ISSUED --> SENT: send to DGII
    SENT --> ACCEPTED: DGII OK
    SENT --> REJECTED: DGII ERROR
    ACCEPTED --> PAID: applyPayment (total)
    ACCEPTED --> PARTIAL: applyPayment (parcial)
    PARTIAL --> PAID: applyPayment (cierra)
    PAID --> VOIDED: creditNote (E34)
    PARTIAL --> VOIDED: creditNote
    REJECTED --> DRAFT: fixAndResubmit
    VOIDED --> [*]
    PAID --> [*]
```

---

## Plantilla: Diagrama de Actividad (Cierre ciego)

```mermaid
flowchart TB
    start([Cajero pide cerrar caja])
    declare[Cajero declara denominaciones contadas]
    submit{Submit}
    block{Sesión OPEN<br/>en este tenant?}
    lock[Lock fila PosSession - SELECT FOR UPDATE]
    sum[Sumar pagos CASH + cashIn - cashOut]
    calc[expected = openingCash + cashSales + cashIn - cashOut]
    decl[declared = SUM denominations]
    diff[discrepancy = declared - expected]
    save[UPDATE PosSession status=CLOSED + persist denominations]
    audit{discrepancy != 0?}
    log[INSERT AuditLog inmutable]
    threshold{abs discrepancy >= umbral?}
    queue[Enqueue DISCREPANCY_DETECTED a BullMQ]
    show[Mostrar resultado al cajero - solo lectura]
    err[ERROR 409 Conflict]
    fin([END])

    start --> declare --> submit --> block
    block -->|NO| err
    block -->|SÍ| lock --> sum --> calc --> decl --> diff --> save --> audit
    audit -->|NO| show
    audit -->|SÍ| log --> threshold
    threshold -->|NO| show
    threshold -->|SÍ| queue --> show
    show --> fin
    err --> fin
```

---

## Plantilla: Diagrama de Despliegue (referencia inicial)

```mermaid
flowchart LR
    subgraph internet["Internet"]
        users[/"Usuarios<br/>(navegador / PWA)"\]
    end

    subgraph edge["Edge / CDN"]
        cdn[Vercel / Cloudflare<br/>Next.js SSR + estáticos]
    end

    subgraph cloud["VPS / Cloud (App tier)"]
        lb[Load Balancer<br/>Nginx / Traefik]
        api1[Node.js<br/>NestJS API #1]
        api2[Node.js<br/>NestJS API #2]
        worker1[Node.js<br/>BullMQ Worker #1]
        worker2[Node.js<br/>BullMQ Worker #2]
    end

    subgraph data["Data tier"]
        pg[(PostgreSQL<br/>primary + replica)]
        redis[(Redis<br/>persistencia AOF)]
        minio[(MinIO<br/>buckets por tenant)]
    end

    subgraph ext["External"]
        dgii[(DGII e-CF)]
        bank[(Pasarela pagos)]
        smtp[(SMTP / SES)]
    end

    users -->|HTTPS| cdn -->|API calls| lb
    lb --> api1
    lb --> api2
    api1 & api2 --> pg
    api1 & api2 --> redis
    api1 & api2 --> minio
    worker1 & worker2 --> redis
    worker1 & worker2 --> pg
    worker1 & worker2 --> dgii
    worker1 & worker2 --> bank
    worker1 & worker2 --> smtp
```

---

## Dónde guardar los diagramas

```
docs/
  architecture/
    01-contenedores.md       ← C4 Nivel 2 (mermaid)
    02-deployment.md         ← Despliegue
  modules/
    accounting/
      erd.md                 ← Mermaid ERD del módulo
      sequence-post-entry.md ← Si el flujo lo amerita
      state-journal.md       ← Si la entidad tiene estados
    pos/
      erd.md
      activity-blind-close.md
      state-pos-session.md
    fiscal-dgii/
      erd.md
      sequence-ecf.md
```

Convención: cada `.md` empieza con un párrafo de contexto + el bloque Mermaid + un párrafo de "decisiones clave" debajo.

---

## Auto-validación: ¿el diagrama está completo?

| Pregunta                                           | ERD | Secuencia | Estados | Actividad |
| -------------------------------------------------- | --- | --------- | ------- | --------- |
| ¿Aparece `tenantId`?                               | ✓   | —         | —       | ✓         |
| ¿Restricciones únicas marcadas?                    | ✓   | —         | —       | —         |
| ¿Tipos de campo críticos (Decimal, enum) visibles? | ✓   | —         | —       | —         |
| ¿Actores externos identificados?                   | —   | ✓         | —       | —         |
| ¿Operaciones async marcadas como tales?            | —   | ✓         | —       | ✓         |
| ¿Cada transición tiene evento + condición?         | —   | —         | ✓       | —         |
| ¿Estado final `[*]` definido?                      | —   | —         | ✓       | —         |
| ¿Decisiones binarias en rombos?                    | —   | —         | —       | ✓         |
| ¿Path de error trazado?                            | —   | ✓         | ✓       | ✓         |
