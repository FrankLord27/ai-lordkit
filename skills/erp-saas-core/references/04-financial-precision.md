# 04 — Precisión Financiera

## Axioma inviolable

**Nunca, jamás, bajo ninguna circunstancia, usar `number` (IEEE 754 float) para dinero.**

```javascript
0.1 + 0.2 ===
  0.3(
    // false → es 0.30000000000000004
    0.1 + 0.2,
  ).toFixed(20); // "0.30000000000000004441"
```

Multiplicado por miles de transacciones diarias = centavos fantasma = discrepancias inexplicables = pérdida de confianza.

---

## Dos opciones válidas

| Estrategia                   | Pros                                                         | Contras                                                                                         | Cuándo                                      |
| ---------------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- | ------------------------------------------- |
| **Decimal.js** (recomendada) | Legible, manipulación natural, soporta operaciones complejas | Más lento que int (irrelevante en práctica)                                                     | Default para la mayoría de ERPs             |
| **BigInt centavos**          | Máxima velocidad, sin librerías                              | Hay que multiplicar/dividir por 100 en cada I/O; difícil con divisas de 3+ decimales (BHD, JOD) | Sistemas de altísimo volumen, pagos masivos |

**Recomendación:** Decimal.js en backend + frontend. Mismo tipo en ambos lados elimina conversiones.

---

## Configuración global de Decimal.js

Hacelo UNA vez al boot de la app, no por uso:

```typescript
// shared/kernel/decimal.config.ts
import Decimal from "decimal.js";

Decimal.set({
  precision: 28,
  rounding: Decimal.ROUND_HALF_EVEN, // ★ Bancario, no aritmético
  toExpNeg: -7,
  toExpPos: 21,
  minE: -9e15,
  maxE: 9e15,
  modulo: Decimal.ROUND_DOWN,
});

export { Decimal };
```

Importar siempre desde acá: `import { Decimal } from '@/shared/kernel/decimal.config';`

---

## Schema Prisma

```prisma
model Invoice {
  id          String   @id @default(uuid())
  subtotal    Decimal  @db.Decimal(18, 2)  // 18 dígitos, 2 decimales
  taxAmount   Decimal  @db.Decimal(18, 2)
  total       Decimal  @db.Decimal(18, 2)
}

// Para precios unitarios con más precisión (productos a granel, etc.)
model Product {
  unitPrice   Decimal  @db.Decimal(18, 4)  // 4 decimales para precios
}
```

**Convención:** montos en `Decimal(18, 2)`, precios unitarios en `Decimal(18, 4)`, factores/tasas en `Decimal(10, 6)`.

---

## Redondeo bancario (Round Half to Even)

### Por qué bancario y no aritmético

| Cálculo      | Aritmético común | Bancario |
| ------------ | ---------------- | -------- |
| 1.225 → 1.22 | NO (1.23)        | SÍ       |
| 1.235 → 1.24 | SÍ               | SÍ       |
| 1.245 → 1.24 | NO (1.25)        | SÍ       |
| 1.255 → 1.26 | SÍ               | SÍ       |

El bancario alterna el redondeo del 0.5 al par más cercano. En el agregado de millones de operaciones, el error promedio tiende a cero. El aritmético común tiene un sesgo positivo permanente.

### Aplicación

```typescript
import { Decimal } from "@/shared/kernel/decimal.config";

// Cálculo de ITBIS 18%
const subtotal = new Decimal("1000.00");
const taxRate = new Decimal("0.18");
const tax = subtotal.times(taxRate).toDecimalPlaces(2); // usa ROUND_HALF_EVEN por config
```

### Solo redondear en fronteras

**Mal:**

```typescript
const a = price.times(qty).toDecimalPlaces(2);
const b = a.times(taxRate).toDecimalPlaces(2);
const c = b.plus(other).toDecimalPlaces(2);
// Acumulás errores de redondeo en cada paso
```

**Bien:**

```typescript
const total = price.times(qty).times(taxRate.plus(1)).plus(other);
return total.toDecimalPlaces(2); // un solo redondeo, al final
```

Redondear solo cuando: (a) vas a persistir, (b) vas a mostrar al usuario, (c) vas a enviar a un sistema externo.

---

## Value Object Money (versión completa)

Ya está en `01-clean-architecture.md`, pero recordá:

- Inmutable: cada operación devuelve nueva instancia.
- Auto-validante: rechaza NaN, Infinity, monedas inválidas.
- Type-safe: no podés sumar DOP con USD sin conversión explícita.

---

## Conversión de monedas

```typescript
// domain/services/currency-converter.service.ts
export class CurrencyConverter {
  constructor(private readonly rateRepo: IExchangeRateRepository) {}

  async convert(amount: Money, toCurrency: string, asOf: Date): Promise<Money> {
    if (amount.currency === toCurrency) return amount;

    const rate = await this.rateRepo.findRate(
      amount.currency,
      toCurrency,
      asOf,
    );
    if (!rate)
      throw new ExchangeRateNotFoundError(amount.currency, toCurrency, asOf);

    const converted = amount.toDecimal().times(rate.value);
    return Money.of(converted.toDecimalPlaces(2), toCurrency);
  }
}
```

**Importante:** la tasa de cambio se persiste con la transacción para auditoría histórica. No usás la tasa de hoy para revaluar movimientos del año pasado.

---

## Cálculo de ITBIS (República Dominicana)

```typescript
const ITBIS_RATES = {
  GENERAL: new Decimal("0.18"), // 18%
  REDUCED: new Decimal("0.16"), // 16% (productos específicos)
  ZERO: new Decimal("0"),
  EXEMPT: new Decimal("0"), // exento ≠ tasa cero a efectos formales
} as const;

// Cálculo desde subtotal (precio sin impuesto)
function calculateTaxFromSubtotal(
  subtotal: Money,
  rate: keyof typeof ITBIS_RATES,
): Money {
  return subtotal.multiply(ITBIS_RATES[rate]);
}

// Cálculo de desglose desde precio final (precio CON impuesto incluido)
function decomposeTaxFromTotal(total: Money, rate: keyof typeof ITBIS_RATES) {
  const rateDecimal = ITBIS_RATES[rate];
  const subtotal = total.toDecimal().dividedBy(rateDecimal.plus(1));
  const tax = total.toDecimal().minus(subtotal);
  return {
    subtotal: Money.of(subtotal.toDecimalPlaces(2), total.currency),
    tax: Money.of(tax.toDecimalPlaces(2), total.currency),
  };
}
```

---

## Test pattern para precisión

```typescript
import { Decimal } from "@/shared/kernel/decimal.config";

describe("Banker rounding", () => {
  const cases = [
    { input: "1.225", expected: "1.22" },
    { input: "1.235", expected: "1.24" },
    { input: "1.245", expected: "1.24" },
    { input: "1.255", expected: "1.26" },
    { input: "2.5", expected: "2" },
    { input: "3.5", expected: "4" },
    { input: "4.5", expected: "4" },
  ];

  it.each(cases)(
    "rounds $input → $expected (banker)",
    ({ input, expected }) => {
      const places = expected.includes(".") ? expected.split(".")[1].length : 0;
      expect(new Decimal(input).toDecimalPlaces(places).toString()).toBe(
        expected,
      );
    },
  );
});

describe("Money arithmetic precision", () => {
  it("does not accumulate float errors over 1000 additions", () => {
    let acc = Money.zero("DOP");
    for (let i = 0; i < 1000; i++) {
      acc = acc.add(Money.of("0.10", "DOP"));
    }
    expect(acc.toDecimal().toString()).toBe("100");
  });
});
```

---

## Display vs almacenamiento

```typescript
// Persistencia: usar toString() en Decimal (no toNumber!)
await prisma.invoice.create({
  data: { total: total.toDecimal().toString() },
});

// Display al usuario (formateo según locale)
new Intl.NumberFormat("es-DO", {
  style: "currency",
  currency: "DOP",
  minimumFractionDigits: 2,
}).format(total.toDecimal().toNumber()); // sólo aquí toNumber, sólo para display
```

Nunca uses `toNumber()` en cálculos. Solo en el último paso de presentación.

---

## Trampas comunes

| Trampa                            | Síntoma                            | Fix                                                      |
| --------------------------------- | ---------------------------------- | -------------------------------------------------------- |
| `JSON.stringify(decimal)` da `{}` | El cliente recibe vacío            | Serializer custom o `.toString()`                        |
| Suma de `Decimal + number`        | TypeScript permite, resultado raro | Tipar estrictamente, usar `Decimal.plus(new Decimal(x))` |
| Comparar con `===`                | Falso aunque sean iguales          | Usar `.equals()`                                         |
| Tasas como `0.18` literal         | Drift entre módulos                | Constantes centralizadas                                 |
| Redondear en cada paso            | Errores acumulados                 | Redondear solo en fronteras                              |
| `parseFloat()` desde formulario   | Perdés precisión antes de empezar  | Tratar input como string, instanciar Decimal directo     |
