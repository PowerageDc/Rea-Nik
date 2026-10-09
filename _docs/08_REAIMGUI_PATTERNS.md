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

## 4. Botón o tecla de "mantener": flancos, layout estable y widgets que cambian

Primer caso: la cola de tap-to-sync de la tab Lyrics del MusicState Helper
(`features/musicstate_lyrics.md` §8.5). Aplica a cualquier control que
dependa de mantener apretado (tap con hold, push-to-talk, arrastre manual).

- **Una sola señal `held`, flancos por comparación con el frame
  anterior.** Si el gesto puede venir de una tecla y de un botón, no
  mezclar `IsKeyPressed`/`IsKeyReleased` con `IsItemActive`: la tecla se
  lee con `IsKeyDown` y el botón con `IsItemActive`, se combinan en un
  booleano, y el "presionó" y el "soltó" salen de comparar con el valor
  del frame anterior (guardado en el estado). Un `IsKeyDown` tampoco
  tiene auto-repeat, así que no hace falta el `false` de `IsKeyPressed`.
- **Guards de la tecla:** ventana enfocada con
  `FocusedFlags_ChildWindows()` y ningún item activo
  (`IsAnyItemActive`), salvo el propio botón (si no, el click sostenido
  se bloquearía a sí mismo). Si la ventana pierde el foco con la tecla
  apretada, `held` pasa a `false` y se genera el "soltó". Si el control
  puede quedar oculto (header colapsado, tab cerrada), reiniciar el
  valor previo en esa rama, o el próximo frame visible genera un flanco
  falso.
- **Un widget que se deshabilita mientras se lo mantiene pierde el
  release.** `BeginDisabled` o dejar de dibujarlo hace que ImGui lo dé
  por inactivo ese mismo frame, y el "soltó" se pierde. Mantenerlo
  habilitado y cambiar solo la etiqueta (con `###id` fijo, ver §2).
- **El layout alrededor tiene que ser estable.** Un texto condicional
  que aparece o desaparece encima o al lado de un botón lo corre
  mientras se lo aprieta, y el mouse suelta fuera de él: el click se
  pierde sin error. Pasa también con avisos que dependen del estado
  del propio botón (`IsAnyItemActive` es `true` durante el click).
  Reservar siempre la línea, con un texto vacío o `' '` como relleno.
- **Colores de un botón "encendido":** el estado apretado o con mouse
  encima pisa a `Col_Button`. Para que un color se vea también con el
  mouse hay que empujar los tres (`Col_Button`, `Col_ButtonHovered`,
  `Col_ButtonActive`) y sacar los tres (`PopStyleColor(ctx, 3)`). Con la
  tecla no se nota, porque el botón no está apretado.
- **Parámetros que se ajustan seguido:** `DragInt` o `SliderInt` en lugar
  de `InputInt`. Un `InputInt` queda con foco tras tipear y bloquea los
  atajos de teclado sin avisar. Persistir con
  `IsItemDeactivatedAfterEdit`, no en cada frame del arrastre. Si igual
  puede haber un item activo, un aviso visible ("atajo desactivado: hay
  un campo en edición") evita la confusión.
- **`ImGui_GetKeyName` no existe** en la versión de ReaImGui instalada
  (error de `nil`): la etiqueta de una tecla se guarda como texto fijo
  junto a la constante de la tecla.

## 5. `InputText` de edición con borrador: commit, foco y atajos globales

Primer caso: el panel de edición de la tab Lyrics del MusicState Helper
(`features/musicstate_lyrics.md` §8.6). Aplica a editar un valor de la fila
seleccionada de una lista con un `InputText` en un panel aparte, en vez de
uno inline por fila.

- **Borrador propio, atado a la identidad.** El texto tipeado vive en un
  borrador (`buf`) junto con su valor original (`orig`) y la clave del
  elemento al que pertenece (tiempo o id estable, nunca el índice, que se
  corre con cada recarga). `InputText` recibe el borrador y, si `changed`,
  se lo reasigna.
- **Recarga solo con el campo inactivo.** El borrador se recarga desde el
  dato cuando cambia el elemento seleccionado o el valor de origen (edición
  externa, Ctrl+Z), pero nunca mientras el campo tiene foco (guardar
  `IsItemActive` en el estado): si no, se pisa lo que el usuario tipea.
- **Commit con `IsItemDeactivatedAfterEdit`** (Enter, Tab o click afuera).
  En un `InputText` simple es confiable; la advertencia de §3 vale para
  `InputInt` con steppers. Se compara el texto limpio con el original: si no
  cambió, no hay nada que aplicar. En las pruebas Esc no produjo cambios por
  esa misma vía. Si el commit falla (validación), restaurar el borrador al
  original y mostrar el aviso.
- **El commit usa la clave del borrador, no la selección actual.** El
  click en otra fila desactiva el campo antes de que la selección cambie (el
  `Selectable` actúa al soltar el mouse). Si el commit leyera la selección
  actual, podría aplicar el texto a la fila equivocada.
- **Atajos globales.** Si el contenedor evalúa los atajos
  (`IsAnyItemActive`) antes de dibujar el panel, ese frame todavía ve el
  `InputText` del frame anterior como activo: Enter y Space tipeados en el
  campo no disparan Play/Stop, y no hace falta marcar la tecla como
  consumida. Si el orden fuera el inverso (atajos después del panel), sí
  hay que marcarla (`H.consumed_enter`).
- **Refresh forzado tras editar.** Un cache que se recarga por
  `GetProjectStateChangeCount` queda un frame viejo tras una edición propia.
  Forzar la recarga con un valor centinela (`S.state_count = -1`) para que
  ocurra al inicio del frame siguiente, antes de que nada lea el cache, y
  parchear en el frame de transición solo lo que la UI use ese mismo frame
  (el tiempo del evento movido, la clave del borrador, la selección).
- **Panel de alto fijo.** Sin selección, deshabilitar los widgets
  (`BeginDisabled`) en vez de ocultarlos, y reservar la línea de aviso:
  aparecer y desaparecer corre la lista y puede hacer perder un click (§4).

## 6. Modales de confirmación y teclas con un popup abierto

Primer caso: el alta de línea de la tab Lyrics del MusicState Helper
(`features/musicstate_lyrics.md` §8.6). Complementa al modal de colisión de
pegado de Armonía, que ya tiene el esqueleto (`OpenPopup`,
`BeginPopupModal`, `EndPopup` solo si devolvió `true`).

- **Estado pendiente, no contexto.** Al hacer click se guardan los datos de
  entrada (posición, texto) y una vista previa congelada de lo que se va a
  pisar; nunca el resultado de una consulta al proyecto (sus índices
  caducan con cualquier edición). Al confirmar se vuelve a consultar y se
  compara con lo que el modal mostró: si cambió (un tap, un Ctrl+Z con el
  modal abierto), se cancela con aviso en vez de aplicar a ciegas. Un cambio
  de proyecto descarta el pendiente.
- **Dibujarlo desde quien dibuja el botón.** `OpenPopup` y
  `BeginPopupModal` tienen que compartir el ID stack y el string; si la
  fila del botón se reutiliza en más de una rama (por ejemplo, con y sin
  track), el modal va dentro de esa función y queda cubierto en todas.
- **El título de un modal es su ID.** `BeginPopupModal(ctx, 'lyrics_add')`
  muestra ese identificador. Usar `'Texto visible###id_fijo'` en las dos
  llamadas (`OpenPopup` y `BeginPopupModal`), como en §2.
- **Esc no cierra un popup con `NoNav`.** ImGui cierra los popups con Esc
  por la ruta de navegación, desactivada en estos paneles. Se lee a mano
  dentro del modal con `IsKeyPressed(ctx, Key_Escape(), false)`. Los
  popups sí dejan navegar con las flechas entre sus botones (no heredan el
  `NoNav` del root).
- **Enter no se apoya en `SetItemDefaultFocus`.** En la prueba no marcó el
  botón por defecto. Se lee Enter a mano **después de dibujar los
  botones**, y solo actúa si el pendiente sigue siendo el mismo: si un
  botón se activó ese frame (flechas más Enter), manda ese. La acción por
  defecto es la no destructiva cuando hay varios botones (Cancelar), y el
  modal muestra la ayuda de teclas.
- **Primer frame y auto-repeat.** Esc y Enter se ignoran el primer frame
  del modal (flag `armed` en el pendiente) y se leen con `repeat = false`:
  el Enter que abre el modal desde un campo no tiene que confirmarlo.
- **Con un popup abierto, ningún atajo global actúa.** Los guards de
  `globalKeyPressed` (ningún item activo, ventana con foco incluyendo
  `ChildWindows`) no detectan el modal: un popup cuenta como hijo de la
  raíz y sus botones no están activos, así que Espacio, Enter y las flechas
  seguían llegando a REAPER. Se agrega
  `IsPopupOpen(ctx, '', PopupFlags_AnyPopupId())` al guard (efecto
  colateral buscado: también bloquea con un combo desplegado). Todo control
  que lea teclas por su cuenta (`IsKeyDown`, como `readHeld` de la tecla de
  tap) necesita el mismo guard.
- **Campo que agrega con Enter.** Usar `IsItemDeactivated` más
  `IsKeyPressed(Enter, false)`, no `IsItemDeactivatedAfterEdit` (§5 es para
  editar un valor existente): tras cancelar un modal el texto sigue ahí sin
  editarse y el commit no dispararía. Tab y click afuera no agregan porque
  exigen Enter.
