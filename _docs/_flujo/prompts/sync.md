# Prompt — Sincronización (integrar un handoff en los docs)

Chat nuevo y corto. Sube: `STATE.md`, `HANDOFF-N.md`, los `stage-X.md` y los docs del proyecto que el handoff dice que se ven afectados. Pega esto:

---
Integra `HANDOFF-N.md` en los documentos. Devuelve:

1. `STATE.md` completo y actualizado (reemplazo, no append).
2. Para cada `stage-X.md` afectado, solo los cambios concretos (diff o sección reescrita).
3. Para cada doc del proyecto afectado, solo los cambios concretos descritos en el handoff.
4. Una lista final "Eliminado/fusionado" con lo que quitaste de STATE, para que lo revise.
5. Dos mensajes de commit (Conventional Commits; tipo en inglés, descripción y cuerpo en español; sin emojis):
   - `docs(state): ...` para STATE y stages.
   - `docs(<scope>): ...` para los docs del proyecto.

Reglas de mantenimiento de STATE:
- Solo presente: lo que existe y es verdad ahora. Sin historia, sin "antes era X", sin planes (la historia es el git log).
- Un hecho, un hogar: si ya está en el SPEC o en un stage, en STATE va solo la referencia por ID.
- Aplica las invalidaciones del handoff: borra o modifica, no acumules versiones.
- Fusiona hechos duplicados o solapados; borra los abiertos ya resueltos.
- Una línea por hecho. Si algo necesita más, es señal de que pertenece a un stage o al SPEC.
- Guía: ~120 líneas. Si se excede, no borres información: mueve lo estable al SPEC, lo operativo a un stage y descarta lo que ya está en el código. Si algo no tiene hogar claro, pregúntame en vez de eliminarlo.
- Marca la etapa N como "hecha" y borra su `stage-N.md` (su contenido útil ya vive en STATE).
- Si el handoff contradice el SPEC, no lo edites: señálalo aparte para que yo decida.
---

## Después del sync (manual)
1. Reemplaza `STATE.md`, aplica los cambios a stages y docs del proyecto.
2. Borra `HANDOFF-N.md` (sin commit) y `stage-N.md` (queda en el git log si ya commiteaste la salida de la madre).
3. Haz los dos commits `docs(...)`.
4. Si era la última etapa de la feature: mueve `docs/features/<feature>/` a `docs/_archive/<feature>/` (o deja solo SPEC y STATE finales).
