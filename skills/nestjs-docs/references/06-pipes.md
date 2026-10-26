# NestJS — Pipes

**Fuente:** https://docs.nestjs.com/pipes

## Concepto

Un Pipe es una clase `@Injectable()` que implementa `PipeTransform`. Se ejecuta ANTES del route handler y sirve para:

- **Transformación**: convertir datos de entrada (ej: string → number)
- **Validación**: evaluar datos; si son inválidos lanzar excepción

## Built-in Pipes (de @nestjs/common)

```typescript
ValidationPipe; // valida DTOs con class-validator
ParseIntPipe; // string → number (entero)
ParseFloatPipe; // string → number (float)
ParseBoolPipe; // string → boolean
ParseArrayPipe; // string → array
ParseUUIDPipe; // valida UUID
ParseEnumPipe; // valida enum
DefaultValuePipe; // valor por defecto si undefined/null
ParseFilePipe; // validación de archivos
ParseDatePipe; // string → Date
```

## Binding pipes en parámetros

```typescript
// Por clase (Nest instancia)
@Get(':id')
findOne(@Param('id', ParseIntPipe) id: number) {
  return this.catsService.findOne(id);
}

// Por instancia (configuración custom)
@Get(':id')
findOne(
  @Param('id', new ParseIntPipe({ errorHttpStatusCode: HttpStatus.NOT_ACCEPTABLE }))
  id: number,
) {}

// UUID
@Get(':uuid')
findOne(@Param('uuid', new ParseUUIDPipe()) uuid: string) {}

// Query param
@Get()
findAll(@Query('id', ParseIntPipe) id: number) {}
```

## ValidationPipe — Uso básico

```typescript
// main.ts — aplicar globalmente (RECOMENDADO)
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true, // elimina propiedades sin decoradores
      forbidNonWhitelisted: true, // lanza error si hay props extra
      transform: true, // transforma tipos automáticamente
    }),
  );
  await app.listen(3000);
}
```

## DTOs con class-validator

```typescript
import {
  IsString,
  IsInt,
  IsEmail,
  IsOptional,
  MinLength,
  Min,
  Max,
  IsEnum,
} from "class-validator";

export class CreateUserDto {
  @IsString()
  @MinLength(2)
  name: string;

  @IsEmail()
  email: string;

  @IsInt()
  @Min(18)
  @Max(120)
  age: number;

  @IsOptional()
  @IsString()
  bio?: string;

  @IsEnum(UserRole)
  role: UserRole;
}
```

## Validación de arrays

```typescript
@Post()
createBulk(
  @Body(new ParseArrayPipe({ items: CreateCatDto }))
  createCatDtos: CreateCatDto[],
) {}
```

## Custom Pipe

```typescript
import { PipeTransform, Injectable, ArgumentMetadata, BadRequestException } from '@nestjs/common';

@Injectable()
export class ParsePositiveIntPipe implements PipeTransform<string, number> {
  transform(value: string, metadata: ArgumentMetadata): number {
    const val = parseInt(value, 10);
    if (isNaN(val) || val <= 0) {
      throw new BadRequestException(`"${value}" is not a positive integer`);
    }
    return val;
  }
}

// Uso:
@Get(':id')
findOne(@Param('id', ParsePositiveIntPipe) id: number) {}
```

## Opciones ValidationPipe

```typescript
new ValidationPipe({
  whitelist: true, // elimina campos sin @IsXxx
  forbidNonWhitelisted: true, // 400 si hay campos extra
  transform: true, // auto-transform a tipos TypeScript
  disableErrorMessages: false, // true en producción opcionalmente
  stopAtFirstError: false, // true = para en el primer error
  exceptionFactory: (errors) => new BadRequestException(errors), // custom error
});
```

## Mapped Types para DTO reutilizables

```typescript
import {
  PartialType,
  OmitType,
  PickType,
  IntersectionType,
} from "@nestjs/mapped-types";

// Todos los campos opcionales
export class UpdateCatDto extends PartialType(CreateCatDto) {}

// Sin campo 'password'
export class PublicUserDto extends OmitType(CreateUserDto, [
  "password",
] as const) {}

// Solo campos seleccionados
export class LoginDto extends PickType(CreateUserDto, [
  "email",
  "password",
] as const) {}

// Combinar dos DTOs
export class FullUserDto extends IntersectionType(CreateUserDto, AddressDto) {}
```

> ✅ `@nestjs/swagger` exporta versiones de estos mapped types que también generan la documentación OpenAPI correctamente.

## ValidationPipe en ruta específica

```typescript
@UsePipes(new ValidationPipe({ transform: true }))
@Post()
create(@Body() createCatDto: CreateCatDto) {}
```

## DefaultValuePipe

```typescript
@Get()
findAll(
  @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
  @Query('limit', new DefaultValuePipe(10), ParseIntPipe) limit: number,
) {}
```

## Decoradores class-validator más usados

```typescript
@IsString()        @IsNumber()       @IsBoolean()      @IsArray()
@IsEmail()         @IsUrl()          @IsUUID()         @IsDate()
@IsEnum(Enum)      @IsOptional()     @IsNotEmpty()     @IsDefined()
@Min(n)            @Max(n)           @MinLength(n)     @MaxLength(n)
@Matches(regex)    @IsIn(array)      @IsPositive()     @IsNegative()
@ValidateNested()  @Type(() => Cls)  @ArrayMinSize(n)  @ArrayMaxSize(n)
```
