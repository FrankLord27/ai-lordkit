# NestJS — Exception Filters

**Fuente:** https://docs.nestjs.com/exception-filters

## Concepto

Nest tiene una capa de excepciones integrada que procesa todas las excepciones no manejadas. Cuando una excepción no es capturada por el código, esta capa la atrapa y envía una response apropiada.

## Lanzar excepciones HTTP estándar

```typescript
// HttpException básico
throw new HttpException("Forbidden", HttpStatus.FORBIDDEN);
// Response: { "statusCode": 403, "message": "Forbidden" }

// Con objeto completo
throw new HttpException(
  {
    status: HttpStatus.FORBIDDEN,
    error: "This is a custom message",
  },
  HttpStatus.FORBIDDEN,
  {
    cause: originalError, // para logging, no se serializa en response
  },
);

// Excepciones específicas built-in
throw new BadRequestException("Validation failed");
throw new UnauthorizedException();
throw new ForbiddenException("Access denied");
throw new NotFoundException(`User #${id} not found`);
throw new ConflictException("Email already exists");
throw new UnprocessableEntityException();
throw new InternalServerErrorException();
```

## Excepciones HTTP built-in

```typescript
// Todas disponibles en @nestjs/common:
BadRequestException; // 400
UnauthorizedException; // 401
ForbiddenException; // 403
NotFoundException; // 404
MethodNotAllowedException; // 405
NotAcceptableException; // 406
RequestTimeoutException; // 408
ConflictException; // 409
GoneException; // 410
PayloadTooLargeException; // 413
UnsupportedMediaTypeException; // 415
UnprocessableEntityException; // 422
TooManyRequestsException; // 429
InternalServerErrorException; // 500
NotImplementedException; // 501
BadGatewayException; // 502
ServiceUnavailableException; // 503
GatewayTimeoutException; // 504
```

## Excepción personalizada

```typescript
export class UserNotFoundException extends NotFoundException {
  constructor(userId: string) {
    super(`User with ID "${userId}" not found`, "USER_NOT_FOUND");
  }
}

// Uso:
throw new UserNotFoundException(id);
```

## Exception Filter personalizado

```typescript
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
} from "@nestjs/common";
import { HttpAdapterHost } from "@nestjs/core";

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  catch(exception: HttpException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse();
    const request = ctx.getRequest();
    const status = exception.getStatus();
    const exceptionResponse = exception.getResponse();

    const errorResponse = {
      statusCode: status,
      timestamp: new Date().toISOString(),
      path: request.url,
      message:
        typeof exceptionResponse === "string"
          ? exceptionResponse
          : (exceptionResponse as any).message,
    };

    response.status(status).json(errorResponse);
  }
}
```

## Catch-all filter (todas las excepciones)

```typescript
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  constructor(private readonly httpAdapterHost: HttpAdapterHost) {}

  catch(exception: unknown, host: ArgumentsHost): void {
    const { httpAdapter } = this.httpAdapterHost;
    const ctx = host.switchToHttp();

    const httpStatus =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const responseBody = {
      statusCode: httpStatus,
      timestamp: new Date().toISOString(),
      path: httpAdapter.getRequestUrl(ctx.getRequest()),
    };

    httpAdapter.reply(ctx.getResponse(), responseBody, httpStatus);
  }
}
```

## Aplicar filters

### En método

```typescript
@Post()
@UseFilters(HttpExceptionFilter)
create(@Body() createCatDto: CreateCatDto) {}
```

### En controller (todos los métodos)

```typescript
@UseFilters(new HttpExceptionFilter())
export class CatsController {}
```

### Global (recomendado para producción)

```typescript
// main.ts
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.useGlobalFilters(new AllExceptionsFilter());
  await app.listen(3000);
}

// O con DI support:
// app.module.ts
@Module({
  providers: [
    {
      provide: APP_FILTER,
      useClass: AllExceptionsFilter,
    },
  ],
})
```

## Extender el filtro global built-in

```typescript
import { Catch, ArgumentsHost } from "@nestjs/common";
import { BaseExceptionFilter } from "@nestjs/core";

@Catch()
export class AllExceptionsFilter extends BaseExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    // lógica extra antes de delegar
    console.error("Exception caught:", exception);
    super.catch(exception, host); // delega al filtro base
  }
}
```

## ArgumentsHost

El `host` permite cambiar de contexto (HTTP, WebSocket, microservicio):

```typescript
catch(exception: unknown, host: ArgumentsHost) {
  // HTTP
  const ctx = host.switchToHttp();
  const req = ctx.getRequest<Request>();
  const res = ctx.getResponse<Response>();

  // WebSocket
  const wsCtx = host.switchToWs();
  const client = wsCtx.getClient();

  // Microservice
  const rpcCtx = host.switchToRpc();
  const data = rpcCtx.getData();
}
```
