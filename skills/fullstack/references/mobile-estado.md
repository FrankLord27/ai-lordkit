# Estado y almacenamiento en móvil

## Qué va dónde

| Dato                        | Dónde                        | Por qué                                  |
| --------------------------- | ---------------------------- | ----------------------------------------- |
| Tokens de sesión            | `expo-secure-store`          | Keychain / Keystore, cifrado por el SO    |
| Cola de envíos pendientes   | Zustand + AsyncStorage       | Debe sobrevivir al cierre de la app       |
| Catálogos del servidor      | TanStack Query               | Caché con invalidación, no estado propio  |
| Estado de un formulario     | `useState` local             | Muere con la pantalla                     |
| Preferencias de UI          | Zustand + AsyncStorage       | No sensible                               |

## Tokens: SecureStore, nunca AsyncStorage

AsyncStorage guarda en claro. En un dispositivo con root o un backup sin cifrar, cualquiera
lee los tokens.

```ts
import * as SecureStore from 'expo-secure-store';

await SecureStore.setItemAsync('acceso', token);
const token = await SecureStore.getItemAsync('acceso');
await SecureStore.deleteItemAsync('acceso');
```

SecureStore es asíncrono y no sirve como backend de `persist` de Zustand. El patrón que
funciona: store en memoria con hidratación explícita al arrancar.

```ts
export const useSesion = create<EstadoSesion>((set, get) => ({
  accessToken: null,
  cargando: true,

  restaurar: async () => {
    const token = await SecureStore.getItemAsync('acceso');
    set({ accessToken: token, cargando: false });
  },
  // ...
}));
```

El flag `cargando` evita que el layout raíz redirija al login antes de leer el disco.

## Cola: Zustand con persist

```ts
export const useCola = create<EstadoCola>()(
  persist(
    (set, get) => ({ /* ... */ }),
    {
      name: 'cola-envios',
      storage: createJSONStorage(() => AsyncStorage),
      // No persistas banderas efímeras: si la app muere a mitad de un envío,
      // `sincronizando: true` quedaría grabado y bloquearía la cola para siempre.
      partialize: (estado) => ({
        pendientes: estado.pendientes,
        ultimaSincronizacion: estado.ultimaSincronizacion,
      }),
    },
  ),
);
```

`partialize` no es un detalle: sin él, un cierre inesperado deja la app convencida de que
hay una sincronización en curso que nunca terminará.

## Leer el store fuera de React

En servicios y listeners no hay hooks:

```ts
const token = useSesion.getState().accessToken;
useCola.getState().sincronizar();
```

## Selectores

```ts
const pendientes = useCola((e) => e.pendientes.length);   // re-render solo si cambia
const { pendientes, sincronizando } = useCola();          // re-render con cualquier cambio
```

En listas largas y pantallas con temporizadores, la diferencia se nota.

## Estilos: tokens compartidos

Tailwind no aplica en React Native. Centraliza los valores para que web y móvil no se
desincronicen visualmente:

```ts
export const colores = {
  fondo: '#f8fafc',
  superficie: '#ffffff',
  marca: '#2563eb',
  alerta: '#dc2626',
  texto: '#0f172a',
  textoSuave: '#64748b',
};
```

`StyleSheet.create` para el resto. Nada de estilos en línea en componentes que se
renderizan en listas.
