# Metro en monorepo pnpm

La configuración por defecto de Metro asume un proyecto suelto. En un monorepo con pnpm
falla de tres formas distintas, todas con mensajes que apuntan al lugar equivocado.

## metro.config.js obligatorio

```js
const { getDefaultConfig } = require('expo/metro-config');
const path = require('node:path');

const raizProyecto = __dirname;
const raizMonorepo = path.resolve(raizProyecto, '../..');

const config = getDefaultConfig(raizProyecto);

// Metro debe vigilar el monorepo entero para ver los paquetes compartidos.
config.watchFolders = [raizMonorepo];

config.resolver.nodeModulesPaths = [
  path.resolve(raizProyecto, 'node_modules'),
  path.resolve(raizMonorepo, 'node_modules'),
];

// pnpm enlaza con symlinks; sin esto Metro los sigue y pierde el contexto.
config.resolver.unstable_enableSymlinks = true;

module.exports = config;
```

## NO pongas `disableHierarchicalLookup: true`

Es el consejo que circula para monorepos con npm/yarn y **rompe pnpm**. Los paquetes de
pnpm resuelven sus dependencias a través de `node_modules` anidados dentro del store
`.pnpm/`, así que la búsqueda jerárquica tiene que seguir activa.

Síntoma cuando está mal:

```
Unable to resolve module @expo/log-box/src/LogBox from
  .../node_modules/@expo/metro-runtime/src/index.ts
```

El módulo existe, pero está bajo el store y Metro tiene prohibido subir a buscarlo.

## Metro tiene que arrancar desde la app, no desde la raíz

```
Unable to resolve module ./index from /ruta/al/monorepo/.
```

Significa que `expo start` corrió con el monorepo como directorio de trabajo. Arranca
siempre desde `apps/mobile`, o con `pnpm --filter mobile start`.

Con `watchFolders` apuntando al monorepo, la raíz del servidor de Metro sube un nivel y la
URL real del bundle pasa a ser `/apps/mobile/node_modules/expo-router/entry.bundle`. No la
adivines: léela del manifiesto.

```bash
curl -s -H "expo-platform: android" -H "Accept: multipart/mixed" http://localhost:8081/ \
  | grep -oE 'https?://[^"]*\.bundle[^"]*'
```

## El paquete compartido debe compilar a JavaScript

Metro no consume TypeScript desde `node_modules`. Si `packages/schemas` expone
`"main": "./src/index.ts"`, la app móvil no lo resuelve.

```json
{
  "name": "@proyecto/schemas",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": { ".": { "types": "./dist/index.d.ts", "default": "./dist/index.js" } },
  "scripts": { "build": "tsc", "dev": "tsc --watch --preserveWatchOutput" }
}
```

En `turbo.json`, que `dev` y `build` dependan de `^build` para que el paquete esté
compilado antes de que arranque Metro.

## Instalación de dependencias

Usa `npx expo install`, no `pnpm add`, para todo lo que tenga código nativo: resuelve la
versión correcta para el SDK instalado.

```bash
npx expo install expo-camera expo-secure-store   # alinea con el SDK
pnpm add zod                                      # JS puro, da igual
```

Si el proyecto tiene política de antigüedad mínima de paquetes (`minimumReleaseAge`), una
versión recién publicada será rechazada. Fija una versión madura explícita en vez de
desactivar la política.

## Verificar que la app compila de verdad

`expo start` levanta el servidor aunque el código no compile. La prueba real es pedir el
bundle:

```bash
curl -s -o /dev/null -w "%{http_code}" "$URL_DEL_MANIFIESTO"
# 200 = compila · 500 = error de resolución · 404 = ruta equivocada
```
