# NestJS — Core Concepts: Modules, Controllers, Providers

## 1. Módulos

El bloque fundamental de organización. Toda app tiene al menos `AppModule`.

```typescript
// cats/cats.module.ts
import { Module } from "@nestjs/common";
import { CatsController } from "./cats.controller";
import { CatsService } from "./cats.service";
import { TypeOrmModule } from "@nestjs/typeorm";

@Module({
  imports: [TypeOrmModule.forFeature([Cat])], // módulos externos
  controllers: [CatsController], // controllers de este módulo
  providers: [CatsService], // services, repos, etc.
  exports: [CatsService], // lo que otros módulos pueden usar
})
export class CatsModule {}
```

### Módulo Global

```typescript
@Global()
@Module({ providers: [SharedService], exports: [SharedService] })
export class SharedModule {}
// Registrar una sola vez en AppModule — no importar en cada módulo
```

### Módulo Dinámico

```typescript
@Module({})
export class DatabaseModule {
  static forRoot(options: DatabaseOptions): DynamicModule {
    return {
      module: DatabaseModule,
      providers: [createDatabaseProvider(options)],
      exports: [DATABASE_PROVIDER],
    };
  }
}
// Uso: DatabaseModule.forRoot({ host: 'localhost' })
```

---

## 2. Controllers

Manejan las rutas HTTP. Solo routing y delegación — la lógica va en services.

```typescript
// cats/cats.controller.ts
import {
  Controller,
  Get,
  Post,
  Put,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  Headers,
  Req,
  Res,
  HttpCode,
  HttpStatus,
  UseGuards,
  UseInterceptors,
  ParseIntPipe,
  ParseUUIDPipe,
} from "@nestjs/common";
import { CatsService } from "./cats.service";
import { CreateCatDto } from "./dto/create-cat.dto";
import { UpdateCatDto } from "./dto/update-cat.dto";

@Controller("cats") // prefijo de ruta: /cats
export class CatsController {
  constructor(private readonly catsService: CatsService) {}

  @Get()
  findAll(@Query("limit") limit?: number) {
    return this.catsService.findAll(limit);
  }

  @Get(":id")
  findOne(@Param("id", ParseUUIDPipe) id: string) {
    return this.catsService.findOne(id);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() createCatDto: CreateCatDto) {
    return this.catsService.create(createCatDto);
  }

  @Patch(":id")
  update(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() updateCatDto: UpdateCatDto,
  ) {
    return this.catsService.update(id, updateCatDto);
  }

  @Delete(":id")
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param("id", ParseUUIDPipe) id: string) {
    return this.catsService.remove(id);
  }
}
```

### Decoradores de parámetros útiles

| Decorador          | Descripción                                   |
| ------------------ | --------------------------------------------- |
| `@Body()`          | Request body completo                         |
| `@Body('name')`    | Campo específico del body                     |
| `@Param('id')`     | Parámetro de ruta                             |
| `@Query('page')`   | Query string param                            |
| `@Headers('auth')` | Header específico                             |
| `@Req()`           | Request object (Express)                      |
| `@Res()`           | Response object (cuidado: rompe interceptors) |
| `@UploadedFile()`  | Archivo subido                                |

---

## 3. Providers (Services)

Contienen la lógica de negocio. Son inyectables via DI.

```typescript
// cats/cats.service.ts
import { Injectable, NotFoundException } from "@nestjs/common";
import { InjectRepository } from "@nestjs/typeorm";
import { Repository } from "typeorm";
import { Cat } from "./entities/cat.entity";
import { CreateCatDto } from "./dto/create-cat.dto";

@Injectable()
export class CatsService {
  constructor(
    @InjectRepository(Cat)
    private readonly catRepository: Repository<Cat>,
  ) {}

  async findAll(): Promise<Cat[]> {
    return this.catRepository.find();
  }

  async findOne(id: string): Promise<Cat> {
    const cat = await this.catRepository.findOneBy({ id });
    if (!cat) throw new NotFoundException(`Cat #${id} not found`);
    return cat;
  }

  async create(createCatDto: CreateCatDto): Promise<Cat> {
    const cat = this.catRepository.create(createCatDto);
    return this.catRepository.save(cat);
  }

  async update(id: string, updateCatDto: UpdateCatDto): Promise<Cat> {
    const cat = await this.findOne(id); // lanza NotFoundException si no existe
    Object.assign(cat, updateCatDto);
    return this.catRepository.save(cat);
  }

  async remove(id: string): Promise<void> {
    const cat = await this.findOne(id);
    await this.catRepository.remove(cat);
  }
}
```

---

## 4. Dependency Injection (DI)

### Registro básico (class provider)

```typescript
@Module({ providers: [CatsService] })
// Equivalente a:
@Module({ providers: [{ provide: CatsService, useClass: CatsService }] })
```

### Value provider (constantes, config)

```typescript
const config = { apiUrl: "https://api.example.com" };

@Module({
  providers: [{ provide: "APP_CONFIG", useValue: config }],
})
export class AppModule {}

// Inyección:
@Injectable()
export class AppService {
  constructor(@Inject("APP_CONFIG") private config: typeof config) {}
}
```

### Factory provider (lógica de creación)

```typescript
@Module({
  providers: [
    {
      provide: 'ASYNC_SERVICE',
      useFactory: async (config: ConfigService) => {
        const options = await config.get('serviceOptions');
        return new ComplexService(options);
      },
      inject: [ConfigService],
    },
  ],
})
```

### Scopes de providers

```typescript
@Injectable({ scope: Scope.DEFAULT })   // Singleton (default) — compartido
@Injectable({ scope: Scope.REQUEST })   // Nueva instancia por request
@Injectable({ scope: Scope.TRANSIENT }) // Nueva instancia por inyección
```

---

## 5. Middleware

Función que se ejecuta ANTES del pipeline (antes de guards).

```typescript
// common/middleware/logger.middleware.ts
import { Injectable, NestMiddleware } from "@nestjs/common";
import { Request, Response, NextFunction } from "express";

@Injectable()
export class LoggerMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    console.log(`[${req.method}] ${req.url}`);
    next();
  }
}

// Aplicar en módulo:
@Module({ controllers: [CatsController] })
export class CatsModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggerMiddleware).forRoutes(CatsController); // o 'cats', o { path: 'cats', method: RequestMethod.GET }
  }
}

// Global (en main.ts):
app.use(loggerMiddleware); // solo funcional (no clases con DI)
```

---

## 6. Exception Handling

### Excepciones HTTP built-in

```typescript
throw new BadRequestException("Mensaje");
throw new UnauthorizedException();
throw new ForbiddenException("No tienes permisos");
throw new NotFoundException(`Item #${id} not found`);
throw new ConflictException("Email ya existe");
throw new UnprocessableEntityException({ errors });
throw new InternalServerErrorException();

// Con detalles:
throw new BadRequestException({
  message: "Validation failed",
  errors: [{ field: "email", error: "invalid format" }],
});
```

### Exception Filter personalizado

```typescript
// common/filters/http-exception.filter.ts
import {
  ExceptionFilter, Catch, ArgumentsHost,
  HttpException, HttpStatus,
} from '@nestjs/common';
import { Request, Response } from 'express';

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  catch(exception: HttpException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request>();
    const status = exception.getStatus();
    const exceptionResponse = exception.getResponse();

    res.status(status).json({
      statusCode: status,
      timestamp: new Date().toISOString(),
      path: req.url,
      message:
        typeof exceptionResponse === 'object'
          ? (exceptionResponse as any).message
          : exceptionResponse,
    });
  }
}

// Aplicar globalmente en main.ts:
app.useGlobalFilters(new HttpExceptionFilter());
// O en módulo (con DI):
@Module({ providers: [{ provide: APP_FILTER, useClass: HttpExceptionFilter }] })
```

---

## 7. Custom Decorators

```typescript
// decorators/current-user.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const CurrentUser = createParamDecorator(
  (data: string, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user;
    return data ? user?.[data] : user;
  },
);

// Uso en controller:
@Get('me')
getMe(@CurrentUser() user: User) { return user; }
@Get('email')
getEmail(@CurrentUser('email') email: string) { return email; }
```

```typescript
// decorators/public.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

// Uso:
@Public()
@Get('health')
healthCheck() { return { status: 'ok' }; }
```
