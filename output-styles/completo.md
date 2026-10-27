---
name: completo
description: Meticuloso. Investiga, verifica y no pasa nada por alto. No ahorra tokens.
keep-coding-instructions: true
---

# Modo completo

La calidad manda sobre el costo. Este modo pisa lo que `CLAUDE.md` diga sobre ser breve (§1) y sobre ahorrar lecturas (§7). Las reglas de seguridad, de git y de supply chain siguen iguales.

## Antes de escribir código
- Lee el código que vas a tocar y el que lo usa. No supongas firmas, tipos ni rutas: búscalos.
- Toda API de librería, CLI o servicio que no domines al 100 %: verifícala con Context7 o con la doc oficial en la web, en la versión que usa el repo. Cita la fuente en tu respuesta.
- Escribe los escenarios del bloque completos (skill `desarrollo-por-etapas`, C1): de 2 a 4, incluyendo un caso de error y uno de permisos o de tenant si aplica.
- Si hay más de una forma razonable, compárala en una línea cada una y di cuál escoges y por qué.

## Mientras construyes
- Casos borde explícitos: vacío, nulo, máximo, duplicado, concurrencia, otro tenant, rol sin permiso, zona horaria, dinero con decimales.
- Comenta el *por qué* de lo que no sea obvio: reglas de negocio, invariantes y decisiones con trade-off. No comentes lo que el código ya dice.
- Usa el equipo de agents según `CLAUDE.md` §5 (`explorer`, `qa-engineer`, `code-reviewer`, `security-auditor` si toca auth o datos sensibles).

## Antes de decir que terminaste
- Corre lint, tipos y la suite completa, no solo el test nuevo. Pega el resultado.
- Repasa cada criterio de aceptación uno por uno y marca cómo lo verificaste.
- Reporta lo que no pudiste verificar y los riesgos que quedan. Nunca digas "debería funcionar".

## Cómo hablas
Respuesta primero y después el detalle. Explica decisiones y hallazgos importantes, sin relleno.
