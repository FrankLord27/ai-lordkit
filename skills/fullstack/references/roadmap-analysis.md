# Análisis del Proyecto — Cómo extraer lo necesario para generar el roadmap

---

## Paso 1: Extraer el contexto mínimo necesario

Antes de generar cualquier fase, necesitas respuestas a estas preguntas.
Si el usuario no las dio, pregúntalas todas juntas en un solo mensaje — nunca
una por una en conversaciones separadas.

### Preguntas obligatorias

**¿Qué hace el producto?**
Describir en una oración. Si no cabe en una oración, el alcance no está claro.

**¿Quién lo usa?**
Usuario final (B2C), empresas (B2B), interno (herramienta interna). Esto define
si necesitas multi-tenancy, roles complejos, o una sola cuenta de admin.

**¿Cuáles son las features?**
Lista completa de lo que el usuario quiere construir. Sin filtrar aún. Todo lo que mencionan.

**¿Hay integraciones externas?**
APIs de terceros, pasarelas de pago, servicios de email, mapas, etc. Estas
van en fases específicas según su criticidad.

**¿Cuál es el stack?**
Si usa el stack fullstack documentado en la skill `fullstack`, el roadmap
se genera con esas convenciones. Si usa otro stack, adaptar.

---

## Paso 2: Clasificar cada feature

Una vez que tienes la lista completa de features, clasifica cada una en una de estas categorías:

### Categoría BLOQUEANTE

Features sin las cuales el producto no puede funcionar en absoluto.
Ejemplos: autenticación, base de datos, API básica, estructura del proyecto.

**Señales de que algo es bloqueante:**

- Si no existe, ninguna otra feature puede funcionar
- Es infraestructura o configuración
- Define la forma en que todo lo demás se construye

### Categoría CORE

La feature principal que define la propuesta de valor del producto.
Es por qué alguien usaría este producto y no otro.

**Señales de que algo es core:**

- Si se elimina, el producto pierde su razón de existir
- Es lo primero que un nuevo usuario va a querer usar
- Es lo que el cliente/dueño del producto menciona primero cuando describe qué hace

### Categoría CLAVE

Features que hacen el producto útil más allá del caso básico.
Sin ellas el producto funciona pero es limitado.

**Señales de que algo es clave:**

- Los usuarios lo pedirían en las primeras semanas de uso
- Completa el flujo de la feature core
- Es difícil de usar el producto sin ella, pero no imposible

### Categoría APOYO

Features que mejoran la experiencia pero no son bloqueantes.
El producto es completamente usable sin ellas.

**Señales de que algo es apoyo:**

- Notificaciones, emails, reportes, exportaciones
- Personalizaciones de perfil
- Configuraciones avanzadas
- Integraciones opcionales

### Categoría PULIDO

Performance, SEO, accesibilidad, animaciones, dark mode.
Solo entran cuando el producto ya funciona correctamente.

---

## Paso 3: Mapear dependencias entre features

Para cada feature, pregunta: **¿Qué necesita existir para que esta feature funcione?**

Construye un mapa mental:

```
Feature A depende de → [lista de features que deben existir antes]
Feature B depende de → [lista de features que deben existir antes]
```

Ejemplo real:

```
"Ver historial de compras" depende de →
  - Sistema de autenticación (¿quién es el usuario?)
  - Módulo de compras (¿qué compras existen?)
  - Módulo de pagos (¿se confirmó el pago?)

"Hacer una compra" depende de →
  - Sistema de autenticación
  - Catálogo de productos
  - Carrito de compras
  - Pasarela de pago

"Catálogo de productos" depende de →
  - Base de datos con productos
  - API de listado y búsqueda
```

Este mapa determina el orden exacto de construcción.

---

## Paso 4: Identificar el MVP real

El MVP (producto mínimo viable) es el conjunto mínimo de features que:

1. Permite a un usuario completar el flujo principal de principio a fin
2. Tiene valor real para ese usuario
3. No incluye nada que no sea estrictamente necesario para ese flujo

**Cómo identificarlo:**
Toma la feature core. Traza el flujo completo que necesita un usuario para usarla.
Todo lo que ese flujo necesita es el MVP. Nada más entra en las Fases 0-2.

**Ejemplo:**
Si el producto es "reservar un servicio":

```
Flujo mínimo: Usuario se registra → busca servicios → selecciona uno
              → elige fecha → confirma reserva → recibe confirmación

MVP incluye: Auth, listado de servicios, detalle de servicio,
             calendario de disponibilidad, creación de reserva, email de confirmación

MVP NO incluye: Reseñas, favoritos, historial avanzado, notificaciones push,
                dashboard de analytics, exportar a PDF
```

---

## Paso 5: Estimar complejidad por feature

Asigna una complejidad a cada feature antes de ordenarlas:

| Complejidad  | Descripción                                                      | Tiempo estimado  |
| ------------ | ---------------------------------------------------------------- | ---------------- |
| **Baja**     | CRUD simple, pantalla informativa, listado básico                | 1-2 días         |
| **Media**    | Lógica de negocio, integraciones simples, flujos de varios pasos | 3-5 días         |
| **Alta**     | Algoritmos complejos, integraciones con terceros, tiempo real    | 1-2 semanas      |
| **Incierta** | No se sabe bien cómo implementar, requiere investigación         | Investigar antes |

**Regla importante:** Las features de complejidad **Incierta** van en fases tempranas,
no al final. Si no sabes si algo es posible, lo descubres antes de construir todo
lo demás sobre esa suposición.

---

## Resultado del análisis

Al terminar este proceso debes tener:

```
CONTEXTO:
- Qué hace el producto (1 oración)
- A quién va dirigido
- Stack tecnológico

FEATURES CLASIFICADAS:
- Bloqueantes: [lista]
- Core: [lista]
- Clave: [lista]
- Apoyo: [lista]
- Pulido: [lista]

MVP DEFINIDO:
- Features que componen el MVP
- Flujo principal que habilitan

DEPENDENCIAS CRÍTICAS:
- Feature X necesita Feature Y
- Feature Z necesita Feature W y Feature V

FEATURES INCIERTAS:
- [lista de features que necesitan investigación técnica previa]
```

Con esto, ir a `references/roadmap-phases.md` para generar el roadmap.
