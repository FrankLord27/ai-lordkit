# Prompt maestro: auditoría y fortalecimiento de Testing + GitHub Actions

Copia y pega este prompt en Claude desde la raíz del repositorio. El objetivo es que Claude inspeccione el proyecto real, proponga una estrategia de pruebas apropiada y la implemente sin inventar comandos, herramientas ni necesidades que no correspondan al stack.

---

## Rol y objetivo

Actúa como un **Senior QA Engineer, Software Engineer y DevOps Engineer** con experiencia en automatización de pruebas, seguridad de aplicaciones y CI/CD con GitHub Actions.

Quiero que audites y refuerces integralmente la estrategia de pruebas de este repositorio. No busco aumentar artificialmente el porcentaje de cobertura ni agregar herramientas por moda. Busco un proyecto confiable, seguro, mantenible y preparado para producción, con pruebas relevantes y un pipeline que detecte errores temprano.

**Reglas de trabajo:**

1. Inspecciona primero el repositorio, su arquitectura, tecnologías, scripts, dependencias, workflows y pruebas existentes.
2. No asumas que el proyecto utiliza Node.js, React, TypeScript, una base de datos específica ni un framework de pruebas concreto: descubre el stack real.
3. No inventes scripts, rutas, variables de entorno, servicios, endpoints ni comandos. Verifica que existan antes de usarlos; si falta algo, implementa la configuración necesaria de manera coherente.
4. No reemplaces herramientas existentes que funcionan sin justificar la migración.
5. No hagas cambios destructivos ni elimines pruebas útiles sin explicar por qué.
6. Prioriza los riesgos reales del proyecto y divide el trabajo en fases pequeñas, verificables.
7. No declares que una prueba pasó si no la ejecutaste. Diferencia claramente entre pruebas ejecutadas, omitidas, bloqueadas y pendientes.
8. Si necesitas secretos, credenciales, servicios externos o acciones que no están disponibles en el entorno, documenta el bloqueo y proporciona una forma segura de validarlo.
9. No expongas secretos en logs, reportes, fixtures, capturas ni artefactos.
10. Mantén el estilo, la arquitectura y las convenciones existentes siempre que sean razonables.

## Fase 1. Auditoría inicial

Antes de modificar archivos:

- Identifica el lenguaje, framework, gestor de paquetes, versiones y estructura del proyecto.
- Examina los archivos de configuración, scripts, dependencias y lockfiles.
- Inspecciona todos los tests y workflows de `.github/workflows/`.
- Identifica las herramientas de lint, formato, type checking, build, testing, cobertura y análisis de seguridad que ya existen.
- Revisa la configuración de CI, cachés, matrices, artefactos, variables de entorno y servicios de prueba.
- Detecta pruebas frágiles, duplicadas, lentas, dependientes del orden, no deterministas o que solo comprueban detalles internos.
- Identifica componentes críticos de negocio, autenticación, autorización, validación, persistencia y manejo de errores.

Entrega primero un resumen de hallazgos priorizados por riesgo: **Crítico, Alto, Medio y Bajo**. Explica qué falta, por qué importa y cuál es la solución recomendada. Después continúa con la implementación; no te limites al informe, salvo que exista un bloqueo real o una operación destructiva que requiera confirmación.

## Fase 2. Estrategia de pruebas por capas

Implementa las categorías que tengan sentido para el stack y la arquitectura del proyecto. No agregues una categoría si no aporta valor; explica cualquier categoría que no aplique.

### 1. Unit testing — 🧪

Prueba unidades pequeñas de lógica de forma aislada, incluyendo, cuando existan:

- Funciones puras, utilidades y helpers.
- Reglas de negocio, cálculos y validaciones.
- Servicios, controladores y middleware.
- Hooks, componentes y módulos independientes.
- Transformaciones de datos y manejo de estados.

Incluye casos normales, límites, entradas inválidas, valores nulos o ausentes, colecciones vacías, errores y excepciones. Evita probar detalles internos irrelevantes y no uses mocks excesivos que hagan las pruebas poco representativas.

### 2. Integration testing — 🔗

Comprueba que los módulos colaboren correctamente:

- API con base de datos.
- Autenticación y autorización con rutas protegidas.
- Servicios y repositorios.
- Almacenamiento, caché, colas u otros servicios, si existen.
- Integraciones entre módulos y componentes.

Prefiere dependencias de prueba reales o servicios aislados cuando sea viable. Usa dobles de prueba cuando la dependencia externa, el costo, la seguridad o la reproducibilidad lo justifiquen.

### 3. End-to-end testing — 🎭

Prueba los recorridos importantes como lo haría una persona usuaria. Según las funciones reales de la aplicación, considera:

- Inicio y cierre de sesión.
- Creación, consulta, edición y eliminación de registros.
- Flujos principales del negocio.
- Validación de formularios y mensajes de error.
- Permisos y rutas protegidas.
- Persistencia de cambios y recuperación ante errores.

Elige una herramienta compatible con el stack existente. No agregues E2E de navegador si el proyecto no tiene una interfaz que lo justifique.

### 4. API testing — 🌐

Para cada endpoint existente y relevante, valida:

- Métodos HTTP y códigos de estado correctos.
- Esquemas de request y response.
- Entradas ausentes, inválidas, malformadas y límites de tamaño.
- Autenticación, autorización y permisos.
- Respuestas 400, 401, 403, 404, 409, 422 y 500 cuando correspondan al diseño de la API.
- Headers, CORS y rate limiting cuando estén configurados.
- Paginación, filtros, ordenamiento y comportamiento ante datos inexistentes.
- Que los errores no filtren secretos, trazas internas ni datos personales.

No fuerces códigos de estado que no correspondan al contrato real de la API; documenta y prueba el comportamiento previsto.

### 5. Database testing — 🗄️

Si el proyecto utiliza una base de datos, verifica:

- Migraciones y esquema.
- Relaciones, restricciones, índices y claves foráneas.
- Restricciones de unicidad.
- Transacciones y rollback.
- Persistencia y lectura de datos.
- Eliminación lógica, si existe.
- Integridad ante fallos y concurrencia, donde sea relevante.
- Consultas críticas y posibles problemas N+1.

Usa una base de datos de prueba aislada y datos reproducibles. Nunca ejecutes pruebas destructivas contra producción.

### 6. Authentication and authorization testing — 🔐

Comprueba, cuando corresponda:

- Inicio y cierre de sesión.
- Tokens, refresh tokens, cookies y sesiones.
- Expiración, revocación e invalidación de credenciales.
- Roles y permisos.
- Usuarios bloqueados, deshabilitados o eliminados.
- Acceso a recursos ajenos y escalamiento de privilegios.
- Protección de rutas y operaciones sensibles.
- Intentos repetidos y limitación de solicitudes, si están implementados.

No asumas que utilizar JWT u otro mecanismo garantiza seguridad: prueba el comportamiento real de la aplicación.

### 7. Security testing — 🛡️

Evalúa los riesgos aplicables al stack y a las funciones del proyecto:

- Inyección SQL/NoSQL y command injection.
- XSS y CSRF, según el tipo de aplicación y sus defensas.
- Path traversal y acceso no autorizado a archivos.
- Mass assignment y asignación insegura de propiedades.
- Validación y sanitización de entradas.
- Configuración de CORS y headers de seguridad.
- Gestión de secretos, sesiones y tokens.
- Control de acceso y exposición de información sensible.
- Dependencias vulnerables y configuración insegura.
- Protección contra abuso y rate limiting, si aplica.

Utiliza herramientas de análisis estático, auditoría de dependencias y escaneo de secretos compatibles con el proyecto. No ejecutes pruebas intrusivas contra sistemas externos sin autorización. No imprimas secretos en los resultados.

### 8. Performance and concurrency testing — ⚡

Cuando sea relevante, identifica:

- Endpoints y consultas lentas.
- Operaciones repetidas e ineficiencias.
- Uso excesivo de CPU o memoria.
- Problemas de concurrencia y condiciones de carrera.
- Cuellos de botella.
- Límites de carga y tiempos de respuesta.

Define umbrales realistas a partir de requisitos o mediciones de referencia. No establezcas límites arbitrarios que produzcan falsos positivos. Mantén las pruebas de carga intensivas fuera del pipeline de cada commit si pueden ser costosas o inestables; ejecútalas en un workflow programado o manual cuando convenga.

### 9. Regression testing — 🔄

Cada bug importante corregido debe incluir una prueba que reproduzca el fallo y compruebe que no reaparezca. Prioriza las regresiones de seguridad, datos, permisos y lógica de negocio.

### 10. Smoke testing — 💨

Implementa pruebas breves que comprueben que la aplicación se puede preparar e iniciar y que las funciones esenciales responden correctamente. Úsalas tras el build o despliegue de prueba cuando corresponda.

### 11. Accessibility testing — ♿

Si hay una interfaz web o móvil, añade pruebas automatizadas de accesibilidad para los flujos importantes. Evalúa etiquetas, navegación por teclado, estructura semántica, nombres accesibles y errores de formularios. Las herramientas automáticas no sustituyen una evaluación manual cuando sea necesaria.

### 12. Cross-browser / compatibility testing — 🌍

Si la aplicación requiere compatibilidad entre navegadores, dispositivos, sistemas operativos o versiones de runtime, define una matriz proporcionada a los usuarios y al soporte real del proyecto. No multipliques combinaciones innecesarias.

### 13. Snapshot testing

Úsalo solo cuando sea apropiado, por ejemplo, para detectar cambios inesperados en salidas estructuradas o componentes visuales. Evita snapshots enormes, frágiles o que se actualicen sin revisión. No los uses como sustituto de aserciones claras sobre el comportamiento.

## Fase 3. Calidad de las pruebas

Todas las pruebas deben aspirar a ser:

- Deterministas y reproducibles.
- Aisladas y con limpieza adecuada.
- Legibles y fáciles de mantener.
- Independientes del orden de ejecución.
- Razonablemente rápidas.
- Explícitas en sus aserciones y mensajes de fallo.
- Libres de dependencias externas innecesarias.
- Seguras con datos y credenciales.
- Ejecutables localmente y en CI con instrucciones documentadas.

Centraliza fixtures y datos comunes cuando aporte valor. Usa factories o builders si ayudan a crear datos válidos y claros. Evita estados globales compartidos, esperas fijas innecesarias y pruebas que dependan de servicios públicos inestables.

Si el diseño del código impide probar correctamente una regla importante, propone una refactorización acotada para mejorar la separación de responsabilidades o la inyección de dependencias. No hagas una reescritura amplia sin necesidad.

## Fase 4. Cobertura inteligente — 📊

Configura la generación y publicación de cobertura con las herramientas compatibles con el stack.

- Prioriza la lógica de negocio, seguridad, autenticación, autorización, validaciones, API y persistencia crítica.
- Mide cobertura de líneas y, si la herramienta lo permite, de ramas y funciones.
- Identifica módulos críticos con cobertura baja.
- Establece umbrales realistas basados en el estado inicial y mejóralos gradualmente.
- Evita perseguir el 100 % sin justificación.
- No escribas pruebas vacías ni aserciones débiles solo para aumentar la cifra.
- No excluyas archivos de forma engañosa para mejorar el porcentaje.
- Publica el resumen de cobertura y conserva reportes como artefactos cuando sea útil.

## Fase 5. GitHub Actions y CI/CD

Audita y optimiza los workflows de `.github/workflows/`. Adapta los nombres y comandos a la estructura real del proyecto.

Incluye, cuando corresponda:

1. Checkout del repositorio.
2. Configuración de la versión correcta del runtime.
3. Instalación reproducible de dependencias mediante el lockfile.
4. Validación de formato.
5. Lint.
6. Type checking.
7. Unit tests.
8. Integration tests.
9. E2E tests.
10. Build.
11. Cobertura y publicación de reportes.
12. Análisis de seguridad y dependencias.
13. Subida de artefactos útiles.
14. Resumen final del pipeline.

### Buenas prácticas de CI

- Utiliza versiones de actions compatibles y mantenidas; revisa sus versiones actuales antes de actualizarlas.
- Fija versiones de actions según la política de seguridad del repositorio; considera SHA completos cuando el nivel de seguridad lo requiera.
- Configura permisos mínimos con `permissions`.
- Usa `concurrency` para cancelar ejecuciones obsoletas cuando sea apropiado.
- Configura caché de dependencias solo si es compatible y segura.
- Paraleliza jobs independientes para reducir el tiempo total.
- Usa matrices únicamente cuando aporten cobertura de runtimes, plataformas o navegadores que el proyecto soporte.
- Aplica `fail-fast` según el propósito de la matriz.
- No permitas que las pruebas críticas fallen silenciosamente.
- Separa los checks rápidos de los tests E2E o de carga más costosos si mejora la velocidad sin reducir la protección.
- Usa servicios de prueba aislados para bases de datos u otras dependencias, cuando sea necesario.
- Sube reportes incluso después de un fallo cuando sea posible, usando condiciones adecuadas como `if: always()` sin ocultar el estado fallido.
- Define claramente qué checks son obligatorios antes de integrar cambios.
- No expongas secretos a workflows de pull requests no confiables.
- Revisa con cuidado los permisos de eventos como `pull_request_target`.
- Mantén Dependabot y CodeQL si son apropiados para el repositorio, y configura el escaneo de secretos disponible en GitHub según las capacidades y el plan de la organización.
- No agregues workflows duplicados ni acciones que no puedan ejecutarse con la configuración real.

No cambies los comandos de CI a variantes que siempre terminen correctamente. Evita patrones que oculten fallos, como ignorar indiscriminadamente códigos de salida.

## Fase 6. Sistema visual de iconos para GitHub Actions

Quiero una nomenclatura visual consistente en los nombres de workflows, jobs, steps y reportes. Los emojis sirven para identificar categorías rápidamente; **no son indicadores oficiales de GitHub ni reemplazan el estado real de ejecución**.

Usa esta convención cuando sea compatible con las convenciones existentes:

| Categoría | Icono | Etiqueta sugerida |
|---|---|---|
| Preparación del entorno | ⚙️ | Setup |
| Checkout del repositorio | 📥 | Checkout |
| Dependencias | 📦 | Dependencies |
| Formato | 📝 | Format Check |
| Linter | 🧹 | Lint |
| Type checking | 🔎 | Type Check |
| Unit testing | 🧪 | Unit Tests |
| Integration testing | 🔗 | Integration Tests |
| End-to-end testing | 🎭 | E2E Tests |
| API testing | 🌐 | API Tests |
| Base de datos | 🗄️ | Database Tests |
| Autenticación y autorización | 🔐 | Auth Tests |
| Seguridad | 🛡️ | Security Audit |
| Rendimiento | ⚡ | Performance Tests |
| Regresión | 🔄 | Regression Tests |
| Smoke tests | 💨 | Smoke Tests |
| Build | 🏗️ | Build |
| Cobertura | 📊 | Coverage |
| Accesibilidad | ♿ | Accessibility Tests |
| Compatibilidad | 🌍 | Compatibility Tests |
| Contenedores | 🐳 | Container Tests |
| Despliegue | 🚀 | Deployment |
| Reportes | 📋 | Test Reports |
| Artefactos | 💾 | Artifacts |
| Resumen final | 🏁 | Pipeline Summary |

Ejemplo ilustrativo de nombres de jobs:

```yaml
jobs:
  lint:
    name: "🧹 Lint"
  typecheck:
    name: "🔎 Type Check"
  unit-tests:
    name: "🧪 Unit Tests"
  integration-tests:
    name: "🔗 Integration Tests"
  e2e-tests:
    name: "🎭 E2E Tests"
  security:
    name: "🛡️ Security Audit"
  build:
    name: "🏗️ Build"
  coverage:
    name: "📊 Coverage Report"
```

Este fragmento es solo un ejemplo. Adáptalo a los jobs reales, usa identificadores YAML válidos y no crees jobs vacíos ni comandos ficticios.

### Iconos en los steps

Usa nombres breves, descriptivos y consistentes, por ejemplo:

- `📥 Checkout repository`
- `⚙️ Setup runtime`
- `📦 Install dependencies`
- `📝 Check formatting`
- `🧹 Run lint`
- `🔎 Run type checking`
- `🧪 Run unit tests`
- `🔗 Run integration tests`
- `🎭 Run E2E tests`
- `📊 Generate coverage report`
- `📋 Publish test summary`

Verifica cada comando contra los scripts y las herramientas del repositorio antes de incorporarlo.

### Iconos en los resultados

Usa esta convención en reportes Markdown y resúmenes:

- ✅ Correcto: el proceso terminó con éxito.
- ❌ Fallido: el proceso falló.
- ⚠️ Advertencia: hay un problema que requiere atención.
- ⏭️ Omitido: no se ejecutó, con una razón válida.
- ⏳ En ejecución: sigue ejecutándose, si el contexto permite mostrar ese estado.
- 📊 Cobertura.
- 📋 Resumen de resultados.

No escribas manualmente un estado de éxito si las pruebas fallaron o no se ejecutaron. El resumen debe reflejar los resultados reales de la ejecución.

### Resumen de GitHub Actions

Cuando aporte valor, publica un resumen legible mediante `$GITHUB_STEP_SUMMARY` que incluya:

1. Estado general del pipeline.
2. Estado de cada categoría de pruebas.
3. Cantidad de pruebas aprobadas, fallidas y omitidas, si las herramientas proporcionan esos datos.
4. Porcentaje de cobertura, si se genera.
5. Enlaces a reportes y artefactos disponibles.
6. Identificación de jobs fallidos o bloqueados.

No inventes cifras ni enlaces. Si un reporte no se generó, indícalo. Mantén los reportes técnicos originales además del resumen visual.

### Compatibilidad visual

- Los emojis son decoración; no deben afectar los códigos de salida ni los criterios de aprobación.
- No cambies los nombres de comandos, archivos, scripts o herramientas por motivos visuales.
- Evita llenar los logs de emojis innecesarios.
- Mantén la accesibilidad y legibilidad.
- Valida la sintaxis YAML y el comportamiento de los workflows después de los cambios.

## Fase 7. Mocking, fixtures y test data

- Reduce los mocks innecesarios.
- Utiliza mocks para dependencias externas cuando sea importante aislar el comportamiento, el costo o la reproducibilidad.
- Comprueba que los mocks reflejen el contrato real.
- Centraliza fixtures compartidas cuando sea útil.
- Usa factories o builders si reducen duplicación sin ocultar la estructura de los datos.
- Limpia los datos creados durante las pruebas.
- Evita datos reales, secretos o información personal en fixtures y reportes.
- Asegura que cada test sea repetible y no dependa de datos residuales.

## Fase 8. Documentación y ejecución local

Actualiza la documentación necesaria para explicar:

- Herramientas de testing utilizadas y por qué.
- Requisitos previos y configuración local.
- Cómo ejecutar todas las pruebas y cada categoría por separado.
- Cómo generar y consultar cobertura.
- Cómo ejecutar E2E y preparar los servicios requeridos.
- Variables de entorno de prueba, con ejemplos seguros y sin secretos reales.
- Cómo interpretar reportes y fallos frecuentes.
- Qué pruebas se ejecutan en cada workflow de GitHub Actions.

Incluye solo comandos que existan y que hayas verificado o configurado correctamente.

## Fase 9. Ejecución y validación

Después de implementar los cambios:

1. Instala o verifica las dependencias de manera reproducible.
2. Ejecuta las validaciones relevantes en el orden adecuado.
3. Ejecuta las pruebas nuevas y existentes.
4. Ejecuta lint, formato, type checking y build cuando estén disponibles.
5. Genera y revisa la cobertura.
6. Valida la sintaxis de workflows YAML con las herramientas disponibles.
7. Comprueba que los fallos se propaguen correctamente y no estén ocultos.
8. Revisa el diff para detectar cambios accidentales, secretos o archivos generados que no deban versionarse.
9. Si un test no puede ejecutarse por falta de credenciales, servicios o herramientas, informa el motivo exacto y el paso necesario para desbloquearlo.
10. No afirmes que GitHub Actions pasó en la nube si solo validaste localmente el YAML o ejecutaste los comandos en tu entorno.

## Fase 10. Informe final obligatorio

Al terminar, presenta un informe con estas secciones:

### 1. Estado inicial
- Arquitectura y stack detectados.
- Herramientas y pruebas existentes.
- Principales riesgos encontrados.

### 2. Cambios realizados
- Archivos creados o modificados.
- Pruebas añadidas o corregidas.
- Workflows actualizados.
- Iconos y nomenclatura visual aplicados.
- Refactorizaciones justificadas.

### 3. Resultados de ejecución

Utiliza una tabla como esta y complétala únicamente con resultados reales:

| Validación | Estado | Resultado / observaciones |
|---|---|---|
| Formato | ✅ / ❌ / ⏭️ | Resultado real |
| Lint | ✅ / ❌ / ⏭️ | Resultado real |
| Type checking | ✅ / ❌ / ⏭️ | Resultado real |
| Unit tests | ✅ / ❌ / ⏭️ | Resultado real |
| Integration tests | ✅ / ❌ / ⏭️ | Resultado real |
| E2E tests | ✅ / ❌ / ⏭️ | Resultado real |
| Seguridad | ✅ / ❌ / ⏭️ | Resultado real |
| Build | ✅ / ❌ / ⏭️ | Resultado real |
| Cobertura | ✅ / ❌ / ⏭️ | Porcentaje real o no disponible |

Adapta la tabla a las categorías que apliquen. No marques como aprobada una categoría que no se ejecutó.

### 4. Cobertura y riesgos pendientes
- Porcentaje medido y tipo de cobertura, si existe.
- Componentes críticos que siguen poco cubiertos.
- Vulnerabilidades o riesgos que no se pudieron resolver.
- Pruebas bloqueadas y por qué.

### 5. Instrucciones de uso
- Comandos locales comprobados.
- Workflows y cuándo se ejecutan.
- Ubicación de los reportes y artefactos.

### 6. Próximos pasos
Enumera solo acciones necesarias y priorizadas. Distingue claramente entre lo implementado y lo recomendado para una fase posterior.

---

## Criterio de éxito

El trabajo estará completo cuando el proyecto tenga una estrategia de pruebas adecuada a su arquitectura, los tests críticos sean reproducibles, los fallos no se oculten, la cobertura sea medible, GitHub Actions ejecute validaciones relevantes, los nombres visuales sean consistentes y la documentación permita a otra persona ejecutar y entender las pruebas.

**Empieza auditando el repositorio real. Después implementa las mejoras priorizadas, valida los cambios y entrega el informe final. No te limites a proponer una lista genérica de pruebas.**
