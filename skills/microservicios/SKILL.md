---
name: microservicios
description: Úsala cuando el usuario pida microservicios, cuando elegir-metodo detecte señales de que un monolito no alcanza (equipos separados, cargas muy distintas, despliegues independientes) o al diseñar gateway, servicios, contratos, eventos o el compose de un sistema distribuido. Dice primero si NO conviene y propone el monolito modular cuando aplica.
---

# Microservicios: la opción para cuando el proyecto la justifica

Esta skill es una **alternativa de arquitectura**, no el estándar. El estándar es `fullstack`: un monolito modular (Next.js + NestJS + Prisma + PostgreSQL). Aquí se explica cuándo vale la pena partirlo, cómo se parte y cómo se construye por bloques sin perder el hilo.

## 1. Primero: ¿hace falta?

Los microservicios no hacen el sistema más ordenado. El orden lo dan las **fronteras** entre módulos. Los microservicios suman red, despliegues, consistencia eventual y observabilidad, y solo se pagan si resuelven un problema que existe hoy.

**No conviene** (recomienda el monolito modular y dilo claro):
- Un solo desarrollador o un equipo de menos de 3 personas.
- MVP o idea sin validar. Las fronteras todavía se van a mover.
- Todas las áreas escalan igual y se despliegan juntas.
- Las áreas comparten casi todas las tablas, o un flujo necesita una transacción que cruza varias áreas en casi cada request.
- No hay quien opere logs centralizados, trazas, alertas y backups de varias bases.

**Sí conviene** cuando hay **dos o más** de estas señales:
- Equipos distintos que se pisan al desplegar el mismo artefacto.
- Un área con carga muy distinta al resto (búsqueda, tiempo real, procesamiento pesado) que hay que escalar sola.
- Un área que necesita otra tecnología u otro almacenamiento (motor de búsqueda, colas, ML).
- Ritmos de cambio muy distintos: una parte cambia a diario y otra es estable y crítica.
- Aislar fallas es requisito: si cae la búsqueda, los pedidos tienen que seguir.

**Camino intermedio, el recomendado casi siempre:** un **monolito modular con fronteras listas para extraer**. Se usa la misma estructura de esta skill (contratos, eventos, un módulo dueño de cada dato), pero todo se despliega como una sola app. Cuando aparezca una señal, se extrae ese módulo como servicio (patrón strangler) sin reescribir el resto.

Si el usuario quiere microservicios sin las señales, dile el costo en 2 o 3 líneas y que la decisión es suya. Si insiste, se hace bien.

## 2. Las piezas

| Pieza | Para qué | Opción por defecto (stack del kit) | Alternativas |
|---|---|---|---|
| **Frontend** | La UI. Solo habla con el gateway. | Next.js (`apps/web`) | Cualquier SPA o app móvil |
| **Gateway** | Única puerta: rutea por prefijo, valida el JWT, CORS, rate limit, timeouts por ruta, request id | NestJS pequeño con `http-proxy-middleware` (`apps/gateway`) | Traefik, Kong, nginx, Spring Cloud Gateway |
| **Servicios** | Uno por área del negocio (bounded context), dueño de sus datos | NestJS 11 + Prisma 7, cada uno con su base | Lo que el área necesite |
| **Discovery** | Encontrar a los servicios por nombre | El DNS de Docker Compose o de Kubernetes (`http://svc-orders:3000`) | Eureka o Consul, solo si no hay orquestador |
| **Configuración** | Variables por servicio | Variables de entorno validadas con Zod al arrancar, `.env.example` por servicio | Config server, Vault |
| **Contratos** | DTOs y eventos compartidos | `packages/contracts` con schemas Zod versionados | OpenAPI o protobuf generados |
| **Llamadas síncronas** | Consultar algo que se necesita ya | HTTP con un cliente tipado desde `contracts`, con timeout y reintento | gRPC, transporte TCP de `@nestjs/microservices` |
| **Eventos** | Avisar que algo pasó, sin esperar | RabbitMQ o NATS JetStream, publicando por **outbox** | Redis Streams si el volumen es bajo y ya hay Redis |
| **Tiempo real** | Avisar al navegador | WebSocket o SSE en el servicio dueño del evento, expuesto por el gateway | Un servicio `realtime` que escucha eventos |
| **Lectura y búsqueda** | Consultas que cruzan áreas | Servicio de búsqueda con su propio índice, alimentado por eventos | PostgreSQL full-text, Meilisearch, OpenSearch |
| **Despliegue** | Levantar todo | Un Dockerfile multi-stage por servicio + compose maestro | Kubernetes cuando haya más de un nodo |

## 3. Reglas que no se negocian

1. **Una base por servicio.** Si dos servicios leen la misma tabla, es un monolito distribuido: tiene el costo de los microservicios sin ninguna ventaja. Como mínimo, un schema de PostgreSQL por servicio con su propio usuario sin permisos sobre los demás. Cada servicio tiene su `prisma/schema.prisma` y sus migraciones. Nada de sincronizar el esquema automáticamente en producción.
2. **El dueño del dato es el único que lo escribe.** Los demás lo piden por API o guardan una copia que actualizan con eventos.
3. **Nada de tragarse errores entre servicios.** Si un paso de un flujo que cruza servicios falla, el flujo tiene que compensar o quedar en un estado visible ("pendiente de stock"). Un `catch` que solo hace log y sigue es un bug.
4. **Efectos en otro servicio van por outbox.** Se guarda el cambio y el evento en la **misma transacción**; un worker publica el outbox. Los consumidores son **idempotentes** (guardan el id del evento procesado).
5. **Sagas para flujos largos.** Por ejemplo, crear pedido → reservar stock → confirmar o cancelar. Cada paso tiene su compensación. Primero coreografía (eventos); orquestador solo si el flujo tiene más de 4 pasos o reglas complejas.
6. **La identidad se valida en el gateway y en cada servicio.** El gateway verifica el JWT y propaga `x-request-id`. Cada servicio vuelve a verificar el token con la llave pública (guard de `packages/service-kit`). Ningún servicio confía en un header que el cliente puede inventar.
7. **Solo el gateway y el frontend publican puertos.** Dos redes: `edge` (web + gateway) e `internal` (gateway + servicios + bases + broker).
8. **Health en todos.** Cada servicio expone `/health` (vivo) y `/ready` (base y broker conectados). El compose usa `depends_on: condition: service_healthy`.
9. **Cero secretos en archivos versionados.** Ni en `.yml` ni en código. `.env.example` por servicio, y la configuración se valida con Zod al arrancar: si falta una variable, el servicio no levanta.
10. **Contratos versionados.** Un evento nunca cambia de forma: se crea `order.created.v2` y se mantienen los dos hasta que nadie use el viejo. Cada servicio tiene un test de contrato contra `packages/contracts`.
11. **Trazabilidad.** Logs JSON con `requestId` y `service`. Con OpenTelemetry desde el Bloque 0 si hay más de 3 servicios.

## 4. Estructura del monorepo

```
apps/
  web/                 Next.js: solo conoce la URL del gateway
  gateway/             ruteo por prefijo, JWT, CORS, rate limit
  svc-identity/        usuarios, sesiones, roles, emite tokens
  svc-<area>/          un servicio por área del negocio
    src/
      <modulo>/        controller, service, repository (patrón de fullstack)
      events/          publishers (outbox) y consumers
      clients/         clientes HTTP tipados a otros servicios
      config.ts        schema Zod de las variables de este servicio
    prisma/schema.prisma
    Dockerfile
    .env.example
packages/
  contracts/           schemas Zod: DTOs HTTP por servicio y eventos versionados
  service-kit/         bootstrap común: config, logger, health, guard JWT, outbox, cliente HTTP
  tsconfig/ eslint-config/
infra/
  compose.yml          todo el sistema, con healthchecks y redes
  compose.dev.yml      overrides de desarrollo (hot reload, puertos de las bases)
docs/
  ARQUITECTURA.md      mapa de servicios (plantilla abajo)
```

Prefijos: cada servicio es dueño de uno o más prefijos (`/orders`, `/returns`) y el gateway rutea por prefijo sin reescribirlo. Así una ruta se ve igual en el gateway y en el servicio. Ejemplos de gateway, compose, outbox y cliente tipado en `references/plantillas.md`.

## 5. Por bloques, también aquí

El método no cambia (`desarrollo-por-etapas`): se construye un flujo de usuario a la vez. Lo que cambia es qué lleva el Bloque 0 y qué revisa cada puerta.

**Bloque 0 (esqueleto distribuido):**
- Monorepo, `packages/contracts`, `packages/service-kit`.
- `gateway` + `svc-identity` (login y JWT) + **un** servicio de ejemplo con su base.
- `infra/compose.yml` con healthchecks y las dos redes; CI que construye cada imagen.
- Un dato del seed llega a una pantalla **pasando por el gateway**.
- Puerta extra: apagar el servicio de ejemplo no tumba el gateway ni el login (responde 503 con mensaje claro).

**Bloque 0.5 (la primera conversación entre servicios):** un segundo servicio y **un evento** de punta a punta con outbox y consumidor idempotente. Puerta: publicar el mismo evento dos veces deja el estado igual que una vez. Este es el patrón que copian los demás.

**Cada bloque después:**
- En C1 se escribe qué servicios toca, qué endpoints y qué eventos publica o consume. **Si toca más de 2 servicios, las fronteras están mal**: se revisan antes de seguir.
- En C3 los schemas nuevos van a `packages/contracts`, no dentro del servicio.
- En C4 la puerta suma: test de contrato, test de idempotencia del consumidor y test del camino de falla (el otro servicio caído o lento).
- En C5 el e2e corre contra el compose completo, a través del gateway.

## 6. Plantilla de docs/ARQUITECTURA.md

```md
# Arquitectura — <proyecto>

Tipo: microservicios | monolito modular listo para extraer
Decidido: <fecha> · Señales que lo justifican: <cuáles de la sección 1>

## Servicios
| Servicio | Dueño de (datos) | Prefijos | Llama a (sync) | Publica | Escucha | Base |
|----------|------------------|----------|----------------|---------|---------|------|
| gateway | — | /* | todos | — | — | — |
| svc-identity | usuarios, roles | /auth | — | user.created.v1 | — | identity_db |

## Flujos que cruzan servicios
| Flujo (bloque) | Pasos | Compensación si falla |
|----------------|-------|-----------------------|

## Cuándo extraer o juntar
- <señal que haría extraer un módulo, o juntar dos servicios que siempre cambian juntos>
```

## 7. Anti-patrones

- Una sola base compartida por todos los servicios.
- Cadenas síncronas largas (A llama a B, que llama a C, que llama a D): latencia sumada y una falla tumba todo. Si hacen falta, es señal de que esos servicios son uno solo.
- Partir por capa técnica (`svc-database`, `svc-validation`) en vez de por área del negocio.
- DTOs copiados a mano en cada servicio en vez de `packages/contracts`.
- Índices de búsqueda o copias de datos que se llenan a mano en vez de con eventos.
- Infraestructura montada pero vacía (config server o service mesh sin uso): o se usa, o se quita.
- Servicios "nano" con un solo endpoint. Si dos servicios siempre se despliegan juntos, júntalos.
- Credenciales por defecto en el README o en el seed de producción.
