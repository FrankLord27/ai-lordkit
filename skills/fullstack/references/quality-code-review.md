# Pull Requests y Code Review

---

## Cómo escribir un PR que se aprueba rápido

Un buen PR le da al reviewer todo el contexto para entender y revisar
sin tener que preguntar qué hace o por qué.

### Template de PR

```markdown
## ¿Qué hace este PR?

Descripción clara en 2-3 oraciones de qué cambia y por qué.

## Motivación

¿Por qué era necesario este cambio? ¿Qué problema resuelve?
Linkar issue si existe: Closes #123

## Cambios realizados

- [ ] Endpoint `POST /bookings/:id/extension` para extender fechas
- [ ] Validación: fecha de extensión debe ser posterior a la fecha actual
- [ ] Tests unitarios del servicio de extensión
- [ ] Tests de integración del endpoint

## Cómo probar

1. Login con `POST /auth/login`
2. Crear una reserva con `POST /bookings`
3. Extender con `POST /bookings/:id/extension` con body `{ "newReturnDate": "..." }`
4. Verificar que la fecha se actualizó en `GET /bookings/:id`

## Screenshots (si hay cambios de UI)

[Antes] vs [Después]

## Notas para el reviewer

- El cálculo de precio de extensión está en `BookingExtensionCalculator` — revisar la lógica con cuidado
- Decidí no cachear el resultado porque la disponibilidad puede cambiar en segundos
- `TODO`: agregar notificación de email en el siguiente PR — lo separé para mantener este PR pequeño
```

---

## Tamaño del PR — la regla más importante

```
< 200 líneas cambiadas  → Revisión rápida (15-30 min)
200-500 líneas          → Revisión estándar (30-60 min)
> 500 líneas            → Difícil de revisar bien — considerar dividir

❌ PRs que hacen múltiples cosas:
  "feat: add booking extension + refactor search + update dependencies"
  ← Imposible de revertir selectivamente. Difícil de revisar.

✅ PRs enfocados en una sola cosa:
  "feat: add booking date extension"  → Un PR
  "refactor: extract search filters to service"  → Otro PR
  "chore: update dependencies"  → Otro PR
```

### Cómo dividir un PR grande

```bash
# Si ya tienes muchos commits en una rama:
# 1. Identificar grupos lógicos de cambios
# 2. Crear ramas separadas para cada grupo

# Ejemplo: tienes 20 commits mezclando feature + refactor
git log --oneline  # Ver todos los commits

# Crear rama para solo la feature
git checkout main
git checkout -b feat/booking-extension
git cherry-pick abc123 def456 ghi789  # Solo los commits de la feature

# Crear rama para solo el refactor
git checkout main
git checkout -b refactor/search-filters
git cherry-pick jkl012 mno345  # Solo los commits del refactor
```

---

## Code Review — qué revisar

### Como reviewer: qué mirar en qué orden

```
1. PRIMERO — Entender el contexto (2 min)
   □ Leer la descripción del PR completa
   □ Ver la lista de archivos cambiados
   □ Entender qué problema resuelve

2. LÓGICA DE NEGOCIO (el más importante)
   □ ¿La lógica es correcta?
   □ ¿Hay edge cases no manejados?
   □ ¿Las validaciones son suficientes?
   □ ¿Los errores se manejan correctamente?

3. SEGURIDAD
   □ ¿Se valida el input?
   □ ¿Hay autorización correcta en endpoints nuevos?
   □ ¿Se expone información sensible?
   □ ¿Hay SQL injection o XSS posible?

4. PERFORMANCE
   □ ¿Hay queries N+1 potenciales?
   □ ¿Faltan índices en columnas nuevas?
   □ ¿Los listados tienen paginación?

5. TESTS
   □ ¿Los tests cubren los happy paths?
   □ ¿Los tests cubren los casos de error?
   □ ¿Los tests son claros y descriptivos?

6. MANTENIBILIDAD
   □ ¿Los nombres son claros?
   □ ¿El código es fácil de entender?
   □ ¿Hay duplicación que podría abstraerse?
   □ ¿Los comentarios explican el porqué?
```

### Tipos de comentarios — cómo distinguirlos

```markdown
# Bloqueante — debe resolverse antes del merge

🚫 Este endpoint no verifica si la reserva pertenece al usuario autenticado.
Cualquier usuario puede extender reservas de otros.

# Sugerencia — sería mejor pero no bloquea

💡 Podrías usar `Promise.all` aquí para ejecutar las dos queries en paralelo
y reducir el tiempo de respuesta ~50%.

# Pregunta — necesita aclaración

❓ ¿Por qué decidiste no cachear el resultado de este endpoint?
¿Hay alguna razón de negocio que no estoy viendo?

# Nitpick — detalle menor, no bloquea, el autor decide

🔍 nit: El nombre `calculateExtensionFee` podría ser más descriptivo,
algo como `calculateAdditionalDaysPrice`. Pero si te parece bien así, ok.

# Aprendizaje — compartir conocimiento, no es feedback

📚 FYI: Prisma tiene un método `upsert` que haría esto en una sola operación
si necesitas hacerlo en el futuro.
```

---

## Cómo responder al code review — como autor

```markdown
# ✅ Resolver el comentario

Si el reviewer tiene razón → corregir y marcar como resuelto.
No necesitas justificarte — el código habla.

# ✅ Discrepar con argumento

Si no estás de acuerdo → explicar por qué con razonamiento técnico.
No personalizar la discusión.

Ej: "Preferí no usar `upsert` aquí porque necesito el comportamiento
específico de error cuando el registro ya existe — upsert lo silenciaría."

# ✅ Pedir aclaración

Si el comentario no es claro → preguntar.
"¿Puedes darme un ejemplo de cuándo esto podría ser un problema?"

# ❌ Nunca

- Resolver comentarios sin haberlos atendido
- Responder defensivamente ("esto ya lo revisé")
- Ignorar comentarios bloqueantes
- Requerir aprobación con comentarios sin resolver
```

---

## Draft PRs — trabajo en progreso

```bash
# Abrir un PR como Draft cuando:
# - Quieres feedback temprano antes de terminar
# - El PR está incompleto pero quieres CI corriendo
# - Estás explorando un approach y quieres input

# En GitHub: "Create draft pull request"
# Se puede convertir a PR normal cuando está listo

# Los Drafts:
# ✅ Corren el pipeline de CI
# ✅ Se pueden comentar
# ❌ No se pueden aprobar ni mergear
```

---

## Checklist del reviewer antes de aprobar

```
✅ Entiendo qué hace el PR y por qué
✅ La lógica de negocio es correcta
✅ Los endpoints nuevos tienen autenticación y autorización
✅ El input se valida correctamente
✅ No hay queries N+1 obvias
✅ Los listados nuevos tienen paginación
✅ Los tests cubren los casos principales
✅ Los nombres de variables, funciones y clases son claros
✅ No hay secrets o datos sensibles hardcodeados
✅ Los comentarios bloqueantes fueron resueltos
```
