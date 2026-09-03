# Sesión bootstrap — pendientes: Solo in front / bug tab selector / compases pre-marker

Nada de lo que sigue está implementado — es diseño conversado en la sesión
anterior, listo para arrancar directo por diffs. Los tres puntos son
independientes entre sí, se puede arrancar por cualquiera.

## 1. Toggle "Solo in front"

- Es preferencia **global de REAPER** (menú Options), no per-track ni
  per-proyecto → no necesita `tab-ui-memory.js`, alcanza con reflejar el
  estado real.
- Track Master como holder fue descartado explícitamente (no
  semánticamente correcto).
- Lugar propuesto: 5° botón en `#optionsBar`, mismo lenguaje visual que
  Undo/Redo/Metro/LoopRec. Hay espacio de sobra en el `viewBox` (274.2 de
  ancho, 4 botones ocupan ~182).

**Pendiente antes de escribir código:**
- Buscar "solo in front" en la Action List de esta PC y conseguir el
  Command ID real (no inventar, no lo tengo confirmado).
- Decidir si el botón refleja estado real vía `CMDSTATE` — mismo patrón
  que ya usa `buttonMetro`/acción `40364` en `core/wwr-dispatch.js` (caso
  `CMDSTATE`) — o si es solo disparador sin feedback visual.

## 2. Bug: selector de project tabs no detiene la reproducción

**Corrección importante sobre el diagnóstico original:** los botones
⏮/⏭ (`tabPrev`/`tabNext`, que encadenan la acción nativa `40667` —
"Transport: Stop, save all recorded media" — antes del script de cambio
de tab) **no son el bug**. Ese comportamiento es intencional/aceptado.

El bug real está en el **selector de project tabs** — el popup de lista
de proyectos (`modals/project-tabs/project-tabs.js`, dispara
`Nik_ProjectTabs_Select.lua`). Al elegir un proyecto de la lista, la
reproducción del proyecto activo actual **no se detiene**, y debería.

**Pendiente:**
- Revisar `project-tabs.js` / `Nik_ProjectTabs_Select.lua`, decidir dónde
  y cómo encadenar el stop (¿misma acción `40667`? ¿algún otro orden?)
  antes de aplicar la selección de proyecto.

**Bug secundario, ya documentado en `remote_control.md`:** parpadeo del
nombre de proyecto al abrir el popup (se ve el resaltado del tab anterior
hasta que llega la respuesta de `Nik_ProjectTabs_Read.lua`, que es
on-demand). Propuesta conversada: resaltado optimista desde el estado ya
conocido del poll de fondo (`active_project_name`) en vez de esperar la
respuesta on-demand. Sin aplicar.

## 3. Compases pre-marker (popup de markers)

Objetivo: tap prolongado sobre un marker en el popup → seek a N compases
antes del marker elegido. Sirve para poder escuchar una sección desde
antes de que arranque, en 2 taps (abrir popup + long-press).

- N configurable, prellenado con default 2 o el último valor aplicado.
- Solo botones de step, sin input de texto.
- Persistencia por tab — mismo patrón que `nikTabMemoryPendingRestore`
  (nueva key nombrada).
- Confirmado con Nico: el control va ubicado dentro del propio popup de
  markers.

**Pendiente:** diseño puntual de layout dentro del popup, Command ID Lua
para el seek relativo, integración con `markers/markers.js`.

## Cómo arrancar

Mismo modo de trabajo de siempre: paso a paso, confirmar diseño antes de
código, diffs listos para buscar/reemplazar. Elegir cualquiera de los
tres para arrancar.
