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
| `Nik_MidiEdit_Strum.lua` | Rasguea los acordes seleccionados (o el del cursor) con el último estado del panel |
| `Nik_MidiEdit_StrumPanel.lua` | Panel ReaImGui para elegir y ajustar el rasguido, con aplicar y re-aplicar en vivo |
| `Nik_MidiEdit_CcCurve.lua` | Dibuja una curva de CC o pitch bend con el último estado del panel |
| `Nik_MidiEdit_CcCurvePanel.lua` | Panel ReaImGui para elegir y ajustar la curva, con aplicar, punto en el cursor y re-aplicar en vivo |

Módulo de soporte (solo `dofile`, no se registra):
- `MidiEditCc_common_logic.lua`: `run(anchor)` con `"first"` o `"last"`. Los dos
  scripts de CC son wrappers de dos líneas.

`AlignChord` no usa módulo: es un único script sin dirección.

Strum: `MidiEditStrum_common_logic.lua` (solo `dofile`) con `resolve`, `run`,
`rerun`, `can_rerun`, `save`, `load` y `preset_text`. El panel usa además
`_Shared/ImGuiButtonStyle_common_logic.lua` y
`_Shared/ImGuiEditorFocus_common_logic.lua`.

Curvas: `MidiEditCcCurve_common_logic.lua` (solo `dofile`) con `resolve`, `load`,
`save`, `preset_text`, `target`, `resolve_range`, `build_points`, `sample`,
`apply`, `rerun`, `can_rerun`, `insert_point` y `run`. No confundir con
`MidiEditCc_common_logic.lua`, que mueve CC seleccionados. El panel usa los
mismos dos módulos de `_Shared/` que el de Strum.

Registro: sección **MIDI Editor** del Action List (`Nik_MidiEdit_StrumPanel.lua`
y `Nik_MidiEdit_CcCurvePanel.lua` van en **Main**: son ventanas flotantes). Los
scripts one-shot necesitan un editor activo y salen sin hacer nada si no lo hay; 
el panel apunta al último editor visto.

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

### Strum (rasguido)
- Notas: las seleccionadas; sin selección, las no muteadas que arrancan a
  `chord_window_ms` del cursor. Se agrupan en acordes por cercanía de inicio
  respecto de la primera nota; un grupo de una sola nota se saltea.
- Tiempo: `total_ms` se reparte entre las notas según `curva` (menor a 1
  acelera, mayor a 1 frena), con `jitter_ms` determinista por posición. Ancla
  `"first"`, `"last"` o `"center"`. Los milisegundos se convierten a ticks por
  tiempo de proyecto, sin depender del timebase ni del mapa de tempo.
- Dirección: `"down"` va de grave a agudo, `"up"` al revés, `"alternate"`
  alterna por acorde.
- Finales: `"keep"` conserva el final original, `"duration"` conserva la
  duración. Una nota solo se modifica si el nuevo inicio queda antes del final;
  si algún inicio quedara antes del origen del take, ese acorde no se toca.
- Velocities: factor `from` a `to` interpolado por orden de ataque con `curve`,
  `up_scale` en los upstrokes y `jitter`, sobre la velocity original y con
  límite 1 a 127.
- Estado: ExtState `Nik_MidiEdit_Strum` (persistente), compartido por el panel
  y el one-shot; pisa los valores del config hasta elegir un estilo o apretar
  Restaurar.
- Panel: combo de estilo, botones por eje y `DragInt`/`DragDouble`. Un `*`
  marca lo modificado respecto del preset (ancla y finales no cuentan).
  **Copiar preset** deja en el portapapeles el texto Lua para el config.
  **En vivo** re-aplica al soltar un slider o elegir un preset, partiendo de
  las notas originales; la sesión se descarta si cambia el hash del take. El
  foco vuelve al editor tras cada interacción, salvo con un item activo o un
  popup abierto.

### Curvas de CC y pitch bend
- Rango: la time selection; si no hay, de la primera nota seleccionada al final
  de la última. Sin ninguno de los dos no escribe y avisa (cuadro de mensaje en
  el one-shot, línea de estado en el panel). El cursor no es origen del rango.
- Lane: `cc_curve.lane` es `"active"` (la última clickeada, leída con
  `last_clicked_cc_lane`), un CC de 0 a 127 o `"pitchbend"`. Velocity, texto,
  program change, channel pressure y CC de 14 bits no sirven y avisan. Canal:
  `"active"` (`default_note_chan`, que devuelve 0 a 15) o un número de 1 a 16.
- Valores: CC de 0 a 127. En pitch bend, en cents: se convierten a nativos con
  `bend_range_st` (8192 equivale al bend range completo hacia cada lado) y se
  recortan al rango de 14 bits. Cambiar el bend range cambia el valor escrito,
  no los cents. El valor crudo del evento es 8192 más el nativo (100 cents con
  range 2 son 4096 nativos y 12288 crudos).
- Presets: juegos de parámetros sobre cuatro motores. `shape`, `tension`,
  `close` (devuelve la lane a `base` en el último tick) y `resolution` (pisa
  la general) aplican a todos menos `bend`, que no usa `close`.

| Motor | Presets de ejemplo | Parámetros |
|---|---|---|
| `swell` | Campana, Crescendo | `lo`, `hi`, `base`, `peak` (posición del máximo, de 0 a 1) |
| `ramp` | Subida suave, Bajada lineal | `from`, `to`, `base` |
| `osc` | Vibrato, Tremolo, Pulsos, Sierra | `center`, `depth`, `base`, `wave` (`sine`, `triangle`, `square`, `saw_up`, `saw_down`), `hz` o `cycles`, `phase`, `fade_in` (fracción del rango) |
| `bend` | Bend, Bend + vibrato, Bend lento | `rise`, `hold`, `fall`, y `base` más los valores del sostén por lane |

- Resolución: `"native"` escribe pocos puntos con la forma de REAPER entre ellos
  (0 cuadrada, 1 lineal, 2 suave, 3 inicio rápido, 4 final rápido, 5 bézier con
  `tension`). El seno usa 2 entre extremos y 3 o 4 entre un cruce por cero y un
  extremo; la cuadrada, 0. `"dense"` escribe un punto cada `dense_step_ms` con
  forma lineal.
- Bend: tres etapas en el mismo rango.
  - `rise` y `fall`: `unit` (`"ms"` o `"pct"` del rango), `amount`, `shape` y
    `tension`. Con `rise.from_previous` la subida parte del último valor de la
    lane antes del rango; si no hay, de `base`.
  - `hold`: `engine` (`flat`, `osc`, `swell` o `ramp`) y los parámetros de ese
    motor. Con `flat`, `center` es el nivel.
  - La subida termina donde empieza el sostén y la bajada parte de su último
    valor, así que no hay saltos. El último punto del rango vale `base`: sin gap
    entre notas, deja la lane lista para la siguiente. Si subida y bajada no
    entran en el rango se escalan y el sostén queda en cero. `fall.amount = 0`
    es un salto a `base` en el último tick.
- Escritura: `mode = "replace"` borra antes los eventos de esa lane y canal
  dentro del rango; `"merge"` los deja. `MIDI_InsertCC` no tiene `noSort`: se
  insertan todos, se ordena una vez y recién ahí se asigna la forma de cada
  evento, buscándolo por tick, tipo, canal y valores. Dos puntos en el mismo
  tick: el anterior retrocede un tick. Un bloque de undo por aplicación.
- Punto en el cursor (`insert_point`): un evento de forma cuadrada en la lane y
  el canal vigentes, con `base`, con el valor del último evento anterior de esa
  lane y canal (o `base` si no hay), o con un valor fijo (en cents en pitch
  bend). Reemplaza el evento de la misma lane y canal en ese tick. Punto de
  undo propio; descarta la sesión de En vivo porque cambia el take.
- One-shot: aplica el último estado guardado por el panel; sin estado, el
  preset de `cc_curve.preset`.
- Panel: arriba, preset (con `*` si se modificó, y Restaurar), lane, canal y
  rango detectados, y una vista previa que usa las mismas funciones que
  escriben (con 2 s de duración si no hay rango, para calcular los ciclos de
  `hz`). Abajo, Aplicar, Copiar preset, En vivo y el estado. En el medio, cuatro
  pestañas: Forma (controles del motor; en bend, subida, sostén y bajada),
  Valores (bend range, valores de la lane e Invertir con `ramp`), Destino (lane,
  canal, modo y resolución) y Punto. Los sliders ocupan todo el ancho, con
  Ctrl+clic para escribir un valor exacto. El `*` compara contra el preset; lane,
  canal, modo, resolución y bend range no cuentan.
- En vivo: re-aplica al soltar un slider, partiendo de los eventos originales
  del rango y en la lane, el canal y el rango de la última aplicación. Con
  `replace` borra y escribe; con `merge` restaura antes los originales. Cambiar
  lane o canal solo guarda: para otra lane hay que apretar Aplicar. La sesión
  se descarta si cambia el hash del take (completo, no solo las notas). Cada
  re-aplicación es un punto de undo propio.
- Estado: ExtState `Nik_MidiEdit_CcCurve`, clave `state_v2` (persistente),
  compartido por el panel y el one-shot. Pisa los valores del preset en el
  config hasta apretar Restaurar o elegir otro preset; lane, canal, modo,
  resolución y bend range se conservan al cambiar de preset. **Copiar preset**
  deja en el portapapeles el texto Lua con nombre `Custom` para pegar en
  `cc_curve.presets`.

## 3. Config (`MidiEdit_config.lua`)

| Sección | Valores |
|---|---|
| `undo` | `enabled` |
| `align_chord` | `starts` (`"earliest"`, `"cursor"`, `false`), `ends` (`"latest"`, `"earliest"`, `false`) |
| `strum` | `default_style`, `chord_window_ms`, `anchor`, `ends`, `timings`, `dynamics`, `styles` |
| `cc_curve` | `preset`, `lane`, `channel`, `mode`, `resolution`, `dense_step_ms`, `bend_range_st`, `verbose`, `presets` |

Los scripts de mover CC solo usan `undo.enabled`. En `cc_curve`, `verbose`
imprime en la consola lo que escribió el one-shot.

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
- **Strum en milisegundos:** el rasguido es un gesto físico y no debe cambiar con
  el tempo; solo los arpegios largos justificarían una unidad musical.
- **Strum con UI:** elegir y ajustar presets de tres ejes (tiempo, dinámica,
  dirección) pide ver los valores, así que el panel es la forma de elegir y el
  one-shot aplica lo último elegido, para usarlo por atajo sin la ventana.
- **Velocities relativas:** el strum escala la velocity escrita en vez de fijar
  una absoluta, para no perder la dinámica del acorde original.
- **Re-aplicar desde el original:** cada re-aplicación es un punto de undo
  propio (no se fusionan) y la sesión se descarta si el take cambió por otro
  lado, para no pisar ediciones manuales.
- **Presets en juegos de parámetros:** campana, rampas y osciladores son
  variantes de `swell`, `ramp` y `osc`, y los presets son valores guardados
  (como los estilos de Strum). `bend` es un motor aparte porque encadena tres
  etapas en un mismo rango.
- **Pitch bend en cents:** el mismo valor nativo suena distinto según el bend
  range del VSTi (de 2 a 4 st). En cents, un preset suena igual en cualquier
  VSTi y el panel cambia el bend range sin reescribir los presets. El CC de 14
  bits queda fuera: ningún VSTi lo pidió.
- **Subida y bajada en ms o en % del rango:** en ms son un gesto físico, igual
  en notas cortas y largas; en % acompañan al largo de la nota. La bajada vive
  dentro del rango para no depender de un gap con la nota siguiente.
- **Lane activa por defecto:** es lo que se ve en el editor, y no se puede
  cambiar por código (ver `features/midi_nav.md`); por eso el panel permite
  fijar lane y canal.
- **Sesión de En vivo atada a lane, canal y rango:** re-aplicar sobre la lane
  activa de ese momento, o con otra selección, pisaría eventos ajenos a la
  sesión.
- **Punto de forma cuadrada:** mantiene su valor hasta el próximo evento, que
  es lo que hace falta para cerrar un bend o fijar un valor.
- **Sliders en vez de drags en el panel de curvas:** el recorrido completo del
  rango cabe en el ancho del control. Las pestañas dejan siempre visibles la
  vista previa y los botones.

## 5. Pendientes

- Limpieza de solapes para exportar a Dorico (notas del mismo pitch que se
  pisan, y otras correcciones solo de playback en REAPER): el formato todavía se
  está depurando antes de scriptearlo.
- Generación de markers y text events: mismo estado, sin formato definido.
- Cuando haya un segundo script que lea notas seleccionadas, extraer esa lectura
  a un módulo común del dominio (hoy vive dentro de `AlignChord`).
- Alta en ReaPack si MidiEdit llega a otras PCs.
- Curvas CC: una curva por nota con varias seleccionadas (hoy una sola sobre
  todo el rango). Es el caso natural de los bends consecutivos y pide varios
  rangos en la sesión de En vivo.
- Curvas CC: lanes de CC de 14 bits, program change y channel pressure.
- Curvas CC: la forma bézier (`shape = 5`, con `tension`) solo se escribe desde
  el config; el panel no la ofrece y la vista previa la dibuja lineal.
- Migrar la devolución de foco de `VstiControlUi_common_logic.lua` a
  `_Shared/ImGuiEditorFocus_common_logic.lua` cuando termine su desarrollo.