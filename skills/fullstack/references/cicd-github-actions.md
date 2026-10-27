# GitHub Actions — CI y CD

---

## Pipeline de CI — corre en cada PR

> Acciones fijadas por SHA con la versión en comentario (un tag se puede mover, un SHA no), todas en runtime Node 24. Runner con versión fija (`ubuntu-24.04`) para que la migración de `ubuntu-latest` no te cambie el sistema sin avisar. `pnpm/action-setup` va sin `version`: toma la de `packageManager` en `package.json` (si pones las dos y no coinciden, falla). Para mantenerlas al día, agrega el `dependabot.yml` del final.

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main, staging]
  push:
    branches: [main]

# Cancelar runs anteriores del mismo PR si llega uno nuevo
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # ─── 1. CALIDAD DE CÓDIGO ────────────────────────────────────────
  quality:
    name: Lint & Typecheck
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - uses: pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0

      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: "24"
          cache: "pnpm"

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Lint
        run: pnpm lint

      - name: Typecheck
        run: pnpm typecheck

  # ─── 2. TESTS UNITARIOS ─────────────────────────────────────────
  test-unit:
    name: Unit Tests
    runs-on: ubuntu-24.04
    needs: quality # Solo corre si lint y typecheck pasan
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: "24"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile
      - name: Unit tests
        run: pnpm test:unit

      - name: Upload coverage
        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        if: always()
        with:
          name: coverage-report
          path: apps/api/coverage/
          retention-days: 7

  # ─── 3. TESTS DE INTEGRACIÓN ────────────────────────────────────
  test-integration:
    name: Integration Tests
    runs-on: ubuntu-24.04
    needs: quality

    # Servicios de infraestructura para los tests
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: testuser
          POSTGRES_PASSWORD: testpass
          POSTGRES_DB: myapp_test
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7-alpine
        ports: ["6379:6379"]
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 5

    env:
      DATABASE_URL: postgresql://testuser:testpass@localhost:5432/myapp_test
      REDIS_HOST: localhost
      REDIS_PORT: 6379
      JWT_SECRET: test-secret-must-be-at-least-32-characters-long
      NODE_ENV: test

    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: "24"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile

      - name: Run migrations on test DB
        run: pnpm --filter api prisma migrate deploy

      - name: Integration tests
        run: pnpm --filter api test:integration

  # ─── 4. BUILD ───────────────────────────────────────────────────
  build:
    name: Build
    runs-on: ubuntu-24.04
    needs: [test-unit, test-integration]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: "24"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile

      - name: Build all apps
        run: pnpm build

      - name: Audit dependencies
        run: pnpm audit --audit-level=high
```

---

## Pipeline de CD — deploy automático

```yaml
# .github/workflows/cd.yml
name: CD

on:
  push:
    branches: [main] # Solo deploy en merge a main

jobs:
  # ─── 1. BUILD Y PUSH DE IMÁGENES DOCKER ────────────────────────
  build-images:
    name: Build & Push Docker Images
    runs-on: ubuntu-24.04
    outputs:
      image-tag: ${{ steps.meta.outputs.version }}

    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Docker meta — generar tags de la imagen
        id: meta
        uses: docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302 # v6.2.0
        with:
          images: |
            ghcr.io/${{ github.repository }}/api
            ghcr.io/${{ github.repository }}/web
          tags: |
            type=sha,prefix=,suffix=,format=short   # Tag con el SHA del commit
            type=raw,value=latest                    # Tag latest (solo para referencia)

      # Buildx con driver docker-container: el driver por defecto no exporta cache type=gha
      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1

      - name: Login al GitHub Container Registry
        uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build y push imagen del API
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          file: apps/api/Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository }}/api:${{ steps.meta.outputs.version }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Build y push imagen del Web
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          file: apps/web/Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository }}/web:${{ steps.meta.outputs.version }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ─── 2. DEPLOY A STAGING ────────────────────────────────────────
  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-24.04
    needs: build-images
    environment: staging # Ambiente de GitHub — permite aprobar/rechazar

    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Deploy a staging vía SSH
        uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
        with:
          host: ${{ secrets.STAGING_HOST }}
          username: ${{ secrets.STAGING_USER }}
          key: ${{ secrets.STAGING_SSH_KEY }}
          script: |
            cd /apps/staging
            export IMAGE_TAG=${{ needs.build-images.outputs.image-tag }}

            # Pull nuevas imágenes
            docker pull ghcr.io/${{ github.repository }}/api:$IMAGE_TAG
            docker pull ghcr.io/${{ github.repository }}/web:$IMAGE_TAG

            # Aplicar migraciones ANTES de reemplazar el contenedor
            docker run --rm \
              --env-file /apps/staging/.env \
              ghcr.io/${{ github.repository }}/api:$IMAGE_TAG \
              npx prisma migrate deploy

            # Actualizar con zero-downtime
            IMAGE_TAG=$IMAGE_TAG docker-compose up -d --no-deps api web

            # Verificar que el health check pasa
            sleep 5
            curl --fail http://localhost:3001/api/v1/health || exit 1

            echo "Deploy a staging completado: $IMAGE_TAG"

  # ─── 3. TESTS E2E EN STAGING ────────────────────────────────────
  e2e-staging:
    name: E2E Tests on Staging
    runs-on: ubuntu-24.04
    needs: deploy-staging

    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: "24"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile
      - run: npx playwright install --with-deps chromium

      - name: E2E tests contra staging
        run: pnpm --filter web test:e2e
        env:
          BASE_URL: ${{ secrets.STAGING_URL }}

      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        if: failure()
        with:
          name: playwright-report-staging
          path: apps/web/playwright-report/
          retention-days: 7

  # ─── 4. DEPLOY A PRODUCCIÓN ─────────────────────────────────────
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-24.04
    needs: e2e-staging
    environment:
      name: production
      url: https://tudominio.com
    # En GitHub: configurar "Required reviewers" en el ambiente production
    # Esto pausa el pipeline hasta que alguien apruebe el deploy

    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Deploy a producción vía SSH
        uses: appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5
        with:
          host: ${{ secrets.PROD_HOST }}
          username: ${{ secrets.PROD_USER }}
          key: ${{ secrets.PROD_SSH_KEY }}
          script: |
            cd /apps/production
            export IMAGE_TAG=${{ needs.build-images.outputs.image-tag }}
            export PREV_TAG=$(docker inspect api --format='{{.Config.Image}}' | cut -d: -f2)

            # Guardar tag anterior para rollback
            echo $PREV_TAG > /apps/production/.prev-tag

            docker pull ghcr.io/${{ github.repository }}/api:$IMAGE_TAG
            docker pull ghcr.io/${{ github.repository }}/web:$IMAGE_TAG

            # Migraciones primero
            docker run --rm \
              --env-file /apps/production/.env \
              ghcr.io/${{ github.repository }}/api:$IMAGE_TAG \
              npx prisma migrate deploy

            IMAGE_TAG=$IMAGE_TAG docker-compose up -d --no-deps api web

            # Health check — si falla, rollback automático
            sleep 10
            if ! curl --fail https://tudominio.com/api/v1/health; then
              echo "Health check falló. Ejecutando rollback..."
              IMAGE_TAG=$PREV_TAG docker-compose up -d --no-deps api web
              exit 1
            fi

            echo "Deploy a producción completado: $IMAGE_TAG"

      - name: Notificar deploy exitoso
        if: success()
        uses: slackapi/slack-github-action@dcb1066f776dd043e64d0e8ba94ca15cc7e1875d # v4.0.0
        with:
          webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
          webhook-type: incoming-webhook
          payload: |
            text: "✅ Deploy a producción completado: ${{ needs.build-images.outputs.image-tag }}"
```

---

## Gestión de secrets en GitHub Actions

```
GitHub → Settings → Secrets and variables → Actions

Secrets por ambiente:
├── (Repository secrets — disponibles en todos los workflows)
│   └── SLACK_WEBHOOK_URL
│
├── (Environment: staging)
│   ├── STAGING_HOST
│   ├── STAGING_USER
│   ├── STAGING_SSH_KEY
│   └── STAGING_URL
│
└── (Environment: production)
    ├── PROD_HOST
    ├── PROD_USER
    ├── PROD_SSH_KEY
    └── PROD_URL
```

```yaml
# Cómo usar secrets en el workflow
- name: Deploy
  env:
    DB_PASSWORD: ${{ secrets.DB_PASSWORD }} # ← Nunca impreso en logs
  run: ./deploy.sh
```

---

## Branch protection — obligatorio en main

```
GitHub → Settings → Branches → Add rule → main

Configuración recomendada:
✅ Require a pull request before merging
✅ Require approvals: 1
✅ Require status checks to pass before merging
   → Seleccionar: lint-typecheck, test-unit, test-integration, build
✅ Require branches to be up to date before merging
✅ Do not allow bypassing the above settings
```

Sin esto, alguien puede pushear directo a main saltando el pipeline.

---

## Dependabot — acciones siempre al día

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
    cooldown:
      default-days: 7 # igual que el minimumReleaseAge de pnpm
    groups:
      actions:
        patterns: ["*"]
    commit-message:
      prefix: ci
```

Actualiza el SHA y el comentario de versión en un solo PR al mes. Así no vuelven los avisos de "Node.js X is deprecated".
