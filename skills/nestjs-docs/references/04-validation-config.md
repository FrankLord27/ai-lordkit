# NestJS — Validación y Configuración

## 1. DTOs con class-validator

```bash
pnpm add class-validator class-transformer
```

### Decoradores más usados

```typescript
import {
  IsString,
  IsEmail,
  IsNumber,
  IsBoolean,
  IsEnum,
  IsOptional,
  IsArray,
  IsUUID,
  IsUrl,
  IsDate,
  IsDateString,
  MinLength,
  MaxLength,
  Min,
  Max,
  Length,
  IsNotEmpty,
  IsPositive,
  IsInt,
  ValidateNested,
  Type,
  Matches,
} from "class-validator";
import { Type, Exclude, Expose, Transform } from "class-transformer";

export class CreateUserDto {
  @IsString()
  @MinLength(2)
  @MaxLength(50)
  name: string;

  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  @Matches(/(?=.*[A-Z])(?=.*[0-9])/, {
    message:
      "Password must contain at least one uppercase letter and one number",
  })
  password: string;

  @IsEnum(Role)
  role: Role;

  @IsOptional()
  @IsString()
  bio?: string;

  @IsOptional()
  @IsInt()
  @Min(18)
  @Max(120)
  age?: number;

  @IsArray()
  @IsString({ each: true })
  tags: string[];
}
```

### Nested Objects (ValidateNested)

```typescript
export class AddressDto {
  @IsString() street: string;
  @IsString() city: string;
  @IsString() country: string;
}

export class CreateOrderDto {
  @ValidateNested()
  @Type(() => AddressDto) // ¡Type() es obligatorio para nested!
  address: AddressDto;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items: OrderItemDto[];
}
```

### UpdateDto con PartialType

```typescript
import {
  PartialType,
  OmitType,
  PickType,
  IntersectionType,
} from "@nestjs/mapped-types";

export class UpdateUserDto extends PartialType(CreateUserDto) {}
// Todos los campos son opcionales

export class PublicUserDto extends OmitType(CreateUserDto, [
  "password",
] as const) {}
// Sin el campo password

export class LoginDto extends PickType(CreateUserDto, [
  "email",
  "password",
] as const) {}
// Solo email y password
```

### Serialización de respuestas (class-transformer)

```typescript
import { Exclude, Expose } from 'class-transformer';

export class UserEntity {
  id: string;
  email: string;

  @Exclude()          // Nunca se incluye en respuesta
  password: string;

  constructor(partial: Partial<UserEntity>) {
    Object.assign(this, partial);
  }
}

// En controller, usando ClassSerializerInterceptor:
@UseInterceptors(ClassSerializerInterceptor)
@Get(':id')
async findOne(@Param('id') id: string) {
  return new UserEntity(await this.usersService.findOne(id));
}

// O globalmente en main.ts:
app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));
```

---

## 2. ConfigModule (@nestjs/config)

```bash
pnpm add @nestjs/config
```

### Setup básico

```typescript
// app.module.ts
import { ConfigModule } from "@nestjs/config";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true, // disponible en todos los módulos sin importar
      envFilePath: [".env.local", ".env"], // en orden de prioridad
      cache: true, // cachea variables de entorno
    }),
  ],
})
export class AppModule {}
```

### ConfigService

```typescript
@Injectable()
export class DatabaseService {
  constructor(private config: ConfigService) {}

  getUrl(): string {
    return this.config.get<string>("DATABASE_URL");
  }

  getPort(): number {
    return this.config.get<number>("PORT", 3000); // default value
  }
}
```

### Config con namespacing

```typescript
// config/database.config.ts
import { registerAs } from "@nestjs/config";

export default registerAs("database", () => ({
  url: process.env.DATABASE_URL,
  host: process.env.DB_HOST || "localhost",
  port: parseInt(process.env.DB_PORT, 10) || 5432,
  name: process.env.DB_NAME,
  username: process.env.DB_USER,
  password: process.env.DB_PASS,
}));

// app.module.ts
ConfigModule.forRoot({ load: [databaseConfig] });

// Uso:
const dbUrl = this.config.get<string>("database.url");
```

### Validación de variables de entorno con Joi

```bash
pnpm add joi
```

```typescript
import * as Joi from "joi";

ConfigModule.forRoot({
  validationSchema: Joi.object({
    NODE_ENV: Joi.string()
      .valid("development", "production", "test")
      .default("development"),
    PORT: Joi.number().default(3000),
    DATABASE_URL: Joi.string().required(),
    JWT_SECRET: Joi.string().min(32).required(),
    JWT_EXPIRES_IN: Joi.string().default("15m"),
    REDIS_URL: Joi.string().required(),
  }),
  validationOptions: {
    allowUnknown: true,
    abortEarly: false, // muestra todos los errores, no solo el primero
  },
});
```

### Validación con Zod (alternativa moderna)

```typescript
// config/env.validation.ts
import { z } from "zod";

export const envSchema = z.object({
  NODE_ENV: z
    .enum(["development", "production", "test"])
    .default("development"),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  JWT_EXPIRES_IN: z.string().default("15m"),
  REDIS_URL: z.string(),
});

export type Env = z.infer<typeof envSchema>;

// Validar al inicio (en main.ts o en config factory):
const env = envSchema.parse(process.env);
```

---

## 3. Variables de entorno (.env)

```env
# App
NODE_ENV=development
PORT=3000

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/mydb

# JWT
JWT_SECRET=your-super-secret-key-minimum-32-characters
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Frontend (CORS)
FRONTEND_URL=http://localhost:3001
```

---

## 4. Validación de query params con DTOs

```typescript
// dto/pagination.dto.ts
import { IsOptional, IsInt, Min, Max, IsString, IsEnum } from 'class-validator';
import { Type } from 'class-transformer';

export enum SortOrder { ASC = 'asc', DESC = 'desc' }

export class PaginationDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20;

  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsEnum(SortOrder)
  order?: SortOrder = SortOrder.DESC;
}

// Controller:
@Get()
findAll(@Query() pagination: PaginationDto) {
  return this.service.findAll(pagination);
}
```

---

## 5. Respuesta paginada estándar

```typescript
// interfaces/paginated-result.interface.ts
export interface PaginatedResult<T> {
  data: T[];
  meta: {
    total: number;
    page: number;
    limit: number;
    totalPages: number;
  };
}

// En service:
async findAll(dto: PaginationDto): Promise<PaginatedResult<Car>> {
  const { page, limit } = dto;
  const skip = (page - 1) * limit;

  const [data, total] = await this.prisma.$transaction([
    this.prisma.car.findMany({ skip, take: limit }),
    this.prisma.car.count(),
  ]);

  return {
    data,
    meta: {
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    },
  };
}
```
