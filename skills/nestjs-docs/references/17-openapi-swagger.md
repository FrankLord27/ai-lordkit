# NestJS — OpenAPI / Swagger

**Fuente:** https://docs.nestjs.com/openapi/introduction

## Instalación

```bash
pnpm add @nestjs/swagger
```

## Setup en main.ts

```typescript
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  const config = new DocumentBuilder()
    .setTitle("My API")
    .setDescription("API documentation")
    .setVersion("1.0")
    .addBearerAuth() // JWT
    .addTag("Users", "User management")
    .addTag("Auth", "Authentication")
    .addServer("http://localhost:3000", "Local")
    .addServer("https://api.myapp.com", "Production")
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup("api/docs", app, document, {
    swaggerOptions: {
      persistAuthorization: true, // guarda el token en el browser
    },
  });

  await app.listen(3000);
}
```

## Decoradores en controllers

```typescript
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiParam,
  ApiQuery,
  ApiBody,
  ApiCreatedResponse,
  ApiOkResponse,
  ApiNotFoundResponse,
  ApiBadRequestResponse,
  ApiUnauthorizedResponse,
  ApiForbiddenResponse,
} from "@nestjs/swagger";

@ApiBearerAuth() // requiere JWT en todos los endpoints del controller
@ApiTags("Cats") // agrupa en sección "Cats"
@Controller("cats")
export class CatsController {
  @ApiOperation({
    summary: "Create a new cat",
    description: "Creates a cat record",
  })
  @ApiCreatedResponse({ description: "Cat created successfully", type: Cat })
  @ApiBadRequestResponse({ description: "Invalid data" })
  @Post()
  create(@Body() createCatDto: CreateCatDto) {}

  @ApiOperation({ summary: "Get all cats" })
  @ApiOkResponse({ description: "Returns all cats", type: [Cat] })
  @ApiQuery({ name: "breed", required: false, type: String })
  @ApiQuery({ name: "page", required: false, type: Number })
  @Get()
  findAll(@Query("breed") breed?: string, @Query("page") page?: number) {}

  @ApiParam({ name: "id", type: String, description: "Cat UUID" })
  @ApiOkResponse({ type: Cat })
  @ApiNotFoundResponse({ description: "Cat not found" })
  @Get(":id")
  findOne(@Param("id") id: string) {}
}
```

## Decoradores en DTOs

```typescript
import {
  ApiProperty,
  ApiPropertyOptional,
  ApiHideProperty,
} from "@nestjs/swagger";

export class CreateCatDto {
  @ApiProperty({ example: "Whiskers", description: "The name of the cat" })
  @IsString()
  name: string;

  @ApiProperty({ example: 5, minimum: 0, maximum: 30 })
  @IsInt()
  age: number;

  @ApiPropertyOptional({ example: "Persian", description: "Cat breed" })
  @IsOptional()
  @IsString()
  breed?: string;

  @ApiProperty({
    enum: CatStatus,
    enumName: "CatStatus",
    default: CatStatus.ACTIVE,
  })
  @IsEnum(CatStatus)
  status: CatStatus;

  @ApiHideProperty() // no aparece en Swagger
  internalField: string;
}
```

## Entities/Response objects

```typescript
import { ApiProperty } from "@nestjs/swagger";
import { Exclude } from "class-transformer";

export class CatEntity {
  @ApiProperty({ example: "uuid-here" })
  id: string;

  @ApiProperty()
  name: string;

  @Exclude()
  @ApiHideProperty()
  password: string;

  @ApiProperty()
  createdAt: Date;
}
```

## Mapped Types con swagger (preserva decoradores)

```typescript
import {
  PartialType,
  OmitType,
  PickType,
  IntersectionType,
} from "@nestjs/swagger";
// ¡Importante! Usar @nestjs/swagger, NO @nestjs/mapped-types

export class UpdateCatDto extends PartialType(CreateCatDto) {}
export class LoginDto extends PickType(CreateCatDto, [
  "email",
  "password",
] as const) {}
```

## Tipos de respuesta y paginación

```typescript
export class PaginatedResponseDto<T> {
  @ApiProperty({ type: "array" })
  data: T[];

  @ApiProperty({ example: 100 })
  total: number;

  @ApiProperty({ example: 1 })
  page: number;

  @ApiProperty({ example: 10 })
  limit: number;
}
```

## CLI Plugin (evita repetir decoradores)

Con el plugin, Nest detecta automáticamente los tipos TypeScript y los añade al Swagger sin necesidad de `@ApiProperty()` manual en todos los campos.

```json
// nest-cli.json
{
  "compilerOptions": {
    "plugins": [
      {
        "name": "@nestjs/swagger",
        "options": {
          "classValidatorShim": true,
          "introspectComments": true
        }
      }
    ]
  }
}
```

## Seguridad en Swagger

```typescript
// Bearer JWT
.addBearerAuth(
  { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
  'access-token',  // nombre del esquema
)

// API Key en header
.addApiKey({ type: 'apiKey', in: 'header', name: 'X-API-KEY' }, 'api-key')

// En controller:
@ApiBearerAuth('access-token')
@Controller('protected')
```

## Exportar Swagger JSON (para CI/CD)

```typescript
import { writeFileSync } from "fs";

const document = SwaggerModule.createDocument(app, config);
writeFileSync("./swagger.json", JSON.stringify(document, null, 2));
```
