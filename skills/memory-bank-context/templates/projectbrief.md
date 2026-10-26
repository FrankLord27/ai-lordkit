# Project Brief

> **Cómo usar esta plantilla:** reemplazá los `[corchetes]` con info real del proyecto.
> Este archivo cambia MUY poco. Si lo modificás, probablemente la dirección del
> proyecto cambió y otros archivos del Memory Bank también deben revisarse.

---

## Nombre

[Nombre del proyecto — ej. Mi POS]

## Propósito (1-2 frases)

[¿Qué hace este software? Ej.: Sistema POS multi-tenant para tiendas físicas
en República Dominicana, con facturación electrónica DGII y contabilidad de
partida doble integrada.]

## Usuario final

[¿Quién lo usa? Ej.: Cajeros, supervisores de turno, administradores de
sucursal, contadores. Tiendas pequeñas y medianas (5-50 empleados, 1-5
sucursales).]

## Objetivos macro

1. [Ej. Permitir vender 100% offline sin perder NCFs ni discrepar al cierre.]
2. [Ej. Cumplir con e-CF DGII a partir del calendario obligatorio del cliente.]
3. [Ej. Generar asientos contables automáticos auditables.]
4. [Ej. Soportar multi-tenant en una sola instancia con aislamiento estricto.]
5. [Ej. Hacer cierres de caja "ciegos" para prevenir robo interno.]

## Restricciones inviolables

- **Legales:** Cumplir Ley 32-23 (e-CF). Conservar comprobantes 10 años.
- **Técnicas:** TypeScript strict. Dinero en `Decimal`, nunca `number`.
  Partida doble validada. Cero `any`.
- **De negocio:** [Ej. No mostrarle el monto esperado al cajero durante el
  cierre — cierre ciego obligatorio.]
- **Operacionales:** [Ej. Operar al menos 4 horas offline en POS.]

## Fuera de alcance

- [Ej. Nómina y RRHH — usuario usará software externo.]
- [Ej. E-commerce / canal online — sólo POS físico.]
- [Ej. Banca / pasarela de pago propietaria — integraciones con terceros.]
- [Ej. Mercados fuera de R.D. en esta fase.]

## Stakeholders clave

- **Producto:** [Nombre del owner]
- **Desarrollo:** [Quién implementa]
- **Cliente piloto:** [Si aplica]

## Estado

- **Fase actual:** [MVP / Beta / Producción]
- **Próximo milestone:** [Nombre + fecha tentativa]

---

_Última actualización: [YYYY-MM-DD] por [autor]_
