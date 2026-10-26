# NestJS — Swagger / OpenAPI

## Instalación

```bash
pnpm add @nestjs/swagger swagger-ui-express
```

## Setup en main.ts

```typescript
import { SwaggerModule, DocumentBuilder } from "@nestjs/swagger";

const config = new DocumentBuilder()
  .setTitle("Mi API")
  .setDescription("Car rental marketplace API")
  .setVersion("1.0")
  .addBearerAuth(
    { type: "http", scheme: "bearer", bearerFormat: "JWT" },
    "JWT-auth", // nombre del scheme (usar en @ApiBearerAuth)
  )
  .addTag("auth", "Authentication endpoints")
  .addTag("cars", "Car management")
  .addTag("bookings", "Booking management")
  .addServer("http://localhost:3000", "Development")
  .addServer("https://api.example.com", "Production")
  .build();

const document = SwaggerModule.createDocument(app, config);
SwaggerModule.setup("docs", app, document, {
  swaggerOptions: {
    persistAuthorization: true, // recuerda el token entre recargas
  },
});
// Docs disponibles en: http://localhost:3000/docs
```

## Decoradores en Controllers

```typescript
import {
  ApiTags, ApiOperation, ApiResponse, ApiBearerAuth,
  ApiParam, ApiQuery, ApiBody, ApiCreatedResponse,
  ApiOkResponse, ApiNotFoundResponse, ApiUnauthorizedResponse,
  ApiForbiddenResponse, ApiNoContentResponse,
  ApiConsumes, ApiProduces,
} from '@nestjs/swagger';

@ApiTags('cars')
@ApiBearerAuth('JWT-auth')
@Controller('cars')
export class CarsController {

  @ApiOperation({ summary: 'Get all cars', description: 'Returns paginated list of cars' })
  @ApiQuery({ name: 'page', required: false, type: Number, example: 1 })
  @ApiQuery({ name: 'limit', required: false, type: Number, example: 20 })
  @ApiQuery({ name: 'search', required: false, type: String })
  @ApiOkResponse({ type: [CarResponseDto] })
  @Get()
  findAll(@Query() query: PaginationDto) { ... }

  @ApiOperation({ summary: 'Get car by ID' })
  @ApiParam({ name: 'id', type: String, description: 'Car UUID' })
  @ApiOkResponse({ type: CarResponseDto })
  @ApiNotFoundResponse({ description: 'Car not found' })
  @Get(':id')
  findOne(@Param('id') id: string) { ... }

  @ApiOperation({ summary: 'Create a new car' })
  @ApiCreatedResponse({ type: CarResponseDto })
  @ApiBearerAuth('JWT-auth')
  @Post()
  create(@Body() dto: CreateCarDto) { ... }

  @ApiNoContentResponse({ description: 'Car deleted successfully' })
  @ApiUnauthorizedResponse()
  @ApiForbiddenResponse()
  @Delete(':id')
  remove(@Param('id') id: string) { ... }
}
```

## Decoradores en DTOs

```typescript
import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";

export class CreateCarDto {
  @ApiProperty({ example: "Toyota Corolla 2023", description: "Car title" })
  @IsString()
  title: string;

  @ApiPropertyOptional({ example: "Excellent condition, low mileage" })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiProperty({ example: 50.0, description: "Price per day in USD" })
  @IsNumber()
  @IsPositive()
  pricePerDay: number;

  @ApiProperty({ enum: CarType, example: CarType.SEDAN })
  @IsEnum(CarType)
  type: CarType;

  @ApiProperty({ type: [String], example: ["https://...jpg"] })
  @IsArray()
  @IsUrl({}, { each: true })
  images: string[];
}

export class CarResponseDto {
  @ApiProperty({ example: "clxyz123..." })
  id: string;

  @ApiProperty()
  title: string;

  @ApiProperty()
  pricePerDay: number;

  @ApiProperty({ type: () => UserSummaryDto })
  owner: UserSummaryDto;

  @ApiProperty()
  createdAt: Date;
}
```

## Tipos avanzados en Swagger

```typescript
// Para respuestas paginadas:
export class PaginatedCarsDto {
  @ApiProperty({ type: [CarResponseDto] })
  data: CarResponseDto[];

  @ApiProperty({
    example: { total: 100, page: 1, limit: 20, totalPages: 5 },
  })
  meta: {
    total: number;
    page: number;
    limit: number;
    totalPages: number;
  };
}

// Para respuestas de error:
export class ErrorResponseDto {
  @ApiProperty({ example: 400 })
  statusCode: number;

  @ApiProperty({ example: ["email must be an email"] })
  message: string | string[];

  @ApiProperty({ example: "2024-01-01T00:00:00.000Z" })
  timestamp: string;
}
```

## CLI Plugin (auto-documenta DTOs)

```json
// nest-cli.json
{
  "compilerOptions": {
    "plugins": [
      {
        "name": "@nestjs/swagger",
        "options": {
          "classValidatorShim": true, // usa class-validator para tipos
          "introspectComments": true // usa JSDoc como descripción
        }
      }
    ]
  }
}
```

Con el plugin activo, `@ApiProperty()` se infiere automáticamente desde class-validator.

## PartialType + Swagger

```typescript
// Con mapped-types de @nestjs/swagger (no @nestjs/mapped-types):
import { PartialType, OmitType, PickType } from "@nestjs/swagger";

export class UpdateCarDto extends PartialType(CreateCarDto) {}
// Preserva los ApiProperty decorators del padre
```
