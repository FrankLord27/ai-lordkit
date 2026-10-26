# Integración Óptima: NestJS 11 + Prisma 7

Este documento muestra cómo integrar NestJS 11 y Prisma 7 de manera óptima, aprovechando lo mejor de cada tecnología para crear una arquitectura robusta, mantenible y eficiente.

---

## Arquitectura de capas

```
┌─────────────────────────────────────────────────────────────┐
│                        Controller                            │
│  - Recibe HTTP requests                                      │
│  - Valida DTOs (ValidationPipe)                              │
│  - Delega al Service                                         │
│  - NO conoce Prisma directamente                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Service                              │
│  - Lógica de negocio                                         │
│  - Orquesta Repository + otros services                      │
│  - Maneja transacciones                                      │
│  - Transforma entidades a DTOs de respuesta                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       Repository                             │
│  - Acceso a datos via Prisma                                 │
│  - Queries optimizadas                                       │
│  - Retorna entidades Prisma                                  │
│  - Encapsula complejidad de queries                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      PrismaService                           │
│  - Cliente Prisma 7 con driver adapter                       │
│  - Extensiones ($extends): soft delete, audit                │
│  - Singleton global (@Global)                                │
└─────────────────────────────────────────────────────────────┘
```

---

## PrismaService completo (Prisma 7)

```typescript
// src/prisma/prisma.service.ts
import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  Logger,
} from "@nestjs/common";
import { PrismaClient } from "../generated/prisma/client.js";
import { PrismaPg } from "@prisma/adapter-pg";
import { ClsService } from "nestjs-cls";
import pg from "pg";

// Configuración del pool de conexiones
const createPool = () =>
  new pg.Pool({
    connectionString: process.env.DATABASE_URL,
    max: parseInt(process.env.DB_POOL_MAX ?? "20"),
    min: parseInt(process.env.DB_POOL_MIN ?? "5"),
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });

// Extensión de soft delete
function softDeleteExtension(prisma: PrismaClient) {
  return prisma.$extends({
    name: "softDelete",
    model: {
      $allModels: {
        async softDelete<T>(this: T, where: any) {
          const context = this as any;
          return context.update({ where, data: { deletedAt: new Date() } });
        },
        async restore<T>(this: T, where: any) {
          const context = this as any;
          return context.update({ where, data: { deletedAt: null } });
        },
      },
    },
    query: {
      $allModels: {
        async findMany({ args, query }) {
          args.where = { ...args.where, deletedAt: null };
          return query(args);
        },
        async findFirst({ args, query }) {
          args.where = { ...args.where, deletedAt: null };
          return query(args);
        },
        async count({ args, query }) {
          args.where = { ...args.where, deletedAt: null };
          return query(args);
        },
      },
    },
  });
}

// Extensión de auditoría
function auditExtension(cls: ClsService) {
  return (prisma: PrismaClient) =>
    prisma.$extends({
      name: "audit",
      query: {
        $allModels: {
          async create({ args, query }) {
            const userId = cls.get("userId");
            const tenantId = cls.get("tenantId");
            if (userId) args.data.createdById = userId;
            if (tenantId && !args.data.tenantId) args.data.tenantId = tenantId;
            return query(args);
          },
          async update({ args, query }) {
            const userId = cls.get("userId");
            if (userId) args.data.updatedById = userId;
            return query(args);
          },
        },
      },
    });
}

@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);
  public readonly client: ReturnType<typeof this.createExtendedClient>;

  constructor(private readonly cls: ClsService) {
    this.client = this.createExtendedClient();
  }

  private createExtendedClient() {
    const pool = createPool();
    const adapter = new PrismaPg(pool);

    const basePrisma = new PrismaClient({
      adapter,
      log:
        process.env.NODE_ENV === "development"
          ? [{ emit: "event", level: "query" }]
          : [],
    });

    // Encadenar extensiones
    return basePrisma
      .$extends(softDeleteExtension(basePrisma))
      .$extends(auditExtension(this.cls)(basePrisma));
  }

  async onModuleInit() {
    await this.client.$connect();
    this.logger.log("Database connected");

    // Log queries lentas en desarrollo
    if (process.env.NODE_ENV === "development") {
      (this.client as any).$on?.("query", (e: any) => {
        if (e.duration > 100) {
          this.logger.warn(`Slow query (${e.duration}ms): ${e.query}`);
        }
      });
    }
  }

  async onModuleDestroy() {
    await this.client.$disconnect();
    this.logger.log("Database disconnected");
  }

  // Helper para transacciones
  async transaction<T>(fn: (tx: typeof this.client) => Promise<T>): Promise<T> {
    return this.client.$transaction(fn);
  }
}
```

---

## PrismaModule global

```typescript
// src/prisma/prisma.module.ts
import { Global, Module } from "@nestjs/common";
import { PrismaService } from "./prisma.service";

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

---

## Repository Pattern

```typescript
// modules/tickets/repositories/ticket.repository.ts
import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../../prisma/prisma.service";
import { Prisma, Ticket } from "../../../generated/prisma/client.js";

export interface FindTicketsParams {
  tenantId: string;
  status?: string;
  assigneeId?: string;
  search?: string;
  page?: number;
  limit?: number;
}

@Injectable()
export class TicketRepository {
  constructor(private readonly prisma: PrismaService) {}

  async findMany(
    params: FindTicketsParams,
  ): Promise<{ data: Ticket[]; total: number }> {
    const {
      tenantId,
      status,
      assigneeId,
      search,
      page = 1,
      limit = 20,
    } = params;
    const skip = (page - 1) * limit;

    const where: Prisma.TicketWhereInput = {
      tenantId,
      ...(status && { status: status as any }),
      ...(assigneeId && { assigneeId }),
      ...(search && {
        OR: [
          { title: { contains: search, mode: "insensitive" } },
          { description: { contains: search, mode: "insensitive" } },
        ],
      }),
    };

    const [data, total] = await this.prisma.client.$transaction([
      this.prisma.client.ticket.findMany({
        where,
        include: {
          assignee: { select: { id: true, name: true, avatar: true } },
          createdBy: { select: { id: true, name: true } },
        },
        orderBy: { createdAt: "desc" },
        skip,
        take: limit,
      }),
      this.prisma.client.ticket.count({ where }),
    ]);

    return { data, total };
  }

  async findById(tenantId: string, id: string): Promise<Ticket | null> {
    return this.prisma.client.ticket.findFirst({
      where: { id, tenantId },
      include: {
        assignee: true,
        createdBy: true,
        comments: {
          include: {
            author: { select: { id: true, name: true, avatar: true } },
          },
          orderBy: { createdAt: "asc" },
        },
      },
    });
  }

  async create(
    tenantId: string,
    data: Prisma.TicketCreateInput,
  ): Promise<Ticket> {
    return this.prisma.client.ticket.create({
      data: { ...data, tenant: { connect: { id: tenantId } } },
      include: { assignee: true, createdBy: true },
    });
  }

  async update(
    tenantId: string,
    id: string,
    data: Prisma.TicketUpdateInput,
  ): Promise<Ticket> {
    return this.prisma.client.ticket.update({
      where: { id },
      data,
      include: { assignee: true },
    });
  }

  async softDelete(tenantId: string, id: string): Promise<Ticket> {
    // Verificar que pertenece al tenant antes de eliminar
    const ticket = await this.findById(tenantId, id);
    if (!ticket) throw new Error("Ticket not found");

    return this.prisma.client.ticket.softDelete({ id });
  }
}
```

---

## Service con lógica de negocio

```typescript
// modules/tickets/services/ticket.service.ts
import {
  Injectable,
  NotFoundException,
  ForbiddenException,
} from "@nestjs/common";
import {
  TicketRepository,
  FindTicketsParams,
} from "../repositories/ticket.repository";
import { CreateTicketDto, UpdateTicketDto, TicketResponseDto } from "../dto";
import { PrismaService } from "../../../prisma/prisma.service";
import { NotificationsService } from "../../notifications/notifications.service";

@Injectable()
export class TicketService {
  constructor(
    private readonly ticketRepo: TicketRepository,
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

  async findAll(
    tenantId: string,
    params: Omit<FindTicketsParams, "tenantId">,
  ): Promise<{
    data: TicketResponseDto[];
    total: number;
    page: number;
    limit: number;
  }> {
    const { data, total } = await this.ticketRepo.findMany({
      tenantId,
      ...params,
    });

    return {
      data: data.map((ticket) => this.toResponseDto(ticket)),
      total,
      page: params.page ?? 1,
      limit: params.limit ?? 20,
    };
  }

  async findOne(tenantId: string, id: string): Promise<TicketResponseDto> {
    const ticket = await this.ticketRepo.findById(tenantId, id);
    if (!ticket) throw new NotFoundException(`Ticket ${id} not found`);

    return this.toResponseDto(ticket);
  }

  async create(
    tenantId: string,
    userId: string,
    dto: CreateTicketDto,
  ): Promise<TicketResponseDto> {
    const ticket = await this.ticketRepo.create(tenantId, {
      title: dto.title,
      description: dto.description,
      priority: dto.priority,
      createdBy: { connect: { id: userId } },
      ...(dto.assigneeId && { assignee: { connect: { id: dto.assigneeId } } }),
    });

    // Notificar al asignado
    if (dto.assigneeId) {
      await this.notifications.send(dto.assigneeId, {
        type: "TICKET_ASSIGNED",
        ticketId: ticket.id,
        title: ticket.title,
      });
    }

    return this.toResponseDto(ticket);
  }

  async update(
    tenantId: string,
    id: string,
    userId: string,
    dto: UpdateTicketDto,
  ): Promise<TicketResponseDto> {
    const existing = await this.ticketRepo.findById(tenantId, id);
    if (!existing) throw new NotFoundException(`Ticket ${id} not found`);

    // Detectar cambio de asignado
    const assigneeChanged =
      dto.assigneeId && dto.assigneeId !== existing.assigneeId;

    const ticket = await this.ticketRepo.update(tenantId, id, {
      ...(dto.title && { title: dto.title }),
      ...(dto.description && { description: dto.description }),
      ...(dto.status && { status: dto.status }),
      ...(dto.priority && { priority: dto.priority }),
      ...(dto.assigneeId && { assignee: { connect: { id: dto.assigneeId } } }),
    });

    // Notificar nuevo asignado
    if (assigneeChanged && dto.assigneeId) {
      await this.notifications.send(dto.assigneeId, {
        type: "TICKET_ASSIGNED",
        ticketId: ticket.id,
        title: ticket.title,
      });
    }

    return this.toResponseDto(ticket);
  }

  async remove(tenantId: string, id: string): Promise<void> {
    await this.ticketRepo.softDelete(tenantId, id);
  }

  // Operación con transacción
  async closeWithResolution(
    tenantId: string,
    ticketId: string,
    userId: string,
    resolution: string,
  ): Promise<TicketResponseDto> {
    return this.prisma.transaction(async (tx) => {
      // Crear comentario de resolución
      await tx.comment.create({
        data: {
          content: resolution,
          ticketId,
          authorId: userId,
          isResolution: true,
        },
      });

      // Actualizar ticket
      const ticket = await tx.ticket.update({
        where: { id: ticketId },
        data: {
          status: "CLOSED",
          closedAt: new Date(),
          closedById: userId,
        },
        include: { assignee: true, createdBy: true },
      });

      // Notificar al creador
      await this.notifications.send(ticket.createdById, {
        type: "TICKET_CLOSED",
        ticketId: ticket.id,
        title: ticket.title,
      });

      return this.toResponseDto(ticket);
    });
  }

  // Transformar entidad a DTO (nunca exponer entidad directamente)
  private toResponseDto(ticket: any): TicketResponseDto {
    return {
      id: ticket.id,
      title: ticket.title,
      description: ticket.description,
      status: ticket.status,
      priority: ticket.priority,
      assignee: ticket.assignee
        ? {
            id: ticket.assignee.id,
            name: ticket.assignee.name,
            avatar: ticket.assignee.avatar,
          }
        : null,
      createdBy: {
        id: ticket.createdBy.id,
        name: ticket.createdBy.name,
      },
      createdAt: ticket.createdAt,
      updatedAt: ticket.updatedAt,
    };
  }
}
```

---

## Controller limpio

```typescript
// modules/tickets/tickets.controller.ts
import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Query,
  Body,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
  UseGuards,
} from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { TicketService } from "./services/ticket.service";
import { CreateTicketDto, UpdateTicketDto, FindTicketsQueryDto } from "./dto";
import { JwtAuthGuard } from "../auth/guards/jwt-auth.guard";
import { CurrentUser, CurrentTenant } from "../../common/decorators";

@ApiTags("Tickets")
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller({ path: "tickets", version: "1" })
export class TicketsController {
  constructor(private readonly ticketService: TicketService) {}

  @Get()
  @ApiOperation({ summary: "List tickets with pagination and filters" })
  findAll(
    @CurrentTenant() tenantId: string,
    @Query() query: FindTicketsQueryDto,
  ) {
    return this.ticketService.findAll(tenantId, query);
  }

  @Get(":id")
  @ApiOperation({ summary: "Get ticket by ID" })
  findOne(
    @CurrentTenant() tenantId: string,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.ticketService.findOne(tenantId, id);
  }

  @Post()
  @ApiOperation({ summary: "Create new ticket" })
  create(
    @CurrentTenant() tenantId: string,
    @CurrentUser("sub") userId: string,
    @Body() dto: CreateTicketDto,
  ) {
    return this.ticketService.create(tenantId, userId, dto);
  }

  @Patch(":id")
  @ApiOperation({ summary: "Update ticket" })
  update(
    @CurrentTenant() tenantId: string,
    @CurrentUser("sub") userId: string,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateTicketDto,
  ) {
    return this.ticketService.update(tenantId, id, userId, dto);
  }

  @Delete(":id")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: "Delete ticket (soft delete)" })
  remove(
    @CurrentTenant() tenantId: string,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.ticketService.remove(tenantId, id);
  }

  @Post(":id/close")
  @ApiOperation({ summary: "Close ticket with resolution" })
  close(
    @CurrentTenant() tenantId: string,
    @CurrentUser("sub") userId: string,
    @Param("id", ParseUUIDPipe) id: string,
    @Body("resolution") resolution: string,
  ) {
    return this.ticketService.closeWithResolution(
      tenantId,
      id,
      userId,
      resolution,
    );
  }
}
```

---

## Module completo

```typescript
// modules/tickets/tickets.module.ts
import { Module } from "@nestjs/common";
import { TicketsController } from "./tickets.controller";
import { TicketService } from "./services/ticket.service";
import { TicketRepository } from "./repositories/ticket.repository";

@Module({
  controllers: [TicketsController],
  providers: [TicketService, TicketRepository],
  exports: [TicketService],
})
export class TicketsModule {}
```

---

## DTOs con Zod (compartidos con frontend)

```typescript
// packages/shared-types/src/tickets.ts
import { z } from "zod";

export const CreateTicketSchema = z.object({
  title: z.string().min(3).max(200),
  description: z.string().max(5000).optional(),
  priority: z.enum(["LOW", "MEDIUM", "HIGH", "CRITICAL"]).default("MEDIUM"),
  assigneeId: z.string().uuid().optional(),
});

export const UpdateTicketSchema = CreateTicketSchema.partial().extend({
  status: z.enum(["OPEN", "IN_PROGRESS", "WAITING", "CLOSED"]).optional(),
});

export type CreateTicketInput = z.infer<typeof CreateTicketSchema>;
export type UpdateTicketInput = z.infer<typeof UpdateTicketSchema>;
```

```typescript
// modules/tickets/dto/create-ticket.dto.ts
import { createZodDto } from "nestjs-zod";
import { CreateTicketSchema } from "@repo/shared-types";

export class CreateTicketDto extends createZodDto(CreateTicketSchema) {}
```

---

## Manejo de errores Prisma → NestJS

```typescript
// common/filters/prisma-exception.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpStatus,
} from "@nestjs/common";
import { Prisma } from "../../generated/prisma/client.js";
import { Response } from "express";

@Catch(Prisma.PrismaClientKnownRequestError)
export class PrismaExceptionFilter implements ExceptionFilter {
  catch(exception: Prisma.PrismaClientKnownRequestError, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message = "Database error";
    let code = exception.code;

    switch (exception.code) {
      case "P2002": // Unique constraint
        status = HttpStatus.CONFLICT;
        const field = (exception.meta?.target as string[])?.[0] ?? "field";
        message = `A record with this ${field} already exists`;
        break;

      case "P2025": // Record not found
        status = HttpStatus.NOT_FOUND;
        message = "Record not found";
        break;

      case "P2003": // Foreign key constraint
        status = HttpStatus.BAD_REQUEST;
        message = "Related record not found";
        break;

      case "P2014": // Required relation violation
        status = HttpStatus.BAD_REQUEST;
        message = "Required relation is missing";
        break;
    }

    response.status(status).json({
      statusCode: status,
      error: HttpStatus[status],
      message,
      code,
      timestamp: new Date().toISOString(),
    });
  }
}
```

---

## Resumen de responsabilidades

| Capa              | NestJS                           | Prisma                           |
| ----------------- | -------------------------------- | -------------------------------- |
| **Controller**    | Routing, validación, decoradores | -                                |
| **Service**       | Lógica de negocio, orquestación  | Transacciones ($transaction)     |
| **Repository**    | -                                | Queries, include/select, filtros |
| **PrismaService** | Lifecycle (OnModuleInit)         | Cliente, extensiones, pool       |
| **DTOs**          | class-validator o nestjs-zod     | -                                |
| **Errores**       | ExceptionFilter                  | PrismaClientKnownRequestError    |
| **Auth context**  | Guards, decoradores              | $extends (audit)                 |
| **Multi-tenant**  | Middleware, CLS                  | $extends (filtro automático)     |

---

## Checklist de integración

- [ ] PrismaService con driver adapter y extensiones
- [ ] PrismaModule global
- [ ] Repository por cada dominio
- [ ] Service con lógica de negocio
- [ ] Controller solo routing/validación
- [ ] DTOs compartidos con frontend (Zod)
- [ ] PrismaExceptionFilter global
- [ ] nestjs-cls para contexto (userId, tenantId)
- [ ] Transacciones en operaciones compuestas
- [ ] Soft delete via $extends
- [ ] Audit automático via $extends
