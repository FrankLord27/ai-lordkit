# Cola offline

El caso real: alguien captura doce registros en una zona sin señal, camina, recupera
cobertura y cierra la app. Si el envío depende de que abra una pestaña y pulse un botón,
esos doce registros se pierden.

## Reglas

1. **Clave de idempotencia generada en el dispositivo.** Un UUID por registro, creado al
   capturar, no al enviar.
2. **El backend responde 200 con el registro original** si ya recibió ese UUID. No 409, no
   500: la app no tiene que distinguir "ya estaba" de "se creó".
3. **Un 4xx saca el elemento del ciclo de reintentos.** Es un dato inválido; reintentar no
   lo arregla.
4. **Backoff exponencial con techo** para errores de red y 5xx.
5. **Límite de intentos.** Tras N fallos se marca y se le muestra al usuario.
6. **La cola persiste en disco** (AsyncStorage), no en memoria.

## Estructura del elemento

```ts
export interface RegistroPendiente {
  clientUuid: string;       // clave de idempotencia
  // ... todos los campos del dominio, no un subconjunto
  capturedAt: string;       // hora del dispositivo, distinta de createdAt del servidor

  intentos: number;
  ultimoError?: string;
  rechazadoDefinitivamente?: boolean;
}
```

`capturedAt` importa: sin él, doce registros de una zona sin señal aparecen todos con la
hora de la sincronización.

## Clasificación del error

```ts
export class ErrorApi extends Error {
  constructor(message: string, readonly status: number) { super(message); }

  /** Un 4xx no se arregla reintentando: el dato es inválido. */
  get esPermanente(): boolean {
    return this.status >= 400 && this.status < 500;
  }
}
```

```ts
try {
  await enviar(registro);
  // sale de la cola
} catch (error) {
  if (error instanceof ErrorApi && error.esPermanente) {
    marcarRechazado(registro, error.message);   // el usuario decide qué hacer
    continue;
  }
  reencolarConBackoff(registro);
}
```

## Disparo automático

```ts
import NetInfo from '@react-native-community/netinfo';

NetInfo.addEventListener((estado) => {
  if (estado.isConnected && estado.isInternetReachable !== false) {
    void sincronizar();
  }
});
```

`isInternetReachable !== false` en vez de `=== true`: al arrancar vale `null` y esperar a
`true` retrasa el primer intento sin motivo.

## Backoff

```ts
export function esperaDeReintento(intentos: number): number {
  return Math.min(2 ** intentos * 1000, 5 * 60 * 1000);
}
```

## Recordatorio local, no push remoto

Para avisar de registros sin enviar basta una notificación **local**: cero infraestructura,
cero token de dispositivo, cero servicio externo.

Reserva el push remoto para cuando el servidor deba iniciar la conversación. Si el aviso lo
puede decidir el dispositivo, no montes infraestructura de push.

### ⚠️ expo-notifications revienta en Expo Go (SDK 53+)

Desde el SDK 53 el módulo **lanza al importarse**, no al usarse — y lo hace incluso si solo
querías notificaciones locales. Un `import` estático tumba en cascada toda pantalla que lo
tenga en su cadena de imports:

```
ERROR  expo-notifications: Android Push notifications ... was removed from Expo Go
WARN   Route "./_layout.tsx" is missing the required default export
ERROR  [TypeError: Cannot read property 'ErrorBoundary' of undefined]
```

Esos tres mensajes son **el mismo fallo**: el módulo no termina de evaluarse, así que su
`export default` nunca existe. Se ven decenas de errores donde hay una sola causa.

Cárgalo de forma diferida y opcional:

```ts
import Constants, { AppOwnership } from 'expo-constants';

const EN_EXPO_GO = Constants.appOwnership === AppOwnership.Expo;

async function cargar() {
  if (EN_EXPO_GO) return null;
  try {
    return await import('expo-notifications');   // dinámico, nunca estático
  } catch {
    return null;                                  // la garantía real
  }
}
```

`executionEnvironment === 'storeClient'` **no** sirve para distinguir: agrupa Expo Go con
los development builds, y en un dev build las notificaciones sí funcionan. `appOwnership`
está deprecado pero es lo único que separa ambos casos.

Y díselo al usuario en pantalla: que el recordatorio no llegue en silencio parece un bug.

```tsx
{!hayNotificaciones() && pendientes.length > 0 && (
  <Aviso texto="Estás en Expo Go: los recordatorios no funcionan aquí. El envío automático sí." />
)}
```

**Regla general:** cualquier módulo nativo con soporte parcial en Expo Go se importa de
forma diferida y detrás de un `try/catch`. Verifícalo pidiendo el bundle y mirando el log
de Metro con el dispositivo conectado — el bundler compila sin quejarse aunque el módulo
vaya a explotar en el teléfono.

## Lecturas: TanStack Query con caché larga

```ts
useQuery({
  queryKey: ['colegios'],
  queryFn: obtenerColegios,
  staleTime: 24 * 60 * 60 * 1000,
  gcTime: 7 * 24 * 60 * 60 * 1000,   // sigue sirviendo sin señal
});
```

Escrituras en Zustand persistido, lecturas en Query. No mezcles: Query no está pensado para
una bandeja de salida que debe sobrevivir al cierre de la app.
