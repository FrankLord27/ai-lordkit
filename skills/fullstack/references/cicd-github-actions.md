# GitHub Actions — CI y CD

---

## Pipeline de CI — corre en cada PR

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
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v3
        with: { version: 8 }

      - uses: actions/setup-node@v4
        with:
          node-version: "20"
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
    runs-on: ubuntu-latest
    needs: quality # Solo corre si lint y typecheck pasan
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v3
        with: { version: 8 }
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile
      - name: Unit tests
        run: pnpm test:unit

      - name: Upload coverage
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage-report
          path: apps/api/coverage/
          retention-days: 7

  # ─── 3. TESTS DE INTEGRACIÓN ────────────────────────────────────
  test-integration:
    name: Integration Tests
    runs-on: ubuntu-latest
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
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v3
        with: { version: 8 }
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile

      - name: Run migrations on test DB
        run: pnpm --filter api prisma migrate deploy

      - name: Integration tests
        run: pnpm --filter api test:integration

  # ─── 4. BUILD ───────────────────────────────────────────────────
  build:
    name: Build
    runs-on: ubuntu-latest
    needs: [test-unit, test-integration]
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v3
        with: { version: 8 }
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
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
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.version }}

    steps:
      - uses: actions/checkout@v4

      - name: Docker meta — generar tags de la imagen
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: |
            ghcr.io/${{ github.repository }}/api
            ghcr.io/${{ github.repository }}/web
          tags: |
            type=sha,prefix=,suffix=,format=short   # Tag con el SHA del commit
            type=raw,value=latest                    # Tag latest (solo para referencia)

      - name: Login al GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build y push imagen del API
        uses: docker/build-push-action@v5
        with:
          context: .
          file: apps/api/Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository }}/api:${{ steps.meta.outputs.version }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Build y push imagen del Web
        uses: docker/build-push-action@v5
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
    runs-on: ubuntu-latest
    needs: build-images
    environment: staging # Ambiente de GitHub — permite aprobar/rechazar

    steps:
      - uses: actions/checkout@v4

      - name: Deploy a staging vía SSH
        uses: appleboy/ssh-action@v1
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
    runs-on: ubuntu-latest
    needs: deploy-staging

    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v3
        with: { version: 8 }
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "pnpm"
      - run: pnpm install --frozen-lockfile
      - run: npx playwright install --with-deps chromium

      - name: E2E tests contra staging
        run: pnpm --filter web test:e2e
        env:
          BASE_URL: ${{ secrets.STAGING_URL }}

      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report-staging
          path: apps/web/playwright-report/
          retention-days: 7

  # ─── 4. DEPLOY A PRODUCCIÓN ─────────────────────────────────────
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: e2e-staging
    environment:
      name: production
      url: https://tudominio.com
    # En GitHub: configurar "Required reviewers" en el ambiente production
    # Esto pausa el pipeline hasta que alguien apruebe el deploy

    steps:
      - uses: actions/checkout@v4

      - name: Deploy a producción vía SSH
        uses: appleboy/ssh-action@v1
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
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "✅ Deploy a producción completado: ${{ needs.build-images.outputs.image-tag }}"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
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
