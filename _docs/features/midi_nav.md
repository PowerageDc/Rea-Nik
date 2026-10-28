# MidiNav — navegación en el MIDI Editor

Acciones one-shot para el MIDI Editor, pensadas para asignar a atajos de
teclado. Sin UI. Todo el comportamiento se ajusta en `MidiNav_config.lua`
(config en código, ver `01_CONVENCIONES.md`).

## 1. Scripts

Carpeta `C:\dev\Rea-Nik\MidiNav\`. Los de gap y selección son wrappers de dos
líneas que cargan su módulo y llaman a `run("next")` o `run("prev")`.

| Script | Qué hace |
|---|---|
| `Nik_MidiNav_CursorMeasureStartOrPrev.lua` | Cursor al inicio del compás actual; si ya está ahí, al inicio del anterior |
| `Nik_MidiNav_CursorGapMid.lua` | Cursor al medio del gap entre la nota actual y la siguiente |
| `Nik_MidiNav_CursorGapMidPrev.lua` | Espejo: gap entre la anterior y la actual |
| `Nik_MidiNav_SelectNoteNext.lua` | Selecciona la primera nota posterior al cursor |
| `Nik_MidiNav_SelectNotePrev.lua` | Selecciona la última nota anterior al cursor |

Módulos de soporte (solo `dofile`, no se registran):
- `MidiNav_common_logic.lua`: `collect_notes`, `move_cursor` y `with_undo`.
- `MidiNavGap_common_logic.lua`: lógica de gap, `run(direction)`.
- `MidiNavSelect_common_logic.lua`: lógica de selección, `run(direction)`.

Registro: sección **MIDI Editor** del Action List. El de compás usa tiempo de
proyecto y también funciona registrado en Main; el resto necesita un editor
activo y sale sin hacer nada si no lo hay.

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

## 3. Config (`MidiNav_config.lua`)

| Sección | Valores |
|---|---|
| raíz | `move_view`, `seek_play` (parámetros de `SetEditCurPos`) |
| `undo` | `enabled` |
| `measure` | `tolerance_sec`, `epsilon_sec` |
| `notes` | `channel_filter` (`"all"` o `"active"`), `include_muted`, `chord_tol_ppq` |
| `select` | `mode`, `move_cursor`, `threshold_sec`, `chord_pick_next`, `chord_pick_prev` |
| `gap` | `position`, `min_gap_ppq`, `no_gap_target`, `no_gap_target_prev`, `selection_continue`, `tiebreak`, `tie_tol_ppq`, `repeat_advances`, `same_pos_tol_sec` |

`notes` es común a gap y selección (filtro de canal, notas muteadas y
tolerancia de acorde).

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
- **Dominios planos por propósito** (`MidiNav/`, y a futuro `MidiGen/` y
  `ScorePrep/`) en vez de una carpeta `Midi/` única: permite filtrar el Action
  List por prefijo, publicar por separado y mantener un config por dominio.

## 5. Pendientes

- Verificar `channel_filter = "active"`: el canal activo se lee con
  `MIDIEditor_GetSetting_int(editor, "default_note_chan")` y no se contrastó
  contra la documentación de la versión instalada.
- `MidiGen/` (glissandos, curvas CC) y `ScorePrep/` (limpieza del duplicado de
  take pre-Dorico): dominios planeados, sin código todavía. Cuando haya un
  segundo consumidor, extraer los helpers de take (enumerar notas, PPQ y
  tiempo, selección) a `_Shared/MidiTake_common_logic.lua`.
- Alta en ReaPack si MidiNav llega a otras PCs.