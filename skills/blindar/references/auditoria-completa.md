# Auditoría completa (`/blindar todo`)

Para cuando el proyecto está avanzado o terminado, en la etapa D. Endurecimiento y antes de producción. Recorre todo el repositorio, no solo un bloque. Son 12 fases; las fases 2 a 8 son los 6 chequeos de `chequeos.md` aplicados a todo el proyecto, más lo que se agrega aquí.

Si el proyecto es grande para una sola pasada: audita todo primero (fases 1 a 9), arregla críticos y altos, y deja el resto por etapas. Guarda el avance en el informe ("hecho / falta") para seguir en otra sesión.

## Fase 1. Reconocimiento y superficie de ataque

Antes de tocar nada:
- `git status`: anota los cambios que ya existían. No los pises ni los reviertas.
- Frameworks y versiones, arquitectura (monorepo, apps, servicios externos).
- Auth y autorización: dónde se crea la sesión, qué guards hay, dónde vive la matriz de permisos.
- BD, ORM y acceso a datos; multi-tenant si aplica.
- Puntos de entrada: rutas HTTP, server actions, WebSockets, colas y workers, cron, webhooks.
- Variables de entorno: solo desde `.env.example` y el schema de config. Qué existe y dónde se usa; **nunca** los valores.
- Archivos (MinIO/S3/disco), infraestructura declarada en el repo (Dockerfile, compose, nginx, CI).

Resultado: un mapa corto de la superficie de ataque y la lista de áreas a inspeccionar.

## Fases 2 a 8. Los 6 chequeos sobre todo el proyecto

| Fase | Chequeo en `chequeos.md` |
|---|---|
| 2. Validación y sanitización de entradas | 1 |
| 3. Rate limiting y abuso | 2 |
| 4. Autenticación, autorización y control de acceso (IDOR/BOLA/BFLA, escalada de privilegios) | 4 y 6 |
| 5. Tokens, sesiones, cookies y JWT | 4 |
| 6. Errores, excepciones y logs | 3 |
| 7. CORS | 5 |
| 8. Inventario completo de rutas con su estado | 6 |

En la fase 4, además: cada ruta tiene una política de acceso explícita (pública, autenticada, admin, por permiso); la autorización se revisa en lectura, creación, edición y borrado; los endpoints internos, de admin y de diagnóstico están protegidos. Un endpoint público no es vulnerable por ser público: decide si es intencional y seguro para lo que hace.

## Fase 9. Protecciones adicionales

- **Headers**: CSP, HSTS, `X-Content-Type-Options`, `Referrer-Policy`, `frame-ancestors`, `Cache-Control: no-store` en respuestas con datos sensibles. NestJS: Helmet (`nestjs-security-hardening` §2). Next.js: `headers()` en `next.config` o el proxy.
- **Contraseñas y recuperación**: argon2id (o bcrypt ≥ 12 en legado), token de reset aleatorio, guardado como hash, con expiración y un solo uso, sin enumeración (`nestjs-security-hardening` §8).
- **Base de datos**: consultas parametrizadas, usuario de BD sin superusuario, transacciones en operaciones críticas, RLS o filtro de tenant en todas las queries.
- **Archivos**: tamaño máximo, tipo real, nombre UUID, sin path traversal, almacenamiento privado con URLs firmadas, nada ejecutable (`nestjs-security-hardening` §14 y la skill `minio-docs`).
- **Configuración**: secretos en el repo (sin mostrar su valor), debug activo en producción, Swagger abierto, endpoints de diagnóstico, proxy mal configurado.
- **Dependencias**: si existe la skill `/brechas`, delégale esta parte (CVEs, paquetes maliciosos, versiones). Si no, `pnpm audit --prod` y anota que es una revisión parcial.
- **Referencia**: OWASP Top 10 y OWASP API Security Top 10, sin limitarte a ellos.

### Next.js (App Router)

- **Server Actions**: cada función en un archivo `'use server'` es un endpoint POST público. Verifica sesión, permisos y valida con Zod **dentro** de la acción. Que el botón no se muestre no protege nada.
- **Route Handlers** (`app/**/route.ts`): igual que un controller; auth y validación en cada método exportado.
- **`proxy.ts`** (antes `middleware.ts` en Next 15): sirve para redirigir y cortar temprano, no como única barrera. Revisa el `matcher`: lo que no cubre queda sin filtro. La autorización real va en la capa de acceso a datos.
- **`NEXT_PUBLIC_*`**: todo lo que empieza así va al navegador. Ningún secreto, llave de API privada ni URL interna.
- **Server → Client**: los props que un Server Component pasa a un Client Component viajan al navegador. Pasa DTOs con los campos necesarios, no el registro completo de Prisma. Marca los módulos de servidor con `import 'server-only'`.
- **Fetch con sesión** desde el servidor hacia la API: no reenvíes cookies a dominios de terceros.

### NestJS

- Guard global deny-by-default con `@Public()` explícito, `ZodValidationPipe` global, filtro global de errores, throttler global con trackers por IP y por usuario, Helmet, CORS por lista blanca, `trust proxy` correcto. El estándar completo y su checklist de 18 puntos están en `nestjs-security-hardening`: en la auditoría completa recórrelo entero y reporta cada punto como OK / FALTA / RIESGO.
- WebSockets: auth en el handshake y tenant en cada evento. Colas y cron: no confían en datos del job sin validar.

## Fase 10. Correcciones

Orden: críticos (acceso no autorizado, acciones privilegiadas, fuga grande de datos) → altos (cuentas, sesiones, datos sensibles) → medios (validación, abuso, configuración) → bajos.

Por cada una: problema, `archivo:línea`, escenario de explotación plausible (sin exploit funcional), arreglo proporcional, test, ejecución del test, comprobación de que lo legítimo sigue funcionando, riesgo residual.

No se hace:
- Cambiar framework, base de datos o mecanismo de auth sin justificarlo y sin el OK del usuario.
- Quitar una funcionalidad para cerrar un hueco.
- Desactivar auth, CORS o validaciones para que un test pase.
- Tocar datos reales, producción o correr migraciones destructivas. Una migración nueva se avisa antes.
- Meter secretos en el código. Si hace falta uno nuevo, va a `.env.example` sin valor y a "Acciones manuales" del informe.

Si un arreglo depende de algo externo (rotar un secreto, cambiar el proxy del servidor, un servicio), prepara lo que se pueda en el código y anótalo como pendiente.

## Fase 11. Pruebas y verificación

Usa las herramientas que ya tiene el proyecto (Jest/Vitest, Supertest, Playwright, `tsc`, lint). Pruebas negativas mínimas:
- Sin sesión no se accede a nada privado.
- El usuario A no lee ni modifica lo de B; otro tenant → 404.
- Un usuario normal no ejecuta acciones de admin.
- Entrada inválida o con campos extra → 400 en el servidor.
- Exceso de requests → 429, y se recupera después de la ventana.
- Token expirado o revocado → 401.
- Un error 500 no trae stack, SQL ni rutas internas.
- Un origen no autorizado no recibe headers CORS.
- Un endpoint público no devuelve datos privados.

Un test que solo mira el status no basta cuando importa el body o el efecto (que el registro no cambió, que el body no trae datos ajenos). Si un test no se puede correr (falta Redis, faltan credenciales de prueba), dilo: "no ejecutado, motivo".

## Fase 12. Informe

Formato en `informe.md`, con la evaluación final.

## Segunda pasada (modo completo)

Después de los arreglos, revisa de nuevo **solo los archivos que cambiaste** como si no los hubieras escrito tú: ¿el arreglo abrió otro hueco, rompió un flujo legítimo o quedó a medias en otra ruta igual? Si hay agents, esta pasada la hace `security-auditor` (o `code-reviewer`) con contexto limpio. Lo que encuentre entra al informe.
