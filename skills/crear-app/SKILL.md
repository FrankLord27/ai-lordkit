---
name: crear-app
description: Úsala cuando el usuario diga que quiere hacer una aplicación, un sistema o una app ("quiero hacer una app", "quiero crear un sistema para...") y no haya escogido arquitectura ni herramientas. Le muestra un selector interactivo con opciones, cada una con su recomendación y su contra, anota lo que escoja y arranca el proyecto sin más vueltas.
---

# Crear una app: selector de arquitectura y herramientas

Para quien llega con una idea y no sabe qué escoger. En vez de una lista larga de preguntas, le muestras un **selector** (la herramienta `AskUserQuestion`): toca una opción y listo. La opción recomendada va primero. El usuario decide; tú recomiendas y después avanzas rápido.

## Cuándo no usarla

- Ya existe `docs/METODO.md` con arquitectura y herramientas: síguelo, no preguntes de nuevo.
- El repo ya tiene código con su stack: respeta ese stack y no lo ofrezcas como pregunta. Solo pregunta lo que falte (por ejemplo, el tipo de app).
- El usuario ya dijo lo que quiere ("en Next.js con Supabase"): no lo preguntes. Solo pregunta lo que no dijo.

## Pasos

1. **Saca del mensaje lo que ya se sabe** (tipo de app, si lleva móvil, alguna herramienta que mencionó). Lo que ya se sabe no se pregunta.

2. **Muestra el selector**: una sola llamada a `AskUserQuestion` con las preguntas que falten, de las de abajo. Reglas:
   - La opción recomendada va primero y su etiqueta termina en `(Recomendado)`.
   - Cada descripción dice en una línea cuándo conviene y su contra principal. Si el mensaje del usuario da pistas (un colegio, una tienda, un equipo de una persona), adapta las descripciones a su caso.
   - La herramienta agrega sola la opción "Other" para que el usuario escriba lo suyo. No la repitas.
   - Cuántas preguntas depende del modo (ver abajo).

3. **Revisa que la combinación tenga sentido.** Si no lo tiene, dilo en una línea y propón el ajuste, pero lo que escogió el usuario manda:
   - Serverless + NestJS: NestJS no está hecho para funciones cortas; mejor Next.js con route handlers, o monolito en un contenedor.
   - Microservicios + equipo de una persona: el costo de infraestructura se come el tiempo; recuérdalo una vez.
   - Un stack que no es el del kit: las skills del kit (`fullstack`, `nestjs-security-hardening`, `blindar`) están hechas para el estándar. Avisa que en lo demás vas a consultar la documentación con Context7 antes de escribir código.

4. **Método de trabajo.** Pasa a la skill `elegir-metodo` con lo ya escogido, sin repetir preguntas. En modo `ahorro`, usa el método recomendado y dilo en una línea (el usuario lo puede cambiar después).

5. **Anota la decisión** en `docs/METODO.md` (plantilla de `elegir-metodo`, líneas `Arquitectura:` y `Herramientas:`). Si es un proyecto nuevo, sigue con `/new-project` usando lo escogido: no vuelvas a preguntar tipo ni móvil.

6. **Arranca.** Un resumen de 3 a 5 líneas (qué se escogió y qué va primero) y empiezas el Bloque 0 de `desarrollo-por-etapas`. Si escogió microservicios, el diseño sale de la skill `microservicios`.

## Las preguntas

Cada pregunta lleva un `header` corto (máximo 12 caracteres), de 2 a 4 opciones y `multiSelect` solo donde se indica.

**Tipo** — "¿Qué tipo de aplicación es?"
- SaaS / sistema de gestión: varios clientes o sucursales, usuarios con roles (colegio, clínica, CRM).
- POS / facturación: ventas, inventario, comprobantes fiscales. Usa la skill `erp-saas-core`.
- Sitio público + panel admin: página para el público y un panel para administrar el contenido.
- Marketplace: proveedores, clientes y comisiones.

**Arquitectura** — "¿Cómo quieres organizar la aplicación?"
- Monolito modular (Recomendado): una sola app con módulos bien separados. Lo más rápido de construir y desplegar, y un módulo se puede sacar a un servicio después. Contra: todo se despliega junto.
- Microservicios: varios servicios con su propia base de datos. Conviene con varios equipos o partes con carga muy distinta. Contra: mucha más infraestructura y errores entre servicios.
- Serverless: funciones en la nube (Vercel, Cloudflare). Bueno para tráfico irregular y poca lógica. Contra: arranques en frío, procesos largos difíciles y amarre al proveedor.
- Frontend + backend como servicio: Supabase o Firebase ponen la base de datos y el login. Lo más rápido para un prototipo. Contra: la lógica de negocio queda repartida y migrar después cuesta.

**Herramientas** — "¿Con qué herramientas lo construimos?"
- Estándar del kit (Recomendado): Next.js 16 + NestJS 11 + Prisma 7 + PostgreSQL 16 + Redis. Todas las skills del kit están hechas para esto. Contra: dos apps que mantener (web y API).
- Next.js fullstack: Next.js con route handlers + Prisma + PostgreSQL, un solo deploy. Bueno para apps pequeñas. Contra: con mucha lógica de negocio se enreda, y las skills de NestJS no aplican.
- Solo API (NestJS): backend para una app móvil u otro frontend que ya existe.
- Otro stack: el usuario lo escribe. Las skills del kit no lo cubren; la documentación se consulta con Context7.

**Plataformas** (`multiSelect: true`) — "¿Dónde se va a usar?"
- Web: navegador en PC y celular (mobile-first).
- App móvil (Expo): app instalable en Android e iOS, con el plugin de Expo.

## Según el modo

- `ahorro`: máximo 2 preguntas, **Arquitectura** y **Herramientas**. Lo demás se deduce o se toma lo recomendado, y lo dices en una línea.
- `intermedio` (por defecto, o si no sabes el modo): las 4 preguntas en una sola llamada, quitando las que ya se saben.
- `completo`: las 4, y después una segunda llamada con lo que aplique al proyecto: login (correo y contraseña, Google, enlace mágico), dónde se despliega (VPS con Docker, Vercel + Railway, Cloudflare) y, si es SaaS, cómo separar los clientes (columna `tenantId` o un schema por cliente).

## Si no hay selector

En `claude -p`, en un subagent o donde `AskUserQuestion` no esté, haz las mismas preguntas en un solo mensaje de texto, numeradas y con letras (`1a`, `2b`...), con la recomendada marcada. El usuario contesta en una línea, por ejemplo `1a 2a 3a 4ab`.
