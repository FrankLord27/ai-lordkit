---
name: desarrollo-por-etapas
description: Úsala en cualquier proyecto, módulo o feature: se construye por bloques (cada bloque cruza UI, datos y API y queda usable), con una puerta de calidad que se pasa con evidencia antes de seguir. Incluye la versión corta para features y para bugs.
---

# Desarrollo por bloques con puerta de calidad

Regla madre: se construye **por bloques**, no por capas. Un bloque es un flujo que un usuario puede completar ("iniciar sesión", "registrar estudiante", "cobrar una factura"). Dentro de cada bloque las etapas van en orden, y hasta que la puerta no se pasa con evidencia no se abre la siguiente.

Por qué no por capas (toda la UI, después toda la BD, después toda la API): con IA la sesión pierde el hilo entre capas enteras, nada funciona hasta el final y un error de diseño se descubre cuando ya hay mucho construido encima.

Si el proyecto tiene una skill propia con etapas, esa manda; esta es la regla general. Si no hay `docs/METODO.md`, usa primero la skill `elegir-metodo`.

## Al empezar cualquier trabajo

1. Leer `docs/METODO.md` (qué método y qué bloques) y `docs/ETAPAS.md` (por dónde vamos). Si `ETAPAS.md` no existe, crearlo con la plantilla de abajo antes de escribir código.
2. Identificar el bloque actual y su etapa.
3. Trabajar SOLO en ese bloque y esa etapa. Si piden algo de otro bloque o de una etapa posterior, decirlo claro, explicar qué puerta falta y no hacerlo.
4. Al cerrar una puerta, registrar la evidencia en `docs/ETAPAS.md`: comando y resultado, captura, decisión.

## Mapa del proceso

```
Definición ─► Bloque 0 (esqueleto) ─► Bloque 1 ─► Bloque 2 ─► … ─► Endurecimiento ─► Piloto ─► Producto
                                      └── cada bloque: escenarios → UI → datos → API → conexión → puerta
```

Definición, Bloque 0, Endurecimiento, Piloto y Producto van una sola vez por proyecto. El ciclo del bloque se repite.

## A. Definición (una vez por proyecto)

Entrega: problema, usuarios y roles con matriz de permisos, reglas de negocio e invariantes, reglas transversales (permisos, multi-tenant, auditoría, dinero), ADRs de decisiones grandes, y la **lista de bloques** con dependencias en `docs/METODO.md`.
Puerta:
- [ ] Cada bloque del MVP descrito como un flujo de inicio a fin.
- [ ] Matriz de permisos sin celdas vacías.
- [ ] MVP cerrado; lo demás marcado V2.
- [ ] Bloques ordenados por dependencias y riesgo.
Prohibido: código de producción.

Si la idea es incierta, la definición es de una página y va después de un spike que se bota.

## B. Bloque 0: esqueleto (una vez por proyecto)

Entrega: repo y monorepo, base de datos con migraciones y seed, auth base con el modelo de usuario y sesión, guards de rol y de tenant, auditoría si aplica, CI, deploy a staging, y **un módulo de ejemplo** (por ejemplo `health` o `perfil`) que viaje de la BD a una pantalla. Ese módulo es el patrón que copian todos los bloques; el `CLAUDE.md` del proyecto debe apuntar a él.
Puerta:
- [ ] `db:reset` crea todo desde cero con seed.
- [ ] Un dato del seed llega hasta una pantalla en staging.
- [ ] Test de aislamiento: el tenant A no lee ni escribe nada del tenant B (si es multi-tenant).
- [ ] CI corre lint, tipos y tests, y bloquea si fallan.
Prohibido: features de negocio.

Si `docs/METODO.md` dice microservicios, el Bloque 0 y su puerta son los de la skill `microservicios` (gateway, un servicio de ejemplo, contratos, compose), seguidos de su Bloque 0.5 con el primer evento entre servicios.

## C. Ciclo de cada bloque

Dentro del bloque el orden es: lo que ve el usuario define el contrato → el contrato define los datos → los datos definen la API → la API alimenta las pantallas.

### C1. Escenarios y criterios
Antes de tocar código se escriben **escenarios**: una persona concreta que necesita algo concreto. De cada escenario salen las tareas del bloque y los criterios, y de cada criterio sale un test. No se escribe un spec largo.

Formato (en `docs/ETAPAS.md`, debajo del bloque):

```md
### Escenario 1: la contadora ve los ingresos del mes
Quién: contadora del colegio (rol `contabilidad`), tenant "Colegio A".
Necesita: una tabla con todos los ingresos de octubre para cuadrar con el banco.
Pasos: entra a Finanzas → Ingresos → escoge el mes → ve la tabla con fecha, concepto, estudiante,
método de pago y monto → ve el total abajo → exporta a Excel.
Tareas: endpoint de ingresos por mes con paginación · total con Decimal · tabla con filtros · exportar a Excel.
Criterios:
- Dado un mes con 3 ingresos, cuando la contadora lo abre, entonces ve 3 filas y el total exacto.
- Dado un mes sin ingresos, cuando lo abre, entonces ve "No hay ingresos en octubre" y total RD$0.00.
- Dado un usuario con rol `profesor`, cuando entra a la ruta, entonces recibe 403 y no ve el menú.
- Dado un ingreso del Colegio B, cuando la contadora del Colegio A pide el mes, entonces no aparece.
```

Cuántos escenarios: el **modo** activo lo decide (`/output-style`). En completo son de 2 a 4, con un caso de error y uno de permisos o de tenant. En intermedio, de 1 a 3. En ahorro es 1, con sus criterios en una línea cada uno. Sin modo, aplica intermedio.

Reglas:
- Personas y datos concretos ("la contadora", "octubre", "3 ingresos"), no "el usuario hace cosas".
- Si un escenario necesita más de 4 criterios, el bloque es muy grande: pártelo.
- No inventes reglas de negocio. Si el escenario pide algo que nadie ha dicho (¿se puede anular un ingreso?), pregunta.
- Los criterios se escriben como Dado / Cuando / Entonces para que pasen directo a un test (e2e en C5, unitario o de API en C3/C4).

Puerta:
- [ ] Cada escenario tiene quién, qué necesita, pasos y criterios.
- [ ] Cada criterio se puede convertir en un test sin preguntar nada más.
- [ ] Están el caso de error y el de permisos (y el de tenant, si aplica), salvo en modo ahorro.

### C2. Experiencia
Entrega: pantallas o componentes del bloque con datos de prueba (fixtures), estados vacío, cargando, error y datos extremos.
Puerta:
- [ ] Fixtures mínimo y máximo.
- [ ] Responsive en 360, 768 y 1440 px.
- [ ] axe sin errores; contraste AA.
- [ ] Ningún componente consulta datos; todo entra por props.

### C3. Datos
Entrega: schemas Zod sacados de las props reales de C2, cambios de Prisma del bloque, índices, migración, seed del bloque.
Puerta:
- [ ] Los fixtures pasan su schema; uno inválido falla con mensaje claro.
- [ ] Migración reversible.
- [ ] Montos con Decimal, nunca float.

### C4. API
Entrega: módulo siguiendo el patrón del Bloque 0, validación con los schemas de C3, transacciones, efectos secundarios por outbox o cola, OpenAPI.
Puerta:
- [ ] Test e2e por endpoint: rol correcto permitido, 403 para otros roles, 404 para otro tenant.
- [ ] Cada invariante del bloque con su test.
- [ ] OpenAPI coincide con las rutas.
- [ ] Sin N+1 en listados.

### C5. Conexión y puerta del bloque
Entrega: pantallas de C2 conectadas a la API con TanStack Query, errores en español, permisos reflejados en la UI.
Puerta del bloque:
- [ ] e2e (Playwright) del flujo completo pasa.
- [ ] Cada criterio de los escenarios de C1 tiene su test en verde.
- [ ] Ninguna acción visible que el rol no pueda hacer.
- [ ] `/mapa-bloque` sin variables sin usar ni ciclos nuevos (o justificados en `ETAPAS.md`).
- [ ] El bloque se puede usar solo en staging.

**Cada 3 o 4 bloques:** ronda de limpieza. `/mapa-bloque` sobre lo construido, refactor de duplicados y de exports muertos, suite completa en verde.

## D. Endurecimiento (una vez, con el MVP completo)

Entrega: headers y CSP, rate limit, revisión de permisos, backups, monitoreo de errores, logs, health checks, uptime, presupuesto de rendimiento y accesibilidad en CI, documentación de uso y de operación.
Puerta:
- [ ] Todos los flujos del MVP pasan e2e en staging.
- [ ] Restauración desde backup probada.
- [ ] Headers de seguridad en A o superior.
- [ ] Alerta de caída llega al teléfono.

## E. Piloto

Entrega: uso real con un cliente, registro de fricciones y errores.
Puerta:
- [ ] El cliente opera solo sin pedir ayuda.
- [ ] Cero errores críticos abiertos.
- [ ] Cada fricción resuelta o pasada a V2.

## F. Producto y escala

Solo después del piloto: onboarding, planes, facturación, V2. Cada cosa nueva entra como un bloque más.

## Versión corta: una feature en un proyecto que ya existe

Es un bloque: C1 → C2 → C3 → C4 → C5, siguiendo los patrones que ya tiene el repo. Empieza igual por los escenarios de C1, aunque sea uno solo. Si toca tenant, test de aislamiento.

## Versión corta: un bug

1. Reproducir con pasos exactos. Puerta: reproducible.
2. Test que falla por el bug. Puerta: test en rojo.
3. Causa raíz confirmada, no supuesta. Puerta: evidencia de la causa.
4. Fix mínimo. Puerta: test en verde y suite completa en verde.

## Cambios hacia atrás

Si en una etapa posterior aparece un defecto de una anterior: se vuelve a esa etapa, se corrige ahí, se repasa su puerta COMPLETA y se continúa. Nunca se parchea desde la capa de arriba. Si el defecto es del Bloque 0 (un patrón mal hecho), se corrige ahí y se revisan los bloques que lo copiaron. Registrar el regreso en `docs/ETAPAS.md`.

## Plantilla de docs/ETAPAS.md

```md
# Etapas — <proyecto>

Bloque actual: 1. <nombre> · etapa C2

## Proyecto
| Etapa | Estado | Cerrada | Evidencia |
|-------|--------|---------|-----------|
| A. Definición | cerrada | 2026-01-10 | docs/METODO.md |
| B. Bloque 0 | en curso | — | — |
| D. Endurecimiento | bloqueada | — | — |
| E. Piloto | bloqueada | — | — |

## Bloques
| # | Bloque | C1 | C2 | C3 | C4 | C5 | Evidencia |
|---|--------|----|----|----|----|----|-----------|
| 1 | Iniciar sesión | ✓ | … | | | | |
| 2 | Registro | | | | | | |

## Puerta actual
- [ ] ...

## Regresos
- (fecha) Bloque X, de C4 a C3: motivo, qué se corrigió, puerta repasada.
```

## Anti-patrones

- Construir por capas: todas las pantallas primero, después toda la API.
- Empezar un bloque sin el Bloque 0: cada bloque inventa su forma de validar, manejar errores y autorizar.
- Dos bloques a la vez.
- Bloques que no se pueden probar con un e2e de un flujo (demasiado grandes).
- Cerrar una puerta sin evidencia ("ya funciona" no es evidencia).
- Construir sin escenarios: sin una persona y un caso concreto, la IA rellena con supuestos.
- Conectar pantallas a una API sin tests de permisos.
- Agregar V2 antes de pasar el piloto.
