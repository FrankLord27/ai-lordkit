# Dependencias — Reglas de Validación del Orden

---

## Dependencias universales — siempre en este orden

Estas no son negociables. En cualquier proyecto con cualquier stack:

```
Fundación (Fase 0)
    ↓ siempre primero
Autenticación (Fase 1)
    ↓ siempre antes que cualquier feature con usuarios
Dominio Core (Fase 2)
    ↓ el producto debe existir antes de extenderse
Features Clave (Fase 3)
    ↓ lo útil antes que lo agradable
Features de Apoyo (Fase 4)
    ↓ funciona bien antes de probarlo con rigor
Calidad (Fase 5)
    ↓ sólido antes de escalar
Escala (Fase 6)
```

---

## Dependencias por tipo de feature

### Features que SIEMPRE necesitan auth primero

Si una feature necesita saber quién es el usuario, auth va antes.

```
✗ Incorrecto:
  Fase 2: Perfil de usuario
  Fase 3: Autenticación  ← el perfil no puede existir sin auth

✓ Correcto:
  Fase 1: Autenticación
  Fase 2: Perfil de usuario
```

Señales de que una feature necesita auth:

- Muestra datos específicos de "mi cuenta"
- Tiene permisos o roles
- Guarda historial por usuario
- Permite editar "mis datos"

---

### Features que necesitan el dominio core primero

Cualquier extensión del dominio core necesita que el core exista.

```
Dominio core: Reservas
    ↓
Feature clave: Historial de reservas       ← necesita que existan reservas
Feature clave: Cancelar reserva            ← necesita que existan reservas
Feature clave: Modificar fecha de reserva  ← necesita que existan reservas
Feature apoyo: Reseña de la reserva        ← necesita reserva completada
```

---

### Features que necesitan otras features específicas

Mapeo de dependencias comunes en proyectos web:

| Feature                  | Depende de                             |
| ------------------------ | -------------------------------------- |
| Checkout / Pago          | Carrito + Auth + Catálogo de productos |
| Historial de compras     | Checkout completo + Auth               |
| Reseñas                  | Auth + Item reseñado                   |
| Favoritos                | Auth + Item favorito                   |
| Notificaciones           | El evento que las dispara              |
| Email de confirmación    | El flujo que se confirma               |
| Dashboard de analytics   | Los datos que se van a mostrar         |
| Búsqueda avanzada        | El catálogo básico que se busca        |
| Exportar a PDF           | Los datos que se exportan              |
| Compartir por link       | El item que se comparte                |
| Sistema de roles / admin | Auth + Dominio core                    |

---

## Checklist de validación del roadmap

Antes de entregar el roadmap, verificar cada punto:

### Validación de orden

- [ ] **Fase 0 es siempre la primera.** Monorepo, configuración base, Docker.
- [ ] **Fase 1 es siempre autenticación.** Ninguna feature de usuario va antes.
- [ ] **Fase 2 es el dominio core.** La feature principal antes que las secundarias.
- [ ] **No hay feature en Fase N que dependa de algo en Fase N+1.**
      Si existe esa dependencia, mover la dependencia a una fase anterior.
- [ ] **No hay dos features en la misma fase donde una depende de la otra.**
      Si Feature A y Feature B están en Fase 3, y B depende de A, A va al inicio
      de Fase 3 y B al final, o A sube a Fase 2.

### Validación de completitud

- [ ] Cada feature del listado original aparece en alguna fase.
- [ ] Ninguna feature está "flotando" sin asignación de fase.
- [ ] Las integraciones externas (APIs de pago, email, mapas) están en una
      fase donde ya existe el dominio que las necesita.
- [ ] Las features de complejidad incierta están en Fase 2 o antes.

### Validación de criterios de salida

- [ ] Cada fase tiene un criterio de salida específico y verificable.
- [ ] El criterio no es "cuando esté listo" o "cuando funcione bien".
- [ ] El criterio se puede probar con un paso concreto (hacer un request,
      completar un flujo en la UI, ver un número en un dashboard).

### Validación del MVP

- [ ] Las Fases 0, 1 y 2 juntas forman un MVP funcional.
- [ ] Al terminar la Fase 2, se puede mostrar el producto a un usuario real
      y que completen el flujo principal.
- [ ] Nada en Fases 3-6 es necesario para que ese flujo funcione.

---

## Errores comunes a evitar

### Error 1: Auth al final

```
✗ Fase 2: Catálogo de productos, perfil de usuario, historial
  Fase 5: Autenticación

  ← Imposible. El perfil no existe sin auth. El historial tampoco.
```

### Error 2: Feature de apoyo antes que el core

```
✗ Fase 2: Sistema de notificaciones por email
  Fase 3: El evento que dispara la notificación

  ← Notificación de ¿qué? El evento debe existir primero.
```

### Error 3: Infraestructura de escala desde el inicio

```
✗ Fase 0: Monorepo + Docker + Kubernetes + Redis cluster + Bull Queue
           + CDN + GraphQL federation

  ← Kubernetes y GraphQL federation son Fase 6. Solo cuando hay
    un problema medido que los justifica.
```

### Error 4: Feature compleja al final como "detalle"

```
✗ Fase 5: Integración con pasarela de pago (Stripe/PayPal)

  ← Las integraciones con terceros tienen incertidumbre técnica alta.
    Van en Fase 2 o 3, nunca al final.
```

### Error 5: Calidad como fase opcional

```
✗ Fase 6 (si hay tiempo): Tests, CI/CD, manejo de errores

  ← La calidad no es opcional. Es lo que define si el proyecto
    puede ir a producción con confianza.
```

---

## Cómo manejar proyectos sin auth

Si el proyecto no tiene usuarios (herramienta interna de un solo admin,
API pública sin restricciones, etc.), la Fase 1 se convierte en
"Configuración de acceso":

```
FASE 1 — ACCESO
- API key básica o IP whitelist
- Variables de entorno de acceso configuradas
- Middleware de validación en todos los endpoints
```

Siempre hay algún nivel de control de acceso antes del dominio core.
Nunca se salta esta fase completamente.

---

## Plantilla para documentar dependencias del proyecto

Usar esto para mapear las dependencias antes de asignar fases:

```
FEATURE: [nombre]
Categoría: Bloqueante / Core / Clave / Apoyo / Pulido
Depende de: [lista de features que deben existir antes]
La necesitan: [lista de features que dependen de esta]
Complejidad: Baja / Media / Alta / Incierta
Fase asignada: 0 / 1 / 2 / 3 / 4 / 5 / 6
Justificación: [por qué va en esa fase]
Criterio de salida: [cómo se sabe que está completa]
```
