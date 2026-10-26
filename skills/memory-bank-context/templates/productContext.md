# Product Context

> **Cómo usar esta plantilla:** describe el "por qué" del producto. Cambia poco
> (cada milestone, no cada sesión). Es la fuente de verdad cuando hay que
> tomar decisiones de producto.

---

## Problema que resolvemos

[Descripción del dolor concreto. Ej.: Las tiendas pequeñas en R.D. usan POS
viejos sin facturación electrónica, hacen cierres a mano con discrepancias
constantes, y dependen de internet 24/7 para operar. Cuando se va la luz,
pierden ventas.]

## Personas principales

### Persona 1: [Nombre del rol — ej. Cajero]

- **Job to be done:** [Ej. Cobrar rápido, sin errores, sin pensar.]
- **Contexto:** [Ej. Turno de 8 horas, 50-200 ventas por día, atiende presencial.]
- **Lo que más le importa:** [Ej. Que el POS responda en < 200ms al escanear,
  que el ticket imprima al toque.]
- **Lo que NO debe pasarle:** [Ej. Quedarse trabado por falta de internet,
  perder un cobro por culpa del sistema.]

### Persona 2: [Ej. Supervisor de turno]

- **Job to be done:** [Ej. Hacer cierre de caja sin que el cajero pueda
  cuadrar el robo.]
- **Contexto:** [Ej. Cierra 1-3 cajas al día, supervisa 5-15 cajeros.]
- **Lo que más le importa:** [Ej. Que la discrepancia sea inmediata y
  auditable, que las denominaciones cuadren.]

### Persona 3: [Ej. Contador externo]

- **Job to be done:** [Ej. Generar el 607 mensual sin tener que reconstruir
  asientos a mano.]
- **Contexto:** [Ej. Visita la tienda 1 vez al mes, trabaja remoto el resto.]
- **Lo que más le importa:** [Ej. Asientos auto-generados auditables,
  formatos DGII al click.]

## Flujos de usuario críticos

1. **[Flujo A — ej. Venta al contado con e-CF]**
   - Cajero escanea items → calcula total → cobra → emite ticket + e-NCF.
   - Si DGII está caída, ticket emitido igual; e-CF queda en cola.
2. **[Flujo B — ej. Cierre ciego de caja]**
   - Cajero declara denominaciones contadas → submit → ve resultado.
   - Sistema calcula esperado independientemente; muestra discrepancia
     solo después del submit.
3. **[Flujo C — ej. Devolución / nota de crédito]**
4. **[Flujo D — ej. Apertura de turno]**

## Métricas de éxito

- [Ej. Tiempo promedio de venta < 30 segundos.]
- [Ej. Discrepancias al cierre < 0.5% del total cobrado.]
- [Ej. 100% de las ventas con e-CF aceptado por DGII en < 5 minutos.]
- [Ej. 0 ventas perdidas por falta de internet.]
- [Ej. Onboarding de nueva tienda < 2 horas.]

## Diferenciación

[Si compite con otros productos, qué nos diferencia. Ej.: Versus POS
tradicionales, ofrecemos: (1) offline-first real, (2) contabilidad
integrada sin export manual a Excel, (3) cierre ciego que previene robos,
(4) multi-tenant en una sola instancia para grupos de tiendas.]

## Restricciones de UX

- [Ej. Pantallas táctiles primero — botones grandes, sin hover.]
- [Ej. Modo accesible para cajeros de baja alfabetización digital.]
- [Ej. Español neutro, no slang regional.]
- [Ej. Imprimibles compatibles con impresoras térmicas estándar.]

---

_Última actualización: [YYYY-MM-DD] por [autor]_
