# NestJS — Configuration (@nestjs/config)

**Fuente:** https://docs.nestjs.com/techniques/configuration

## Instalación

```bash
pnpm add @nestjs/config
```

## Setup básico (root module)

```typescript
// app.module.ts
import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true, // accesible en todos los módulos sin importar
      envFilePath: ".env", // default: .env en root
    }),
  ],
})
export class AppModule {}
```

## Múltiples archivos .env

```typescript
ConfigModule.forRoot({
  envFilePath: [".env.local", ".env"], // primer archivo tiene precedencia
});
```

## Usar ConfigService

```typescript
import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

@Injectable()
export class AppService {
  constructor(private configService: ConfigService) {}

  getPort() {
    return this.configService.get<number>("PORT");
  }

  // Con valor por defecto
  getDbUrl() {
    return this.configService.get<string>(
      "DATABASE_URL",
      "postgresql://localhost",
    );
  }
}
```

## Custom configuration files (namespaced)

```typescript
// config/database.config.ts
import { registerAs } from "@nestjs/config";

export default registerAs("database", () => ({
  host: process.env.DB_HOST || "localhost",
  port: parseInt(process.env.DB_PORT, 10) || 5432,
  username: process.env.DB_USER,
  password: process.env.DB_PASS,
  name: process.env.DB_NAME,
}));

// app.module.ts
import databaseConfig from "./config/database.config";

ConfigModule.forRoot({
  load: [databaseConfig],
});

// Uso:
const dbHost = this.configService.get<string>("database.host");
const dbConfig = this.configService.get("database"); // objeto completo
```

## Inyección tipada de configuración (ConfigType)

```typescript
import { ConfigType } from "@nestjs/config";
import databaseConfig from "./config/database.config";

@Injectable()
export class DatabaseService {
  constructor(
    @Inject(databaseConfig.KEY)
    private dbConfig: ConfigType<typeof databaseConfig>,
  ) {
    // Autocompletado completo
    console.log(this.dbConfig.host);
    console.log(this.dbConfig.port);
  }
}
```

## Schema validation con Joi

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
  }),
  validationOptions: {
    allowUnknown: true, // ignora variables no declaradas
    abortEarly: false, // reporta todos los errores, no solo el primero
  },
});
```

## Schema validation con class-validator

```typescript
import { plainToInstance } from "class-transformer";
import { IsEnum, IsNumber, IsString, validateSync } from "class-validator";

enum Environment {
  Development = "development",
  Production = "production",
  Test = "test",
}

class EnvironmentVariables {
  @IsEnum(Environment)
  NODE_ENV: Environment;

  @IsNumber()
  PORT: number;

  @IsString()
  DATABASE_URL: string;

  @IsString()
  JWT_SECRET: string;
}

function validate(config: Record<string, unknown>) {
  const validatedConfig = plainToInstance(EnvironmentVariables, config, {
    enableImplicitConversion: true,
  });
  const errors = validateSync(validatedConfig, {
    skipMissingProperties: false,
  });
  if (errors.length > 0) {
    throw new Error(errors.toString());
  }
  return validatedConfig;
}

ConfigModule.forRoot({ validate });
```

## Expandable variables (.env)

```bash
# .env
APP_URL=mywebsite.com
SUPPORT_EMAIL=support@${APP_URL}  # soportado con expand: true
```

```typescript
ConfigModule.forRoot({ expandVariables: true });
```

## Usar en main.ts (antes del app bootstrap)

```typescript
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);
  const port = configService.get<number>("PORT") ?? 3000;
  await app.listen(port);
}
```

## Ejemplo .env completo

```bash
# App
NODE_ENV=development
PORT=3000

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/mydb

# JWT
JWT_SECRET=super-secret-key-at-least-32-chars-long
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# CORS
ALLOWED_ORIGINS=http://localhost:3000,https://myapp.com
```
