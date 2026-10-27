# Informe de blindar

Se guarda en `docs/seguridad/blindar-<bloque o "completo">-<AAAA-MM-DD>.md`. Nunca lleva valores de secretos, tokens ni datos personales reales.

## Cierre de bloque

```md
# Blindar — <bloque> — <AAAA-MM-DD>

Modo: intermedio · Stack: NestJS 11 + Next.js 16 · Alcance: 14 archivos del bloque + 4 globales

## Resumen
| Chequeo | Estado | Crít. | Altos | Medios | Bajos |
|---|---|---|---|---|---|
| 1. Validación de inputs | ⚠️ | 0 | 1 | 1 | 0 |
| 2. Rate limit usuario/IP | ✅ | 0 | 0 | 0 | 1 |
| 3. Errores | … |
| 4. Tokens y sesiones | … |
| 5. CORS | … |
| 6. Rutas sin auth/validación | … |

¿Alguien puede quedarse conectado sin querer? <sí/no, con evidencia>
¿Alguien puede actuar como otro usuario? <sí/no, con evidencia>

## Hallazgos
### [ALTO-1] Body sin schema en crear estudiante
- Dónde: `apps/api/src/students/students.controller.ts:42`
- Riesgo: se puede mandar `tenantId` y crear el estudiante en otro colegio.
- Arreglo: <diff corto> (ref. nestjs-security-hardening §9)
- Verificación: `pnpm test:e2e students` → 12 pasan, incluido "rechaza tenantId extra con 400".
- Estado: corregido · pendiente (motivo) · aceptado por el usuario (motivo)

## Rutas del bloque
<tabla del chequeo 6>

## Lo que está bien
- <2 o 3 cosas concretas>

## Pendiente
- <lo que no se pudo verificar y qué haría falta>
```

## Auditoría completa

```md
# Auditoría de seguridad — <proyecto> — <AAAA-MM-DD>

Modo · alcance · commit auditado

## 1. Resumen ejecutivo
Estado general, principales riesgos, correcciones más importantes, riesgos pendientes.

## 2. Vulnerabilidades
Por cada una: id, nombre, severidad, archivo:línea, descripción técnica, impacto,
escenario de explotación, corrección, resultado de la verificación.

## 3. Inventario de endpoints
Todas las rutas con auth, autorización, validación, rate limit y estado
(CONTROLES OK / VULNERABLE / REQUIERE REVISIÓN / PÚBLICO INTENCIONAL).

## 4. Cambios
Archivos modificados, protecciones nuevas, cambios de configuración.

## 5. Pruebas
| Comando o procedimiento | Resultado | Qué demuestra | Qué no demuestra |
|---|---|---|---|
Resultado es uno de: pasó · falló · omitida · no ejecutable (motivo).

## 6. Riesgos pendientes
Vulnerabilidades sin corregir, chequeos incompletos, lo que depende de terceros.

## 7. Acciones manuales
Variables a configurar, secretos a rotar, servicios a habilitar, cambios de infraestructura.
(Nombres, nunca valores.)

## 8. Evaluación final
Una de las tres, justificada con lo de arriba.
```

## Evaluación final

- **NO APTO PARA PRODUCCIÓN**: quedan críticos o altos sin resolver, o faltan controles esenciales.
- **APTO CON RESERVAS**: sin críticos ni altos pendientes en lo revisado, pero hay riesgos o verificaciones importantes pendientes.
- **SIN HALLAZGOS CRÍTICOS PENDIENTES EN EL ALCANCE AUDITADO**: se corrigió o verificó lo relevante dentro del alcance. No es una garantía de seguridad.

Nunca se escribe "la app es segura". El informe dice qué se revisó, qué se corrigió, qué se probó y qué no.

En el cierre de bloque la evaluación es más corta: **bloque cerrado** (0 críticos y 0 altos abiertos) o **bloque bloqueado** (lista de lo que falta).
