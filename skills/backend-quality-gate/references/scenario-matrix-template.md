# Plantilla: Matriz de Escenarios de Negocio (Por Módulo)

Esta plantilla debe utilizarse para capturar todos los escenarios de negocio **antes** de comenzar la implementación. Se crea una matriz **por módulo** o bounded context.

## 1. Contexto del Módulo
**Módulo:** `[Nombre del Módulo]`
**Objetivo:** `[Breve descripción del propósito de este módulo]`

## 2. Actores
*Definir quién interactúa con este módulo.*
- `[Actor 1]`: `[Descripción y nivel de permisos]`
- `[Actor 2]`: `[Descripción y nivel de permisos]`

## 3. Entidades Core
*Entidades de dominio principales gestionadas en este módulo.*
- `[Entidad]`: `[Propósito clave]`

## 4. Requisitos No Funcionales del Módulo
*Requisitos de rendimiento, concurrencia o escalabilidad específicos de este módulo.*
- `[Requisito 1]`: `[Descripción]`

## 5. Reglas de Negocio
*Reglas invariantes que deben cumplirse siempre en este módulo.*
1. `[Regla 1]`
2. `[Regla 2]`

## 6. Escenarios
*(Los IDs deben usar el formato BSM-<MÓDULO>-<NUMERO>, ej: BSM-AUTH-001)*

### Happy Paths (Caminos Felices)
| ID | Escenario | Precondiciones | Acciones | Resultado Esperado |
|---|---|---|---|---|
| BSM-MOD-001 | | | | |

### Failure Paths (Caminos de Fallo Esperados)
| ID | Escenario | Precondiciones | Causa del Fallo | Respuesta del Sistema |
|---|---|---|---|---|
| BSM-MOD-002 | | | | |

### Edge Cases (Casos Extremos y Concurrencia)
| ID | Escenario | Condición Extrema | Mitigación/Resultado |
|---|---|---|---|
| BSM-MOD-003 | | | |

## 7. Transiciones de Estado
| Entidad | Estado Actual | Acción | Siguiente Estado | Validaciones Requeridas |
|---|---|---|---|---|
| | | | | |

## 8. Matriz de Autorización (Auth Matrix)
| Recurso / Acción | `[Actor 1]` | `[Actor 2]` |
|---|---|---|
| `[Endpoint/Acción]` | `[Permiso]` | `[Permiso]` |

## 9. Requisitos de Auditoría
*Qué eventos requieren ser registrados en el audit log o en tablas de historial.*
- `[Evento]`: `[Datos a registrar]`

---

## Ejemplos de Llenado

### Ejemplo: Módulo de Autenticación (AUTH)
**Reglas:**
1. Las contraseñas deben estar hasheadas con bcrypt (salt rounds: 10).
2. Los tokens JWT tienen un TTL de 15 minutos, los refresh tokens de 7 días.

**Happy Paths:**
| ID | Escenario | Precondiciones | Acciones | Resultado Esperado |
|---|---|---|---|---|
| BSM-AUTH-001 | Login exitoso | Usuario registrado y activo | Ingresa credenciales correctas | Retorna access_token y refresh_token |

### Ejemplo: Módulo Punto de Venta (POS)
**Reglas:**
1. Un carrito vacío no puede procesar el checkout.
2. Si un producto no tiene stock, no puede añadirse al carrito.
3. Se requiere aplicar la skill `erp-saas-core` para manejo de dinero (Decimal).

**Edge Cases:**
| ID | Escenario | Condición Extrema | Mitigación/Resultado |
|---|---|---|---|
| BSM-POS-005 | Compra concurrente del último ítem | Dos usuarios intentan checkout al mismo tiempo | Prisma transaccional con versión o select for update falla para el segundo usuario, retorna 409 Conflict. |

### Ejemplo: Módulo de Logística (TRUCKING)
**Transiciones de Estado (Viaje):**
| Entidad | Estado Actual | Acción | Siguiente Estado | Validaciones Requeridas |
|---|---|---|---|---|
| Viaje | PROGRAMADO | Iniciar viaje | EN_TRANSITO | El camión no debe tener otro viaje activo. |

---

## Anti-patrones a Evitar
- **Matriz Global Monolítica:** Intentar poner todo el sistema en una sola matriz. Siempre divide por módulo.
- **Saltarse los Caminos de Fallo:** Los desarrolladores asumen que la data siempre será perfecta.
- **Descripciones Vagas:** Usar "Falla" en lugar de "Retorna 400 Bad Request con mensaje de error específico".
- **Ignorar Concurrencia:** No contemplar qué pasa si dos requests modifican el mismo recurso en milisegundos.
