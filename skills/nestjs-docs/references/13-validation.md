# NestJS — Validation

**Fuente:** https://docs.nestjs.com/techniques/validation

## Setup global (RECOMENDADO)

```typescript
// main.ts
import { ValidationPipe } from "@nestjs/common";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true, // elimina campos sin decoradores @Is*
      forbidNonWhitelisted: true, // 400 si hay campos inesperados
      transform: true, // transforma tipos automáticamente
      transformOptions: {
        enableImplicitConversion: true, // string "3" → number 3
      },
    }),
  );
  await app.listen(3000);
}
```

## Dependencias

```bash
pnpm add class-validator class-transformer
```

## DTO completo con validaciones

```typescript
import {
  IsString,
  IsEmail,
  IsNumber,
  IsEnum,
  IsOptional,
  IsBoolean,
  IsArray,
  IsUUID,
  IsDate,
  IsUrl,
  IsPhoneNumber,
  MinLength,
  MaxLength,
  Min,
  Max,
  Matches,
  ValidateNested,
  ArrayMinSize,
} from "class-validator";
import { Type } from "class-transformer";

export enum UserRole {
  ADMIN = "admin",
  USER = "user",
  PROVIDER = "provider",
}

export class CreateUserDto {
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  name: string;

  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  @Matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/, {
    message: "Password must contain uppercase, lowercase, and number",
  })
  password: string;

  @IsOptional()
  @IsPhoneNumber("DO") // código ISO del país
  phone?: string;

  @IsEnum(UserRole)
  role: UserRole;

  @IsOptional()
  @IsNumber()
  @Min(18)
  @Max(120)
  age?: number;

  @IsOptional()
  @IsArray()
  @IsString({ each: true }) // valida cada elemento del array
  tags?: string[];
}
```

## Nested objects validation

```typescript
export class AddressDto {
  @IsString() street: string;
  @IsString() city: string;
  @IsString() country: string;
}

export class CreateUserDto {
  @ValidateNested()
  @Type(() => AddressDto) // class-transformer necesita esto
  address: AddressDto;
}
```

## Arrays de objetos

```typescript
export class BulkCreateDto {
  @IsArray()
  @ValidateNested({ each: true })
  @ArrayMinSize(1)
  @Type(() => CreateUserDto)
  users: CreateUserDto[];
}
```

## Mapped Types (DTOs reutilizables)

```typescript
import {
  PartialType,
  OmitType,
  PickType,
  IntersectionType,
} from "@nestjs/mapped-types";
// Para Swagger: importar de @nestjs/swagger en su lugar

// Update: todos los campos opcionales
export class UpdateUserDto extends PartialType(CreateUserDto) {}

// Sin password
export class PublicUserDto extends OmitType(CreateUserDto, [
  "password",
] as const) {}

// Solo email y password
export class LoginDto extends PickType(CreateUserDto, [
  "email",
  "password",
] as const) {}

// Combinar DTOs
export class FullProfileDto extends IntersectionType(
  CreateUserDto,
  AddressDto,
) {}
```

## Validación manual (fuera de pipe)

```typescript
import { validate } from "class-validator";
import { plainToInstance } from "class-transformer";

const dto = plainToInstance(CreateUserDto, { email: "bad", name: "a" });
const errors = await validate(dto);
if (errors.length > 0) {
  throw new BadRequestException(errors);
}
```

## Custom validator

```typescript
import { registerDecorator, ValidationOptions, ValidationArguments } from 'class-validator';

export function IsPasswordStrong(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'isPasswordStrong',
      target: object.constructor,
      propertyName,
      constraints: [],
      options: validationOptions,
      validator: {
        validate(value: any) {
          return typeof value === 'string' && value.length >= 8 && /[A-Z]/.test(value);
        },
        defaultMessage(args: ValidationArguments) {
          return `${args.property} is too weak`;
        },
      },
    });
  };
}

// Uso en DTO:
@IsPasswordStrong({ message: 'Password too weak' })
password: string;
```

## Grupos de validación

```typescript
export class CreateUserDto {
  @IsString({ groups: ["create"] })
  @IsOptional({ groups: ["update"] })
  name: string;
}

// Aplicar grupo:
new ValidationPipe({ groups: ["create"] });
```

## Transformación con class-transformer

```typescript
import { Transform, Type, Exclude, Expose } from "class-transformer";

export class UserResponseDto {
  @Expose()
  id: string;

  @Expose()
  name: string;

  @Exclude() // nunca en la respuesta
  password: string;

  @Transform(({ value }) => value.toUpperCase())
  role: string;

  @Type(() => Date)
  createdAt: Date;
}

// Usar con ClassSerializerInterceptor global:
app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));
```
