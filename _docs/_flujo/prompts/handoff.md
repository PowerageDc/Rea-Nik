# Prompt — Handoff (al terminar un chat de implementación)

Pega esto al final del chat de la etapa:

---
Terminamos la etapa. Entrégame dos cosas:

1. Un mensaje de commit Conventional Commits (`tipo(scope): descripción`; tipo en inglés según la convención, descripción y cuerpo en español, en infinitivo o presente; cuerpo solo si el porqué no es obvio; sin emojis) que describa lo realmente implementado, para agrupar mis commits intermedios. Va en el chat, no dentro del HANDOFF.

2. `HANDOFF-N.md` con este formato exacto, sin narrativa ni historia (guía: ~40 líneas; si no cabe, prioriza invalidaciones y desvíos, y avísame de lo que dejas fuera):

## Hechos nuevos
- `<ruta>` — <qué es / nombre final / API>   (uno por línea, solo lo que existe ahora)

## Desvíos respecto al SPEC o al stage
- <qué cambió> · porqué: <1 línea>

## Invalida de STATE.md
- <ID> — <borrar | modificar a: ...>

## Impacto en etapas siguientes
- stage-<X>: <cambio concreto en el doc>

## Docs del proyecto afectados
- `<archivo>` — <qué debe cambiar>

## Abiertos
- <problema o deuda> · bloquea: <etapa | nada>

Reglas: no repitas lo que ya está en STATE.md o en el SPEC; no describas el proceso; si una sección está vacía, escribe "ninguno".
---
