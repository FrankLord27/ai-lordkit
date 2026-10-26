# HTTP QUERY (RFC 10008) — Guía Técnica de Referencia

> Documento de contexto para IA y equipos de desarrollo. Cubre el método HTTP `QUERY` estandarizado en junio de 2026, su semántica, diseño de APIs alrededor de él, y ejemplos aplicados a un stack NestJS + Prisma + PostgreSQL multi-tenant.

**Última actualización:** julio 2026
**Fuente normativa:** RFC 10008 (IETF, Proposed Standard) — Reschke, Snell, Bishop

---

## Tabla de contenidos

1. [Resumen ejecutivo](#1-resumen-ejecutivo)
2. [El problema que resuelve](#2-el-problema-que-resuelve)
3. [Semántica HTTP: comparación de métodos](#3-semántica-http-comparación-de-métodos)
4. [El método QUERY en detalle](#4-el-método-query-en-detalle)
5. [Content-Type y negociación de contenido](#5-content-type-y-negociación-de-contenido)
6. [El header Accept-Query](#6-el-header-accept-query)
7. [Recurso equivalente: Location y Content-Location](#7-recurso-equivalente-location-y-content-location)
8. [Redirecciones](#8-redirecciones)
9. [Peticiones condicionales (caché, ETag)](#9-peticiones-condicionales-caché-etag)
10. [Caché: clave y estrategia](#10-caché-clave-y-estrategia)
11. [Códigos de estado y errores](#11-códigos-de-estado-y-errores)
12. [CORS y preflight](#12-cors-y-preflight)
13. [Qué NO define el RFC (y por qué importa)](#13-qué-no-define-el-rfc-y-por-qué-importa)
14. [Diseño de un Query Schema propio](#14-diseño-de-un-query-schema-propio)
15. [Catálogo de operadores](#15-catálogo-de-operadores)
16. [Ejemplos completos por caso de uso](#16-ejemplos-completos-por-caso-de-uso)
17. [Implementación en NestJS](#17-implementación-en-nestjs)
18. [Migración desde POST /search](#18-migración-desde-post-search)
19. [Buenas prácticas](#19-buenas-prácticas)
20. [Anti-patrones](#20-anti-patrones)
21. [Checklist de adopción](#21-checklist-de-adopción)
22. [Reglas de decisión para IA (cuándo usar cada método)](#22-reglas-de-decisión-para-ia-cuándo-usar-cada-método)
23. [Preguntas frecuentes](#23-preguntas-frecuentes)
24. [Referencias](#24-referencias)

---

## 1. Resumen ejecutivo

`QUERY` es un método HTTP nuevo, estandarizado en **RFC 10008** (2026), el primer método HTTP nuevo en más de veinte años. Nace para llenar un vacío entre `GET` y `POST`:

| | GET | QUERY | POST |
|---|---|---|---|
| Body en la petición | No (no estandarizado) | Sí | Sí |
| Seguro (no modifica estado) | Sí | **Sí** | No garantizado |
| Idempotente | Sí | **Sí** | No garantizado |
| Cacheable | Sí | **Sí** | Solo si el servidor lo indica explícitamente |
| Reintentable automáticamente | Sí | **Sí** | No |
| URI para la consulta misma | Sí (la propia URL) | Opcional (`Location`) | No |
| URI para el resultado | Opcional (`Content-Location`) | Opcional (`Content-Location`) | Opcional |

**Idea central:** `QUERY` es "un GET con body". Envías una consulta compleja (filtros, joins, agregaciones, SQL, JSONPath, lo que sea) en el cuerpo de la petición, igual que harías con `POST /recurso/search`, pero el método comunica correctamente que la operación es de solo lectura. Esto permite caché automático, reintentos seguros y clientes HTTP más inteligentes.

**Lo que reemplaza:** patrones como `POST /users/search`, `POST /products/filter`, `POST /reports/query`.

**Lo que NO reemplaza:** `GET /users`, `GET /users/:id`, `GET /users?status=active` — estos siguen siendo `GET` normal.

```
QUERY /users HTTP/1.1
Host: api.ejemplo.com
Content-Type: application/json
Accept: application/json

{
  "filter": { "status": "active", "country": "DO" },
  "sort": [{ "field": "createdAt", "direction": "desc" }],
  "limit": 50
}
```

---

## 2. El problema que resuelve

### 2.1 GET con query string: límites reales

```
GET /users?status=active&country=DO&sort=-createdAt&limit=50
```

Funciona bien para filtros simples, pero se degrada cuando:

- Hay muchos filtros, filtros anidados, o arrays (`?roles[]=admin&roles[]=editor` vs `?roles=admin,editor` — no hay convención única).
- El tamaño del contenido excede límites prácticos. El propio RFC recomienda soportar al menos **8000 octetos** en la URI, pero no lo garantiza más allá de eso.
- La URL queda registrada en logs de servidores, proxies, historial del navegador y bookmarks — problemático si la consulta contiene datos sensibles.
- Codificar estructuras de datos complejas en query string es ineficiente (overhead de encoding).

### 2.2 GET con body: por qué no funciona

Técnicamente ningún RFC de HTTP prohíbe un body en `GET`, pero tampoco define semántica para él. En la práctica:

- Algunos clientes lo descartan silenciosamente.
- Algunos proxies y balanceadores lo rechazan.
- El comportamiento es inconsistente entre implementaciones.

Por eso nunca se estandarizó "GET con body" — habría roto compatibilidad con infraestructura existente.

### 2.3 El workaround histórico: POST /search

La solución que la industria adoptó fue usar `POST` para consultas complejas:

```
POST /users/search HTTP/1.1
Content-Type: application/json

{ "filter": { "status": "active" } }
```

Esto funciona, pero rompe la semántica HTTP:

- `POST` no es seguro ni idempotente por definición → no se puede reintentar automáticamente sin riesgo.
- No es cacheable de forma automática (proxies, CDNs y navegadores no cachean `POST` por defecto).
- Un cliente HTTP genérico no puede saber, solo por el método, que la operación es de solo lectura.
- Proliferan endpoints artificiales: `/search`, `/filter`, `/find`, `/query`, `/advancedSearch`, uno por cada recurso.

### 2.4 La solución: QUERY

```
QUERY /users HTTP/1.1
Content-Type: application/json

{ "filter": { "status": "active" } }
```

Mismo body que `POST`, pero el método declara explícitamente: *"esto es una consulta segura e idempotente"*. Esto habilita caché, reintentos automáticos y mejor tooling, sin sacrificar la expresividad de un body JSON.

---

## 3. Semántica HTTP: comparación de métodos

| Método | Significado | Seguro | Idempotente | Modifica estado | Body |
|---|---|---|---|---|---|
| `GET` | Obtener un recurso | Sí | Sí | No | No (no estandarizado) |
| `QUERY` | Consultar con lógica compleja | Sí | Sí | No | Sí (semántica según recurso) |
| `POST` | Crear / ejecutar acción | No | No | Generalmente sí | Sí |
| `PUT` | Reemplazar un recurso completo | No | Sí | Sí | Sí |
| `PATCH` | Modificar parcialmente | No | No (generalmente) | Sí | Sí |
| `DELETE` | Eliminar | No | Sí | Sí | Opcional |

**Seguro** (*safe*, RFC 9110 §9.2.1): el cliente no espera ni solicita ningún cambio de estado en el servidor.

**Idempotente** (RFC 9110 §9.2.2): repetir la misma petición N veces produce el mismo efecto que hacerla una vez. Esto es lo que habilita reintentos automáticos ante fallos de red.

---

## 4. El método QUERY en detalle

### 4.1 Definición formal (RFC 10008 §2)

> El método QUERY solicita al recurso destino que realice una operación de consulta dentro del alcance de ese recurso. El contenido de la petición y su tipo de medio (`Content-Type`) definen la consulta. El servidor determina el alcance de la operación en base al recurso destino.

Puntos clave:

- El servidor **debe** rechazar la petición si falta `Content-Type` o es inconsistente con el contenido enviado.
- La query string de la URL destino también participa en identificar el recurso (por ejemplo, `QUERY /reports?version=2`), pero su efecto exacto es específico de cada implementación.
- `QUERY` es seguro e idempotente **por definición** — es responsabilidad del servidor cumplir esto; el RFC no lo fuerza a nivel de protocolo.

### 4.2 Sintaxis básica

```
QUERY /students HTTP/1.1
Host: api.ejemplo.com
Content-Type: application/json
Accept: application/json

{
  "filter": { "grade": "6A", "status": "active" },
  "sort": [{ "field": "lastName", "direction": "asc" }],
  "limit": 20
}
```

Respuesta:

```
HTTP/1.1 200 OK
Content-Type: application/json

[
  { "id": 1, "firstName": "Ana", "lastName": "Pérez", "grade": "6A" },
  { "id": 2, "firstName": "Luis", "lastName": "Ramírez", "grade": "6A" }
]
```

### 4.3 No es un endpoint, es un método

Error común: pensar que `QUERY` implica una ruta especial como `/query` o `/users/query`.

```
❌ POST /users/query
❌ QUERY /users/query

✅ QUERY /users
```

La URL sigue representando el recurso (`/users`). El **método** (`QUERY`) es lo que comunica la intención de consulta. Esto es coherente con el principio REST de que la URI identifica el recurso y el verbo HTTP identifica la acción.

---

## 5. Content-Type y negociación de contenido

El RFC **no define ningún formato obligatorio** para el body de `QUERY`. El servidor decide qué formatos acepta vía `Content-Type` de la petición y `Accept-Query` en la respuesta (ver sección 6). Formatos posibles:

- `application/json` (el más común en APIs REST modernas)
- `application/x-www-form-urlencoded` (compatible con formularios clásicos)
- `application/sql` (consultas SQL directas — usado en ejemplos del propio RFC)
- `application/jsonpath` (JSONPath, RFC 9535)
- `application/xslt+xml` (transformaciones XSLT)
- Cualquier media type que el servidor decida soportar

### 5.1 Reglas de validación del servidor (RFC 10008 §2.1)

| Situación | Código de respuesta |
|---|---|
| Falta `Content-Type` | `400 Bad Request` |
| `Content-Type` no soportado por el recurso | `415 Unsupported Media Type` (incluir `Accept-Query`) |
| `Content-Type` inconsistente con el contenido real | `400 Bad Request` (el servidor **no debe** hacer *content sniffing*) |
| Contenido bien formado pero semánticamente inválido (ej. SQL correcto mas tabla inexistente) | `422 Unprocessable Content` |
| El cliente pide un formato de respuesta (`Accept`) no soportado | `406 Not Acceptable` |

---

## 6. El header Accept-Query

`Accept-Query` es un **header de respuesta** nuevo que un recurso usa para anunciar qué formatos de consulta acepta. Es un *Structured Field* (RFC 9651), tipo Lista.

```
HEAD /contacts HTTP/1.1
Host: api.ejemplo.com
```

```
HTTP/1.1 200 OK
Accept-Query: "application/json", "application/sql"
```

Esto le dice al cliente: *"este recurso acepta consultas en JSON o en SQL crudo"*.

- Aplica a **todos los URIs que comparten el mismo path** (la query string se ignora a estos efectos).
- Si llegan valores distintos en distintas respuestas, se usa el más reciente y "fresco" según las reglas de caché HTTP.
- Es útil para **descubrimiento**: un cliente puede hacer `OPTIONS` o `HEAD` antes de construir la petición `QUERY`, o simplemente intentar `QUERY` y leer `Accept-Query` de una respuesta `415`.

En una API NestJS práctica, normalmente basta con anunciar `application/json` únicamente:

```
Accept-Query: "application/json"
```

---

## 7. Recurso equivalente: Location y Content-Location

Esta es la parte más innovadora del RFC: una consulta puede convertirse en un **recurso HTTP direccionable**.

### 7.1 Concepto: "Equivalent Resource" (§2.2)

El *equivalent resource* de una petición `QUERY` es un recurso hipotético que respondería a `GET` con el mismo resultado, incorporando tanto el contenido de la petición como sus metadatos (Content-Type, etc.). El servidor **puede** (no está obligado a) asignarle una URI real.

### 7.2 Content-Location: "aquí está el resultado que te acabo de dar"

```
HTTP/1.1 200 OK
Content-Type: application/json
Content-Location: /users/stored-results/17

[ ... resultados ... ]
```

Un cliente puede después hacer:

```
GET /users/stored-results/17
```

Y obtiene **exactamente el mismo conjunto de resultados** obtenido en ese momento (aunque los datos originales hayan cambiado después). Es una especie de snapshot.

### 7.3 Location: "aquí puedes repetir esta misma consulta"

```
HTTP/1.1 200 OK
Content-Type: application/json
Location: /users/stored-queries/42

[ ... resultados ... ]
```

```
GET /users/stored-queries/42
```

Esto **re-ejecuta la consulta original** (mismos filtros) y devuelve el resultado **actual** — si los datos cambiaron, el resultado será distinto. Es conceptualmente similar a un *prepared statement*: la consulta queda "compilada" y accesible por URL, sin reenviar el body cada vez.

Analogía útil: `Location` = la consulta guardada (como una vista o un prepared statement). `Content-Location` = una foto congelada del resultado en ese instante.

### 7.4 Cuándo implementarlo

No es obligatorio. Para la mayoría de APIs CRUD internas (SaaS multi-tenant, dashboards administrativos) **no hace falta** implementar `Location`/`Content-Location` — son opcionales y añaden complejidad (persistencia de queries, expiración, etc.). Tiene sentido implementarlos cuando:

- Necesitas compartir/bookmarkear resultados de consultas complejas.
- Quieres aprovechar caché HTTP estándar (`ETag`, `If-None-Match`) sobre resultados de queries pesadas.
- Estás construyendo algo tipo reporting/BI donde las consultas se reutilizan mucho.

---

## 8. Redirecciones

`QUERY` soporta las redirecciones estándar de HTTP, con una diferencia importante respecto a `POST`:

| Código | Significado |
|---|---|
| `301` / `308` | El recurso destino se movió permanentemente. El cliente reenvía la misma petición `QUERY` (con su body) a la nueva URI. |
| `302` / `307` | Movimiento temporal. Igual, se reenvía `QUERY` con el mismo body a la nueva URI. |
| `303 See Other` | El servidor indica que el resultado puede obtenerse con `GET` en la URI dada en `Location` (normalmente apuntando al *stored query*). |

**Diferencia clave con POST:** las excepciones históricas que convierten un `POST` redirigido en un `GET` (por compatibilidad con navegadores antiguos) **no aplican a QUERY**. Un `301`/`302` sobre `QUERY` se reintenta como `QUERY`, no se degrada a `GET`.

---

## 9. Peticiones condicionales (caché, ETag)

`QUERY` soporta el mismo mecanismo condicional que `GET` (RFC 9110 §13): `If-None-Match`, `If-Modified-Since`, etc.

```
QUERY /rfc-index.xml HTTP/1.1
Content-Type: application/sql
If-Modified-Since: Sun, 31 Aug 2025 08:44:00 GMT

SELECT decade, COUNT(*) FROM rfcs GROUP BY decade
```

Si los datos no cambiaron desde esa fecha:

```
HTTP/1.1 304 Not Modified
Last-Modified: Sun, 31 Aug 2025 08:44:00 GMT
```

Esto evita transferir el resultado completo cuando no hay cambios — igual que con `GET`, pero ahora también para consultas complejas con body.

Si el servidor asignó una URI de *equivalent resource* (`Location`), el cliente puede simplificar futuras peticiones usando `GET` sobre esa URI en vez de repetir el `QUERY` completo con su body.

---

## 10. Caché: clave y estrategia

Este es uno de los puntos donde `QUERY` se comporta **distinto a GET** y requiere atención en la implementación:

- La respuesta a `QUERY` **es cacheable** (RFC 9111 aplica).
- La clave de caché **debe incorporar el contenido de la petición** (el body), no solo la URI — a diferencia de `GET`, donde la URI sola es suficiente.
- Los cachés pueden normalizar el contenido antes de generar la clave (por ejemplo, eliminar espacios en blanco insignificantes en JSON) para mejorar la tasa de aciertos, siempre que la normalización no altere el significado de la consulta.
- El cliente puede pedir explícitamente que no se transforme el contenido con la directiva `no-transform`.

**Implicación práctica:** cachear `QUERY` a nivel de CDN/proxy es más complejo que cachear `GET`, porque requiere leer y hashear el body completo para construir la clave. Si tu caso de uso depende mucho de caché de borde (CDN), considera usar el mecanismo `Location` (sección 7.3) para que, tras la primera consulta, el cliente cambie a `GET` sobre una URI estable — eso sí se cachea con la simplicidad habitual de `GET`.

---

## 11. Códigos de estado y errores

| Código | Cuándo usarlo con QUERY |
|---|---|
| `200 OK` | Consulta procesada, resultado en el body |
| `304 Not Modified` | Petición condicional, sin cambios desde la última vez |
| `303 See Other` | Redirección indirecta hacia el *stored query* |
| `400 Bad Request` | Falta `Content-Type`, o es inconsistente con el body enviado |
| `403 Forbidden` | El tenant/usuario no tiene permiso sobre el recurso consultado |
| `406 Not Acceptable` | El `Accept` solicitado por el cliente no puede satisfacerse |
| `415 Unsupported Media Type` | El `Content-Type` de la consulta no está soportado (incluir `Accept-Query`) |
| `422 Unprocessable Content` | Sintaxis válida pero la consulta no puede ejecutarse (ej. campo inexistente) |
| `405 Method Not Allowed` | El recurso no soporta `QUERY` (incluir `Allow`) |

---

## 12. CORS y preflight

`QUERY` **no** pertenece al conjunto de métodos "safelisted" de CORS (solo `GET`, `POST` y `HEAD` con restricciones lo están). Esto significa que **toda petición QUERY desde un navegador dispara un preflight `OPTIONS`**.

Configuración necesaria en el servidor:

```
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, QUERY, OPTIONS
```

Y en el `Allow` de respuestas `OPTIONS`:

```
OPTIONS /users HTTP/1.1
```

```
HTTP/1.1 200 OK
Allow: GET, QUERY, POST, PATCH, DELETE, OPTIONS
```

En Nginx, hay que asegurarse de que el método `QUERY` no sea bloqueado por configuración restrictiva de métodos permitidos (algunos setups antiguos solo permiten explícitamente `GET`, `POST`, `HEAD`, `OPTIONS`).

---

## 13. Qué NO define el RFC (y por qué importa)

El RFC define el **transporte** (el método HTTP, sus garantías de seguridad/idempotencia, headers relacionados, caché, condicionales). **No define:**

- El formato del body de la consulta (JSON, SQL, lo que sea).
- Una sintaxis de filtros, operadores, paginación, ordenamiento, etc.
- Cómo estructurar `include`/`select`/`groupBy` u otras operaciones típicas de una API REST moderna.

**Esto es intencional y es donde entra el diseño propio.** El RFC te da el vehículo (el método HTTP correcto); el "lenguaje de consulta" (Query Schema) lo diseñas tú, consistente en toda tu API. La sección 14 propone un esquema concreto para eso.

---

## 14. Diseño de un Query Schema propio

Esquema recomendado, pensado para ser el mismo en **todos** los recursos de una API (usuarios, productos, facturas, estudiantes, etc.):

```jsonc
{
  // Filtros de igualdad, rango, texto, etc.
  "filter": {
    "status": "active",
    "createdAt": { "gte": "2026-01-01", "lte": "2026-06-30" },
    "role": { "in": ["admin", "editor"] }
  },

  // Búsqueda de texto libre sobre uno o varios campos
  "search": {
    "term": "juan perez",
    "fields": ["firstName", "lastName", "email"]
  },

  // Ordenamiento, soporta múltiples campos
  "sort": [
    { "field": "lastName", "direction": "asc" },
    { "field": "createdAt", "direction": "desc" }
  ],

  // Selección de columnas (reduce payload)
  "fields": ["id", "firstName", "lastName", "email"],

  // Relaciones a incluir (equivalente a un include de Prisma)
  "include": ["profile", "roles"],

  // Agregaciones
  "aggregate": {
    "count": true,
    "sum": ["amount"],
    "avg": ["score"]
  },

  // Agrupación
  "groupBy": ["status", "region"],

  // Filtro post-agregación (equivalente a HAVING en SQL)
  "having": {
    "count": { "gt": 5 }
  },

  // Paginación offset-based
  "pagination": {
    "page": 1,
    "limit": 20
  },

  // Alternativa: paginación cursor-based (recomendada para datasets grandes)
  "cursor": {
    "after": "eyJpZCI6IDEyM30=",
    "limit": 20
  },

  // Evitar duplicados
  "distinct": false
}
```

### 14.1 Reglas de diseño

- **Un solo esquema para toda la API.** No inventes `filter` en un recurso y `where` en otro.
- **Todos los campos son opcionales.** Un body vacío `{}` equivale a "traer todo con valores por defecto".
- **Paginación obligatoria por defecto** con un `limit` máximo razonable (ej. 100) para evitar abuso, incluso si el cliente no lo especifica.
- **Valida el body con un DTO/schema** (class-validator, zod) — nunca ejecutes filtros arbitrarios directo contra la base de datos sin whitelisting de campos permitidos (riesgo de inyección / exposición de columnas internas).
- En sistemas **multi-tenant**, el `tenantId` **nunca** viaja en el body del `QUERY` — se resuelve del contexto de autenticación (JWT/sesión) y se inyecta server-side, igual que en cualquier otro endpoint.

---

## 15. Catálogo de operadores

Para el campo `filter`, un set de operadores típico y suficiente para la mayoría de dominios:

| Operador | Significado | Ejemplo |
|---|---|---|
| `eq` | Igual a | `{ "status": { "eq": "active" } }` (o forma corta `{ "status": "active" }`) |
| `neq` | Distinto de | `{ "status": { "neq": "deleted" } }` |
| `gt` / `gte` | Mayor que / mayor o igual | `{ "amount": { "gte": 1000 } }` |
| `lt` / `lte` | Menor que / menor o igual | `{ "createdAt": { "lt": "2026-01-01" } }` |
| `between` | Rango inclusivo | `{ "amount": { "between": [100, 500] } }` |
| `like` / `contains` | Coincidencia parcial (case-insensitive recomendado) | `{ "email": { "contains": "@gmail.com" } }` |
| `startsWith` / `endsWith` | Prefijo / sufijo | `{ "code": { "startsWith": "FAC-" } }` |
| `in` / `notIn` | Pertenece / no pertenece a un conjunto | `{ "role": { "in": ["admin", "editor"] } }` |
| `exists` | El campo/relación existe | `{ "profile": { "exists": true } }` |
| `null` / `notNull` | Es nulo / no es nulo | `{ "deletedAt": { "null": true } }` |

Estos operadores mapean casi 1:1 a los operadores de filtro de Prisma (`equals`, `not`, `gt`, `gte`, `lt`, `lte`, `in`, `notIn`, `contains`, `startsWith`, `endsWith`), lo que hace la traducción trivial en un backend NestJS + Prisma.

---

## 16. Ejemplos completos por caso de uso

### 16.1 Marketplace / e-commerce: filtrar productos

```
QUERY /products HTTP/1.1
Content-Type: application/json

{
  "filter": {
    "category": { "in": ["ropa", "calzado"] },
    "price": { "between": [500, 5000] },
    "stock": { "gt": 0 }
  },
  "sort": [{ "field": "price", "direction": "asc" }],
  "pagination": { "page": 1, "limit": 24 }
}
```

### 16.2 SaaS B2B (helpdesk): tickets de soporte con agregación

```
QUERY /tickets HTTP/1.1
Content-Type: application/json

{
  "filter": {
    "status": { "in": ["open", "in_progress"] },
    "priority": { "gte": 3 },
    "assignedTo": "user_123"
  },
  "include": ["requester", "assignedAgent"],
  "sort": [{ "field": "priority", "direction": "desc" }],
  "pagination": { "page": 1, "limit": 50 }
}
```

### 16.3 Sistema de horarios escolares: aulas disponibles

```
QUERY /classrooms HTTP/1.1
Content-Type: application/json

{
  "filter": {
    "building": "A",
    "capacity": { "gte": 30 }
  },
  "search": { "term": "laboratorio", "fields": ["name", "description"] },
  "include": ["schedule"],
  "sort": [{ "field": "capacity", "direction": "desc" }]
}
```

### 16.4 Facturación DGII (POS): reporte agregado por período

```
QUERY /invoices HTTP/1.1
Content-Type: application/json

{
  "filter": {
    "issuedAt": { "gte": "2026-06-01", "lte": "2026-06-30" },
    "status": "issued"
  },
  "groupBy": ["ncfType"],
  "aggregate": { "count": true, "sum": ["total", "itbis"] }
}
```

Respuesta:

```json
[
  { "ncfType": "B01", "count": 142, "sum_total": 1284500.00, "sum_itbis": 231210.00 },
  { "ncfType": "B02", "count": 38, "sum_total": 95200.00, "sum_itbis": 17136.00 }
]
```

---

## 17. Implementación en NestJS

NestJS no tiene decorador nativo `@Query()` HTTP-method (el `@Query()` existente es para query params de la URL, algo completamente distinto). Hay que registrar el método manualmente, ya que Express/Fastify no lo reconocen como verbo estándar por defecto.

### 17.1 Decorador de método personalizado

```typescript
// common/decorators/http-query.decorator.ts
import { RequestMapping, RequestMethod } from '@nestjs/common';

export const HttpQuery = (path?: string) =>
  RequestMapping({ path, method: RequestMethod.ALL })(
    // NestJS no expone RequestMethod.QUERY nativamente (aún),
    // así que se intercepta a nivel de adapter/middleware.
    undefined as any,
    undefined as any,
    undefined as any,
  );
```

En la práctica, la forma más estable hoy (dado que `QUERY` es un método muy reciente) es interceptar a nivel de adapter HTTP subyacente (Express o Fastify) antes de que llegue al router de Nest, reescribiendo `QUERY` a un verbo interno que Nest sí entiende, o registrando explícitamente el método en el adapter.

**Con Express (`main.ts`):**

```typescript
import { NestFactory } from '@nestjs/core';
import { ExpressAdapter } from '@nestjs/platform-express';
import express from 'express';
import { AppModule } from './app.module';

async function bootstrap() {
  const server = express();

  // Express no reconoce QUERY por defecto en su router de métodos;
  // se normaliza el método antes de que llegue a Nest.
  server.use((req, _res, next) => {
    if (req.method === 'QUERY') {
      // Se preserva el método original para lógica de negocio/logging
      (req as any).originalHttpMethod = 'QUERY';
    }
    next();
  });

  const app = await NestFactory.create(AppModule, new ExpressAdapter(server));
  app.enableCors({
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'QUERY', 'OPTIONS'],
  });
  await app.listen(3000);
}
bootstrap();
```

**Controlador (usando `@All()` + verificación de método, mientras Nest no soporte QUERY nativamente):**

```typescript
import { All, Controller, Req, Res, HttpStatus } from '@nestjs/common';
import { Request, Response } from 'express';
import { UsersService } from './users.service';
import { QueryUsersDto } from './dto/query-users.dto';
import { validateOrReject } from 'class-validator';
import { plainToInstance } from 'class-transformer';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @All()
  async handleQuery(@Req() req: Request, @Res() res: Response) {
    if (req.method !== 'QUERY') {
      // Deja pasar a otros handlers (GET, POST, etc.) si los hubiera
      return res.status(HttpStatus.METHOD_NOT_ALLOWED).json({
        message: 'Method not allowed on this handler',
      });
    }

    const dto = plainToInstance(QueryUsersDto, req.body);
    await validateOrReject(dto);

    const tenantId = (req as any).user.tenantId; // del JWT/guard, nunca del body
    const result = await this.usersService.query(tenantId, dto);

    return res.status(HttpStatus.OK).json(result);
  }
}
```

> Nota: a medida que el ecosistema (Express, Fastify, Nest) añada soporte nativo de primera clase para `QUERY`, este boilerplate se simplificará a algo como `@HttpMethod('QUERY') @Controller('users')`. Mientras tanto, la normalización manual arriba es el enfoque más portable.

### 17.2 DTO de validación (class-validator)

```typescript
// dto/query-users.dto.ts
import { Type } from 'class-transformer';
import {
  IsOptional,
  IsString,
  IsIn,
  IsArray,
  ValidateNested,
  IsInt,
  Min,
  Max,
} from 'class-validator';

class FilterDto {
  @IsOptional() @IsString() status?: string;
  @IsOptional() @IsString() country?: string;
}

class SortDto {
  @IsString() field: string;
  @IsIn(['asc', 'desc']) direction: 'asc' | 'desc';
}

class PaginationDto {
  @IsInt() @Min(1) page: number = 1;
  @IsInt() @Min(1) @Max(100) limit: number = 20;
}

export class QueryUsersDto {
  @IsOptional()
  @ValidateNested()
  @Type(() => FilterDto)
  filter?: FilterDto;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SortDto)
  sort?: SortDto[];

  @IsOptional()
  @ValidateNested()
  @Type(() => PaginationDto)
  pagination?: PaginationDto = new PaginationDto();
}
```

### 17.3 Traducción del Query Schema a Prisma

```typescript
// users.service.ts
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { QueryUsersDto } from './dto/query-users.dto';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async query(tenantId: string, dto: QueryUsersDto) {
    const { filter, sort, pagination } = dto;
    const { page = 1, limit = 20 } = pagination ?? {};

    const where = {
      tenantId, // siempre inyectado server-side, RLS multi-tenant
      ...(filter?.status && { status: filter.status }),
      ...(filter?.country && { country: filter.country }),
    };

    const orderBy = sort?.map((s) => ({ [s.field]: s.direction })) ?? [
      { createdAt: 'desc' as const },
    ];

    const [data, total] = await this.prisma.$transaction([
      this.prisma.user.findMany({
        where,
        orderBy,
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.user.count({ where }),
    ]);

    return {
      data,
      meta: { page, limit, total, totalPages: Math.ceil(total / limit) },
    };
  }
}
```

### 17.4 CORS para QUERY en NestJS

```typescript
app.enableCors({
  origin: ['https://app.ejemplo.com'],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'QUERY', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Accept-Query'],
});
```

---

## 18. Migración desde POST /search

| Antes | Después |
|---|---|
| `POST /users/search` | `QUERY /users` |
| `POST /products/filter` | `QUERY /products` |
| `POST /reports/query` | `QUERY /reports` |
| `POST /analytics/search` | `QUERY /analytics` |

### 18.1 Estrategia de migración gradual (recomendada para 2026)

Dado que el soporte de `QUERY` en frameworks, proxies y clientes todavía está madurando (RFC publicado en junio de 2026), conviene una migración en fases:

1. **Fase 1 — Coexistencia:** implementa el handler `QUERY /recurso` reutilizando exactamente la misma lógica de negocio que el actual `POST /recurso/search`, sin eliminar este último todavía.
2. **Fase 2 — Deprecación anunciada:** marca `POST /recurso/search` como deprecated en la documentación OpenAPI (`deprecated: true`), agrega header `Deprecation` en las respuestas.
3. **Fase 3 — Retiro:** una vez que los consumidores (frontend propio, SDKs, integraciones externas) migraron, retira el endpoint `POST /search`.

### 18.2 Consideraciones de infraestructura

- **Nginx/Apache:** verificar que no bloqueen el método `QUERY` a nivel de configuración (`limit_except` en Nginx, por ejemplo).
- **API Gateways / balanceadores (AWS ALB, Cloudflare, etc.):** confirmar soporte antes de depender de `QUERY` en producción — algunos productos gestionados pueden tardar en soportarlo.
- **Clientes HTTP:** verificar que el cliente usado en el frontend (fetch, axios) permita enviar el método `QUERY` con body — `fetch` lo permite sin problema (`fetch(url, { method: 'QUERY', body: ... })`), pero conviene probarlo contra el navegador objetivo.

---

## 19. Buenas prácticas

- Usa **un solo Query Schema consistente** en toda la API (sección 14).
- Valida siempre el body contra un DTO/schema — nunca ejecutes filtros dinámicos sin whitelist de campos.
- Inyecta `tenantId` / contexto de autenticación **server-side**, nunca lo aceptes desde el body del `QUERY`.
- Define un `limit` máximo por defecto y forzado (evita que un cliente pida `limit: 999999`).
- Documenta `QUERY` en tu OpenAPI/Swagger igual que cualquier otro método (algunas herramientas de generación de specs aún no lo soportan nativamente — verifica la versión que usas).
- Anuncia `Accept-Query` si soportas más de un formato de body.
- Configura CORS explícitamente para `QUERY` (preflight obligatorio).
- Si necesitas compartir/bookmarkear resultados, implementa `Location`/`Content-Location`; si no, omítelo sin culpa — es opcional.
- Mantén `GET` para todo lo que ya funciona bien con query string simple; no migres por migrar.

---

## 20. Anti-patrones

```
❌ QUERY /search                  → QUERY no es un endpoint, es un método sobre un recurso
❌ QUERY /users/query             → redundante, el método ya dice "query"
❌ POST /users con lógica de solo lectura   → usa QUERY, no POST
❌ Ejecutar SQL crudo construido por concatenación de strings desde el filter del cliente → inyección SQL
❌ Aceptar tenantId o userId dentro del body del QUERY → nunca confíes en el cliente para el contexto de seguridad
❌ Usar QUERY para operaciones que modifican estado (aunque sea "solo actualizar un contador de vistas") → rompe la garantía de "safe"
❌ Definir un Query Schema distinto por cada recurso ("a veces filter, a veces where, a veces conditions") → inconsistencia que complica SDKs y documentación
```

---

## 21. Checklist de adopción

- [ ] Definido el Query Schema único para la API (filter, sort, fields, include, pagination, etc.)
- [ ] DTOs de validación creados por recurso (class-validator / zod)
- [ ] Middleware/adapter configurado para reconocer el método `QUERY`
- [ ] CORS actualizado (`Access-Control-Allow-Methods` incluye `QUERY`, preflight probado)
- [ ] `tenantId`/contexto de auth inyectado server-side, nunca leído del body
- [ ] `limit` máximo forzado en paginación
- [ ] Nginx/Apache/Gateway verificado que no bloquea `QUERY`
- [ ] Documentación OpenAPI actualizada
- [ ] (Opcional) `Accept-Query` anunciado si hay múltiples formatos soportados
- [ ] (Opcional) `Location`/`Content-Location` implementados si hace falta compartir/cachear consultas
- [ ] Plan de migración gradual desde `POST /search` existente, si aplica

---

## 22. Reglas de decisión para IA (cuándo usar cada método)

Al diseñar o generar código de API, aplicar esta lógica:

1. ¿La operación **modifica** datos? → `POST` (crear), `PUT`/`PATCH` (actualizar), `DELETE` (eliminar). Nunca `QUERY`.
2. ¿Es una consulta simple identificable por pocos parámetros planos que caben cómodamente en una URL (< ~2000 caracteres) y que tiene sentido que sea bookmarkeable/compartible? → `GET /recurso?param=valor`.
3. ¿Es una consulta con filtros complejos, anidados, múltiples condiciones, agregaciones, o que simplemente no cabe razonablemente en una query string? → `QUERY /recurso` con el Query Schema estándar del proyecto.
4. ¿El proyecto/infraestructura del usuario todavía no garantiza soporte de `QUERY` en toda su cadena (proxy, gateway, clientes)? → usar temporalmente `POST /recurso/search` como fallback documentado, con plan de migración a `QUERY`.
5. Nunca crear rutas como `/search`, `/filter`, `/find` cuando `QUERY` sobre el recurso ya cubre esa necesidad.
6. Siempre inyectar el contexto multi-tenant (`tenantId`) server-side; nunca confiar en el body de `QUERY` para esto.

---

## 23. Preguntas frecuentes

**¿QUERY reemplaza a GET?**
No. `GET /users`, `GET /users/:id`, `GET /users?status=active` siguen siendo la forma correcta para obtener recursos identificables o con filtros simples.

**¿Puedo usar QUERY para crear o actualizar datos "de paso" (side effects menores)?**
No. `QUERY` está definido como seguro e idempotente. Cualquier efecto secundario (incluso "solo incrementar un contador de vistas") viola esa garantía y puede romper caché/reintentos de clientes que confían en ella.

**¿Necesito implementar Location y Content-Location obligatoriamente?**
No, son opcionales. Solo tienen sentido si necesitas compartir/cachear/bookmarkear resultados de consultas.

**¿Qué pasa si un proxy o cliente no soporta QUERY todavía?**
La petición probablemente falle o sea rechazada antes de llegar a tu servidor. Por eso se recomienda mantener temporalmente un fallback `POST /recurso/search` mientras la infraestructura involucrada (navegadores, proxies, gateways, SDKs) termina de adoptar el método, dado que el RFC es de 2026 y la adopción es reciente.

**¿El body de QUERY tiene que ser JSON?**
No. El RFC no define el formato — puede ser JSON, SQL, JSONPath, XSLT, form-urlencoded, o cualquier media type que el servidor decida soportar y anuncie vía `Accept-Query`. Para una API REST típica, JSON es la elección práctica recomendada.

---

## 24. Referencias

- RFC 10008 — *The HTTP QUERY Method* (J. Reschke, J.M. Snell, M. Bishop), IETF, 2026.
- RFC 9110 — *HTTP Semantics*.
- RFC 9111 — *HTTP Caching*.
- RFC 9651 — *Structured Field Values for HTTP*.
- RFC 9535 — *JSONPath: Query Expressions for JSON*.
- WHATWG Fetch Standard (CORS, preflight).
