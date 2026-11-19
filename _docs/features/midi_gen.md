# MidiGen — generación de eventos MIDI

Scripts del MIDI Editor que crean datos MIDI nuevos (curvas de CC y pitch bend,
glissando de teclado) sobre una selección. Pensados para asignar a atajos de
teclado, con un panel ReaImGui para elegir y ajustar los parámetros. Config en
código en `MidiGen_config.lua` (ver `01_CONVENCIONES.md`). Lo que modifica notas
o eventos que ya existen vive en `MidiEdit/` (ver `features/midi_edit.md`) y la
navegación y selección en `MidiNav/` (ver `features/midi_nav.md`).

## 1. Scripts

Carpeta `C:\dev\Rea-Nik\MidiGen\`.

| Script | Qué hace |
|---|---|
| `Nik_MidiGen_CcCurve.lua` | Dibuja una curva de CC o pitch bend con el último estado del panel |
| `Nik_MidiGen_CcCurvePanel.lua` | Panel ReaImGui para elegir y ajustar la curva, con aplicar, punto en el cursor y re-aplicar en vivo |
| `Nik_MidiGen_Gliss.lua` | Genera un glissando de teclado con el último estado del panel |
| `Nik_MidiGen_GlissPanel.lua` | Panel ReaImGui para elegir y ajustar el glissando, con vista previa, aplicar y re-aplicar en vivo |

Módulos de soporte (solo `dofile`, no se registran):
- `MidiGenCcCurve_common_logic.lua`: `resolve`, `load`, `save`, `preset_text`,
  `target`, `resolve_range`, `build_points`, `sample`, `apply`, `rerun`,
  `can_rerun`, `insert_point` y `run`. El panel usa además
  `_Shared/ImGuiButtonStyle_common_logic.lua` y
  `_Shared/ImGuiEditorFocus_common_logic.lua`.
- `MidiGenGliss_common_logic.lua`: `resolve`, `load`, `save`, `preset_text`,
  `read_input`, `plan`, `apply`, `rerun`, `can_rerun` y `run`. El panel usa los
  mismos dos módulos de `_Shared/` que el de curvas.

Sonda de la sesión de rehacer: `Tests-Debug/Nik_MidiGen_ProbeGlissRerun.lua`
(aplica un glissando y lo rehace con otros presets sobre la misma sesión).

Registro: los one-shot (`Nik_MidiGen_CcCurve.lua` y `Nik_MidiGen_Gliss.lua`) en
la sección **MIDI Editor** del Action List y los paneles
(`Nik_MidiGen_CcCurvePanel.lua` y `Nik_MidiGen_GlissPanel.lua`) en **Main**
(son ventanas flotantes). Los one-shot necesitan un editor activo y salen sin
hacer nada si no lo hay; los paneles apuntan al último editor visto.

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

### Glissando de teclado
- Genera notas de un conjunto de teclas (blancas o negras) entre un origen y
  un destino, en el canal elegido. Las notas generadas no quedan seleccionadas.
- Origen, por orden de prioridad:
  - Con time selection: ella fija el tiempo (de su inicio a su final) y las
    notas seleccionadas los pitches. Con dos o más, los de la primera y la
    última por inicio; con una, es el destino y el glissando llega a su pitch
    con las `single.count` notas del conjunto que lo preceden; sin notas, el
    `range` del config (`from_pitch` a `to_pitch`, con `direction`). Los dos
    extremos entran si pertenecen al conjunto. La última nota se recorta al
    final de la selección.
  - Sin time selection y con dos o más notas seleccionadas: rellena el hueco.
    La primera (por inicio) es el origen y la última el destino; ambas se
    conservan y se generan solo las notas del conjunto estrictamente entre
    ellas, de grave a agudo o al revés según sus pitches, repartidas entre el
    inicio del origen y el del destino.
  - Sin time selection y con una sola nota seleccionada: es el destino y el
    glissando llega a ella. El origen es `single.from_pitch` (pitch absoluto,
    incluido) o, si no está, `single.count` notas del conjunto en
    `single.direction` (`"up"` viene desde abajo, `"down"` desde arriba). Las
    notas terminan en el inicio del destino.
  - Sin nada de lo anterior no escribe y avisa. Con el origen o el destino
    fuera del conjunto (por ejemplo, un destino en tecla negra con teclas
    blancas) se generan solo las del conjunto y el destino queda tal cual.
- Conjuntos: `sets` guarda los pitch classes de cada uno (`white`, `black`).
  Son fijos: no siguen la tonalidad.
- Tiempo: con una sola nota seleccionada, `timing.mode` es `"total"`
  (`total_ms`) o `"per_note"` (`note_ms` por intervalo); en los otros casos el
  origen fija el tiempo y esos valores no se usan. La duración se mide de la
  primera nota generada al inicio del destino, que hace de nota siguiente.
  `curve` reparte con `f ^ curve` (menor a 1 acelera, mayor a 1 frena) y
  `jitter_ms` suma un desvío determinista desde la segunda nota. Se calcula en
  tiempo de proyecto, así que respeta los cambios de tempo.
- Largo: `contact` es la cantidad de teclas apretadas a la vez. Cada nota dura
  hasta el inicio de la que está `contact` posiciones adelante: 1 es el gesto de
  pulgar (sin solapes ni huecos) y de 2 a 4 el de palma (solape). Las últimas
  se recortan al inicio del destino (o al final de la time selection).
- Velocity: factor de `from` a `to` sobre la velocity del destino, interpolado
  por orden de la nota con `curve` y con `jitter`, entre 1 y 127. Con time
  selection y sin notas, la base es `range.velocity`.
- Canal: `channel` es `"active"` (`default_note_chan`) o un número de 1 a 16.
- Modo: `"merge"` conserva las notas existentes; `"replace"` borra antes las
  notas no seleccionadas del canal que arrancan entre la primera nota generada
  y el final (el destino queda), sin tocar origen ni destino aunque se hayan
  deseleccionado.
- Escritura: inserta todas las notas con `noSort`, ordena una vez y abre un
  solo bloque de undo.
- Presets: juegos de `set`, `contact`, `timing` y `velocity` (Pulgar, Palma y
  Negras).
- One-shot: aplica el último estado guardado por el panel; sin estado, el
  preset de `gliss.preset`.
- Panel: arriba, preset (con `*` si se modificó, y Restaurar) y una vista previa
  de piano roll que usa la misma función que escribe (`plan`): barras con el ancho
  real de cada nota (se ve el solape) y opacidad según la velocity, y en azul las
  notas existentes que rodean al glissando; debajo, un resumen (cantidad de
  notas, rango, duración y origen) o el motivo si no hay glissando posible. En
  el medio, cuatro pestañas: Tiempo, Teclas (conjunto, contacto y velocity),
  Origen (una nota, por cantidad con dirección o por pitch; rango con dirección,
  desde, hasta y velocity) y Salida (canal y modo). Abajo, Aplicar, Copiar
  preset, En vivo y el estado. Los pitches se muestran como nota en cifrado y
  octava (C4 es 60; `OCTAVE_OFFSET` en el panel cambia la convención), y
  Ctrl+clic escribe el número MIDI. En el rango, Desde y Hasta se acomodan según
  la dirección: el que se mueve arrastra al otro cuando lo pasa, y cambiar la
  dirección los intercambia. El `*` compara conjunto, contacto, timing y
  velocity contra el preset; canal, modo, origen y rango no cuentan.
- En vivo: re-aplica al soltar un slider, partiendo del take original: borra lo
  escrito, restaura las notas que borró `replace` y escribe de nuevo sobre el
  origen (notas y time selection) y el canal de la última aplicación; cambiar
  el canal solo guarda. La sesión se descarta si cambia el hash del take
  completo. Cada re-aplicación es un punto de undo propio. La vista previa
  sigue la selección actual; En vivo, la de la última aplicación.
- Estado: ExtState `Nik_MidiGen_Gliss`, clave `state` (persistente), compartido
  por el panel y el one-shot. Pisa los valores del preset en el config hasta
  apretar Restaurar o elegir otro preset; canal, modo, origen y rango se
  conservan al cambiar de preset. **Copiar preset** deja en el portapapeles el
  texto Lua con nombre `Custom` para pegar en `gliss.presets`.

## 3. Config (`MidiGen_config.lua`)

| Sección | Valores |
|---|---|
| `undo` | `enabled` |
| `cc_curve` | `preset`, `lane`, `channel`, `mode`, `resolution`, `dense_step_ms`, `bend_range_st`, `verbose`, `presets` |
| `gliss` | `preset`, `channel`, `mode`, `verbose`, `sets`, `single` (`count`, `direction`, `from_pitch` opcional), `range` (`direction`, `from_pitch`, `to_pitch`, `velocity`), `presets` (`set`, `contact`, `timing`, `velocity`) |

En `cc_curve` y en `gliss`, `verbose` imprime en la consola lo que escribió el
one-shot.

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
- **Glissando solo con conjuntos ejecutables:** blancas (el gesto de pulgar) y
  negras (una pentatónica, con el dorso del dedo). El cromático no es un gesto de
  un solo dedo (en piano se aproxima con la palma o con dos manos) y la escala no
  tiene sentido en un teclado real (sí en arpa o en cuerdas). Como el conjunto es
  una lista de pitch classes, sumar otro es agregar una entrada a `sets`.
- **Largo por contacto en vez de largo fijo:** el pulgar apoya una tecla a la vez;
  la palma, de dos a cuatro, y en un Hammond, sin sustain, suelta enseguida. Un
  solo parámetro cubre ambos gestos y fija el solape.
- **Duración medida hasta el inicio del destino:** el destino hace de nota
  siguiente de la secuencia y el ritmo no tiene un salto al final.
- **Cálculo en tiempo de proyecto:** los ms de los gestos no dependen del tempo
  y no hizo falta el `ms_to_ticks` de Strum.
- **La time selection manda en el tiempo y las notas en los pitches:** como en
  las curvas, una time selection olvidada tiene prioridad sobre la selección de
  notas.
- **Velocity relativa al destino:** las notas generadas no tienen velocity
  propia; escalar la del destino conserva la dinámica de la frase.
- **`merge` por defecto y origen y destino protegidos en `replace`:** borrar
  notas es más riesgoso que reemplazar CC.
- **`plan` puro compartido:** la vista previa, Aplicar y En vivo usan el mismo
  cálculo, que no toca el take.
- **Vista previa de piano roll:** lo que distingue a un glissando de otro es el
  solape, la aceleración y la llegada al destino; un resumen en texto no lo
  muestra.
- **Pitches en cifrado y dirección del rango:** el cifrado es la forma de leer
  del panel y la dirección evita que Desde y Hasta se crucen sin querer.
- **Módulo propio dentro de `MidiGen/`:** lo común con Strum (pseudoaleatorio
  determinista) se extrae a `_Shared/` cuando lo use otro dominio.

## 5. Pendientes

- Glissando: con una sola nota seleccionada y sin time selection siempre llega a
  ella (ancla de llegada); falta un ancla de salida para el glissando que parte
  de una nota.
- Pedal de sustain (CC64) para teclados: panel y one-shot. Sin código todavía;
  falta definir los puntos de cambio (compás, acorde, armonía o marcadores de
  MusicState), el estilo (legato, sostenido o medio pedal) y qué hacer con los
  CC64 existentes.
- Módulo común del glissando y el pedal: hoy el glissando es autosuficiente
  (`MidiGenGliss_common_logic.lua`, con su propio pseudoaleatorio determinista,
  lectura de notas y escritura); con el pedal, extraer lo común dentro de
  `MidiGen/`, y a `_Shared/MidiTake_common_logic.lua` solo cuando lo use otro
  dominio (hoy Strum duplica `ms_to_ticks` y el pseudoaleatorio).
- Curvas CC: una curva por nota con varias seleccionadas (hoy una sola sobre
  todo el rango). Es el caso natural de los bends consecutivos y pide varios
  rangos en la sesión de En vivo.
- Curvas CC: lanes de CC de 14 bits, program change y channel pressure.
- Curvas CC: la forma bézier (`shape = 5`, con `tension`) solo se escribe desde
  el config; el panel no la ofrece y la vista previa la dibuja lineal.
- Alta en ReaPack si MidiGen llega a otras PCs.