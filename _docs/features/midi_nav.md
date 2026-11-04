# MidiNav — navegación en el MIDI Editor

Acciones one-shot para el MIDI Editor, pensadas para asignar a atajos de
teclado. Sin UI. Todo el comportamiento se ajusta en `MidiNav_config.lua`
(config en código, ver `01_CONVENCIONES.md`). Las acciones que modifican
notas o eventos viven en `MidiEdit/` (ver `features/midi_edit.md`); MidiNav
solo mueve el cursor y cambia la selección.

## 1. Scripts

Carpeta `C:\dev\Rea-Nik\MidiNav\`. Los de gap, selección de nota y CC son
wrappers de dos líneas que cargan su módulo y llaman a `run("next")` o
`run("prev")`; los de rango de CC llaman a `run(<origen>)`.

| Script | Qué hace |
|---|---|
| `Nik_MidiNav_CursorMeasureStartOrPrev.lua` | Cursor al inicio del compás actual; si ya está ahí, al inicio del anterior |
| `Nik_MidiNav_CursorGapMid.lua` | Cursor al medio del gap entre la nota actual y la siguiente |
| `Nik_MidiNav_CursorGapMidPrev.lua` | Espejo: gap entre la anterior y la actual |
| `Nik_MidiNav_SelectNoteNext.lua` | Selecciona la primera nota posterior al cursor |
| `Nik_MidiNav_SelectNotePrev.lua` | Selecciona la última nota anterior al cursor |
| `Nik_MidiNav_ToggleMainEditor.lua` | Alterna el foco entre la ventana principal y el MIDI Editor flotante; si no hay editor abierto, abre el del ítem seleccionado |
| `Nik_MidiNav_SelectNotesAtCursor.lua` | Selecciona todas las notas que suenan en el cursor |
| `Nik_MidiNav_CursorToCcNext.lua` | Cursor al siguiente evento CC (según `cc.lane_mode`) |
| `Nik_MidiNav_CursorToCcPrev.lua` | Espejo: cursor al evento CC anterior |
| `Nik_MidiNav_SelectCcInTimeSel.lua` | Selecciona los CC dentro de la time selection |
| `Nik_MidiNav_SelectCcFromCursor.lua` | Selecciona los CC desde el cursor hasta el final del take |
| `Nik_MidiNav_SelectCcToCursor.lua` | Selecciona los CC desde el inicio del take hasta el cursor |

Módulos de soporte (solo `dofile`, no se registran):
- `MidiNav_common_logic.lua`: `collect_notes`, `move_cursor` y `with_undo`.
- `MidiNavGap_common_logic.lua`: lógica de gap, `run(direction)`.
- `MidiNavSelect_common_logic.lua`: lógica de selección, `run(direction)`.
- `MidiNavCc_common_logic.lua`: cursor al CC siguiente y previo, `run(direction)`,
  y `make_filter(editor, take, mode)`, el filtro de lanes que comparte con el
  módulo de rango.
- `MidiNavCcRange_common_logic.lua`: selección de CC por rango, `run(source)`
  con `"time_selection"`, `"from_cursor"` o `"to_cursor"`.

Registro: sección **MIDI Editor** del Action List. El de compás usa tiempo de
proyecto y también funciona registrado en Main; el resto necesita un editor
activo y sale sin hacer nada si no lo hay.

`ToggleMainEditor` es la excepción: se registra en **Main** y en **MIDI
Editor** (dos registros del mismo archivo, cada uno con su Command ID) y se le
asigna la misma tecla en ambas secciones, para que el mismo atajo vaya y vuelva.
Requiere la extensión js_ReaScriptAPI y avisa con un mensaje si falta.

## 2. Comportamiento

### Compás
Con `TimeMap2_timeToBeats` se calcula el inicio del compás que contiene al
cursor. Si el cursor está a más de `measure.tolerance_sec` del inicio, va al
inicio; si no, va al inicio del compás anterior. Si ya está en el inicio del
compás 1, no hace nada. Respeta cambios de compás y de tempo.

### Gap
- Las notas se ordenan por inicio y se agrupan en acordes (inicios dentro de
  `notes.chord_tol_ppq`). El final de un acorde es el de su nota más larga.
- Destino: final del acorde actual + `gap.position` * gap. Con
  `position = 0.5` es el medio.
- Sin gap (solape o notas pegadas, gap <= `gap.min_gap_ppq`): hacia adelante va
  al inicio de la siguiente (`no_gap_target`); hacia atrás, al final de la
  anterior (`no_gap_target_prev`).
- **Con selección:** la referencia es la selección. Con varias notas, se usa
  el acorde de la última (adelante) o de la primera (atrás) seleccionada. La
  selección nunca se modifica.
- **Continuación (`selection_continue`):** la selección es ancla hasta que el
  cursor alcanza o pasa el gap que ella define; desde ahí el script sigue con
  la lógica sin selección y recorre los gaps subsiguientes.
- **Sin selección:** la referencia es la nota más cercana al cursor
  (`tiebreak` y `tie_tol_ppq` resuelven empates). Si el destino coincide con
  la posición actual (`same_pos_tol_sec`) y `repeat_advances` está activo,
  avanza al gap siguiente o anterior.
- Sin nota siguiente (o anterior): no hace nada ni crea punto de undo.

### Selección
- La referencia es siempre el cursor, nunca la selección previa.
- Siguiente: primera nota cuyo inicio queda después de cursor +
  `select.threshold_sec`. Previa: última nota cuyo inicio queda antes de
  cursor - `threshold_sec`. Con el cursor justo en el inicio de una nota,
  `Prev` va a la anterior.
- En acordes elige una nota por `chord_pick_next` / `chord_pick_prev`
  (`"highest"` o `"lowest"`).
- `select.mode`: `"replace"` des-selecciona las notas filtradas y selecciona
  la elegida; `"extend"` solo suma. `select.move_cursor`: `"start"` salta al
  inicio de la nota elegida, `"none"` deja el cursor.
- Sin selección previa funciona igual, por lo que no depende de las acciones
  nativas de siguiente y previa nota.

### Notas bajo el cursor
- Una nota cuenta si su inicio es `<=` cursor + `at_cursor.tolerance_sec` y su
  final es `>` cursor. Una nota que termina justo en el cursor no entra; una
  que empieza apenas después (fuera de la grilla) sí.
- Respeta `notes.include_muted` y `notes.channel_filter`.
- `at_cursor.mode`: `"replace"` des-selecciona el resto, `"extend"` solo suma.
- No mueve el cursor. Sin notas bajo el cursor no hace nada ni crea punto de undo.

### Cursor al siguiente y previo CC
- Siguiente: primer evento cuya posición queda después de cursor +
  `cc.threshold_sec`. Previo: último que queda antes de cursor - `threshold_sec`.
- `cc.lane_mode` define qué eventos cuentan:
  - `"active"`: solo la lane activa (la última clickeada), leída con
    `MIDIEditor_GetSetting_int(editor, "last_clicked_cc_lane")`.
  - `"visible"`: las lanes visibles, leídas de las líneas `VELLANE` del chunk
    del item. Excluye las lanes ocultas.
  - `"selected"`: solo los CC seleccionados.
  - `"all"`: cualquier CC del take, incluidas las lanes ocultas.
- Codificación de la lane activa: 0-127 es CC, 256-287 es una lane de 14 bits
  (CC n y n+32), 513 pitch bend, 514 program change, 515 channel pressure. La
  lane de velocity (512) y las de texto o sysex no tienen eventos CC: en
  `"active"` no hace nada.
- En el chunk, pitch bend figura como `128`; se traduce a 513. Las lanes de
  program change y channel pressure no se traducen: `"visible"` las ignora.
- No filtra por canal MIDI y cuenta los eventos muteados. Sin evento
  siguiente (o anterior) no hace nada ni crea punto de undo.

### Selección de CC por rango
- Origen: la time selection de REAPER (sin time selection no hace nada), desde
  el cursor hasta el final del take, o desde el inicio del take hasta el cursor.
- Bordes inclusivos, con `cc_range.tolerance_sec`: un evento justo en el cursor
  entra en los dos scripts de cursor.
- Filtro de lane con `cc_range.lane_mode`, independiente de `cc.lane_mode`
  (`"active"`, `"visible"` o `"all"`; `"selected"` no tiene sentido acá).
- `cc_range.mode`: `"replace"` des-selecciona los CC fuera del rango, `"extend"`
  solo suma. Las notas no se tocan.
- Sin eventos en el rango no hace nada ni crea punto de undo. Combina con
  `MoveSelCcToCursor` de `MidiEdit/` para desplazar un tramo de automatización.

### Foco entre ventana principal y MIDI Editor
- Si la ventana en primer plano es un MIDI Editor, enfoca la principal.
- Si no, busca el editor abierto (con `JS_Window_ArrayAllTop`, y como respaldo
  `MIDIEditor_GetActive()`) y lo enfoca.
- Solo si no hay ningún editor abierto lanza `40153` (abrir el ítem
  seleccionado en el editor integrado). Esa acción abre el editor con el zoom
  que tenía al cerrarse, pero con el editor ya abierto lo resetea al zoom del
  contenido del ítem, por eso nunca se la llama si hay un editor.
- Con varios editores abiertos elige uno solo, que no siempre es el último
  usado.

### Marcadores (sin script)
La sección MIDI Editor no tiene acciones de marcador siguiente y previo. Se
resuelve asignando las mismas teclas que tienen esas acciones en el arrange
(`´` y `ç`) a `Misc: Pass through key to main window` en la sección MIDI
Editor. No es una acción que se pueda incluir en una custom action: reenvía
la pulsación a la ventana principal, donde la tecla ya está asignada.

## 3. Config (`MidiNav_config.lua`)

| Sección | Valores |
|---|---|
| raíz | `move_view`, `seek_play` (parámetros de `SetEditCurPos`) |
| `undo` | `enabled` |
| `measure` | `tolerance_sec`, `epsilon_sec` |
| `notes` | `channel_filter` (`"all"` o `"active"`), `include_muted`, `chord_tol_ppq` |
| `select` | `mode`, `move_cursor`, `threshold_sec`, `chord_pick_next`, `chord_pick_prev` |
| `at_cursor` | `mode`, `tolerance_sec` |
| `cc` | `lane_mode`, `threshold_sec` |
| `cc_range` | `mode`, `lane_mode`, `tolerance_sec` |
| `gap` | `position`, `min_gap_ppq`, `no_gap_target`, `no_gap_target_prev`, `selection_continue`, `tiebreak`, `tie_tol_ppq`, `repeat_advances`, `same_pos_tol_sec` |

`notes` es común a gap, selección y notas bajo el cursor (filtro de canal,
notas muteadas y tolerancia de acorde). Los CC no pasan por `notes`.

## 4. Decisiones

- **Sin acciones nativas intermedias:** se lee y se calcula todo con la API de
  MIDI (`MIDI_GetNote`, `MIDI_GetProjTimeFromPPQPos`), sin seleccionar y
  des-seleccionar notas para obtener posiciones. La selección original queda
  intacta y el tiempo respeta cambios de tempo.
- **Dos scripts por acción con dirección** en vez de una variable de config: un
  atajo ejecuta un script fijo, y la ida y la vuelta tienen que estar en dos
  teclas.
- **Undo:** mover el cursor solo genera punto si está activada en las
  preferencias de undo la opción de incluir la posición del cursor; igual se
  envuelve en un bloque para consolidarlo en ambos casos.
- **Dominios planos por propósito** (`MidiNav/`, `MidiEdit/`, y a futuro `MidiGen/` y
  `ScorePrep/`) en vez de una carpeta `Midi/` única: permite filtrar el Action
  List por prefijo, publicar por separado y mantener un config por dominio.
- **Script propio para el foco, no `_S&M_WNFOCUS9`:** la acción de SWS (Cycle
  focused window) va de la ventana principal al editor pero no a la vuelta, ya
  que en el editor no existe una equivalente, y además incluye en el anillo
  cualquier otra ventana abierta. `ToggleMainEditor` solo conoce la principal y
  el editor, y no tiene config.
- **`40153` solo si no hay editor abierto:** con el editor abierto la acción
  resetea el zoom, por eso el script primero busca un editor existente y
  recién después la usa.
- **Marcadores por pass-through, sin script:** `Misc: Pass through key to main
  window` reenvía las teclas del arrange al editor y alcanza para ir al
  marcador siguiente y previo. Un script con `Main_OnCommand` sería la
  alternativa si alguna tecla (por ejemplo una tecla muerta del teclado) no
  se reenviara bien.
- **MidiNav no edita:** selecciona y mueve el cursor; lo que modifica datos va
  a `MidiEdit/` y opera sobre la selección. La selección de CC por rango es
  selección pura y por eso vive acá.
- **Cursor al inicio y final de una nota, sin script:** alcanzan las acciones
  nativas `Navigate: Move edit cursor to start of selected events` y
  `... to end of selected events`.
- **La lane activa no se puede cambiar por código:**
  `MIDIEditor_SetSetting_int(editor, "last_clicked_cc_lane", ...)` devuelve
  `false` y no cambia el valor; solo cambia con un click. Por eso existe
  `lane_mode = "visible"`, que no necesita activar nada.
- **`"visible"` lee el chunk del item:** las `VELLANE` reflejan el orden y las
  lanes mostradas con el editor abierto (ocultar una lane quita su línea;
  mostrarla la agrega según su posición). No equivale a `"all"`: este último
  incluye lanes ocultas. Las sondas están en `Tests-Debug/`
  (`Nik_MidiNav_ProbeCcLane.lua`, `Nik_MidiNav_ProbeLanes.lua`).
- **Filtro de lanes compartido:** `make_filter` vive en `MidiNavCc_common_logic.lua`
  y lo consume el módulo de rango, para que ambos usen la misma lógica.

## 5. Pendientes

- Verificar `channel_filter = "active"`: el canal activo se lee con
  `MIDIEditor_GetSetting_int(editor, "default_note_chan")` y no se contrastó
  contra la documentación de la versión instalada.
- `MidiGen/` (glissandos, curvas CC) y `ScorePrep/` (limpieza del duplicado de
  take pre-Dorico): dominios planeados, sin código todavía. La edición para
  Dorico (solapes, markers y text events) se evalúa en `MidiEdit/`
  (ver `features/midi_edit.md`). Cuando haya un segundo consumidor, extraer
  los helpers de take (enumerar notas, PPQ y tiempo, selección) a
  `_Shared/MidiTake_common_logic.lua`.
- Lanes de program change y channel pressure en `lane_mode = "visible"`: los
  códigos del chunk no están verificados y hoy se ignoran.
- Ciclar la lane activa por código: no hay API de escritura. Alternativa
  descartada por ahora: lista fija `cc.lane_cycle` en config.
- Alta en ReaPack si MidiNav llega a otras PCs. `ToggleMainEditor` depende de
  js_ReaScriptAPI (deployar implica considerar su declaración o dejar fuera)
