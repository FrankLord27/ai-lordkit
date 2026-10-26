# Prisma 7 — JSON Fields y Full-Text Search

Operaciones avanzadas en campos JSON y búsqueda full-text nativa de PostgreSQL.

---

## JSON Fields

### Definir campo JSON en el schema

```prisma
model Product {
  id         String   @id @default(uuid())
  name       String
  metadata   Json     // Datos flexibles
  attributes Json?    // Opcional
  tags       String[] // Array nativo (alternativa a JSON para listas simples)

  @@map("products")
}

model User {
  id          String @id @default(uuid())
  preferences Json   @default("{}")
  settings    Json   @default("{\"theme\": \"light\", \"notifications\": true}")

  @@map("users")
}
```

### Crear con datos JSON

```typescript
await prisma.product.create({
  data: {
    name: "Laptop Pro",
    metadata: {
      brand: "TechCorp",
      specs: {
        ram: "16GB",
        storage: "512GB SSD",
        cpu: "Intel i7",
      },
      certifications: ["ISO9001", "CE"],
    },
    attributes: {
      color: "silver",
      weight: 1.8,
      dimensions: { width: 35, height: 24, depth: 1.5 },
    },
  },
});
```

### Filtrar por valores dentro de JSON

```typescript
// Filtrar por path exacto
const techProducts = await prisma.product.findMany({
  where: {
    metadata: {
      path: ["brand"],
      equals: "TechCorp",
    },
  },
});

// Filtrar por valor anidado
const highRamProducts = await prisma.product.findMany({
  where: {
    metadata: {
      path: ["specs", "ram"],
      equals: "16GB",
    },
  },
});

// Filtrar por array que contiene valor
const certifiedProducts = await prisma.product.findMany({
  where: {
    metadata: {
      path: ["certifications"],
      array_contains: "ISO9001",
    },
  },
});

// Comparaciones numéricas en JSON
const lightProducts = await prisma.product.findMany({
  where: {
    attributes: {
      path: ["weight"],
      lt: 2.0, // Menor que 2kg
    },
  },
});
```

### Actualizar campos JSON

```typescript
// Reemplazar todo el JSON
await prisma.product.update({
  where: { id: productId },
  data: {
    metadata: {
      brand: "NewBrand",
      specs: { ram: "32GB" },
    },
  },
});

// Actualizar campo específico dentro del JSON (raw query)
await prisma.$executeRaw`
  UPDATE products 
  SET metadata = jsonb_set(metadata, '{specs,ram}', '"32GB"')
  WHERE id = ${productId}
`;

// Agregar elemento a array dentro de JSON
await prisma.$executeRaw`
  UPDATE products 
  SET metadata = jsonb_set(
    metadata, 
    '{certifications}', 
    metadata->'certifications' || '"NewCert"'
  )
  WHERE id = ${productId}
`;
```

### Índices en campos JSON (PostgreSQL)

```sql
-- Índice GIN para búsquedas en todo el JSON
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Índice en path específico (más eficiente)
CREATE INDEX idx_products_brand ON products ((metadata->>'brand'));

-- Índice para búsquedas en array dentro de JSON
CREATE INDEX idx_products_certifications ON products USING GIN ((metadata->'certifications'));
```

---

## Full-Text Search

PostgreSQL tiene búsqueda full-text nativa sin necesidad de Elasticsearch.

### Habilitar en el schema

```prisma
model Article {
  id        String   @id @default(uuid())
  title     String
  content   String
  createdAt DateTime @default(now())

  @@map("articles")
}
```

### Búsqueda básica

```typescript
// Buscar en un campo
const articles = await prisma.article.findMany({
  where: {
    content: {
      search: "typescript prisma", // Busca ambas palabras
    },
  },
});

// Buscar con operadores
const articles = await prisma.article.findMany({
  where: {
    content: {
      search: "typescript & prisma", // AND
    },
  },
});

const articles = await prisma.article.findMany({
  where: {
    content: {
      search: "typescript | javascript", // OR
    },
  },
});

const articles = await prisma.article.findMany({
  where: {
    content: {
      search: "typescript & !javascript", // NOT
    },
  },
});
```

### Búsqueda en múltiples campos

```typescript
// Buscar en título O contenido
const articles = await prisma.article.findMany({
  where: {
    OR: [{ title: { search: query } }, { content: { search: query } }],
  },
});
```

### Configurar índice full-text en PostgreSQL

```sql
-- Crear columna de búsqueda (tsvector)
ALTER TABLE articles
ADD COLUMN search_vector tsvector
GENERATED ALWAYS AS (
  setweight(to_tsvector('spanish', coalesce(title, '')), 'A') ||
  setweight(to_tsvector('spanish', coalesce(content, '')), 'B')
) STORED;

-- Índice GIN para búsqueda rápida
CREATE INDEX idx_articles_search ON articles USING GIN (search_vector);
```

### Búsqueda avanzada con ranking

```typescript
// Búsqueda con relevancia usando raw query
const results = await prisma.$queryRaw<
  Array<{
    id: string;
    title: string;
    rank: number;
  }>
>`
  SELECT 
    id, 
    title,
    ts_rank(search_vector, plainto_tsquery('spanish', ${query})) as rank
  FROM articles
  WHERE search_vector @@ plainto_tsquery('spanish', ${query})
  ORDER BY rank DESC
  LIMIT 20
`;
```

### Highlighting de resultados

```typescript
const results = await prisma.$queryRaw`
  SELECT 
    id,
    ts_headline(
      'spanish',
      content,
      plainto_tsquery('spanish', ${query}),
      'StartSel=<mark>, StopSel=</mark>, MaxWords=50, MinWords=25'
    ) as highlighted_content
  FROM articles
  WHERE search_vector @@ plainto_tsquery('spanish', ${query})
`;
```

### Sugerencias (autocomplete)

```typescript
// Búsqueda de prefijo para autocomplete
const suggestions = await prisma.$queryRaw<Array<{ title: string }>>`
  SELECT DISTINCT title
  FROM articles
  WHERE title ILIKE ${query + "%"}
  LIMIT 10
`;

// O usando trigrams para coincidencias fuzzy
// Primero: CREATE EXTENSION pg_trgm;
const fuzzySuggestions = await prisma.$queryRaw`
  SELECT title, similarity(title, ${query}) as sim
  FROM articles
  WHERE similarity(title, ${query}) > 0.3
  ORDER BY sim DESC
  LIMIT 10
`;
```

---

## Combinando JSON y Full-Text

```typescript
// Buscar productos por texto Y filtrar por atributos JSON
const products = await prisma.$queryRaw`
  SELECT *
  FROM products
  WHERE 
    to_tsvector('spanish', name || ' ' || COALESCE(description, '')) 
      @@ plainto_tsquery('spanish', ${searchQuery})
    AND metadata->>'brand' = ${brand}
    AND (attributes->>'weight')::numeric < ${maxWeight}
  ORDER BY created_at DESC
  LIMIT 20
`;
```

---

## Service de búsqueda completo

```typescript
// modules/search/search.service.ts
@Injectable()
export class SearchService {
  constructor(private readonly prisma: PrismaService) {}

  async searchProducts(params: {
    query: string;
    filters?: {
      brand?: string;
      minPrice?: number;
      maxPrice?: number;
      categories?: string[];
    };
    page?: number;
    limit?: number;
  }) {
    const { query, filters = {}, page = 1, limit = 20 } = params;
    const offset = (page - 1) * limit;

    // Construir condiciones dinámicamente
    const conditions: string[] = [];
    const values: any[] = [];
    let paramIndex = 1;

    // Full-text search
    if (query) {
      conditions.push(
        `search_vector @@ plainto_tsquery('spanish', $${paramIndex})`,
      );
      values.push(query);
      paramIndex++;
    }

    // Filtros JSON
    if (filters.brand) {
      conditions.push(`metadata->>'brand' = $${paramIndex}`);
      values.push(filters.brand);
      paramIndex++;
    }

    if (filters.minPrice !== undefined) {
      conditions.push(`price >= $${paramIndex}`);
      values.push(filters.minPrice);
      paramIndex++;
    }

    if (filters.maxPrice !== undefined) {
      conditions.push(`price <= $${paramIndex}`);
      values.push(filters.maxPrice);
      paramIndex++;
    }

    if (filters.categories?.length) {
      conditions.push(`category_id = ANY($${paramIndex})`);
      values.push(filters.categories);
      paramIndex++;
    }

    // Soft delete
    conditions.push("deleted_at IS NULL");

    const whereClause =
      conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";

    // Query con ranking
    const results = await this.prisma.$queryRawUnsafe(
      `
      SELECT 
        id, name, price, metadata,
        ${query ? `ts_rank(search_vector, plainto_tsquery('spanish', $1)) as rank` : "1 as rank"}
      FROM products
      ${whereClause}
      ORDER BY rank DESC, created_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `,
      ...values,
    );

    // Count total
    const [{ count }] = await this.prisma.$queryRawUnsafe(
      `
      SELECT COUNT(*) as count
      FROM products
      ${whereClause}
    `,
      ...values,
    );

    return {
      data: results,
      pagination: {
        page,
        limit,
        total: Number(count),
        pages: Math.ceil(Number(count) / limit),
      },
    };
  }
}
```

---

## Checklist

### JSON Fields:

- [ ] Usar `Json` para datos flexibles/dinámicos
- [ ] Usar `String[]` para arrays simples (más eficiente)
- [ ] Índices GIN para búsquedas en JSON
- [ ] Validar estructura JSON en el service (Zod)

### Full-Text Search:

- [ ] Columna `tsvector` con pesos (A=título, B=contenido)
- [ ] Índice GIN en la columna tsvector
- [ ] Configurar idioma correcto ('spanish', 'english')
- [ ] Ranking para ordenar por relevancia
- [ ] Highlighting para mostrar contexto
