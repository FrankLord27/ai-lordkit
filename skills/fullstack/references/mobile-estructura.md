# Estructura y navegación con Expo Router

Expo Router es routing por archivos, igual que el App Router de Next.js. Si entiendes uno,
entiendes el otro: los paréntesis agrupan sin aparecer en la URL, `_layout` envuelve.

## Carpetas

```
apps/mobile/
├── app/                        # rutas — nada más vive aquí
│   ├── _layout.tsx             # raíz: providers y guardia de sesión
│   ├── (auth)/                 # grupo público
│   │   ├── login.tsx
│   │   ├── cambiar-password.tsx
│   │   └── verificacion.tsx
│   └── (app)/                  # grupo privado
│       ├── _layout.tsx         # tabs
│       ├── inicio.tsx
│       ├── pendientes.tsx
│       └── perfil.tsx
├── src/
│   ├── componentes/            # UI reutilizable
│   ├── lib/                    # api, sincronización, utilidades
│   └── store/                  # stores de Zustand
├── assets/
├── app.json
├── metro.config.js
└── package.json                # main: "expo-router/entry"
```

`app/` solo contiene rutas. Todo lo demás va a `src/`, o Expo Router intentará convertirlo
en pantalla.

## Guardia de sesión en el layout raíz

```tsx
export default function LayoutRaiz() {
  const { accessToken, debeCambiarPassword, cargando, restaurar } = useSesion();
  const segmentos = useSegments();
  const router = useRouter();

  useEffect(() => { void restaurar(); }, [restaurar]);

  useEffect(() => {
    if (cargando) return;                       // no navegues antes de hidratar

    const enZonaPrivada = segmentos[0] === '(app)';

    if (!accessToken && enZonaPrivada) {
      router.replace('/(auth)/login');
    } else if (accessToken && debeCambiarPassword) {
      router.replace('/(auth)/cambiar-password');
    } else if (accessToken && !debeCambiarPassword && !enZonaPrivada) {
      router.replace('/(app)/inicio');
    }
  }, [accessToken, debeCambiarPassword, cargando, segmentos, router]);

  if (cargando) return <Cargando />;            // evita el parpadeo de login

  return <Stack screenOptions={{ headerShown: false }} />;
}
```

El `if (cargando) return` no es cosmético: sin él, la app muestra el login medio segundo
antes de restaurar la sesión, en cada arranque.

## Tabs con indicador

```tsx
<Tabs.Screen
  name="pendientes"
  options={{
    title: 'Pendientes de envío',
    tabBarIcon: ({ color, size }) => <CloudUpload color={color} size={size} />,
    tabBarBadge: pendientes > 0 ? pendientes : undefined,
  }}
/>
```

El contador en la pestaña avisa sin obligar a entrar. En una app de campo eso es la
diferencia entre notar que faltan envíos y no notarlo.

## Rutas tipadas

```json
{ "expo": { "experiments": { "typedRoutes": true } } }
```

Convierte un `router.push('/pantala-mal-escrita')` en error de compilación.

## Formularios

React Hook Form funciona en React Native, pero para formularios de 4-6 campos con
validación por Zod compartido, `useState` + una función `validar()` es menos ceremonia. Usa
RHF cuando haya arrays dinámicos, pasos o dependencias entre campos.

Siempre:

- `keyboardShouldPersistTaps="handled"` en el `ScrollView`, o el primer toque solo cierra
  el teclado y el usuario cree que el botón no responde.
- `KeyboardAvoidingView` con `behavior="padding"` en iOS.
- `keyboardType="number-pad"` en campos numéricos.
- `accessibilityLabel` y `accessibilityRole` en controles propios.
- Altura mínima de 48 px en los botones: se usan de pie y con prisa.
