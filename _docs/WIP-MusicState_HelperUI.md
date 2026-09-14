# Sesión: Modularización de Nik_MusicState_Helper.lua + Armonía (sticky header, agrupado, auto-scroll, highlight)

Doc de traspaso para continuar en otra sesión. Contexto: `Nik_MusicState_Helper.lua`
(panel ReaImGui, feature MusicState) tenía 545 líneas mezclando estado global,
carga/guardado y el dibujo de las 4 tabs en un solo archivo. Se hizo la
modularización primero (completa y probada), y después se construyó UX nueva
sobre la tab Armonía: sticky header sin romper Nav, agrupado de filas por
sección, auto-scroll a la fila activa según el cursor de REAPER, y highlight
visual de esa fila.

## 1. Refactor hecho (completo, probado en REAPER)

Se extrajeron las 4 tabs del Helper a módulos propios, siguiendo el patrón ya
usado en el proyecto (`dofile` + `local M = {}` ... `return M`, ver
`01_CONVENCIONES.md`):

- `MusicStateTonalidad_common_logic.lua`
- `MusicStateRoles_common_logic.lua`
- `MusicStateArmonia_common_logic.lua`
- `MusicStateCues_common_logic.lua`

Cada uno expone `M.draw(ctx, H, helpers)`. `H` es la tabla de estado global,
mutada in-place (igual que ya hacía `RowInputs`). `helpers` es una tabla de
dependencias armada **una sola vez** en el contenedor (no `dofile` repetido
por módulo de tab):

```lua
local helpers = {
  TONICS_STR = TONICS_STR,
  MODES_STR = MODES_STR,
  captureCursorPosition = nikMusicStateCaptureCursorPosition,
  RowInputs = RowInputs,
  InputCommit = InputCommit,
  moveCursorToRow = nikMusicStateMoveCursorToRow,
  rowToTime = nikMusicStateRowToTime,
  getSections = nikMusicStateGetSections,
  getListFooterReserveH = function() return reaper.ImGui_GetFrameHeightWithSpacing(ctx) * 2 end,
}
```

Los 4 módulos nuevos viven junto al Helper (no en `_Shared/`) porque los
consume un solo dominio — mismo criterio que `ActiveProject_common_logic.lua`
en `RemoteControl/` (ver `01_CONVENCIONES.md`, sección "Estructura de
subcarpetas").

El Helper (contenedor) quedó reducido a: contexto/font ImGui, detección de
cambio de project tab, carga/guardado ProjExtState↔`H`
(`nikMusicStateLoadFromProjExtState` / `nikMusicStateSaveAndPublish`),
captura de cursor, atajos de teclado globales, y el `TabBar` delegando a cada
módulo.

**Orden de extracción y commits** (uno por tab, probado en REAPER entre cada
uno): Tonalidad → Roles → Armonía → Cues. Sin cambios de comportamiento —
refactor puro. Hay un mensaje de commit "squash" armado si se prefiere
colapsar los 4 en uno solo (no aplicado todavía, a decisión de Keith).

**Nota aparte, no relacionada al refactor**: hay un glitch preexistente de
Enter en la tab Roles, confirmado que ya ocurría *antes* de este refactor
(no introducido por los cambios). Queda pendiente, ver sección 4.

## 2. Sticky header sin romper Nav — patrón a seguir

### El problema y la causa raíz

Un `BeginTable` con `TableFlags_ScrollY()` + `TableSetupScrollFreeze(ctx, 0, 1)`
(la forma obvia de lograr header fijo con scroll) crea **internamente** una
child window propia para la región de scroll. Esa child no hereda
`WindowFlags_NoNav()` del root window del panel, y `BeginTable` no expone
forma de pasarle flags — es opaca. Resultado: dentro de esa tabla aparecen
recuadros de foco (Nav highlight) en botones/headers, y doble disparo en
Space/Enter (la acción de REAPER + la reactivación del botón enfocado por
Nav). El `config_flags` pasado a `ImGui_CreateContext` y el `WindowFlags_NoNav()`
del `Begin()` raíz del panel no alcanzan a cubrir esa child interna — son
mecanismos de scope de ventana, y esa child es un scope nuevo que no se
puede tocar desde afuera.

### La solución (implementada y confirmada: desaparece el recuadro Y el doble disparo)

Separar en **dos tablas**, ninguna con `ScrollY`:

1. Una tabla de **header**, fija, sin body — solo `TableHeadersRow()`.
2. Una tabla de **body** (las filas de datos), envuelta en un `BeginChild`
   **propio**, creado a mano, con `WindowFlags_NoNav()` explícito. Como
   nosotros creamos ese child (no lo crea `BeginTable` internamente), sí
   podemos pasarle el flag. El scroll lo maneja el child, no la tabla —
   por eso la tabla de body tampoco lleva `ScrollY`: si lo tuviera, volvería
   a crear su propia child interna sin `NoNav`, reintroduciendo el bug un
   nivel más adentro (`NoNav` **no es transitivo** a través de un segundo
   nivel de child window — cada child necesita su propio flag).

Columnas sincronizadas entre header y body vía una función compartida
(`setupHarmonyColumns(ctx)`, que llama `TableSetupColumn` con anchos fijos
tomados de una constante `COLUMN_WIDTHS`) — así no se pueden desalinear,
porque ambas tablas arman sus columnas exactamente igual.

```lua
local table_flags = reaper.ImGui_TableFlags_SizingFixedFit()  -- SIN ScrollY

if reaper.ImGui_BeginTable(ctx, 'harmony_header', 7, table_flags) then
  setupHarmonyColumns(ctx)
  reaper.ImGui_TableHeadersRow(ctx)
  reaper.ImGui_EndTable(ctx)
end

local body_visible = reaper.ImGui_BeginChild(ctx, 'harmony_body', 0, body_h, 0, reaper.ImGui_WindowFlags_NoNav())
if body_visible then
  if reaper.ImGui_BeginTable(ctx, 'harmony_table', 7, table_flags) then
    setupHarmonyColumns(ctx)
    -- filas...
    reaper.ImGui_EndTable(ctx)
  end
end
reaper.ImGui_EndChild(ctx)  -- EndChild se llama SIEMPRE, a diferencia de EndTable
```

### Gotchas para extender este patrón (ej. aplicarlo a Cues)

- **`BeginChild`/`EndChild` sigue el patrón de `Begin`/`End`, no el de
  `BeginTable`/`EndTable`**: `EndChild` se llama siempre, aunque
  `BeginChild` haya devuelto `false`. Al revés de la tabla, donde `EndTable`
  solo se llama si `BeginTable` devolvió `true`. Es el error más fácil de
  cometer al copiar el patrón.
- La firma exacta de `ImGui_BeginChild(ctx, str_id, size_w, size_h,
  child_flags, window_flags)` puede variar levemente según versión de
  ReaImGui — confirmar contra la instalación antes de correr.
- Ninguna de las dos tablas (`harmony_header`, `harmony_table`/body) lleva
  `ScrollY` ni `TableSetupScrollFreeze` — si en algún refactor futuro se le
  vuelve a agregar a la de body "para que ande mejor el scroll", se
  reintroduce el bug completo.
- El fix en `ImGuiInputCommit_common_logic.lua`
  (`IsWindowFocused(ctx, FocusedFlags_ChildWindows())` en vez de
  `IsWindowFocused(ctx)` a secas) sigue siendo necesario aparte de este
  patrón — es lo que permite que los atajos de teclado globales del
  contenedor sigan funcionando estando el foco dentro del `BeginChild` de
  body. No depende de si hay o no `ScrollY`, es requisito de tener
  cualquier child window navegable dentro del panel.

## 3. Agrupado por sección + auto-scroll + highlight (implementado)

### Qué hace

- Las filas de `H.harmony` se agrupan por sección, usando los markers del
  proyecto (`helpers.getSections()`, cualquier marker cuenta — no filtra por
  la nomenclatura estándar de `01_CONVENCIONES.md`, para no bloquear la
  nomenclatura alternativa abreviada todavía sin parser). Cada fila va a la
  **última** sección cuyo marker es anterior o igual a su tiempo
  (`helpers.rowToTime(row)`); sin marker anterior → grupo `"Sin sección"`.
- Cada grupo se dibuja como `CollapsingHeader` + una tabla propia sin
  `ScrollY` (mismo `setupHarmonyColumns` que header/body, así no se
  desalinea con la tabla de header fija de arriba).
- Al mover el cursor de edición de REAPER a otra sección, esa sección se
  auto-abre y hace scroll a la fila con tiempo más cercano al cursor dentro
  de ese grupo.
- La fila "activa" (última fila con tiempo `<=` cursor, o sea la que suena
  por carry-over del acorde) se resalta con `TableSetBgColor` — sólido si el
  cursor coincide exacto con esa fila (igualdad estricta measure/beat/
  hundredths, son enteros), tenue si es carry-over. Sin timer/parpadeo a
  propósito.

### Gotchas — IDs estables en widgets dentro de loops dinámicos

Esto es el aprendizaje reusable más importante de esta sesión, más allá de
Armonía puntual:

- **Nunca usar el índice de una lista ya filtrada** (como `ordered_groups`,
  que solo contiene grupos con filas) como base de `PushID`. Si un ítem
  aparece o desaparece de esa lista, se corre el índice de todo lo que
  viene después → IDs distintos → ImGui trata los widgets como "nuevos" y
  pierde su estado (ej. `CollapsingHeader` colapsado/abierto). Usar en
  cambio un identificador que no se mueva — acá, la posición de la sección
  en la lista maestra de markers (`sections`, nunca filtrada), con `0` fijo
  reservado para "Sin sección".
- **El label de un widget con texto dinámico no puede ser también su ID.**
  `CollapsingHeader('%s (%d)', nombre, cantidad)` cambia de ID cada vez que
  cambia la cantidad (`(%d)`), perdiendo el estado abierto/cerrado en cada
  Agregar/Borrar. Fix: sufijo `###algo_fijo` en el label — todo lo que
  precede a `###` se muestra, pero el ID se calcula solo a partir de lo que
  sigue. El `###` no reemplaza al `PushID` estable del punto anterior, son
  complementarios (uno resuelve colisión entre grupos, el otro resuelve que
  el propio label no arrastre el conteo al ID).
- **Forzar apertura (`SetNextItemOpen`) es un flag consumible, no un
  estado persistente.** Hay que llamarlo una sola vez el frame en que
  corresponde y no repetirlo, o se vuelve imposible para el usuario colapsar
  manualmente esa sección (cada frame se le volvería a forzar abierta). Acá
  se resuelve con dos campos en `H`: `H._armonia_seen_groups` (set de
  `stable_id` ya vistos alguna vez — dispara apertura la primera vez que
  aparece una sección) y `H._armonia_force_open_id` (un solo `stable_id` a
  forzar este frame, compartido entre "sección recién vista" y "acabo de
  agregar/mover una fila hacia esta sección" — se limpia a `nil` apenas se
  consume).

### Campos de estado agregados a `H` (namespace `_armonia_*`)

Todos viven en la tabla global `H`, mutados por el módulo de Armonía. Si se
extrae a un módulo compartido con Cues (pendiente #3 abajo), estos nombres
necesitan un namespace paralelo por tab (ej. `_cues_*`), no reuso directo —
cada tab tiene su propio `H.harmony`/`H.cues` y su propio recorrido de
cursor.

| Campo | Qué guarda |
|---|---|
| `H._armonia_seen_groups` | set (`{[stable_id]=true}`) de secciones ya vistas alguna vez — evita reforzar apertura en cada frame |
| `H._armonia_force_open_id` | `stable_id` a forzar abierto este frame (sección nueva, o destino de fila recién agregada/movida) — se consume y limpia |
| `H._armonia_last_section_idx` | última sección conocida del cursor de REAPER — dispara el auto-scroll cuando cambia |
| `H._armonia_scroll_target_idx` | índice real (en `H.harmony`) de la fila a la que hay que hacer `SetScrollHereY` este frame — se consume y limpia |

### Función local `findSectionIdx(sections, time)`

Vive en `MusicStateArmonia_common_logic.lua` (no en `helpers` — solo la
consume este módulo por ahora). Devuelve el índice de la última sección con
marker `<=` time, o `nil`. Reusada por: el agrupado de filas, el auto-scroll
por cambio de sección del cursor, y "+ Agregar fila" (para saber a qué
sección forzar apertura). Si se extrae el módulo compartido con Cues,
migra junto con `rowToTime`.

### Supuesto no verificado formalmente

El loop que busca la fila "activa" para highlight asume que `H.harmony` está
ordenado cronológicamente (corta con `break` en la primera fila posterior al
cursor). Si en algún momento se permite insertar filas fuera de orden, este
loop necesita cambiar a recorrido completo sin `break`.

### Pendiente de calibración (no bloqueante, cosmético)

Colores de highlight hardcodeados a ojo (`0x3FBF3FA0` sólido / `0x3FBF3F40`
carry-over, verde). Keith los va a ajustar mientras sigue probando. Además,
mencionó que hoy los inputs/botones de la fila pintan "encima" y tapan un
poco el highlight de fondo — pendiente evaluar si conviene pasar los
widgets a variantes con fondo transparente, o si alcanza con el ajuste de
color/alfa.

## 4. Pendientes

1. **Aplicar el patrón de la sección 2 (dos tablas + `BeginChild` con
   `NoNav`) a la tab Cues** — hoy no tiene sticky header implementado
   todavía; cuando se agregue, previsiblemente comparte el mismo bug de Nav
   si se usara `ScrollY` directo.
2. **Copiar bloque de filas** (multi-selección por rango + copiar/pegar
   anclado al cursor) — diseñado agnóstico a secciones, aplica tanto a
   Armonía como a Cues.
3. **Extraer módulo compartido de "lista posicionada"** (Armonía + Cues) a
   `_Shared/` — según `01_CONVENCIONES.md`, corresponde recién cuando hay
   un segundo consumidor real. Ahora que Armonía tiene una implementación
   completa (agrupado + auto-scroll + highlight, no solo el trío de
   posición de `MusicStateRowInputs_common_logic.lua`), conviene esperar a
   que Cues tenga su propia versión (pendiente #1) para ver qué generaliza
   limpio y qué es específico de cada tab, en vez de adivinar la
   abstracción de antemano.
4. **Particulares de Cues** sobre la base del punto 3: botón "Usar
   selección de tiempo" para `duration_qn` (vía `GetSet_LoopTimeRange`).
5. **Calibración cosmética del highlight** (ver sección 3, colores y
   visibilidad detrás de inputs/botones) — no bloqueante, a criterio de
   Keith mientras sigue probando.
6. **Glitch preexistente de Enter en tab Roles** — confirmado que no lo
   introdujo el refactor de modularización; pendiente de investigar aparte,
   sin mezclar con el trabajo de UX de Armonía/Cues.
7. **Fuente centralizada del diccionario color/traducción de secciones**,
   compartida entre `web/config.js` (JS, navegador) y el Helper (Lua,
   REAPER) — hoy son runtimes separados sin puente directo (Lua no puede
   ejecutar `config.js` como módulo). Serviría para colorear de fondo los
   `CollapsingHeader` de grupo en Armonía/Cues según la sección (y,
   potencialmente, degradado por fila con `ImGui_DrawList_AddRectFilledMultiColor`,
   más esfuerzo que un color plano vía `TableSetBgColor`).
   - **Ojo con el path dev vs. deploy** (mismo problema ya documentado en
     `00_CONTEXTO_GENERAL.md` para los Command IDs): en dev, `MusicState/`
     y `web/` son hermanas bajo `C:\dev\Rea-Nik\`; deployado vía ReaPack,
     el Helper vive en `Scripts/Rea-Nik/MusicState` sin relación de ruta
     fija con `web/` (que se sirve desde `reaper_www_root`). Una ruta
     relativa tipo `../web/config.js` funcionaría en dev y se rompería en
     una PC de ensayo.
   - **Opción A** (evaluar primero): módulo Lua en `_Shared/`
     (ej. `SectionColors_common_logic.lua`, `local M = {...} return M`)
     como fuente canónica — el Helper lo consume directo con `dofile`,
     sin parsing. `config.js` mantiene una copia derivada, marcada en
     comentario como reflejo de ese módulo (sincronización manual o via
     mini script de build a futuro).
   - **Opción B**: archivo de datos neutral (`.json` plano, servido desde
     `web/`) parseado por ambos lados — JS vía `fetch()`, Lua con un
     parser simple a medida (no hace falta librería JSON completa para un
     diccionario plano nombre→color). Sigue sin resolver el problema de
     path si el Helper deployado necesita leerlo directamente.
   - Definir primero si el color de sección lo necesita el Helper en
     tiempo real (togglear en el panel ReaImGui) o solo importa del lado
     web — eso decide si conviene A o B.
