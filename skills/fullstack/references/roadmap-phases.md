# Fases — Formato y Contenido del Roadmap

---

## Formato de cada fase

Cada fase se entrega con esta estructura exacta:

```
## FASE N — NOMBRE DE LA FASE
**Objetivo:** Qué capacidad tiene el proyecto al terminar esta fase.
**Resultado tangible:** Qué puede hacer un usuario/desarrollador al final.
**Duración estimada:** Rango realista en días o semanas.

### Backend
- [ ] Tarea concreta 1
- [ ] Tarea concreta 2

### Frontend
- [ ] Tarea concreta 1
- [ ] Tarea concreta 2

### Infra / Config
- [ ] Tarea concreta 1

### Criterio de salida
Condición específica y verificable que indica que la fase está completa.
No es "cuando esté listo" — es algo que se puede probar.
```

---

## FASE 0 — FUNDACIÓN

**Siempre igual en todos los proyectos con el stack fullstack documentado.**

**Objetivo:** El proyecto existe, está configurado, y un desarrollador puede
clonarlo, levantar la infra y tener todo corriendo en menos de 10 minutos.

**Resultado tangible:** Next.js corre en localhost:3000, NestJS corre en
localhost:3001, Swagger está en /docs, PostgreSQL y Redis están levantados,
el paquete shared-types está disponible en ambas apps.

**Duración estimada:** 1-2 días

### Backend

- [ ] Monorepo con Turborepo + pnpm workspace configurado
- [ ] Paquetes compartidos: `shared-types`, `typescript-config`
- [ ] NestJS creado con TypeScript strict
- [ ] `main.ts` con Helmet, CORS, GlobalPrefix, ValidationPipe, ExceptionFilter, TransformInterceptor, Swagger
- [ ] `PrismaService` y `PrismaModule`
- [ ] `RedisService` y `RedisModule`
- [ ] Validación de variables de entorno con Zod al arrancar
- [ ] Schema Prisma inicial con entidades base del proyecto
- [ ] Primera migration aplicada

### Frontend

- [ ] Next.js 16 con App Router, TypeScript strict, Sass
- [ ] `apiClient` tipado con fetch wrapper
- [ ] `QueryClient` configurado con defaults
- [ ] `QueryClientProvider` en layout raíz
- [ ] Variables Sass: design tokens de colores, espaciado, tipografía
- [ ] Componentes base: Button, Input (sin lógica de negocio)

### Infra / Config

- [ ] `docker-compose.yml` con PostgreSQL y Redis (con healthchecks)
- [ ] `.env.example` documentado con todas las variables
- [ ] `.gitignore` correcto
- [ ] `commitlint` + `husky` para Conventional Commits
- [ ] `README.md` con instrucciones de setup local

### Criterio de salida

`pnpm dev` levanta web y api sin errores. `GET /api/v1` retorna 200.
Swagger carga en `/docs`. `docker-compose up -d` levanta DB y Redis sin errores.

---

## FASE 1 — AUTENTICACIÓN

**Siempre la segunda fase. Sin auth no se construye nada que requiera saber quién es el usuario.**

**Objetivo:** El sistema sabe quién es cada usuario. Las rutas protegidas
rechazan requests sin token válido.

**Resultado tangible:** Un usuario puede registrarse, iniciar sesión, acceder
a rutas protegidas, refrescar su token y cerrar sesión.

**Duración estimada:** 3-5 días

### Backend

- [ ] Modelo `User` en Prisma con campos base (id, email, password hash, role, timestamps)
- [ ] `AuthModule` con `AuthController` y `AuthService`
- [ ] `POST /auth/register` — crea usuario, hashea contraseña con bcrypt
- [ ] `POST /auth/login` — valida credenciales, genera access token (15min) + refresh token (7d)
- [ ] `POST /auth/refresh` — lee cookie httpOnly, valida contra Redis, genera nuevo access token
- [ ] `POST /auth/logout` — invalida refresh token en Redis, limpia cookie
- [ ] `GET /auth/me` — retorna usuario autenticado (protegido con JwtAuthGuard)
- [ ] `JwtStrategy` con Passport
- [ ] `JwtAuthGuard` reutilizable
- [ ] `@CurrentUser()` decorator
- [ ] Refresh token guardado en Redis con TTL
- [ ] DTOs: `RegisterDto`, `LoginDto` con validación

### Frontend

- [ ] Páginas: `/login`, `/register`
- [ ] Formularios con React Hook Form + Zod (schemas de shared-types)
- [ ] `useLogin`, `useRegister`, `useLogout` — hooks con TanStack Query mutations
- [ ] `useMe` — hook que retorna el usuario autenticado
- [ ] Store de auth en Zustand: usuario actual, estado de autenticación
- [ ] Layout de rutas protegidas: redirige a `/login` si no hay sesión
- [ ] Manejo de token expirado: intercepta 401 y refresca automáticamente
- [ ] Schemas Zod de auth en `shared-types`

### Infra / Config

- [ ] Variables: `JWT_SECRET`, `JWT_EXPIRES_IN`, `REFRESH_TOKEN_EXPIRES_IN`

### Criterio de salida

Un usuario puede registrarse con email/password, iniciar sesión, acceder a una
ruta protegida, y si el access token expira el sistema lo renueva sin interrumpir
al usuario. Un request sin token a una ruta protegida retorna 401.

---

## FASE 2 — DOMINIO CORE

**La feature principal del producto. El motivo por el que existe.**

Esta fase varía completamente según el proyecto. El objetivo es tener
el flujo principal funcionando end-to-end, aunque sea en su forma más básica.

**Objetivo:** Un usuario puede completar el flujo principal del producto
de principio a fin.

**Resultado tangible:** [Describir el flujo completo específico del proyecto]

**Duración estimada:** 1-3 semanas dependiendo de la complejidad

### Qué incluye siempre

**Backend:**

- [ ] Schema Prisma de las entidades del dominio core con índices correctos
- [ ] Migration del schema
- [ ] Repository con métodos: `findAll`, `findById`, `create`, `update`, `delete`
- [ ] Service con lógica de negocio + cache Redis en búsquedas
- [ ] Controller con endpoints documentados en Swagger
- [ ] DTOs de input y validación
- [ ] Mappers para no exponer entidades de Prisma directamente
- [ ] Paginación en listados
- [ ] Guards de autorización (quién puede hacer qué)

**Frontend:**

- [ ] Query keys del dominio en constantes
- [ ] Hooks TanStack Query: `useList[Entidad]`, `use[Entidad]Detail`, `useCreate[Entidad]`, `useUpdate[Entidad]`
- [ ] Páginas: listado, detalle, creación, edición
- [ ] Componentes específicos del dominio
- [ ] Formularios con validación (schema de shared-types)
- [ ] Estados de carga y error en todas las vistas
- [ ] Zustand store si hay estado UI complejo (wizard, carrito, filtros)

### Criterio de salida

El flujo principal completo funciona end-to-end sin errores. Un usuario puede
completar la acción principal del producto desde la UI.

---

## FASE 3 — FEATURES CLAVE

Features que completan y hacen útil el producto más allá del caso básico.
Estas features extienden el dominio core o agregan capacidades relacionadas.

**Objetivo:** El producto cubre todos los casos de uso que un usuario
esperaría encontrar al usarlo por primera vez.

**Duración estimada:** 1-2 semanas por feature clave

### Cómo ordenar las features dentro de esta fase

Si hay múltiples features clave, ordenarlas dentro de la fase por:

1. **Dependencia** — si Feature B necesita Feature A, A va primero
2. **Frecuencia de uso** — lo que más usuarios van a usar, antes
3. **Complejidad de integración** — si una feature requiere un servicio
   externo (pago, email, mapa), va antes para descubrir problemas a tiempo
4. **Valor para el usuario** — lo que más valor aporta, antes

### Formato por sub-feature

```
### [Nombre de la feature]
**Por qué en esta fase:** [justificación]
**Depende de:** [features que deben existir]

Backend:
- [ ] tarea
Frontend:
- [ ] tarea
Criterio: [condición verificable]
```

---

## FASE 4 — FEATURES DE APOYO

Features que mejoran la experiencia pero no bloquean el uso del producto.

**Objetivo:** El producto es agradable de usar y cubre casos secundarios.

**Incluye típicamente:**

- Sistema de notificaciones (in-app o email)
- Historial y logs de actividad
- Exportación de datos (PDF, CSV)
- Configuración de perfil y preferencias
- Búsqueda avanzada con filtros complejos
- Dashboard con métricas básicas para el usuario

**Duración estimada:** Variable. Ordenar igual que Fase 3.

---

## FASE 5 — CALIDAD

**No es opcional. Es la fase que convierte un proyecto que funciona en uno que es confiable.**

**Objetivo:** El proyecto puede ir a producción con confianza.

**Duración estimada:** 1-2 semanas

### Backend

- [ ] Tests unitarios de servicios con lógica de negocio (Jest)
- [ ] Tests de integración de repositories contra DB de test
- [ ] Rate limiting con `@nestjs/throttler`
- [ ] Logging estructurado con correlationId por request
- [ ] Sentry para captura de errores en producción
- [ ] Health check endpoint `/api/v1/health`

### Frontend

- [ ] Tests de componentes críticos (React Testing Library)
- [ ] Tests E2E de los flujos principales (Playwright): registro, login, flujo core
- [ ] Error boundaries en segmentos críticos
- [ ] Manejo correcto de estados de red lenta / error de conexión

### Infra / Config

- [ ] GitHub Actions: lint → typecheck → tests → build en cada PR
- [ ] Dockerfile para el API (producción)
- [ ] Dockerfile para el Web (producción)
- [ ] Variables de entorno de producción documentadas

### Criterio de salida

Pipeline de CI pasa verde. Los 3 flujos principales tienen cobertura E2E.
Sentry captura errores en staging. El build de producción compila sin errores.

---

## FASE 6 — ESCALA

**Solo entra cuando hay usuarios reales y un problema medido que justifica cada adición.**

No agregar nada de esta fase "por si acaso".

| Adición                    | Cuándo justificada                                     |
| -------------------------- | ------------------------------------------------------ |
| Bull Queue                 | Jobs que tardan más de lo que el usuario puede esperar |
| S3 / Cloudinary            | Upload de archivos por usuarios                        |
| Redis pub/sub / WebSockets | Necesidad real de tiempo real                          |
| GraphQL                    | Múltiples clientes con necesidades distintas de datos  |
| Microservicios             | Equipos independientes necesitan deployar por separado |
| Kubernetes                 | El servidor no aguanta la carga con scaling vertical   |

---

## Reglas de presentación del roadmap

1. **Siempre mostrar todas las fases**, aunque algunas estén vacías o sean cortas.
   El usuario necesita ver el panorama completo.

2. **Criterio de salida obligatorio** en cada fase. Sin él, no se sabe cuándo pasar
   a la siguiente.

3. **Duraciones como rangos**, nunca fechas exactas. El software no se puede
   estimar con precisión de calendario.

4. **Marcar dependencias explícitamente** cuando una tarea necesita otra que
   está en una fase diferente.

5. **Separar backend / frontend / infra** dentro de cada fase. Ayuda a ver
   si hay trabajo que se puede paralelizar.

6. **Las features inciertas** (identificadas en el análisis) siempre van en
   Fase 2 o antes, nunca al final.
