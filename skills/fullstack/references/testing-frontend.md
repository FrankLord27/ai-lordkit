# Testing en Next.js / React — React Testing Library

---

## Configuración inicial

```bash
pnpm add -D @testing-library/react @testing-library/user-event @testing-library/jest-dom
pnpm add -D jest jest-environment-jsdom @types/jest ts-jest
pnpm add -D msw   # Mock Service Worker — mockear fetch sin tocar el código
```

```typescript
// apps/web/jest.config.ts
import type { Config } from "jest";
import nextJest from "next/jest.js";

const createJestConfig = nextJest({ dir: "./" });

const config: Config = {
  coverageProvider: "v8",
  testEnvironment: "jsdom",
  setupFilesAfterFramework: ["<rootDir>/jest.setup.ts"],
};

export default createJestConfig(config);
```

```typescript
// apps/web/jest.setup.ts
import "@testing-library/jest-dom"; // Matchers: toBeInTheDocument, toHaveValue, etc.
```

---

## Principios de React Testing Library

**Regla central:** Testear lo que el usuario ve y hace, no los detalles de implementación.

```typescript
// ❌ Mal — testea implementación interna
expect(component.state.isLoading).toBe(true);
expect(wrapper.find("Button").prop("onClick")).toBeDefined();

// ✅ Bien — testea lo que el usuario experimenta
expect(screen.getByRole("button", { name: /guardar/i })).toBeDisabled();
expect(screen.getByText("Cargando...")).toBeInTheDocument();
```

### Jerarquía de queries — usar en este orden

```typescript
// 1. Por accesibilidad (preferido — si funciona así, es accesible)
screen.getByRole("button", { name: /enviar/i });
screen.getByRole("textbox", { name: /email/i });
screen.getByLabelText("Contraseña");

// 2. Por texto visible
screen.getByText("Iniciar sesión");
screen.getByPlaceholderText("tu@email.com");

// 3. Por test id (solo cuando no hay otra opción)
screen.getByTestId("submit-button");

// Variantes: getBy lanza error si no existe, queryBy retorna null, findBy espera async
```

---

## Testear componentes

```typescript
// features/auth/components/LoginForm/LoginForm.spec.tsx
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { LoginForm } from './LoginForm';

// Mock de la mutación de TanStack Query
const mockMutateAsync = jest.fn();
jest.mock('../api/use-login', () => ({
  useLogin: () => ({
    mutateAsync: mockMutateAsync,
    isPending: false,
  }),
}));

describe('LoginForm', () => {
  const user = userEvent.setup(); // Simula interacciones reales del usuario

  beforeEach(() => {
    mockMutateAsync.mockClear();
  });

  it('renderiza los campos de email y contraseña', () => {
    render(<LoginForm />);

    expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/contraseña/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /iniciar sesión/i })).toBeInTheDocument();
  });

  it('muestra error de validación cuando el email es inválido', async () => {
    render(<LoginForm />);

    await user.type(screen.getByLabelText(/email/i), 'no-es-email');
    await user.click(screen.getByRole('button', { name: /iniciar sesión/i }));

    expect(await screen.findByText(/email inválido/i)).toBeInTheDocument();
  });

  it('llama a mutateAsync con los datos del formulario al enviar', async () => {
    render(<LoginForm />);

    await user.type(screen.getByLabelText(/email/i), 'test@example.com');
    await user.type(screen.getByLabelText(/contraseña/i), 'Password123!');
    await user.click(screen.getByRole('button', { name: /iniciar sesión/i }));

    await waitFor(() => {
      expect(mockMutateAsync).toHaveBeenCalledWith({
        email: 'test@example.com',
        password: 'Password123!',
      });
    });
  });

  it('deshabilita el botón mientras se procesa el submit', () => {
    // Simular estado de carga
    jest.mock('../api/use-login', () => ({
      useLogin: () => ({ mutateAsync: jest.fn(), isPending: true }),
    }));

    render(<LoginForm />);
    expect(screen.getByRole('button', { name: /iniciar sesión/i })).toBeDisabled();
  });

  it('muestra error del servidor cuando el login falla', async () => {
    mockMutateAsync.mockRejectedValue(new Error('Credenciales incorrectas'));

    render(<LoginForm />);
    await user.type(screen.getByLabelText(/email/i), 'test@example.com');
    await user.type(screen.getByLabelText(/contraseña/i), 'WrongPassword1!');
    await user.click(screen.getByRole('button', { name: /iniciar sesión/i }));

    expect(await screen.findByText(/credenciales incorrectas/i)).toBeInTheDocument();
  });
});
```

---

## Testear hooks de TanStack Query con MSW

MSW intercepta las llamadas fetch reales — no mockeas el código, mockeas la red.

```typescript
// test/setup/msw-server.ts — servidor MSW compartido
import { setupServer } from "msw/node";
import { http, HttpResponse } from "msw";

export const server = setupServer();

// Setup global en jest.setup.ts
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

```typescript
// features/rent/api/use-search-cars.spec.tsx
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { http, HttpResponse } from 'msw';
import { server } from '../../../../test/setup/msw-server';
import { useSearchCars } from './use-search-cars';

// Wrapper con QueryClient para cada test — cliente fresco, sin cache contaminado
const createWrapper = () => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } }, // Sin reintentos en tests
  });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
};

describe('useSearchCars', () => {
  const filters = {
    locationId: 'loc-123',
    pickupDate: '2025-03-20T10:00:00Z',
    returnDate: '2025-03-25T10:00:00Z',
  };

  it('retorna autos cuando la búsqueda es exitosa', async () => {
    // Definir qué retorna la API para este test
    server.use(
      http.post('http://localhost:3001/api/v1/rent/cars/search', () =>
        HttpResponse.json({
          data: {
            cars: [{ id: '1', model: 'Corolla', dailyRate: 80 }],
            totalCount: 1,
          },
        }),
      ),
    );

    const { result } = renderHook(() => useSearchCars(filters), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data?.cars).toHaveLength(1);
    expect(result.current.data?.cars[0].model).toBe('Corolla');
  });

  it('maneja el error de la API correctamente', async () => {
    server.use(
      http.post('http://localhost:3001/api/v1/rent/cars/search', () =>
        HttpResponse.json(
          { statusCode: 500, message: 'Error interno' },
          { status: 500 },
        ),
      ),
    );

    const { result } = renderHook(() => useSearchCars(filters), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(result.current.error).toBeDefined();
  });

  it('no ejecuta la query cuando locationId está vacío', () => {
    const { result } = renderHook(
      () => useSearchCars({ ...filters, locationId: '' }),
      { wrapper: createWrapper() },
    );

    // enabled: !!filters.locationId — no debe ejecutarse
    expect(result.current.fetchStatus).toBe('idle');
    expect(result.current.data).toBeUndefined();
  });
});
```

---

## Testear stores de Zustand

```typescript
// features/booking/stores/use-booking-store.spec.ts
import { act, renderHook } from "@testing-library/react";
import { useBookingStore } from "./use-booking-store";

describe("useBookingStore", () => {
  // Resetear el store antes de cada test
  beforeEach(() => {
    useBookingStore.getState().reset();
  });

  it("inicia con step 1 y sin item seleccionado", () => {
    const { result } = renderHook(() => useBookingStore());

    expect(result.current.step).toBe(1);
    expect(result.current.selectedItemId).toBeNull();
  });

  it("avanza al paso correcto al llamar setStep", () => {
    const { result } = renderHook(() => useBookingStore());

    act(() => result.current.setStep(3));

    expect(result.current.step).toBe(3);
  });

  it("selecciona un item y avanza al paso 2", () => {
    const { result } = renderHook(() => useBookingStore());

    act(() => result.current.selectItem("car-uuid-123"));

    expect(result.current.selectedItemId).toBe("car-uuid-123");
  });

  it("resetea todo el estado al llamar reset", () => {
    const { result } = renderHook(() => useBookingStore());

    act(() => {
      result.current.setStep(3);
      result.current.selectItem("car-uuid-123");
    });

    act(() => result.current.reset());

    expect(result.current.step).toBe(1);
    expect(result.current.selectedItemId).toBeNull();
  });
});
```

---

## Testear componentes con contexto — wrapper pattern

```typescript
// test/utils/render-with-providers.tsx
// Un wrapper reutilizable que provee todos los contextos necesarios
import { render, RenderOptions } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const createTestQueryClient = () =>
  new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false },
    },
  });

interface RenderWithProvidersOptions extends RenderOptions {
  queryClient?: QueryClient;
}

export function renderWithProviders(
  ui: React.ReactElement,
  { queryClient = createTestQueryClient(), ...options }: RenderWithProvidersOptions = {},
) {
  function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    );
  }

  return { queryClient, ...render(ui, { wrapper: Wrapper, ...options }) };
}

// Uso
import { renderWithProviders } from '../../../../test/utils/render-with-providers';

it('muestra el listado de autos', async () => {
  renderWithProviders(<CarsList />);
  // ...
});
```

---

## Buenas prácticas de testing en React

- **`userEvent` sobre `fireEvent`** — `userEvent` simula comportamiento real del browser (focus, blur, typing). `fireEvent` dispara eventos sintéticos simples. Usar `userEvent.setup()` antes de los tests.
- **`findBy` para elementos async** — cuando un elemento aparece después de una operación async, usar `findByText` / `findByRole` que esperan automáticamente.
- **No testear estilos** — testear comportamiento, no CSS. Si el botón está deshabilitado, testear `toBeDisabled()`, no el color.
- **Cada test es independiente** — sin estado compartido entre tests. El `QueryClient` fresco en cada test evita cache contaminado.
- **MSW sobre jest.mock del fetch** — MSW intercepta a nivel de red, no modifica el código. Los tests se comportan más cercano a producción.
- **`data-testid` como último recurso** — si no puedes seleccionar por role, label o texto visible, agrega `data-testid`. Pero siempre intentar primero con queries semánticas.
