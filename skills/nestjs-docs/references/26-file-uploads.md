# NestJS — File Uploads

Subir archivos con Multer, validación, y almacenamiento local o S3.

---

## Instalación

```bash
pnpm add @nestjs/platform-express multer
pnpm add -D @types/multer
```

---

## Upload de un archivo

```typescript
import {
  Controller,
  Post,
  UploadedFile,
  UseInterceptors,
  ParseFilePipe,
  MaxFileSizeValidator,
  FileTypeValidator,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";

@Controller("files")
export class FilesController {
  @Post("upload")
  @UseInterceptors(FileInterceptor("file")) // 'file' = nombre del campo en form-data
  uploadFile(
    @UploadedFile(
      new ParseFilePipe({
        validators: [
          new MaxFileSizeValidator({ maxSize: 5 * 1024 * 1024 }), // 5MB
          new FileTypeValidator({ fileType: /(jpg|jpeg|png|gif)$/ }),
        ],
      }),
    )
    file: Express.Multer.File,
  ) {
    return {
      originalName: file.originalname,
      filename: file.filename,
      size: file.size,
      mimetype: file.mimetype,
    };
  }
}
```

---

## Upload de múltiples archivos

```typescript
import {
  FilesInterceptor,
  FileFieldsInterceptor,
} from "@nestjs/platform-express";

@Controller("files")
export class FilesController {
  // Múltiples archivos del mismo campo
  @Post("gallery")
  @UseInterceptors(FilesInterceptor("photos", 10)) // max 10 archivos
  uploadGallery(@UploadedFiles() files: Express.Multer.File[]) {
    return files.map((f) => ({ name: f.originalname, size: f.size }));
  }

  // Múltiples campos con archivos
  @Post("profile")
  @UseInterceptors(
    FileFieldsInterceptor([
      { name: "avatar", maxCount: 1 },
      { name: "documents", maxCount: 5 },
    ]),
  )
  uploadProfile(
    @UploadedFiles()
    files: {
      avatar?: Express.Multer.File[];
      documents?: Express.Multer.File[];
    },
  ) {
    return {
      avatar: files.avatar?.[0]?.originalname,
      documents: files.documents?.map((d) => d.originalname),
    };
  }
}
```

---

## Configuración de Multer

### Almacenamiento local con nombres únicos

```typescript
import { Module } from "@nestjs/common";
import { MulterModule } from "@nestjs/platform-express";
import { diskStorage } from "multer";
import { extname } from "path";
import { v4 as uuid } from "uuid";

@Module({
  imports: [
    MulterModule.register({
      storage: diskStorage({
        destination: "./uploads",
        filename: (req, file, callback) => {
          const uniqueName = `${uuid()}${extname(file.originalname)}`;
          callback(null, uniqueName);
        },
      }),
      limits: {
        fileSize: 10 * 1024 * 1024, // 10MB global
      },
      fileFilter: (req, file, callback) => {
        if (!file.mimetype.match(/\/(jpg|jpeg|png|gif|pdf)$/)) {
          callback(new Error("Tipo de archivo no permitido"), false);
        }
        callback(null, true);
      },
    }),
  ],
})
export class FilesModule {}
```

### Almacenamiento en memoria (para procesar o subir a S3)

```typescript
MulterModule.register({
  storage: memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});
```

---

## Validadores personalizados

```typescript
// common/validators/file-validators.ts
import { FileValidator } from '@nestjs/common';

export class ImageDimensionsValidator extends FileValidator<{
  minWidth: number;
  minHeight: number;
}> {
  constructor(options: { minWidth: number; minHeight: number }) {
    super(options);
  }

  async isValid(file: Express.Multer.File): Promise<boolean> {
    // Usar sharp o similar para verificar dimensiones
    const sharp = require('sharp');
    const metadata = await sharp(file.buffer).metadata();

    return (
      metadata.width >= this.validationOptions.minWidth &&
      metadata.height >= this.validationOptions.minHeight
    );
  }

  buildErrorMessage(): string {
    return `La imagen debe ser al menos ${this.validationOptions.minWidth}x${this.validationOptions.minHeight}px`;
  }
}

// Uso:
@UploadedFile(
  new ParseFilePipe({
    validators: [
      new MaxFileSizeValidator({ maxSize: 5 * 1024 * 1024 }),
      new FileTypeValidator({ fileType: /(jpg|jpeg|png)$/ }),
      new ImageDimensionsValidator({ minWidth: 200, minHeight: 200 }),
    ],
  }),
)
```

---

## Subir a S3

```typescript
// common/services/s3.service.ts
import { Injectable } from "@nestjs/common";
import {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
} from "@aws-sdk/client-s3";
import { v4 as uuid } from "uuid";
import { extname } from "path";

@Injectable()
export class S3Service {
  private readonly s3: S3Client;
  private readonly bucket = process.env.AWS_S3_BUCKET!;

  constructor() {
    this.s3 = new S3Client({
      region: process.env.AWS_REGION,
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
      },
    });
  }

  async upload(file: Express.Multer.File, folder = "uploads"): Promise<string> {
    const key = `${folder}/${uuid()}${extname(file.originalname)}`;

    await this.s3.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: file.buffer,
        ContentType: file.mimetype,
        ACL: "public-read", // O 'private' para URLs firmadas
      }),
    );

    return `https://${this.bucket}.s3.amazonaws.com/${key}`;
  }

  async delete(url: string): Promise<void> {
    const key = url.split(".amazonaws.com/")[1];

    await this.s3.send(
      new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: key,
      }),
    );
  }
}
```

### Controller con S3

```typescript
@Controller("files")
export class FilesController {
  constructor(private readonly s3Service: S3Service) {}

  @Post("avatar")
  @UseInterceptors(FileInterceptor("file", { storage: memoryStorage() }))
  async uploadAvatar(
    @UploadedFile(
      new ParseFilePipe({
        validators: [
          new MaxFileSizeValidator({ maxSize: 2 * 1024 * 1024 }),
          new FileTypeValidator({ fileType: /(jpg|jpeg|png)$/ }),
        ],
      }),
    )
    file: Express.Multer.File,
    @CurrentUser() user: User,
  ) {
    const url = await this.s3Service.upload(file, "avatars");

    // Guardar URL en la DB
    await this.usersService.updateAvatar(user.id, url);

    return { url };
  }
}
```

---

## Presigned URLs (upload directo del cliente a S3)

```typescript
// s3.service.ts
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { PutObjectCommand } from '@aws-sdk/client-s3';

@Injectable()
export class S3Service {
  async getPresignedUploadUrl(
    filename: string,
    contentType: string,
    folder = 'uploads',
  ): Promise<{ uploadUrl: string; fileUrl: string }> {
    const key = `${folder}/${uuid()}${extname(filename)}`;

    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: contentType,
    });

    const uploadUrl = await getSignedUrl(this.s3, command, { expiresIn: 300 }); // 5 min

    return {
      uploadUrl,
      fileUrl: `https://${this.bucket}.s3.amazonaws.com/${key}`,
    };
  }
}

// Controller
@Post('presigned-url')
async getPresignedUrl(
  @Body() dto: { filename: string; contentType: string },
) {
  return this.s3Service.getPresignedUploadUrl(dto.filename, dto.contentType);
}
```

Frontend sube directamente a S3 con el URL firmado, sin pasar por tu servidor.

---

## Procesar imágenes con Sharp

```bash
pnpm add sharp
pnpm add -D @types/sharp
```

```typescript
import sharp from 'sharp';

@Injectable()
export class ImageService {
  async processAvatar(file: Express.Multer.File): Promise<Buffer> {
    return sharp(file.buffer)
      .resize(200, 200, { fit: 'cover' })
      .jpeg({ quality: 80 })
      .toBuffer();
  }

  async createThumbnail(file: Express.Multer.File): Promise<Buffer> {
    return sharp(file.buffer)
      .resize(100, 100, { fit: 'inside' })
      .png()
      .toBuffer();
  }
}

// En el controller
@Post('avatar')
@UseInterceptors(FileInterceptor('file', { storage: memoryStorage() }))
async uploadAvatar(@UploadedFile() file: Express.Multer.File) {
  const processed = await this.imageService.processAvatar(file);

  // Subir el buffer procesado
  const url = await this.s3Service.uploadBuffer(processed, 'avatars', 'image/jpeg');

  return { url };
}
```

---

## Servir archivos estáticos

```typescript
// main.ts
import { NestExpressApplication } from "@nestjs/platform-express";
import { join } from "path";

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  // Servir archivos de ./uploads en /files
  app.useStaticAssets(join(__dirname, "..", "uploads"), {
    prefix: "/files/",
  });

  await app.listen(3000);
}
// GET /files/avatar-123.jpg → sirve ./uploads/avatar-123.jpg
```

---

## Streaming de archivos grandes

```typescript
import { createReadStream } from 'fs';
import { Response } from 'express';

@Get('download/:filename')
async downloadFile(
  @Param('filename') filename: string,
  @Res() res: Response,
) {
  const filePath = join(__dirname, '..', 'uploads', filename);

  res.setHeader('Content-Type', 'application/octet-stream');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

  const stream = createReadStream(filePath);
  stream.pipe(res);
}
```

---

## Checklist

- [ ] Configurar Multer con límites de tamaño
- [ ] Validar tipos de archivo (whitelist)
- [ ] Generar nombres únicos (uuid)
- [ ] Decidir storage: local vs S3 vs memory
- [ ] Procesar imágenes (resize, compress) antes de guardar
- [ ] Usar presigned URLs para uploads grandes
- [ ] Configurar limpieza de archivos huérfanos
