---
name: minio-docs
description: >
  Referencia completa de MinIO para almacenamiento de objetos (imágenes, documentos,
  facturas PDF, backups) en el stack fullstack como alternativa self-hosted a S3.
  Úsala cuando trabajes con: buckets, upload de archivos desde NestJS, presigned URLs
  para acceso temporal, políticas de acceso, integración con el SDK de AWS (compatible
  con MinIO), generación de thumbnails, o almacenamiento de archivos adjuntos en
  tickets de soporte o comprobantes de un POS.
---

# MinIO — Referencia Completa

## Documentación oficial (Context7)

Para la doc oficial y actualizada de MinIO, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

## Integración NestJS + MinIO (SDK AWS S3)

```typescript
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

// Configuración (compatible con MinIO)
const s3 = new S3Client({
  endpoint: process.env.MINIO_ENDPOINT, // http://localhost:9000
  region: "us-east-1", // cualquier valor
  credentials: {
    accessKeyId: process.env.MINIO_ACCESS_KEY,
    secretAccessKey: process.env.MINIO_SECRET_KEY,
  },
  forcePathStyle: true, // OBLIGATORIO para MinIO
});

// Upload
await s3.send(
  new PutObjectCommand({
    Bucket: "facturas",
    Key: `${tenantId}/${invoiceId}.pdf`,
    Body: buffer,
    ContentType: "application/pdf",
  }),
);

// Presigned URL (acceso temporal 1 hora)
const url = await getSignedUrl(
  s3,
  new GetObjectCommand({
    Bucket: "facturas",
    Key: `${tenantId}/${invoiceId}.pdf`,
  }),
  { expiresIn: 3600 },
);
```

## Reglas no negociables

- **`forcePathStyle: true`** siempre en la config del cliente — sin esto MinIO falla
- **Organizar por tenant**: prefijo `{tenantId}/` en todos los keys — multi-tenancy a nivel de objeto
- **Presigned URLs** para acceso del cliente — nunca exponer credenciales al frontend
- **Buckets separados por dominio**: `facturas`, `avatars`, `adjuntos`, `backups`
- **Lifecycle policies** para auto-eliminar archivos temporales (ej: presigned uploads sin confirmar)
