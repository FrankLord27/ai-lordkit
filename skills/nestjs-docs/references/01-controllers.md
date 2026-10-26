# NestJS — Controllers

**Fuente:** https://docs.nestjs.com/controllers

## Concepto

Los controllers manejan **requests entrantes** y devuelven **responses** al cliente. El mecanismo de routing determina qué controller maneja cada request. Un controller tiene múltiples routes, cada una puede realizar una acción diferente.

```typescript
import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Patch,
  Body,
  Param,
  Query,
  HttpCode,
  Header,
  Redirect,
} from "@nestjs/common";
import { CreateCatDto } from "./dto/create-cat.dto";

@Controller("cats")
export class CatsController {
  @Post()
  create(@Body() createCatDto: CreateCatDto) {
    return "This action adds a new cat";
  }

  @Get()
  findAll(@Query("age") age: number, @Query("breed") breed: string) {
    return `Filtered by age: ${age} and breed: ${breed}`;
  }

  @Get(":id")
  findOne(@Param("id") id: string) {
    return `Cat #${id}`;
  }

  @Put(":id")
  update(@Param("id") id: string, @Body() updateCatDto: UpdateCatDto) {
    return `Updated cat #${id}`;
  }

  @Delete(":id")
  remove(@Param("id") id: string) {
    return `Removed cat #${id}`;
  }
}
```

## Registrar en módulo

```typescript
@Module({
  controllers: [CatsController],
})
export class AppModule {}
```

## Decoradores de parámetros

| Decorador             | Equivalente Express               |
| --------------------- | --------------------------------- |
| `@Request(), @Req()`  | `req`                             |
| `@Response(), @Res()` | `res`                             |
| `@Next()`             | `next`                            |
| `@Session()`          | `req.session`                     |
| `@Param(key?)`        | `req.params / req.params[key]`    |
| `@Body(key?)`         | `req.body / req.body[key]`        |
| `@Query(key?)`        | `req.query / req.query[key]`      |
| `@Headers(name?)`     | `req.headers / req.headers[name]` |
| `@Ip()`               | `req.ip`                          |
| `@HostParam()`        | `req.hosts`                       |

## Status codes

- Default: **200** (todos los métodos)
- POST default: **201**
- Cambiar con `@HttpCode(204)`

```typescript
@Post()
@HttpCode(204)
create() { return; }
```

## Route parameters

```typescript
@Get(':id')
findOne(@Param('id') id: string): string {
  return `Cat #${id}`;
}

// Múltiples params
@Get(':userId/cats/:catId')
findOne(@Param('userId') userId: string, @Param('catId') catId: string) {}
```

## Wildcards

```typescript
@Get('abcd/*')   // coincide con abcd/, abcd/123, etc.
findAll() {}
```

## Sub-domain routing

```typescript
@Controller({ host: ":account.example.com" })
export class AccountController {
  @Get()
  getInfo(@HostParam("account") account: string) {
    return account;
  }
}
```

## Async handlers

```typescript
@Get()
async findAll(): Promise<Cat[]> {
  return this.catsService.findAll();
}

// También acepta RxJS Observables
@Get()
findAll(): Observable<Cat[]> {
  return of([]);
}
```

## Respuesta estándar vs library-specific

**Estándar (recomendado):**

```typescript
@Get()
findAll() {
  return []; // Nest serializa automáticamente a JSON
}
```

**Library-specific** (solo cuando necesitas control total de headers/cookies):

```typescript
@Get()
findAll(@Res({ passthrough: true }) res: Response) {
  res.status(HttpStatus.OK);
  return [];
}
```

> ⚠️ `passthrough: true` es OBLIGATORIO si quieres que Nest siga manejando la response. Sin `passthrough`, debes llamar `res.json()` / `res.send()` manualmente y los interceptors NO funcionan.

## DTOs (Data Transfer Objects)

```typescript
// Usar CLASES no interfaces (las interfaces desaparecen en transpilación)
export class CreateCatDto {
  name: string;
  age: number;
  breed: string;
}
```

## Generador CLI

```bash
nest g controller cats        # genera cats.controller.ts
nest g resource cats          # genera módulo completo CRUD con validación
```

## Redirect dinámico

```typescript
@Get('docs')
@Redirect('https://docs.nestjs.com', 302)
getDocs(@Query('version') version: string) {
  if (version === '5') {
    return { url: 'https://docs.nestjs.com/v5/' }; // override
  }
}
```

## Headers custom

```typescript
@Post()
@Header('Cache-Control', 'no-store')
create() {}
```
