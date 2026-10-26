# 04 - CRUD Services and Controllers (Prisma 7)

Note: Query patterns are the same as v6. The only difference is the import path for Prisma types.

## Full Service with Error Handling

```typescript
// src/users/users.service.ts
import {
  Injectable,
  NotFoundException,
  ConflictException,
} from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service.js";
import { User, Prisma } from "../generated/prisma/client.js";

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(params?: {
    skip?: number;
    take?: number;
    where?: Prisma.UserWhereInput;
    orderBy?: Prisma.UserOrderByWithRelationInput;
  }) {
    return this.prisma.user.findMany({
      skip: params?.skip ?? 0,
      take: params?.take ?? 20,
      where: params?.where,
      orderBy: params?.orderBy ?? { createdAt: "desc" },
    });
  }

  async findOne(id: number) {
    try {
      return await this.prisma.user.findUniqueOrThrow({
        where: { id },
        include: { profile: true },
      });
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === "P2025"
      )
        throw new NotFoundException(`User ${id} not found`);
      throw e;
    }
  }

  async create(data: Prisma.UserCreateInput) {
    try {
      return await this.prisma.user.create({ data });
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === "P2002"
      )
        throw new ConflictException("Email already in use");
      throw e;
    }
  }

  async update(id: number, data: Prisma.UserUpdateInput) {
    try {
      return await this.prisma.user.update({ where: { id }, data });
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === "P2025"
      )
        throw new NotFoundException(`User ${id} not found`);
      throw e;
    }
  }

  async remove(id: number) {
    try {
      return await this.prisma.user.delete({ where: { id } });
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === "P2025"
      )
        throw new NotFoundException(`User ${id} not found`);
      throw e;
    }
  }
}
```

## Controller

```typescript
// src/users/users.controller.ts
import {
  Controller,
  Get,
  Post,
  Body,
  Patch,
  Param,
  Delete,
  ParseIntPipe,
  Query,
  HttpCode,
  HttpStatus,
} from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { UsersService } from "./users.service.js";

@ApiTags("users")
@ApiBearerAuth()
@Controller("users")
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Post()
  create(@Body() dto: any) {
    return this.usersService.create(dto);
  }

  @Get()
  findAll(@Query("skip") skip?: string, @Query("take") take?: string) {
    return this.usersService.findAll({
      skip: skip ? +skip : 0,
      take: take ? +take : 20,
    });
  }

  @Get(":id")
  findOne(@Param("id", ParseIntPipe) id: number) {
    return this.usersService.findOne(id);
  }

  @Patch(":id")
  update(@Param("id", ParseIntPipe) id: number, @Body() dto: any) {
    return this.usersService.update(id, dto);
  }

  @Delete(":id")
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param("id", ParseIntPipe) id: number) {
    return this.usersService.remove(id);
  }
}
```

## DTOs

```typescript
// create-user.dto.ts
import { IsEmail, IsString, IsOptional } from "class-validator";
import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";

export class CreateUserDto {
  @ApiProperty()
  @IsEmail()
  email: string;

  @ApiPropertyOptional()
  @IsString()
  @IsOptional()
  name?: string;
}
```

```typescript
// update-user.dto.ts
import { PartialType } from "@nestjs/swagger";
import { CreateUserDto } from "./create-user.dto.js";
export class UpdateUserDto extends PartialType(CreateUserDto) {}
```

## Validation Setup

```bash
pnpm add class-validator class-transformer
```

main.ts:

```typescript
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  }),
);
```

## Pagination Patterns

Offset pagination:

```typescript
async paginate(page = 1, limit = 20) {
  const [data, total] = await this.prisma.$transaction([
    this.prisma.user.findMany({ skip: (page - 1) * limit, take: limit }),
    this.prisma.user.count(),
  ]);
  return { data, meta: { total, page, limit, lastPage: Math.ceil(total / limit) } };
}
```

Cursor pagination:

```typescript
async cursor(cursor?: number, take = 20) {
  return this.prisma.user.findMany({
    take,
    skip: cursor ? 1 : 0,
    cursor: cursor ? { id: cursor } : undefined,
    orderBy: { id: 'asc' },
  });
}
```
