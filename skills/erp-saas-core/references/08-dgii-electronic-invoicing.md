# 08 — Facturación Electrónica DGII (R.D.)

## Marco regulatorio

Ley **32-23** (mayo 2023) hace obligatorio el uso de Comprobantes Fiscales Electrónicos (e-CF). Calendario de adopción escalonado entre 2024 y 2026 según clasificación del contribuyente.

> Este documento es guía técnica. Para fechas exactas y obligaciones legales del cliente, consultar a un contador. Las normas DGII pueden cambiar; verificar la versión vigente en `dgii.gov.do`.

---

## Tipos de comprobante (más usados en POS / ERP)

| Código  | Nombre                    | Uso                                                                       |
| ------- | ------------------------- | ------------------------------------------------------------------------- |
| **E31** | Factura de Crédito Fiscal | B2B. Permite al comprador descontar ITBIS. RNC del comprador obligatorio. |
| **E32** | Factura de Consumo        | B2C. Consumidor final. Sin efectos tributarios para el comprador.         |
| **E33** | Nota de Débito            | Aumenta el valor de una factura previa (intereses, fletes, etc.)          |
| **E34** | Nota de Crédito           | Disminuye el valor (devoluciones, descuentos posteriores, anulaciones)    |
| **E41** | Compras                   | Cuando el proveedor no es contribuyente formal                            |
| **E43** | Gastos Menores            | Caja chica, viáticos, gastos sin comprobante formal                       |
| **E44** | Regímenes Especiales      | Zonas francas, etc.                                                       |
| **E45** | Gubernamental             | Ventas a entidades del estado                                             |
| **E47** | Pagos al Exterior         | Servicios de no residentes                                                |

Para un POS de tienda física, los críticos son **E32** (la mayoría de ventas) y **E31** (cuando el cliente pide crédito fiscal con su RNC).

---

## Schema Prisma para invoicing fiscal

```prisma
enum ECFType {
  E31  // Crédito Fiscal
  E32  // Consumo
  E33  // Nota Débito
  E34  // Nota Crédito
  E41  // Compras
  E43  // Gastos Menores
  E44  // Regímenes Especiales
  E45  // Gubernamental
  E47  // Pagos al Exterior
}

enum ECFStatus {
  PENDING        // generado, no enviado
  IN_QUEUE       // encolado para envío
  ACCEPTED       // DGII aceptó
  ACCEPTED_COND  // aceptado condicional (solo E32 < umbral)
  REJECTED       // DGII rechazó
  CONTINGENCY    // operando offline, pendiente sincronizar
}

model ECF {
  id              String     @id @default(uuid())
  tenantId        String
  invoiceId       String     @unique
  invoice         Invoice    @relation(fields: [invoiceId], references: [id])

  type            ECFType
  eNCF            String     // formato: "E310000000001"
  trackId         String?    // ID de seguimiento DGII
  status          ECFStatus  @default(PENDING)

  xmlPayload      String     @db.Text   // XML firmado completo
  xmlSignature    String     @db.Text   // firma criptográfica
  dgiiResponseXml String?    @db.Text
  rejectionReason String?

  issuedAt        DateTime   @default(now())
  sentAt          DateTime?
  acceptedAt      DateTime?

  @@unique([tenantId, eNCF])
  @@index([tenantId, status])
  @@index([tenantId, issuedAt])
}

model ECFSequence {
  id           String   @id @default(uuid())
  tenantId     String
  type         ECFType
  currentValue Int      @default(0)
  maxValue     Int      // tope autorizado por DGII
  expiresAt    DateTime // las secuencias expiran

  @@unique([tenantId, type])
}
```

---

## Generación del e-NCF

Formato: `E` + tipo (2 dígitos) + secuencia (10 dígitos)

Ejemplo: `E320000000123` = E32, secuencia 123.

```typescript
function formatECF(type: ECFType, sequence: number): string {
  const code = type.substring(1); // "E32" → "32"
  const seq = sequence.toString().padStart(10, "0");
  return `E${code}${seq}`;
}
```

Asignación con lock serializado (ver `05-idempotency-concurrency.md`):

```typescript
async assignNextECF(tenantId: string, type: ECFType): Promise<string> {
  return this.prisma.$transaction(async (tx) => {
    const result = await tx.$queryRaw<Array<{ next_value: number; max_value: number; expires_at: Date }>>`
      UPDATE "ECFSequence"
      SET "currentValue" = "currentValue" + 1
      WHERE "tenantId" = ${tenantId} AND "type" = ${type}::"ECFType"
      RETURNING "currentValue" AS next_value, "maxValue" AS max_value, "expiresAt" AS expires_at
    `;
    if (!result.length) throw new ECFSequenceNotConfiguredError(type);
    const { next_value, max_value, expires_at } = result[0];
    if (next_value > max_value) throw new ECFSequenceExhaustedError(type);
    if (expires_at < new Date()) throw new ECFSequenceExpiredError(type);
    return formatECF(type, next_value);
  }, { isolationLevel: 'Serializable' });
}
```

---

## Validaciones obligatorias

### E31 (Crédito Fiscal)

- `customerRnc` obligatorio, 9 u 11 dígitos.
- `customerBusinessName` obligatorio.
- Verificar RNC contra DGII (al menos formato; idealmente cache de RNCs válidos).
- Monto: sin límite.

### E32 (Consumo)

- `customerRnc` opcional.
- Si monto >= RD$ 250,000 → exige RNC del cliente.
- Si monto < RD$ 250,000 → puede ir como "Consumidor Final".

### Validación de RNC

```typescript
function validateRncFormat(rnc: string): boolean {
  // Cédula: 11 dígitos sin guiones | RNC: 9 dígitos sin guiones
  return /^\d{9}$|^\d{11}$/.test(rnc.replace(/[-\s]/g, ""));
}

// Validación con dígito verificador (RNC)
function validateRncChecksum(rnc: string): boolean {
  const cleaned = rnc.replace(/[-\s]/g, "");
  if (cleaned.length !== 9) return false;
  const weights = [7, 9, 8, 6, 5, 4, 3, 2];
  let sum = 0;
  for (let i = 0; i < 8; i++) sum += parseInt(cleaned[i]) * weights[i];
  const remainder = sum % 11;
  const checkDigit = remainder === 0 ? 2 : remainder === 1 ? 1 : 11 - remainder;
  return checkDigit === parseInt(cleaned[8]);
}
```

---

## Estructura del XML (resumen)

El XML real es extenso. Para detalles completos, consultar el "Catálogo de Mensajes" de DGII. Estructura simplificada:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ECF xmlns="https://dgii.gov.do/etrib/documentos">
  <Encabezado>
    <Version>1.0</Version>
    <IdDoc>
      <TipoeCF>32</TipoeCF>
      <eNCF>E320000000123</eNCF>
      <FechaVencimientoSecuencia>31-12-2026</FechaVencimientoSecuencia>
      <IndicadorMontoGravado>1</IndicadorMontoGravado>
      <TipoIngresos>01</TipoIngresos>
      <TipoPago>1</TipoPago>
      <FechaEmision>15-05-2026</FechaEmision>
    </IdDoc>
    <Emisor>
      <RNCEmisor>131234567</RNCEmisor>
      <RazonSocialEmisor>Mi Empresa SRL</RazonSocialEmisor>
      <DireccionEmisor>Av. Principal 123, La Vega</DireccionEmisor>
    </Emisor>
    <Comprador>
      <RNCComprador>00123456789</RNCComprador>
      <RazonSocialComprador>Juan Pérez</RazonSocialComprador>
    </Comprador>
    <Totales>
      <MontoGravadoTotal>1000.00</MontoGravadoTotal>
      <MontoGravadoI1>1000.00</MontoGravadoI1>
      <ITBIS1>18</ITBIS1>
      <TotalITBIS>180.00</TotalITBIS>
      <TotalITBIS1>180.00</TotalITBIS1>
      <MontoTotal>1180.00</MontoTotal>
    </Totales>
  </Encabezado>
  <DetallesItems>
    <Item>
      <NumeroLinea>1</NumeroLinea>
      <IndicadorFacturacion>1</IndicadorFacturacion>
      <NombreItem>Producto X</NombreItem>
      <CantidadItem>1</CantidadItem>
      <PrecioUnitarioItem>1000.00</PrecioUnitarioItem>
      <MontoItem>1000.00</MontoItem>
    </Item>
  </DetallesItems>
  <FechaHoraFirma>15-05-2026 14:30:00</FechaHoraFirma>
</ECF>
```

El XML se firma con el certificado digital del contribuyente usando XAdES-BES (XML Signature).

---

## Flujo de envío a DGII

```
[Sale completada]
        ↓
[Generar XML + firmar]
        ↓
[POST a DGII /recepcion/ecf]  (ambiente TesteCF / CerteCF)
        ↓
   ┌────┴────┐
   ↓         ↓
[202]    [4xx/5xx]
   ↓         ↓
[poll status]  [retry / DLQ / contingencia]
   ↓
   ↓
[GET /respuesta/{trackId}]
   ↓
[Aceptado / AceptadoCondicional / Rechazado]
   ↓
[update ECF status + AuditLog]
```

Implementación en el processor:

```typescript
@Processor(QUEUE_NAMES.FISCAL_DGII, { concurrency: 2 })
export class FiscalDgiiProcessor extends WorkerHost {
  async process(job: Job<{ ecfId: string }>) {
    const ecf = await this.ecfRepo.findById(job.data.ecfId);

    try {
      const trackId = await this.dgiiClient.send(ecf.xmlPayload);
      await this.ecfRepo.markAsSent(ecf.id, trackId);

      // Poll de respuesta (puede demorar segundos a minutos)
      const response = await this.pollWithBackoff(trackId, {
        maxAttempts: 20,
        baseDelayMs: 3000,
      });

      if (response.status === "ACEPTADO") {
        await this.ecfRepo.markAsAccepted(ecf.id, response);
      } else {
        await this.ecfRepo.markAsRejected(ecf.id, response.rejectionReason);
        await this.notifyOps(
          `ECF ${ecf.eNCF} rejected: ${response.rejectionReason}`,
        );
      }
    } catch (err) {
      if (this.isDgiiOutage(err)) {
        // Modo contingencia: dejar en cola para retry, no fallar venta
        throw err; // BullMQ reintentará
      }
      throw err;
    }
  }
}
```

---

## Modo contingencia

Cuando DGII no responde, el ERP debe seguir operando:

1. La venta se completa en el POS (cliente se va con su ticket).
2. El e-CF se marca como `CONTINGENCY` y se encola.
3. El worker reintenta con backoff exponencial.
4. Si tras N intentos sigue fallando, alertar a operaciones.
5. Cuando DGII vuelve, se procesa el backlog automáticamente.

Plazo legal: la normativa permite operar en contingencia siempre que se envíe el e-CF en un plazo razonable (típicamente 24-48h). Verificar la versión actual de la norma.

---

## Persistencia de XMLs

**Obligatorio guardar el XML original y la respuesta DGII por al menos 10 años.**

- Backend: `xmlPayload` en DB es válido pero pesado.
- Recomendado: guardar en MinIO/S3 con key estructurada: `tenantId/year/month/eCF/{eNCF}.xml`.
- Mantener en DB solo el path y un hash SHA-256 para verificación.

---

## Formatos de envío mensual (606 / 607 / 608)

Reportes mensuales que el contribuyente envía a DGII:

- **606**: Compras de bienes y servicios.
- **607**: Ventas (ingresos).
- **608**: Comprobantes anulados.

Formato: TXT delimitado por pipes `|`, encoding ANSI/Windows-1252.

Generador típico:

```typescript
async generate607(tenantId: string, period: { year: number; month: number }) {
  const sales = await this.salesRepo.findForPeriod(tenantId, period);
  const lines = sales.map(this.formatLine607);
  const header = `607|${formatRnc(tenant.rnc)}|${period.year}${String(period.month).padStart(2, '0')}|${sales.length}`;
  return [header, ...lines].join('\r\n');
}

private formatLine607(sale: Sale): string {
  return [
    sale.customerRnc ?? '',
    sale.customerRncType,  // 1=RNC, 2=Cédula, 3=Pasaporte
    sale.eCF.type.substring(1),  // "E32" → "32"
    sale.eCF.eNCF,
    formatDate(sale.issuedAt, 'YYYYMMDD'),
    sale.subtotal.toFixed(2),
    sale.itbisAmount.toFixed(2),
    sale.total.toFixed(2),
    // ... más columnas según especificación oficial
  ].join('|');
}
```

> El layout exacto de 606/607/608 cambia ocasionalmente. **Siempre validar contra la última publicación oficial DGII antes de soltar a producción.**

---

## Tests críticos

```typescript
describe("ECF assignment", () => {
  it("assigns sequential e-NCF without gaps", async () => {
    const ids = await Promise.all(
      [1, 2, 3].map(() => service.assignNextECF(tenantId, "E32")),
    );
    expect(ids).toEqual(["E320000000001", "E320000000002", "E320000000003"]);
  });

  it("throws when sequence is exhausted", async () => {
    await prisma.eCFSequence.update({
      where: { tenantId_type: { tenantId, type: "E32" } },
      data: { currentValue: 999 },
    });
    await service.assignNextECF(tenantId, "E32"); // 1000
    await expect(service.assignNextECF(tenantId, "E32")).rejects.toThrow(
      ECFSequenceExhaustedError,
    );
  });

  it("throws when sequence is expired", async () => {
    await prisma.eCFSequence.update({
      where: { tenantId_type: { tenantId, type: "E32" } },
      data: { expiresAt: new Date("2020-01-01") },
    });
    await expect(service.assignNextECF(tenantId, "E32")).rejects.toThrow(
      ECFSequenceExpiredError,
    );
  });
});

describe("E31 validation", () => {
  it("requires customer RNC", () => {
    expect(() => Invoice.createE31({ customerRnc: null /* ... */ })).toThrow();
  });

  it("validates RNC format", () => {
    expect(validateRncFormat("131234567")).toBe(true);
    expect(validateRncFormat("12345")).toBe(false);
  });
});
```
