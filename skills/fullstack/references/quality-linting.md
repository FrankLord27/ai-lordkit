# ESLint y Prettier — Configuración Completa

---

## Instalación en el monorepo

```bash
# En la raíz del monorepo
pnpm add -D -w \
  eslint \
  prettier \
  @typescript-eslint/eslint-plugin \
  @typescript-eslint/parser \
  eslint-config-prettier \
  eslint-plugin-import \
  eslint-plugin-unused-imports \
  husky \
  lint-staged
```

---

## Prettier — un solo archivo para todo el monorepo

```javascript
// .prettierrc.js (raíz del monorepo)
module.exports = {
  // Comillas simples — consistente con la mayoría del ecosistema TS
  singleQuote: true,
  // Punto y coma siempre
  semi: true,
  // Ancho de línea — 100 es más cómodo que 80 para TypeScript
  printWidth: 100,
  // Tabs de 2 espacios
  tabWidth: 2,
  useTabs: false,
  // Trailing comma en ES5 — más git diffs limpios al agregar elementos
  trailingComma: "es5",
  // Paréntesis en arrow functions con un solo parámetro
  arrowParens: "always",
  // Fin de línea LF — consistente entre Mac, Linux y Windows
  endOfLine: "lf",
};
```

```
# .prettierignore
node_modules
dist
.next
coverage
*.generated.ts
prisma/migrations
```

---

## ESLint — configuración para TypeScript + NestJS + React

```javascript
// packages/eslint-config/index.js — configuración base compartida
module.exports = {
  parser: "@typescript-eslint/parser",
  plugins: ["@typescript-eslint", "import", "unused-imports"],
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:@typescript-eslint/recommended-requiring-type-checking",
    "prettier", // Desactiva reglas de ESLint que conflictúan con Prettier
  ],
  rules: {
    // TypeScript
    "@typescript-eslint/no-explicit-any": "error", // Prohibir any
    "@typescript-eslint/no-unused-vars": "off", // Manejado por unused-imports
    "@typescript-eslint/explicit-function-return-type": "off",
    "@typescript-eslint/explicit-module-boundary-types": "off",
    "@typescript-eslint/no-floating-promises": "error", // Promises sin await o .catch
    "@typescript-eslint/await-thenable": "error", // await en algo que no es Promise
    "@typescript-eslint/no-misused-promises": "error",
    "@typescript-eslint/prefer-nullish-coalescing": "warn", // ?? en lugar de ||
    "@typescript-eslint/prefer-optional-chain": "warn", // ?. en lugar de &&

    // Imports no usados — elimina automáticamente con --fix
    "unused-imports/no-unused-imports": "error",
    "unused-imports/no-unused-vars": [
      "warn",
      {
        vars: "all",
        varsIgnorePattern: "^_",
        args: "after-used",
        argsIgnorePattern: "^_",
      },
    ],

    // Orden de imports — agrupa y ordena automáticamente
    "import/order": [
      "error",
      {
        groups: [
          "builtin", // node:path, node:fs
          "external", // npm packages
          "internal", // @myapp/shared-types
          "parent", // ../service
          "sibling", // ./dto
          "index",
        ],
        "newlines-between": "always",
        alphabetize: { order: "asc", caseInsensitive: true },
      },
    ],

    // Buenas prácticas generales
    "no-console": "warn", // Usar Logger de NestJS en backend
    "prefer-const": "error", // const sobre let cuando no hay reasignación
    "no-var": "error", // Nunca var
    eqeqeq: ["error", "always"], // === siempre, nunca ==
    "no-nested-ternary": "error", // Ternarios anidados → muy difíciles de leer
  },
};
```

```javascript
// apps/api/.eslintrc.js — extiende la config base con reglas de NestJS
module.exports = {
  extends: ["@mystack/eslint-config"],
  parserOptions: {
    project: "tsconfig.json",
    tsconfigRootDir: __dirname,
  },
  rules: {
    // En NestJS los decoradores son el patrón — no son código muerto
    "@typescript-eslint/no-empty-function": "off",
    // Los servicios inyectados en constructores se usan indirectamente
    "unused-imports/no-unused-vars": ["warn", { varsIgnorePattern: "^_" }],
  },
};
```

```javascript
// apps/web/.eslintrc.js — extiende con reglas de React
module.exports = {
  extends: [
    "@mystack/eslint-config",
    "next/core-web-vitals", // Reglas de Next.js
  ],
  rules: {
    // React 17+ no requiere importar React
    "react/react-in-jsx-scope": "off",
    // Accesibilidad
    "jsx-a11y/alt-text": "error",
    "jsx-a11y/aria-props": "error",
  },
};
```

---

## Pre-commit hooks — automatizar la calidad

```bash
# Configurar husky y lint-staged
npx husky init
echo "npx lint-staged" > .husky/pre-commit
echo "npx commitlint --edit \$1" > .husky/commit-msg
```

```javascript
// lint-staged.config.js — qué ejecutar en cada archivo antes del commit
module.exports = {
  // TypeScript y JavaScript — lint + format
  "**/*.{ts,tsx,js,jsx}": [
    "eslint --fix --max-warnings=0", // 0 warnings permitidos
    "prettier --write",
  ],
  // JSON, YAML, Markdown — solo format
  "**/*.{json,yml,yaml,md}": ["prettier --write"],
  // Schemas de Prisma — format
  "**/*.prisma": ["prettier --write"],
};
```

```javascript
// commitlint.config.js — validar mensajes de commit
module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // Tipos permitidos
    "type-enum": [
      2,
      "always",
      [
        "feat", // Nueva feature
        "fix", // Bug fix
        "refactor", // Refactoring sin feat ni fix
        "chore", // Build, deps, config
        "docs", // Documentación
        "test", // Tests
        "perf", // Performance
        "ci", // CI/CD
        "style", // Formateo (no lógica)
        "revert", // Revertir commit anterior
      ],
    ],
    "subject-case": [2, "always", "lower-case"],
    "subject-max-length": [2, "always", 72],
    "body-max-line-length": [2, "always", 100],
  },
};
```

---

## Scripts en package.json

```json
{
  "scripts": {
    "lint": "turbo run lint",
    "lint:fix": "turbo run lint -- --fix",
    "format": "prettier --write \"**/*.{ts,tsx,js,json,md,prisma}\"",
    "format:check": "prettier --check \"**/*.{ts,tsx,js,json,md,prisma}\"",
    "typecheck": "turbo run typecheck"
  }
}
```

---

## Integración con VS Code

```json
// .vscode/settings.json — compartir configuración del editor con el equipo
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit",
    "source.organizeImports": "never" // ESLint ya ordena imports
  },
  "typescript.preferences.importModuleSpecifier": "relative",
  "typescript.updateImportsOnFileMove.enabled": "always",
  "[prisma]": {
    "editor.defaultFormatter": "Prisma.prisma"
  }
}
```

```json
// .vscode/extensions.json — extensiones recomendadas para el equipo
{
  "recommendations": [
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",
    "Prisma.prisma",
    "bradlc.vscode-tailwindcss",
    "ms-azuretools.vscode-docker"
  ]
}
```
