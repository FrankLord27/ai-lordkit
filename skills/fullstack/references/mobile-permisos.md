# Permisos nativos

## Principio

El diálogo de permisos del sistema operativo se pide, se respeta y nunca se evade. Si el
usuario dice que no, la app toma el camino degradado. No hay excepciones "porque el
producto lo necesita".

Esto no es solo ética: iOS y Android rechazan apps que intentan capturar sin consentimiento,
y el usuario que descubre la trampa desinstala.

## Patrón de doble consentimiento

Cuando la captura es sensible, dos pasos explícitos:

1. **Aviso en la app.** Se explica qué se va a hacer, por qué, y qué pasa si dice que no.
2. **Permiso nativo del sistema.** Solo se dispara si aceptó el paso 1.

Si falla cualquiera de los dos, el flujo alternativo se ejecuta y **no se captura nada**.

```tsx
const [permiso, pedirPermiso] = useCameraPermissions();

const aceptar = async () => {
  await registrarConsentimiento(true);            // paso 1 confirmado

  const concedido = permiso?.granted ? permiso : await pedirPermiso();  // paso 2, nativo

  if (!concedido?.granted) {
    await rechazar();                             // sin foto, camino degradado
    return;
  }
  setPaso('camara');
};
```

Y el texto del aviso dice la verdad completa:

> Si continúas, tu teléfono te pedirá permiso para usar la cámara. Puedes negarte: en ese
> caso tu cuenta quedará bloqueada temporalmente y no se tomará ninguna foto.

## El backend también lo exige

La validación no puede vivir solo en el cliente. El endpoint rechaza cualquier envío que no
declare el consentimiento:

```ts
export const fotoVerificacionSchema = z.object({
  username: z.string().min(1),
  fotoBase64: z.string().min(1),
  permisoNativoConcedido: z.literal(true, {
    error: 'Solo se acepta la foto si el permiso nativo de cámara fue concedido',
  }),
});
```

`z.literal(true)` hace imposible enviar la foto sin la afirmación explícita.

## Textos de uso en app.json

iOS rechaza el build sin ellos; Android los muestra en la ficha de la app.

```json
{
  "expo": {
    "ios": {
      "infoPlist": {
        "NSCameraUsageDescription": "Se usa unicamente para verificar tu identidad cuando se detectan varios intentos fallidos, y solo si aceptas."
      }
    },
    "android": {
      "permissions": ["android.permission.CAMERA", "android.permission.ACCESS_NETWORK_STATE"]
    },
    "plugins": [
      ["expo-camera", { "cameraPermission": "Se usa unicamente para verificar tu identidad..." }]
    ]
  }
}
```

Explica el caso concreto, no "la app necesita la cámara".

## Notificaciones

Se piden cuando el usuario ya entiende para qué sirven, no en el primer arranque. Si las
niega, la app sigue funcionando sin recordatorios.

```ts
const actual = await Notifications.getPermissionsAsync();
if (!actual.granted && actual.canAskAgain) {
  await Notifications.requestPermissionsAsync();
}
```

`canAskAgain` evita insistir cuando el sistema ya bloqueó el diálogo: volver a pedirlo no
muestra nada y solo confunde.

## Almacenamiento de lo capturado

- Bucket **privado**, nunca con política pública de lectura.
- Se sirve con URL prefirmada de vida corta (5 minutos), a través del API.
- Cada consulta deja rastro: quién, cuándo, desde dónde.
- La clave del objeto nunca se expone al cliente.
