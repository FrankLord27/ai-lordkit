# Assets y distribución

## Íconos

| Archivo                        | Uso                                            |
| ------------------------------ | ---------------------------------------------- |
| `icon.png`                     | 1024×1024, base de iOS                         |
| `android-icon-foreground.png`  | Capa frontal del ícono adaptativo              |
| `android-icon-background.png`  | Capa de fondo                                  |
| `android-icon-monochrome.png`  | Íconos temáticos de Android 13+, un solo tono  |
| `splash-icon.png`              | Pantalla de arranque                           |
| `favicon.png`                  | Web                                            |

El ícono adaptativo de Android recorta según la máscara del fabricante. Deja la marca dentro
de la zona segura: el 66% central del lienzo.

**Revisa los exportados antes de publicar.** Es habitual que las guías de construcción del
programa de diseño (círculos concéntricos, ejes punteados, punto de registro) queden
horneadas en el PNG, o que el splash salga sin el logo compuesto. Ábrelos uno por uno:
el error se descubre en el arranque en frío, delante del usuario.

## app.json

```json
{
  "expo": {
    "name": "Nombre visible",
    "slug": "identificador-del-proyecto",
    "version": "1.0.0",
    "orientation": "portrait",
    "scheme": "miapp",
    "newArchEnabled": true,
    "ios": { "bundleIdentifier": "do.empresa.miapp", "supportsTablet": true },
    "android": { "package": "do.empresa.miapp" },
    "plugins": ["expo-router", "expo-secure-store"],
    "experiments": { "typedRoutes": true }
  }
}
```

`plugins` es para **config plugins**, no una lista de dependencias. Meter ahí un paquete que
no lo es (por ejemplo `expo-status-bar`) rompe el prebuild.

## Variables de entorno

Solo las que empiezan con `EXPO_PUBLIC_` llegan al bundle. **Van dentro del binario**: nunca
pongas ahí un secreto.

```ts
const API = process.env.EXPO_PUBLIC_API_URL
  ?? `http://${Constants.expoConfig?.hostUri?.split(':')[0]}:7100/api/v1`;
```

El fallback por `hostUri` hace que la app funcione en un teléfono físico sin editar código
al cambiar de red.

## Distribución del APK

Tres rutas reales para Android:

| Opción                    | Costo         | Cuándo                                              |
| ------------------------- | ------------- | --------------------------------------------------- |
| Auto-hospedado en tu VPS  | $0            | Control total, sin terceros. Sirve el APK y un QR.  |
| EAS Build + link de Expo  | free / ~$99mo | Rápido de montar, dependes de su cola de build.     |
| Play Store, canal interno | US$25 único   | Requiere revisión y correo de cada usuario.          |

Para reparto interno, auto-hospedar suele ganar: el usuario escanea un QR, descarga e
instala. Android pedirá permitir "fuentes desconocidas" una vez; adviértelo en la pantalla
de descarga en vez de dejar que parezca un error.

**iOS no tiene equivalente.** Distribuir un `.ipa` fuera de la App Store exige TestFlight o
cuenta Enterprise (US$99/año). Si el proyecto asume Android, déjalo escrito.

## Modelo de versiones

```prisma
model AppRelease {
  version      String   // semántico
  buildNumber  Int
  objectKey    String   // en el almacenamiento de objetos
  fileSize     Int
  sha256       String   // permite verificar la descarga
  isCurrent    Boolean  @default(false)
  @@unique([version, buildNumber])
}
```

Solo una versión vigente a la vez: al publicar, marca las demás como `isCurrent: false`
dentro de la misma transacción.

## Build

```bash
npx expo install --check                       # alinea versiones con el SDK
eas build -p android --profile preview         # APK instalable
eas build -p android --profile production      # AAB para Play Store
```

`--profile preview` produce APK; el perfil de producción genera AAB, que **no se instala
directamente**. Si vas a repartir el archivo a mano, necesitas el APK.

## Antes de publicar

- [ ] Los íconos no traen guías de construcción.
- [ ] El splash muestra el logo, no un lienzo vacío.
- [ ] `bundleIdentifier` y `package` definidos y estables.
- [ ] Ningún secreto en variables `EXPO_PUBLIC_`.
- [ ] La URL del API apunta al entorno correcto.
- [ ] Textos de uso de permisos redactados por caso concreto.
- [ ] Probado en un dispositivo físico, no solo en emulador.
