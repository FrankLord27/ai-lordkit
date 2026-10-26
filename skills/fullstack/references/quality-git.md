# Git y Estrategia de Ramas

---

## Convenciones de commits — Conventional Commits

```
tipo(scope): descripción corta en imperativo presente

[body opcional — explica el QUÉ y el POR QUÉ, no el CÓMO]

[footer opcional — referencias a issues, breaking changes]
```

### Ejemplos reales

```bash
# Feature nueva
feat(booking): add date extension for active bookings

# Bug fix con referencia a issue
fix(auth): refresh token not invalidated on logout

Closes #142

# Breaking change
feat(api)!: change booking response to use pagination wrapper

BREAKING CHANGE: GET /bookings now returns { items, pagination }
instead of an array directly. Update all consumers.

# Chore sin scope
chore: update prisma to v5.10.0

# Refactor con contexto
refactor(search): extract filter parsing to dedicated service

The SearchService was growing too large. Filter parsing logic
is now in FilterParserService which is easier to test in isolation.

# Fix simple
fix(cars): correct daily rate calculation for weekend pricing

# Docs
docs(readme): add Docker setup instructions for Windows

# Test
test(booking): add integration tests for date overlap validation

# CI
ci: add E2E tests to deployment pipeline
```

### Reglas del mensaje de commit

```
✅ Imperativo presente: "add feature" no "added feature" ni "adds feature"
✅ Primera letra minúscula en la descripción
✅ Sin punto al final de la descripción
✅ Máximo 72 caracteres en la primera línea
✅ Línea en blanco entre descripción y body
✅ Body explica el QUÉ y POR QUÉ — no el CÓMO (el código explica el cómo)

❌ "WIP" como commit — usar draft PRs
❌ "fix bug" — sin contexto de qué bug
❌ "changes" — vago
❌ Commitear todo junto en un solo commit gigante
```

---

## Estrategia de ramas — GitHub Flow simplificado

```
main ────────────────────────────────────────── producción
  │
  ├── feat/booking-date-extension ── merge → main ── deploy
  ├── fix/auth-refresh-token ──────── merge → main ── deploy
  └── chore/update-dependencies ───── merge → main ── deploy
```

**Solo dos tipos de ramas permanentes:** `main` y `staging` (si aplica).
Todas las demás son temporales y se eliminan al hacer merge.

### Nomenclatura de ramas

```bash
# Formato: tipo/descripción-en-kebab-case
feat/booking-date-extension
feat/user-profile-settings
fix/auth-refresh-token-invalidation
fix/car-search-empty-results
refactor/search-service-filter-parsing
chore/update-dependencies-march
docs/api-swagger-improvements
test/booking-integration-tests
hotfix/payment-calculation-error   # Solo para fixes urgentes en producción
```

### Ciclo de vida de una rama

```bash
# 1. Crear rama desde main actualizado
git checkout main
git pull origin main
git checkout -b feat/booking-date-extension

# 2. Desarrollar con commits pequeños y frecuentes
git add apps/api/src/modules/booking/
git commit -m "feat(booking): add date extension validation"
git commit -m "feat(booking): add extension endpoint and DTO"
git commit -m "test(booking): add tests for date extension"

# 3. Mantener la rama actualizada con main (rebase, no merge)
git fetch origin
git rebase origin/main
# Si hay conflictos: resolverlos, luego git rebase --continue

# 4. Push y abrir PR
git push origin feat/booking-date-extension
# Abrir PR en GitHub

# 5. Después de aprobación: merge squash en GitHub
# La rama se elimina automáticamente (configurar en GitHub)
```

---

## Rebase vs Merge — cuándo usar cada uno

```
Rebase — para mantener la rama actualizada con main
  Resultado: historial lineal, commits de la rama encima de main
  Usar: siempre al actualizar una rama de feature

  git rebase origin/main

Merge — para integrar una rama a main
  Resultado: merge commit que une las dos ramas
  Usar: al hacer merge de un PR (o squash merge en GitHub)

  git merge feat/mi-feature --no-ff

Squash merge — un solo commit en main por PR
  Resultado: el PR completo se convierte en un commit en main
  Usar: el método preferido para PRs — historial de main queda limpio
  Configurar en GitHub: Settings → General → Allow squash merging ✅
```

---

## Comandos de Git que salvan la vida

```bash
# Ver qué cambió y cuándo — muy útil para debugging
git log --oneline --graph --all

# Ver quién modificó cada línea de un archivo
git blame apps/api/src/modules/booking/booking.service.ts

# Buscar en qué commit se introdujo un string
git log -S "función que busco" --all --oneline

# Deshacer el último commit SIN perder los cambios
git reset --soft HEAD~1

# Deshacer el último commit Y los cambios (cuidado)
git reset --hard HEAD~1

# Guardar cambios temporalmente sin commitear
git stash push -m "trabajo en progreso booking extension"
git stash list
git stash pop

# Aplicar un commit específico de otra rama
git cherry-pick abc1234

# Ver diferencia de un archivo entre dos commits
git diff HEAD~3 HEAD -- apps/api/src/modules/booking/booking.service.ts

# Buscar el commit que introdujo un bug — bisect binario
git bisect start
git bisect bad HEAD           # El bug existe aquí
git bisect good v1.2.0        # El bug no existía aquí
# Git navega automáticamente, tú marcas cada punto como good/bad
git bisect reset              # Al terminar

# Limpiar ramas locales que ya no existen en remoto
git fetch --prune
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -d
```

---

## Protección de ramas — configuración en GitHub

```
GitHub → Settings → Branches → Branch protection rules → main

✅ Require a pull request before merging
   └── Required approvals: 1 (o más para proyectos con equipo)
✅ Require status checks to pass before merging
   └── Checks requeridos: lint-typecheck, test-unit, test-integration, build
✅ Require branches to be up to date before merging
✅ Require conversation resolution before merging
✅ Do not allow bypassing the above settings
✅ Restrict who can push to matching branches (solo maintainers)

Opciones recomendadas para el repo:
✅ Allow squash merging    (el método preferido)
❌ Allow merge commits     (crea historial ruidoso)
✅ Allow rebase merging    (para casos especiales)
✅ Automatically delete head branches (limpieza automática)
```

---

## .gitignore para el monorepo

```gitignore
# Dependencias
node_modules/
.pnpm-store/

# Builds
dist/
build/
.next/
.turbo/

# Entorno — NUNCA commitear
.env
.env.local
.env.*.local
# Sí commitear:
# .env.example ✅

# Logs
*.log
npm-debug.log*
pnpm-debug.log*

# IDEs
.vscode/*
!.vscode/settings.json   # Sí compartir settings y extensions
!.vscode/extensions.json
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Testing
coverage/
playwright-report/
test-results/

# Prisma
# Los migrations SÍ van al repo
# Los archivos generados NO
apps/api/src/generated/
```
