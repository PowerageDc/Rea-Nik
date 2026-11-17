# MidiGen — generación de eventos MIDI

Scripts del MIDI Editor que crean datos MIDI nuevos (hoy, eventos CC y pitch
bend) sobre una selección. Pensados para asignar a atajos de teclado, con un
panel ReaImGui para elegir y ajustar los parámetros. Config en código en
`MidiGen_config.lua` (ver `01_CONVENCIONES.md`). Lo que modifica notas o
eventos que ya existen vive en `MidiEdit/` (ver `features/midi_edit.md`) y
la navegación y selección en `MidiNav/` (ver `features/midi_nav.md`).

## 1. Scripts

Carpeta `C:\dev\Rea-Nik\MidiGen\`.

| Script | Qué hace |
|---|---|
| `Nik_MidiGen_CcCurve.lua` | Dibuja una curva de CC o pitch bend con el último estado del panel |
| `Nik_MidiGen_CcCurvePanel.lua` | Panel ReaImGui para elegir y ajustar la curva, con aplicar, punto en el cursor y re-aplicar en vivo |

Módulo de soporte (solo `dofile`, no se registra):
- `MidiGenCcCurve_common_logic.lua`: `resolve`, `load`, `save`, `preset_text`,
  `target`, `resolve_range`, `build_points`, `sample`, `apply`, `rerun`,
  `can_rerun`, `insert_point` y `run`. El panel usa además
  `_Shared/ImGuiButtonStyle_common_logic.lua` y
  `_Shared/ImGuiEditorFocus_common_logic.lua`.

Registro: `Nik_MidiGen_CcCurve.lua` en la sección **MIDI Editor** del Action
List y `Nik_MidiGen_CcCurvePanel.lua` en **Main** (es una ventana flotante).
El one-shot necesita un editor activo y sale sin hacer nada si no lo hay; el
panel apunta al último editor visto.

## 2. Comportamiento

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
  `tension`). El seno usa 2 entre extremos y 3 o 4 entre un cruce por cero y
  un extremo; la cuadrada, 0. `"dense"` escribe un punto cada `dense_step_ms`
  con forma lineal.
- Bend: tres etapas en el mismo rango.
  - `rise` y `fall`: `unit` (`"ms"` o `"pct"` del rango), `amount`, `shape` y
    `tension`. Con `rise.from_previous` la subida parte del último valor de la
    lane antes del rango; si no hay, de `base`.
  - `hold`: `engine` (`flat`, `osc`, `swell` o `ramp`) y los parámetros de ese
    motor. Con `flat`, `center` es el nivel.
  - La subida termina donde empieza el sostén y la bajada parte de su último
    valor, así que no hay saltos. El último punto del rango vale `base`: sin
    gap entre notas, deja la lane lista para la siguiente. Si subida y bajada
    no entran en el rango se escalan y el sostén queda en cero.
    `fall.amount = 0` es un salto a `base` en el último tick.
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
  Ctrl+clic para escribir un valor exacto. El `*` compara contra el preset;
  lane, canal, modo, resolución y bend range no cuentan.
- En vivo: re-aplica al soltar un slider, partiendo de los eventos originales
  del rango y en la lane, el canal y el rango de la última aplicación. Con
  `replace` borra y escribe; con `merge` restaura antes los originales. Cambiar
  lane o canal solo guarda: para otra lane hay que apretar Aplicar. La sesión
  se descarta si cambia el hash del take (completo, no solo las notas). Cada
  re-aplicación es un punto de undo propio.
- Estado: ExtState `Nik_MidiGen_CcCurve`, clave `state_v2` (persistente),
  compartido por el panel y el one-shot. Pisa los valores del preset en el
  config hasta apretar Restaurar o elegir otro preset; lane, canal, modo,
  resolución y bend range se conservan al cambiar de preset. **Copiar preset**
  deja en el portapapeles el texto Lua con nombre `Custom` para pegar en
  `cc_curve.presets` de `MidiGen_config.lua`.

## 3. Config (`MidiGen_config.lua`)

| Sección | Valores |
|---|---|
| `undo` | `enabled` |
| `cc_curve` | `preset`, `lane`, `channel`, `mode`, `resolution`, `dense_step_ms`, `bend_range_st`, `verbose`, `presets` |

`verbose` imprime en la consola lo que escribió el one-shot.

## 4. Decisiones

- **Dominio propio, separado de MidiEdit:** MidiEdit modifica lo que ya existe
  (Strum reacomoda notas, mover CC desplaza eventos); MidiGen crea eventos
  nuevos. Las curvas se movieron de `MidiEdit/` a `MidiGen/` antes de sumar
  glissando y pedal de sustain, que también crean.
- **Re-aplicar desde el original:** cada re-aplicación es un punto de undo
  propio (no se fusionan) y la sesión se descarta si el take cambió por otro
  lado, para no pisar ediciones manuales.
- **Presets en juegos de parámetros:** campana, rampas y osciladores son
  variantes de `swell`, `ramp` y `osc`, y los presets son valores guardados.
  `bend` es un motor aparte porque encadena tres etapas en un mismo rango.
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

- Glissando para teclados: panel y one-shot, con tiempo en milisegundos. Sin
  código todavía; falta definir origen y destino, conjunto de notas (cromático,
  teclas blancas o negras, escala), reparto de tiempo y de velocity, largo de
  cada nota y qué hacer con las notas existentes del rango.
- Pedal de sustain (CC64) para teclados: panel y one-shot. Sin código todavía;
  falta definir los puntos de cambio (compás, acorde, armonía o marcadores de
  MusicState), el estilo (legato, sostenido o medio pedal) y qué hacer con los
  CC64 existentes.
- Módulo común de glissando y pedal: dentro de `MidiGen/` hasta que otro
  dominio lo necesite; extraer a `_Shared/MidiTake_common_logic.lua` solo
  cuando haya un segundo consumidor (hoy Strum duplica `ms_to_ticks`).
- Curvas CC: una curva por nota con varias seleccionadas (hoy una sola sobre
  todo el rango). Es el caso natural de los bends consecutivos y pide varios
  rangos en la sesión de En vivo.
- Curvas CC: lanes de CC de 14 bits, program change y channel pressure.
- Curvas CC: la forma bézier (`shape = 5`, con `tension`) solo se escribe desde
  el config; el panel no la ofrece y la vista previa la dibuja lineal.
- Alta en ReaPack si MidiGen llega a otras PCs.