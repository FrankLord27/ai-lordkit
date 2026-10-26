---
name: http-query-docs
description: Referencia del método HTTP QUERY (RFC 10008, IETF junio 2026) — el primer método HTTP nuevo en 20 años, un "GET con body" seguro, idempotente y cacheable para consultas complejas. Úsala SIEMPRE que diseñes o generes endpoints de búsqueda/filtrado en APIs REST, veas o vayas a crear patrones como POST /search, POST /filter, POST /find, o el usuario mencione "QUERY", "RFC 10008", "búsqueda avanzada", "filtros complejos", "query con body". Cubre: semántica y comparación con GET/POST, header Accept-Query, Location/Content-Location (stored queries), caché y peticiones condicionales, CORS/preflight, Query Schema estándar del proyecto (filter/sort/include/pagination), catálogo de operadores, implementación en NestJS + Prisma, y estrategia de migración desde POST /search.
---

# HTTP QUERY (RFC 10008)

Método HTTP estandarizado en junio de 2026 para consultas de solo lectura con body. Reemplaza el anti-patrón `POST /recurso/search`.

## Regla de decisión rápida (aplícala al generar endpoints)

1. ¿Modifica datos? → `POST`/`PUT`/`PATCH`/`DELETE`. Nunca QUERY.
2. ¿Filtros simples que caben en query string (<~2000 chars) y conviene que sean bookmarkeables? → `GET /recurso?param=valor`.
3. ¿Filtros complejos, anidados, agregaciones, o body necesario? → `QUERY /recurso` con el Query Schema estándar.
4. ¿La infraestructura (proxy, gateway, cliente) aún no soporta QUERY? → fallback documentado `POST /recurso/search` con plan de migración.
5. NUNCA crear rutas `/search`, `/filter`, `/find` si QUERY cubre el caso. QUERY es un MÉTODO, no un endpoint: `QUERY /users`, jamás `QUERY /users/query`.
6. Multi-tenant: `tenantId` SIEMPRE server-side (JWT/guard), nunca en el body del QUERY.

## Puntos que no debes olvidar al implementar

- Sin `Content-Type` → `400`. Content-Type no soportado → `415` + header `Accept-Query`. Consulta bien formada pero inválida → `422`.
- QUERY dispara preflight CORS siempre: agrega `QUERY` a `Access-Control-Allow-Methods`.
- La clave de caché incluye el body, no solo la URI.
- Valida el body con DTO/Zod y whitelist de campos — nunca filtros arbitrarios directo a Prisma. Nota: los ejemplos de DTO de la guía de referencia usan class-validator; al generar código, tradúcelos a **Zod + `nestjs-zod`** (regla del estándar).
- Documenta el endpoint QUERY en Swagger como cualquier otro (algunas versiones de generadores OpenAPI aún no soportan el método QUERY nativamente — verifica la versión; si no lo soporta, documenta el schema del body igualmente).
- Paginación con `limit` máximo forzado por defecto.

## Referencia completa

Lee `references/rfc10008-guia-completa.md` para: semántica formal, Accept-Query, stored queries (Location/Content-Location), redirecciones, condicionales/ETag, diseño del Query Schema, catálogo de operadores (eq/in/between/contains/...), ejemplos por dominio (marketplace, SaaS tickets, facturación DGII), implementación NestJS completa (adapter, DTO, traducción a Prisma) y checklist de adopción.
