# Prompts de inicio

## Chat madre
Adjunta: `PLAYBOOK-madre.md`, las plantillas y los archivos del proyecto que importan.

---
Sigue `PLAYBOOK-madre.md`.

Feature: <nombre-feature> (los docs irán a `docs/features/<nombre-feature>/`)
Tipo: <app nueva | feature | fix | refactor>
Requerimiento: <qué quiero, por qué, restricciones conocidas>
Adjuntos: <archivo — para qué sirve>
---

## Chat de implementación (etapa N)
Adjunta: `SPEC.md`, `STATE.md` y `stage-N.md` (de `docs/features/<nombre-feature>/`) y el código que el stage lista en "Leer antes".

---
Implementa la etapa N siguiendo `stage-N.md`. Solo esa etapa; respeta "Fuera de alcance".
Si el stage contradice el código real, detente y avísame antes de improvisar.
[Opcional: haz una pausa tras cada paso para que lo pruebe.]
---
