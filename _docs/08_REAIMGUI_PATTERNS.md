# ReaImGui — Patrones y gotchas para paneles nativos

Catálogo técnico de "cómo hacer X sin el bug conocido Y" en ReaImGui. No
es documentación de una feature: aplica a cualquier panel nativo del
proyecto, presente o futuro (hoy: `Nik_MusicState_Helper.lua`; también
relevante para `ReaPitchBus/Nik_ReaPitchBus_Knob.lua` y cualquier panel
nuevo). Primer caso donde se resolvió cada patrón: la tab Armonía del
MusicState Helper (`features/musicstate.md` §8).

## 1. Sticky header sin romper Nav (tablas con scroll)

**El problema:** un `BeginTable` con `TableFlags_ScrollY()` +
`TableSetupScrollFreeze(ctx, 0, 1)` (la forma obvia de lograr header fijo
con scroll) crea **internamente** una child window propia para la región
de scroll. Esa child no hereda `WindowFlags_NoNav()` del root window del
panel, y `BeginTable` no expone forma de pasarle flags — es opaca.
Resultado: dentro de esa tabla aparecen recuadros de foco (Nav highlight)
en botones/headers, y doble disparo en Space/Enter (la acción de REAPER
más la reactivación del botón enfocado por Nav). El `config_flags`
pasado a `ImGui_CreateContext` y el `WindowFlags_NoNav()` del `Begin()`
raíz del panel no alcanzan a cubrir esa child interna: son mecanismos de
scope de ventana, y esa child es un scope nuevo que no se puede tocar
desde afuera.

**La solución:** separar en **dos tablas**, ninguna con `ScrollY`.

1. Una tabla de **header**, fija, sin body — solo `TableHeadersRow()`.
2. Una tabla de **body** (las filas de datos), envuelta en un
   `BeginChild` **propio**, creado a mano, con `WindowFlags_NoNav()`
   explícito. Como el child lo crea el propio código (no `BeginTable`
   internamente), sí se le puede pasar el flag. El scroll lo maneja el
   child, no la tabla — por eso la tabla de body tampoco lleva
   `ScrollY`: si lo tuviera, volvería a crear su propia child interna sin
   `NoNav`, reintroduciendo el bug un nivel más adentro (`NoNav` **no es
   transitivo** a través de un segundo nivel de child window — cada
   child necesita su propio flag).

Columnas sincronizadas entre header y body vía una función compartida
que arma las mismas columnas para las dos tablas (mismos anchos fijos),
así no se pueden desalinear.

```lua
local table_flags = reaper.ImGui_TableFlags_SizingFixedFit()  -- SIN ScrollY

if reaper.ImGui_BeginTable(ctx, 'mytable_header', ncols, table_flags) then
  setupColumns(ctx)
  reaper.ImGui_TableHeadersRow(ctx)
  reaper.ImGui_EndTable(ctx)
end

local body_visible = reaper.ImGui_BeginChild(ctx, 'mytable_body', 0, body_h, 0, reaper.ImGui_WindowFlags_NoNav())
if body_visible then
  if reaper.ImGui_BeginTable(ctx, 'mytable_rows', ncols, table_flags) then
    setupColumns(ctx)
    -- filas...
    reaper.ImGui_EndTable(ctx)
  end
end
reaper.ImGui_EndChild(ctx)  -- EndChild se llama SIEMPRE, a diferencia de EndTable
```

**Gotchas al aplicar el patrón:**

- **`BeginChild`/`EndChild` sigue el patrón de `Begin`/`End`, no el de
  `BeginTable`/`EndTable`**: `EndChild` se llama siempre, aunque
  `BeginChild` haya devuelto `false`. Al revés de la tabla, donde
  `EndTable` solo se llama si `BeginTable` devolvió `true`. Es el error
  más fácil de cometer al copiar el patrón.
- La firma exacta de `ImGui_BeginChild(ctx, str_id, size_w, size_h,
  child_flags, window_flags)` puede variar levemente según versión de
  ReaImGui — confirmar contra la instalación antes de correr.
- Ninguna de las dos tablas lleva `ScrollY` ni `TableSetupScrollFreeze` —
  agregarlo de nuevo "para que ande mejor el scroll" reintroduce el bug
  completo.
- El fix en `_Shared/ImGuiInputCommit_common_logic.lua`
  (`IsWindowFocused(ctx, FocusedFlags_ChildWindows())` en vez de
  `IsWindowFocused(ctx)` a secas) es un requisito aparte de este patrón,
  necesario en cualquier panel que registre atajos de teclado globales en
  el contenedor: permite que esos atajos sigan funcionando con el foco
  dentro de un `BeginChild`. No depende de si hay o no `ScrollY`.

## 2. IDs estables en widgets dentro de loops dinámicos

- **Nunca usar el índice de una lista ya filtrada** (por ejemplo, solo
  los grupos que tienen elementos) como base de `PushID`. Si un ítem
  aparece o desaparece de esa lista, se corre el índice de todo lo que
  viene después → IDs distintos → ImGui trata los widgets como "nuevos" y
  pierde su estado (ej. un `CollapsingHeader` se cierra solo). Usar en
  cambio un identificador que no se mueva — la posición en la lista
  maestra sin filtrar, con un valor fijo reservado para el grupo
  "sin categoría" si existe.
- **El label de un widget con texto dinámico no puede ser también su
  ID.** `CollapsingHeader('%s (%d)', nombre, cantidad)` cambia de ID cada
  vez que cambia la cantidad, perdiendo el estado abierto/cerrado en cada
  alta o baja. Fix: sufijo `###algo_fijo` en el label — todo lo que
  precede a `###` se muestra, pero el ID se calcula solo a partir de lo
  que sigue. El `###` no reemplaza al `PushID` estable del punto
  anterior, son complementarios (uno resuelve colisión entre grupos, el
  otro resuelve que el propio label no arrastre el conteo al ID).
- **`SetNextItemOpen` es un flag consumible, no un estado persistente.**
  Hay que llamarlo una sola vez el frame en que corresponde y no
  repetirlo, o se vuelve imposible para el usuario colapsar manualmente
  ese ítem (cada frame se le volvería a forzar abierta). Requiere
  distinguir "abrir la primera vez que aparece" de "forzar abierto este
  frame en particular", con dos piezas de estado separadas: un set de
  IDs ya vistos alguna vez, y un ID puntual a forzar que se limpia apenas
  se consume.

## 3. Foco y commit de edición en `InputInt` con steppers

Un `InputInt` con steppers +/- **no expone un evento puntual de "terminó
de editar"** confiable: `IsItemDeactivatedAfterEdit` puede dar falso
positivo con el primer keypress, perdiendo el foco al primer dígito
(confirmado en pruebas reales, no es un caso hipotético).

**Patrón:** en vez de buscar un evento de un solo frame, devolver si el
campo tiene foco *este* frame (`active`), y que el llamador detecte
"terminó de editar" por la **transición** de `active` de `true` a
`false` entre un frame y el siguiente, guardando qué elemento estaba
activo el frame anterior. Cualquier acción que dependa de un valor
final y estable (reordenar una lista, recalcular una agrupación,
disparar una validación costosa) debe esperar esa transición, no
ejecutarse en cada frame mientras el campo tiene foco — si lee el valor
en vivo mientras se edita, un solo dígito tipeado puede reubicar el
propio widget (por ejemplo, si depende de un agrupamiento) y cortarle el
foco a mitad de edición. La mitigación es usar un valor **congelado**,
capturado al entrar en edición, para todo lo que no sea el propio input,
y aplicar el valor final recién cuando la transición confirma que se
terminó de editar.
