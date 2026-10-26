# Tests E2E con Playwright

---

## Configuración

```bash
pnpm add -D @playwright/test
npx playwright install   # Instala los browsers
```

```typescript
// apps/web/playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.ts",

  // Cada test tiene timeout de 30 segundos
  timeout: 30_000,

  // Reintentos en CI — localmente ninguno para ver el fallo inmediato
  retries: process.env.CI ? 2 : 0,

  // Paralelo en CI, secuencial local para debugging más fácil
  workers: process.env.CI ? 4 : 1,

  // Guardar evidencia de fallos
  reporter: [["html", { outputFolder: "playwright-report" }], ["list"]],

  use: {
    baseURL: "http://localhost:3000",
    // Screenshot y video solo en fallos
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    trace: "on-first-retry",
  },

  // Levantar la app antes de correr los tests
  webServer: [
    {
      command: "pnpm dev",
      url: "http://localhost:3000",
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
    {
      command: "pnpm --filter api dev",
      url: "http://localhost:3001/api/v1/health",
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
  ],

  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    // Agregar mobile solo si la app necesita ser responsive
    // { name: 'mobile', use: { ...devices['iPhone 13'] } },
  ],
});
```

---

## Page Object Model — estructura de los tests E2E

El Page Object encapsula los selectores y acciones de una página.
Los tests no conocen los detalles del DOM — solo llaman métodos del Page Object.

```typescript
// e2e/pages/login.page.ts
import { Page, expect } from "@playwright/test";

export class LoginPage {
  constructor(private page: Page) {}

  // Locators — definidos una vez, usados en muchos tests
  private emailInput = () => this.page.getByLabel(/email/i);
  private passwordInput = () => this.page.getByLabel(/contraseña/i);
  private submitButton = () =>
    this.page.getByRole("button", { name: /iniciar sesión/i });
  private errorMessage = () => this.page.getByRole("alert");

  async goto() {
    await this.page.goto("/login");
    await expect(this.submitButton()).toBeVisible();
  }

  async login(email: string, password: string) {
    await this.emailInput().fill(email);
    await this.passwordInput().fill(password);
    await this.submitButton().click();
  }

  async expectErrorMessage(message: string) {
    await expect(this.errorMessage()).toContainText(message);
  }

  async expectRedirectToDashboard() {
    await this.page.waitForURL("/dashboard");
    await expect(this.page).toHaveURL("/dashboard");
  }
}
```

```typescript
// e2e/pages/rent-search.page.ts
import { Page, expect } from "@playwright/test";

export class RentSearchPage {
  constructor(private page: Page) {}

  private locationSelect = () => this.page.getByLabel(/ubicación/i);
  private pickupDateInput = () => this.page.getByLabel(/fecha de recogida/i);
  private returnDateInput = () => this.page.getByLabel(/fecha de devolución/i);
  private searchButton = () =>
    this.page.getByRole("button", { name: /buscar/i });
  private carCards = () => this.page.getByTestId("car-card");
  private loadingSpinner = () => this.page.getByRole("status");

  async goto() {
    await this.page.goto("/rent");
  }

  async searchCars(locationId: string, pickup: string, returnDate: string) {
    await this.locationSelect().selectOption(locationId);
    await this.pickupDateInput().fill(pickup);
    await this.returnDateInput().fill(returnDate);
    await this.searchButton().click();
    // Esperar a que desaparezca el loading
    await this.loadingSpinner().waitFor({ state: "hidden" });
  }

  async expectCarsCount(count: number) {
    await expect(this.carCards()).toHaveCount(count);
  }

  async selectFirstCar() {
    await this.carCards()
      .first()
      .getByRole("button", { name: /seleccionar/i })
      .click();
  }
}
```

---

## Fixture de autenticación — no repetir login en cada test

```typescript
// e2e/fixtures/auth.fixture.ts
import { test as base, Page } from "@playwright/test";
import { LoginPage } from "../pages/login.page";

// Credenciales del usuario de test — creado en la DB de test
const TEST_USER = {
  email: "e2e-test@example.com",
  password: "TestPassword123!",
};

// Fixture que provee una página ya autenticada
export const test = base.extend<{ authenticatedPage: Page }>({
  authenticatedPage: async ({ page }, use) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(TEST_USER.email, TEST_USER.password);
    await loginPage.expectRedirectToDashboard();

    // Usar la página autenticada en el test
    await use(page);

    // Cleanup: logout después del test
    await page.goto("/logout");
  },
});

export { expect } from "@playwright/test";
```

---

## Los flujos E2E que siempre hay que testear

Son los flujos más críticos del producto. Si estos fallan, el negocio para.

```typescript
// e2e/auth.e2e.ts
import { test, expect } from "@playwright/test";
import { LoginPage } from "./pages/login.page";
import { RegisterPage } from "./pages/register.page";

test.describe("Autenticación", () => {
  test("usuario puede registrarse con datos válidos", async ({ page }) => {
    const registerPage = new RegisterPage(page);
    await registerPage.goto();

    await registerPage.register({
      name: "Usuario Test",
      email: `test-${Date.now()}@example.com`, // Email único por ejecución
      password: "SecurePassword123!",
    });

    // Después del registro exitoso: redirige al dashboard
    await expect(page).toHaveURL("/dashboard");
    await expect(page.getByText("Usuario Test")).toBeVisible();
  });

  test("usuario puede iniciar sesión con credenciales correctas", async ({
    page,
  }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login("e2e-test@example.com", "TestPassword123!");
    await loginPage.expectRedirectToDashboard();
  });

  test("muestra error con credenciales incorrectas", async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login("e2e-test@example.com", "WrongPassword");
    await loginPage.expectErrorMessage("Credenciales incorrectas");
    // Sigue en /login
    await expect(page).toHaveURL("/login");
  });

  test("redirige a login cuando accede a ruta protegida sin sesión", async ({
    page,
  }) => {
    await page.goto("/dashboard");
    await expect(page).toHaveURL("/login");
  });
});
```

```typescript
// e2e/rent-flow.e2e.ts — flujo principal del dominio core
import { test, expect } from "./fixtures/auth.fixture";
import { RentSearchPage } from "./pages/rent-search.page";
import { BookingPage } from "./pages/booking.page";

test.describe("Flujo de reserva de autos", () => {
  // Estos tests usan el fixture authenticatedPage — ya están logueados
  test("usuario puede buscar y reservar un auto", async ({
    authenticatedPage,
  }) => {
    const searchPage = new RentSearchPage(authenticatedPage);
    const bookingPage = new BookingPage(authenticatedPage);

    // Paso 1: Buscar autos
    await searchPage.goto();
    await searchPage.searchCars("loc-sto-domingo", "2025-06-01", "2025-06-05");
    await searchPage.expectCarsCount(3); // Hay 3 autos en la DB de test

    // Paso 2: Seleccionar el primero
    await searchPage.selectFirstCar();
    await expect(authenticatedPage).toHaveURL(/\/rent\/cars\/.+/);

    // Paso 3: Confirmar reserva
    await bookingPage.confirmBooking({ driverAge: 25, insurance: "basic" });

    // Paso 4: Verificar confirmación
    await expect(authenticatedPage).toHaveURL("/bookings/confirmation");
    await expect(
      authenticatedPage.getByText(/reserva confirmada/i),
    ).toBeVisible();
    await expect(
      authenticatedPage.getByText(/número de reserva/i),
    ).toBeVisible();
  });

  test("muestra mensaje cuando no hay autos disponibles", async ({
    authenticatedPage,
  }) => {
    const searchPage = new RentSearchPage(authenticatedPage);

    await searchPage.goto();
    // Fechas sin disponibilidad en la DB de test
    await searchPage.searchCars("loc-sto-domingo", "2099-01-01", "2099-01-05");

    await expect(
      authenticatedPage.getByText(/no hay autos disponibles/i),
    ).toBeVisible();
  });
});
```

---

## Setup y limpieza de datos para E2E

```typescript
// e2e/setup/global-setup.ts
// Se ejecuta UNA VEZ antes de todos los tests E2E
import { chromium } from "@playwright/test";

async function globalSetup() {
  // Crear datos de test en la DB
  // Opción 1: llamar a un endpoint de la API de test
  const response = await fetch("http://localhost:3001/api/v1/test/seed", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-test-secret": process.env.TEST_SECRET,
    },
  });

  if (!response.ok) throw new Error("Falló el seed de datos de test");

  // Opción 2: llamar directamente a Prisma desde el setup
  // (solo si los tests corren en el mismo proceso que el seed)
}

export default globalSetup;
```

```typescript
// En playwright.config.ts
export default defineConfig({
  globalSetup: "./e2e/setup/global-setup.ts",
  globalTeardown: "./e2e/setup/global-teardown.ts", // Limpia al final
  // ...
});
```

---

## Correr Playwright en CI

```yaml
# .github/workflows/e2e.yml
name: E2E Tests

on: [push, pull_request]

jobs:
  e2e:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: testuser
          POSTGRES_PASSWORD: testpass
          POSTGRES_DB: myapp_test
        ports: ["5432:5432"]
      redis:
        image: redis:7
        ports: ["6379:6379"]

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "20" }

      - name: Install pnpm
        run: corepack enable pnpm

      - name: Install dependencies
        run: pnpm install

      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium

      - name: Run migrations
        run: pnpm --filter api prisma migrate deploy
        env:
          DATABASE_URL: postgresql://testuser:testpass@localhost:5432/myapp_test

      - name: Run E2E tests
        run: pnpm --filter web test:e2e
        env:
          DATABASE_URL: postgresql://testuser:testpass@localhost:5432/myapp_test
          REDIS_HOST: localhost

      # Subir reporte de Playwright como artefacto en fallos
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: apps/web/playwright-report/
          retention-days: 7
```

---

## Qué NO testear con E2E

Los E2E son lentos y costosos. Solo cubrir lo que no se puede testear de otra forma.

```
✅ E2E para:                    ❌ No usar E2E para:
Flujos de múltiples páginas     Validaciones de un formulario
Auth completa end-to-end        Lógica de negocio en services
Flujo de pago                   Estilos y layout
Flujo de reserva completo       Mensajes de error específicos
Navegación y redirecciones      Variaciones de datos
```

La regla: si se puede testear con RTL o Jest, va ahí. E2E solo para el camino feliz de los flujos principales y los casos de error más críticos.
