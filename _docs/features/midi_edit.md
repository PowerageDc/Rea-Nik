# MidiEdit — edición MIDI sobre la selección

Acciones one-shot para el MIDI Editor que modifican notas o eventos CC, pensadas
para asignar a atajos de teclado. Sin UI. Operan siempre sobre lo que está
seleccionado, así que se componen con cualquier criterio de selección (por
ejemplo los scripts de `features/midi_nav.md`). Config en código en
`MidiEdit_config.lua` (ver `01_CONVENCIONES.md`).

## 1. Scripts

Carpeta `C:\dev\Rea-Nik\MidiEdit\`.

| Script | Qué hace |
|---|---|
| `Nik_MidiEdit_AlignChord.lua` | Iguala inicios y/o finales de las notas seleccionadas |
| `Nik_MidiEdit_MoveSelCcToCursor.lua` | Mueve los CC seleccionados al cursor, con el primero como ancla |
| `Nik_MidiEdit_MoveSelCcEndToCursor.lua` | Igual, con el último como ancla |

Módulo de soporte (solo `dofile`, no se registra):
- `MidiEditCc_common_logic.lua`: `run(anchor)` con `"first"` o `"last"`. Los dos
  scripts de CC son wrappers de dos líneas.

`AlignChord` no usa módulo: es un único script sin dirección.

Registro: sección **MIDI Editor** del Action List. Los tres necesitan un editor
activo y salen sin hacer nada si no lo hay.

## 2. Comportamiento

### AlignChord
- Lee las notas seleccionadas del take (sin filtrar por canal ni por muteadas:
  la selección ya es el criterio).
- `align_chord.starts`: `"earliest"` lleva todos los inicios al más temprano de
  la selección, `"cursor"` los lleva al cursor, `false` no los toca.
- `align_chord.ends`: `"latest"` lleva todos los finales al más lejano,
  `"earliest"` recorta al más corto, `false` no los toca.
- Iguala posiciones, no duraciones: con inicios distintos, dos notas de igual
  largo no terminarían en el mismo punto. No alinea a la grilla.
- Una nota solo se modifica si el nuevo inicio queda antes del nuevo final (con
  `starts = "cursor"`, una nota que termina antes del cursor no se toca).
- Si ninguna nota cambia, no hace nada ni crea punto de undo.
- Para llevar el grupo a la grilla se encadena como custom action con la acción
  nativa `43454` (Edit: Lengthen notes to grid), que respeta la grilla del
  editor (recta, con puntillo o swing). Con dos o más notas seleccionadas esa
  acción necesita que los finales estén en el mismo segmento de grilla, y por
  eso va después de `AlignChord`. Con un final ya sobre una línea, la acción lo
  lleva a la línea siguiente.
- Combinación habitual: `SelectNotesAtCursor` (MidiNav), `AlignChord` y `43454`.

### Mover CC seleccionados al cursor
- Mueve todos los eventos CC seleccionados del take: CC, pitch bend, program
  change y channel pressure. Los eventos de texto y sysex no entran.
- La selección de CC es una sola por take, no por lane: con puntos
  seleccionados en una lane se mueven solo esos; con selección en varias lanes
  se mueven todos y se conservan los offsets entre lanes. También se mueven
  los seleccionados en lanes ocultas.
- Ancla `"first"`: el evento más temprano de la selección queda en el cursor.
  Ancla `"last"`: el más tardío queda en el cursor y el resto se desplaza igual,
  hacia atrás si hace falta.
- Se conservan los offsets relativos y no se toca la forma de las curvas.
- La posición del cursor se redondea al tick. Si el desplazamiento es cero, o
  si algún evento quedaría en posición negativa (antes del inicio del take), no
  mueve nada ni crea punto de undo.
- Para seleccionar un tramo de automatización antes de moverlo, ver
  `SelectCcFromCursor`, `SelectCcToCursor` y `SelectCcInTimeSel` en
  `features/midi_nav.md`.

## 3. Config (`MidiEdit_config.lua`)

| Sección | Valores |
|---|---|
| `undo` | `enabled` |
| `align_chord` | `starts` (`"earliest"`, `"cursor"`, `false`), `ends` (`"latest"`, `"earliest"`, `false`) |

Los scripts de CC solo usan `undo.enabled`.

## 4. Decisiones

- **Dominio propio, separado de MidiNav:** MidiNav solo mueve el cursor y cambia
  la selección; MidiEdit modifica datos. Un script de edición opera sobre la
  selección y no repite filtros de canal ni de muteadas.
- **Igualar, no quantizar:** el quantize nativo lleva a la línea de grilla más
  cercana, no a la siguiente, y no iguala posiciones entre notas. Primero se
  iguala con `AlignChord` y después se usa la acción nativa para la grilla; así
  no se reimplementa la lógica de grilla (swing incluido).
- **Un script para inicios y finales:** comparten la lectura de la selección y
  se activan por separado desde config; con `false` en uno de los dos, el otro
  funciona solo.
- **Dos scripts por ancla** en vez de una variable de config, por la misma razón
  que en MidiNav: un atajo ejecuta un script fijo. El módulo `MidiEditCc` nació
  cuando apareció el segundo consumidor; el wrapper original conserva nombre y
  Command ID.
- **Escritura con `noSort`:** las ediciones usan `noSort = true` y un único
  `MIDI_Sort` al final, para no reordenar el take en cada nota o evento.
- **Undo:** el bloque se abre solo si hay algo para cambiar, así que una
  ejecución sin efecto no deja punto de undo.

## 5. Pendientes

- Limpieza de solapes para exportar a Dorico (notas del mismo pitch que se
  pisan, y otras correcciones solo de playback en REAPER): el formato todavía se
  está depurando antes de scriptearlo.
- Generación de markers y text events: mismo estado, sin formato definido.
- Cuando haya un segundo script que lea notas seleccionadas, extraer esa lectura
  a un módulo común del dominio (hoy vive dentro de `AlignChord`).
- Alta en ReaPack si MidiEdit llega a otras PCs.