# Código Limpio y Refactoring

---

## Nombres que se explican solos

```typescript
// ❌ Nombres crípticos o demasiado generales
const d = new Date();
const u = await getUser(id);
const arr = bookings.filter(b => b.s === 'CONFIRMED');
function process(data: any) { ... }
function handleClick() { ... }

// ✅ Nombres que revelan intención
const today = new Date();
const authenticatedUser = await getUserById(userId);
const confirmedBookings = bookings.filter(b => b.status === 'CONFIRMED');
function calculateExtensionFee(booking: Booking, extraDays: number): number { ... }
function handleBookingCancellation() { ... }

// ❌ Nombres con contexto redundante
interface BookingInterface { ... }
class BookingClass { ... }
const bookingObject = new Booking();

// ✅ El contexto ya está claro por el tipo
interface Booking { ... }
class BookingService { ... }
const booking = new Booking();

// ❌ Nombres de parámetros que no dicen qué reciben
function createBooking(a: string, b: string, c: Date, d: Date) { ... }

// ✅ Parámetros descriptivos
function createBooking(
  userId: string,
  carId: string,
  pickupDate: Date,
  returnDate: Date,
): Promise<Booking> { ... }
```

---

## Funciones — una sola responsabilidad

```typescript
// ❌ Función que hace demasiadas cosas
async function processBooking(dto: CreateBookingDto, userId: string) {
  // 1. Validar disponibilidad
  const car = await prisma.car.findUnique({ where: { id: dto.carId } });
  if (!car) throw new NotFoundException('Auto no encontrado');
  const conflicts = await prisma.booking.findMany({
    where: {
      carId: dto.carId,
      status: { in: ['CONFIRMED', 'ACTIVE'] },
      AND: [
        { pickupDate: { lt: dto.returnDate } },
        { returnDate: { gt: dto.pickupDate } },
      ],
    },
  });
  if (conflicts.length > 0) throw new ConflictException('Auto no disponible');

  // 2. Calcular precio
  const days = Math.ceil(
    (dto.returnDate.getTime() - dto.pickupDate.getTime()) / (1000 * 60 * 60 * 24)
  );
  const totalPrice = car.dailyRate * days;

  // 3. Crear la reserva
  const booking = await prisma.booking.create({
    data: { ...dto, userId, totalPrice, status: 'CONFIRMED' },
  });

  // 4. Enviar email
  await sendEmail({
    to: user.email,
    subject: 'Reserva confirmada',
    template: 'booking-confirmation',
    data: { booking, car },
  });

  // 5. Invalidar cache
  await redis.delByPattern('cars:search:*');

  return booking;
}

// ✅ Cada función hace una sola cosa — fácil de testear y mantener
class BookingService {
  async create(dto: CreateBookingDto, userId: string): Promise<Booking> {
    await this.validateCarAvailability(dto.carId, dto.pickupDate, dto.returnDate);
    const totalPrice = await this.calculateTotalPrice(dto.carId, dto.pickupDate, dto.returnDate);
    const booking = await this.bookingRepository.create({ ...dto, userId, totalPrice });
    await this.notificationService.sendBookingConfirmation(booking);
    await this.invalidateSearchCache();
    return BookingMapper.toDto(booking);
  }

  private async validateCarAvailability(
    carId: string,
    pickupDate: Date,
    returnDate: Date,
  ): Promise<void> { ... }

  private async calculateTotalPrice(
    carId: string,
    pickupDate: Date,
    returnDate: Date,
  ): Promise<number> { ... }

  private async invalidateSearchCache(): Promise<void> { ... }
}
```

---

## Comentarios — el porqué, no el qué

```typescript
// ❌ Comentario que describe lo obvio
// Verificar si el usuario existe
const user = await prisma.user.findUnique({ where: { id } });

// ❌ Comentario que describe el qué — el código ya lo dice
// Multiplicar días por tarifa diaria
const totalPrice = days * car.dailyRate;

// ✅ Comentario que explica el porqué — información que el código no puede expresar
// bcrypt trunca a 72 bytes — contraseñas más largas son igualmente seguras
// pero confundiría al usuario si la UI permite más de 72 caracteres
const MAX_PASSWORD_LENGTH = 72;

// ✅ Comentario que explica una decisión no obvia
// Usar SCAN en lugar de KEYS para no bloquear Redis en producción.
// KEYS bloquea el event loop de Redis mientras escanea — peligroso con > 10k keys.
async delByPattern(pattern: string) { ... }

// ✅ TODO con contexto — quién, qué y por qué no ahora
// TODO(2025-Q2): Migrar a cursor pagination cuando la tabla supere 100k registros.
// Offset pagination se vuelve lenta con skip > 50k. Ver: references/performance-database.md (paginación cursor)
async findAll(page: number, limit: number) { ... }
```

---

## Señales de deuda técnica — qué detectar

```typescript
// 🔴 Código duplicado — el mismo bloque en 3 lugares distintos
// Señal: "ya vi esto en otro archivo"
// Solución: extraer a función o service compartido

// 🔴 Función de más de 50 líneas
// Señal: tienes que hacer scroll para ver una función completa
// Solución: extraer sub-funciones con nombres descriptivos

// 🔴 Comentario que explica código confuso
// Señal: el comentario es necesario para entender el código
// Solución: renombrar variables y extraer funciones hasta que el comentario sobre

// 🔴 Más de 3 niveles de indentación
// Señal: demasiado anidamiento
if (user) {
  if (user.isActive) {
    if (booking) {
      if (booking.status === "CONFIRMED") {
        // ← 4 niveles — difícil de seguir
      }
    }
  }
}
// Solución: early returns y guard clauses
if (!user || !user.isActive) throw new UnauthorizedException();
if (!booking) throw new NotFoundException();
if (booking.status !== "CONFIRMED") throw new ConflictException();
// Lógica principal aquí

// 🔴 Parámetros booleanos
// Señal: createUser(name, email, true, false, true)
// No se entiende qué significa cada boolean sin leer la firma
// Solución: usar un objeto de opciones
createUser({
  name,
  email,
  isActive: true,
  sendWelcomeEmail: false,
  requireVerification: true,
});

// 🔴 Any en TypeScript
// Señal: const data: any = response;
// Solución: definir el tipo correctamente

// 🔴 Magic numbers y strings
// ❌ if (bookings.length > 5) throw new Error('...');
// ✅ const MAX_CONCURRENT_BOOKINGS = 5;
//    if (bookings.length > MAX_CONCURRENT_BOOKINGS) throw new ConflictException();
```

---

## Refactoring seguro — el proceso correcto

El refactoring modifica la estructura del código sin cambiar su comportamiento.
Si no tienes tests, estás reescribiendo — no refactorizando.

```
Proceso de refactoring seguro:
1. ✅ Verificar que hay tests que cubren el código a refactorizar
   Si no hay → escribir los tests primero
2. ✅ Los tests pasan en verde antes de empezar
3. ✅ Hacer UN cambio pequeño
4. ✅ Correr los tests — deben seguir en verde
5. ✅ Commitear el cambio
6. ✅ Repetir desde el paso 3
```

### Técnicas de refactoring más usadas

```typescript
// 1. EXTRACT FUNCTION — código duplicado o bloque largo
// Antes:
const days = Math.ceil(
  (returnDate.getTime() - pickupDate.getTime()) / (1000 * 60 * 60 * 24),
);
const totalPrice = car.dailyRate * days;

// Después:
function calculateRentalDays(pickupDate: Date, returnDate: Date): number {
  const msPerDay = 1000 * 60 * 60 * 24;
  return Math.ceil((returnDate.getTime() - pickupDate.getTime()) / msPerDay);
}

const days = calculateRentalDays(pickupDate, returnDate);
const totalPrice = car.dailyRate * days;
```

```typescript
// 2. REPLACE CONDITIONAL WITH EARLY RETURN — eliminar anidamiento
// Antes:
async function processPayment(booking: Booking) {
  if (booking) {
    if (booking.status === "PENDING") {
      if (booking.totalPrice > 0) {
        return await chargeCard(booking);
      }
    }
  }
}

// Después:
async function processPayment(booking: Booking) {
  if (!booking) return;
  if (booking.status !== "PENDING") return;
  if (booking.totalPrice <= 0) return;
  return await chargeCard(booking);
}
```

```typescript
// 3. REPLACE MAGIC NUMBER WITH CONSTANT
// Antes:
if (failedAttempts > 5) lockAccount();
await redis.set(key, value, 900);

// Después:
const MAX_LOGIN_ATTEMPTS = 5;
const LOGIN_LOCKOUT_SECONDS = 900; // 15 minutos

if (failedAttempts > MAX_LOGIN_ATTEMPTS) lockAccount();
await redis.set(key, value, LOGIN_LOCKOUT_SECONDS);
```

```typescript
// 4. EXTRACT CLASS — service que creció demasiado
// Señal: BookingService tiene 500+ líneas y hace booking + pricing + notification + cache

// Antes: todo en BookingService
class BookingService {
  create() { ... }
  calculatePrice() { ... }  // ← Mover a PricingService
  sendConfirmation() { ... } // ← Mover a BookingNotificationService
  invalidateCache() { ... }  // ← Mover a BookingCacheService
}

// Después: responsabilidades separadas
class BookingService {
  constructor(
    private readonly pricingService: PricingService,
    private readonly notificationService: BookingNotificationService,
    private readonly cacheService: BookingCacheService,
  ) {}
  create() { ... } // Solo orquesta — delega en los otros servicios
}
```

---

## Cuándo refactorizar

```
✅ Refactorizar AHORA:
   - Antes de agregar una feature sobre código confuso
     ("boy scout rule" — dejar el código mejor de como lo encontraste)
   - Cuando la duplicación aparece por tercera vez (rule of three)
   - Cuando el code review señala un problema estructural

✅ Refactorizar en una tarea separada:
   - Refactoring grande que no está relacionado con la feature actual
   - Cuando cambiaría demasiadas líneas en el PR actual

❌ No refactorizar:
   - Código que no vas a tocar en el futuro próximo
   - Código que funciona perfectamente y tiene tests
   - Solo porque "no te gusta" sin un motivo técnico claro
   - Antes de tener tests que protejan el comportamiento
```
