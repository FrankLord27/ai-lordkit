---
name: testing-actions
description: Estrategia de pruebas y pipelines de GitHub Actions ordenados por etapas, con íconos por categoría y un resumen final con resultados reales. Úsala SIEMPRE que se hable de tests, pruebas, cobertura, CI, CD, pipeline, GitHub Actions, workflows, jobs, steps, runners (de GitHub o propios / self-hosted), "la CI falla", "ordena los tests", "auditoría de pruebas", o al crear o tocar cualquier archivo de `.github/workflows/`. También al cerrar un bloque cuando hay que decidir qué pruebas faltan.
---

# Testing + GitHub Actions

Objetivo: un proyecto confiable con pruebas que importan y un pipeline que se lee de un vistazo, como una línea de producción con etapas e íconos, y que **nunca esconde un fallo**.

Para una auditoría completa del repositorio (fases 1 a 10, informe final obligatorio) sigue `references/prompt-maestro.md`. Para armar o reordenar un workflow, parte de `references/ci-template.yml`. Esta página es la versión corta que se aplica siempre.

## Reglas que no se negocian

1. **Primero mira el repo real**: stack, gestor de paquetes, scripts, workflows y pruebas que ya existen. No inventes comandos, rutas, variables ni servicios: verifica que existan antes de usarlos.
2. **No declares que algo pasó si no lo corriste.** Distingue siempre: ejecutado ✅ / fallido ❌ / omitido ⏭️ / bloqueado ⚠️. "Validé el YAML" no es "la CI pasó en la nube".
3. **Ningún paso que oculte fallos**: nada de `|| true`, `continue-on-error: true` en pruebas críticas ni comandos que siempre salen con 0. `if: always()` solo para subir reportes o limpiar, nunca para tapar el estado.
4. **Los íconos son decoración**: identifican la categoría, no cambian comandos, nombres de scripts ni criterios de aprobación.
5. **Nada de secretos** en logs, fixtures, reportes, capturas ni artefactos. No expongas secretos a PRs no confiables ni uses `pull_request_target` sin revisarlo.
6. **Permisos mínimos** (`permissions: contents: read` por defecto), `concurrency` para cancelar corridas viejas, acciones mantenidas y fijadas según la política del repo.
7. **Pruebas que importan**, no porcentaje: lógica de negocio, dinero, auth, permisos, validación, persistencia y errores primero. Cada bug corregido trae su prueba de regresión.

## Las capas (solo las que aplican al proyecto)

| Capa | Ícono | Cuándo |
|---|---|---|
| Unit | 🧪 | Funciones, reglas de negocio, cálculos, servicios, hooks |
| Integration | 🔗 | API + base de datos, auth con rutas protegidas, colas, almacenamiento |
| E2E | 🎭 | Recorridos reales de usuario en el navegador (solo si hay interfaz) |
| API | 🌐 | Códigos de estado, esquemas, permisos, errores que no filtran datos |
| Database | 🗄️ | Migraciones, restricciones, transacciones, N+1 |
| Auth | 🔐 | Sesiones, tokens, roles, acceso a recursos ajenos |
| Security | 🛡️ | Dependencias, secretos, inyección, CORS, rate limit |
| Performance | ⚡ | En workflow programado o manual, no en cada commit |
| Regression | 🔄 | Una prueba por cada bug importante corregido |
| Smoke | 💨 | Que la app arranque y responda después del build |
| Accessibility | ♿ | Flujos importantes de interfaces web o móviles |
| Compatibility | 🌍 | Solo la matriz que el proyecto soporta de verdad |

Explica por qué una capa no aplica en vez de crear jobs vacíos.

## El pipeline por etapas

Ordena los jobs con `needs:` para que el gráfico de Actions se lea de izquierda a derecha:

```
🧹 Lint & Format ─┐
                  ├─► 🧪 Unit Tests ─► 🏗️ Build ─┬─► 🎭 E2E Tests ─────┐
🔎 Type Check ────┘          │                   ├─► 💨 Smoke Tests ───┼─► 🏁 Pipeline Summary
                             └─► 🔗 Integration ─┴─► ♿ Accessibility ─┘
```

- Los checks rápidos van primero y en paralelo: si fallan, no se gasta tiempo en lo caro.
- `🏁 Pipeline Summary` corre siempre (`if: always()`), lee `needs.<job>.result` y escribe la tabla en `$GITHUB_STEP_SUMMARY`. Termina en error si algún job falló, así no tapa nada.
- Nombres de job y step con ícono + etiqueta corta en inglés (`🧪 Unit Tests`, `📦 Install dependencies`); los ids YAML quedan en kebab-case sin emoji.

### Íconos de steps y resultados

| Step | Ícono | | Resultado | Ícono |
|---|---|---|---|---|
| Checkout | 📥 | | Correcto | ✅ |
| Setup del runtime | ⚙️ | | Fallido | ❌ |
| Dependencias | 📦 | | Advertencia | ⚠️ |
| Formato | 📝 | | Omitido | ⏭️ |
| Lint | 🧹 | | En ejecución | ⏳ |
| Type check | 🔎 | | Cobertura | 📊 |
| Build | 🏗️ | | Resumen | 📋 |
| Contenedores | 🐳 | | | |
| Despliegue | 🚀 | | | |
| Reportes / artefactos | 📋 / 💾 | | | |

## Runner propio (self-hosted)

Sirve para no pagar minutos de GitHub en repos privados. Lo que cambia frente a las máquinas de GitHub:

- **La máquina no se borra entre corridas.** Todo contenedor que lance un step con `docker run` lleva `--name` fijo, se borra el anterior antes de arrancar (`docker rm -f <nombre> || true` solo en esa limpieza) y se apaga al final con `if: always()`.
- **Puertos compartidos.** Un runner hace un job a la vez: así los servicios (`services:` con puertos fijos, la API, la web) no chocan. Para correr jobs en paralelo hacen falta varios runners **y** puertos distintos por job.
- **Sin sudo.** Las librerías del sistema (por ejemplo, las de Chrome para Playwright) se instalan una vez en la máquina; en la CI, `playwright install chromium` sin `--with-deps`.
- **Seguridad.** El runner ejecuta el código de cada PR con acceso a Docker (equivale a root en esa máquina). Solo en repos privados, sin correr workflows de forks, con un usuario propio para el runner y, si se puede, en una máquina o VM que no sea la de producción. Mejor aún: runners efímeros (`--ephemeral`) dentro de un contenedor que se borra al terminar.
- **Etiqueta propia** (`runs-on: [self-hosted, <etiqueta>]`) para que otros repos no tomen el runner.

## Al terminar

Entrega una tabla solo con resultados reales:

| Validación | Estado | Resultado |
|---|---|---|
| 🧹 Lint | ✅ / ❌ / ⏭️ | Lo que pasó de verdad |
| 🔎 Type check | | |
| 🧪 Unit | | N pasaron / N fallaron |
| 🎭 E2E | | |
| 🏗️ Build | | |
| 📊 Cobertura | | Porcentaje real o "no se generó" |

Y aparte: lo que quedó bloqueado (y qué falta para desbloquearlo) y los próximos pasos priorizados. Lo implementado y lo recomendado, siempre separados.
