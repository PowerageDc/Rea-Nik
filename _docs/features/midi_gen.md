# MidiGen — generación de eventos MIDI

Scripts del MIDI Editor que crean datos MIDI nuevos (curvas de CC y pitch bend,
glissando de teclado, pedal de sustain) sobre una selección. Pensados para 
asignar a atajos de teclado, con un panel ReaImGui para elegir y ajustar los
parámetros. Config en código en `MidiGen_config.lua` (ver `01_CONVENCIONES.md`).
Lo que modifica notas o eventos que ya existen vive en `MidiEdit/` (ver 
`features/midi_edit.md`) y la navegación y selección en `MidiNav/` (ver 
`features/midi_nav.md`).

## 1. Scripts

Carpeta `C:\dev\Rea-Nik\MidiGen\`.

| Script | Qué hace |
|---|---|
| `Nik_MidiGen_CcCurve.lua` | Dibuja una curva de CC o pitch bend con el último estado del panel |
| `Nik_MidiGen_CcCurvePanel.lua` | Panel ReaImGui para elegir y ajustar la curva, con aplicar, punto en el cursor y re-aplicar en vivo |
| `Nik_MidiGen_Gliss.lua` | Genera un glissando de teclado con el último estado del panel |
| `Nik_MidiGen_GlissPanel.lua` | Panel ReaImGui para elegir y ajustar el glissando, con vista previa, aplicar y re-aplicar en vivo |
| `Nik_MidiGen_Pedal.lua` | Genera el pedal de sustain (CC64) con el último estado del panel |
| `Nik_MidiGen_PedalPanel.lua` | Panel ReaImGui para elegir y ajustar el pedal, con vista previa de notas y pedal, aplicar, presionar y soltar en el cursor y re-aplicar en vivo |
| `Nik_MidiGen_PedalPress.lua` | Escribe el pedal presionado en el cursor, con el último estado del panel |
| `Nik_MidiGen_PedalRelease.lua` | Escribe el pedal suelto (0) en el cursor, con el último estado del panel |

Módulos de soporte (solo `dofile`, no se registran):
- `MidiGenCcCurve_common_logic.lua`: `resolve`, `load`, `save`, `preset_text`,
  `target`, `resolve_range`, `build_points`, `sample`, `apply`, `rerun`,
  `can_rerun`, `insert_point` y `run`. El panel usa además
  `_Shared/ImGuiButtonStyle_common_logic.lua` y
  `_Shared/ImGuiEditorFocus_common_logic.lua`.
- `MidiGenGliss_common_logic.lua`: `resolve`, `load`, `save`, `preset_text`,
  `read_input`, `plan`, `apply`, `rerun`, `can_rerun` y `run`. El panel usa los
  mismos dos módulos de `_Shared/` que el de curvas.
- `MidiGenCc_common_logic.lua`: escritura de eventos CC y pitch bend en un take
  (`lane_info`, `encode`, `matches`, `floor_ppq`, `take_hash`, `read_range`,
  `delete_range` e `insert_events`). Lo consumen las curvas y el pedal.
- `MidiGenPedal_common_logic.lua`: `resolve`, `load`, `save`, `preset_text`,
  `read_input`, `from_source`, `plan`, `apply`, `rerun`, `can_rerun`, `run`,
  `cursor_point`, `run_cursor` y `LIMITS`. Toma `resolve_range` del módulo de
  curvas. El panel usa los mismos dos módulos de `_Shared/` que los otros.

Sondas: `Tests-Debug/Nik_MidiGen_ProbeGlissRerun.lua` (aplica un glissando y lo
rehace con otros presets sobre la misma sesión),
`Tests-Debug/Nik_MidiGen_ProbePedalPlan.lua` (imprime en la consola el plan del
pedal con un preset, sin escribir) y `Tests-Debug/Nik_MidiGen_ProbePedalRerun.lua`
(aplica el pedal y lo rehace con otro preset, y compara los CC64 del rango con
lo planeado).

Registro: los one-shot (`Nik_MidiGen_CcCurve.lua`, `Nik_MidiGen_Gliss.lua`,
`Nik_MidiGen_Pedal.lua`, `Nik_MidiGen_PedalPress.lua` y
`Nik_MidiGen_PedalRelease.lua`) en la sección **MIDI Editor** del Action List y
los paneles (`Nik_MidiGen_CcCurvePanel.lua`, `Nik_MidiGen_GlissPanel.lua` y
`Nik_MidiGen_PedalPanel.lua`) en **Main** (son ventanas flotantes). Los one-shot
necesitan un editor activo y salen sin hacer nada si no lo hay; los paneles
apuntan al último editor visto.

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

### Pedal de sustain (CC64)
- Escribe el pedal de un teclado sobre la time selection o, sin ella, desde la
  primera nota seleccionada hasta el final de la última (el mismo rango que las
  curvas, vía `resolve_range`). La time selection manda sobre la selección de
  notas; sin ninguna de las dos avisa y no escribe.
- Ataques: las notas no muteadas del take que arrancan dentro del rango,
  filtradas por el canal de origen (`source_channel`: `all`, `active` o 1 a 16).
  Solo importan al cambio por acorde.
- Estilo `legato`: en cada punto de cambio el pedal se levanta y vuelve a bajar.
  Estilo `sustained`: baja al inicio del rango y se suelta al final, sin puntos
  de cambio.
- Punto de cambio (`change`): `chord` agrupa los ataques por `chord_window_ms`
  (el punto es el inicio del primero) y descarta los que quedan a menos de
  `min_gap_ms` del anterior; `bar` toma el inicio de cada compás del rango según
  el mapa de compases. El plan recibe los puntos como lista de ticks y no sabe
  de dónde vinieron.
- Levantado: `offset_ms` lo desplaza respecto del punto (negativo: antes, para
  un corte limpio; positivo: después de que suena el acorde nuevo) y `dip_ms` es
  el tiempo total entre el inicio del levantado y el del re-presionado. `dip_ms`
  se recorta contra el siguiente levantado, así que el plan nunca produce
  eventos desordenados.
- Primer punto: en `chord` no levanta (no hay acorde anterior en el rango); en
  `bar` levanta todo punto posterior al inicio. Con `lift_first` también levanta
  el primer punto de `chord`, para cortar un pedal que venía presionado de antes;
  si su levantado cae antes del inicio del rango, se recorta al inicio y
  reemplaza al presionado inicial.
- Valores y forma: `down_value` (127) y `up_value` (0; con un valor intermedio
  es medio pedal, que Pianoteq y Keyscape leen como continuo), siempre con
  `down_value` mayor que `up_value`. `shape` 0 es cuadrada; de 1 a 5 cada rampa
  dura `transition_ms` dentro del `dip_ms` (se achica si no entra y cae a
  cuadrada si no llega a un tick).
- Arranque (`start`): `range` escribe `down_value` en el inicio del rango;
  `first_attack`, en el primer ataque. Cierre (`close`): escribe 0, no
  `up_value`, al final del rango.
- CC64 existentes: `replace` borra los del canal de salida dentro del rango;
  `merge` los conserva. El canal de salida (`channel`: `active` o 1 a 16) y el
  de origen son independientes.
- Panel: vista previa de dos franjas sobre el mismo eje de tiempo (arriba las
  notas, las de otros canales atenuadas; abajo la línea del pedal con relleno y
  una línea tenue en cada punto de cambio). Las rampas se dibujan rectas aunque
  `shape` sea de 2 a 5. Preset con `*` y Restaurar; el `*` compara estilo,
  cambio, arranque, cierre, `lift_first` y los números contra el preset (canal,
  origen, modo y `cursor_shape` no cuentan). Pestañas Cambio, Valores y Salida,
  con los rangos de los sliders en `LIMITS`.
- En vivo: re-aplica al soltar un slider, partiendo de los CC64 originales del
  rango y en el canal de salida y el rango de la última aplicación. Con
  `replace` borra y escribe; con `merge` restaura antes los originales. Cambiar
  el canal de salida solo guarda; cambiar el de origen re-aplica. La sesión se
  descarta si cambia el hash del take completo. Cada re-aplicación es un punto de
  undo propio.
- Presionar y soltar en el cursor (botones del panel y one-shots
  `Nik_MidiGen_PedalPress.lua` y `Nik_MidiGen_PedalRelease.lua`): escriben
  `down_value` o 0 en el cursor y en el canal de salida, reemplazando el CC64 del
  mismo tick, en un solo punto de undo. Con `cursor_shape = "inherit"` el punto
  toma la forma y la tensión del evento anterior si hay uno posterior (así el
  tramo siguiente conserva su clase); sin evento posterior queda cuadrado. Con
  `"square"` queda cuadrado y el evento anterior se reescribe cuadrado, para que
  el tramo hasta el cursor sea un salto seco. Con el cursor fuera del item
  avisa y no escribe. Cambia el hash del take, así que En vivo queda sin sesión
  hasta el próximo Aplicar.
- Estado: ExtState `Nik_MidiGen_Pedal`, clave `state` (persistente), compartido
  por el panel y los one-shot. Pisa los valores del preset en el config hasta
  apretar Restaurar o elegir otro preset; canal, origen, modo y `cursor_shape`
  se conservan al cambiar de preset, y al cargar se descartan los números fuera
  de `LIMITS` y un par `down_value`, `up_value` invertido. **Copiar preset** deja
  en el portapapeles el texto Lua con nombre `Custom` para pegar en
  `pedal.presets` (sin canales, modo ni `cursor_shape`).

## 3. Config (`MidiGen_config.lua`)

| Sección | Valores |
|---|---|
| `undo` | `enabled` |
| `cc_curve` | `preset`, `lane`, `channel`, `mode`, `resolution`, `dense_step_ms`, `bend_range_st`, `verbose`, `presets` |
| `gliss` | `preset`, `channel`, `mode`, `verbose`, `sets`, `single` (`count`, `direction`, `from_pitch` opcional), `range` (`direction`, `from_pitch`, `to_pitch`, `velocity`), `presets` (`set`, `contact`, `timing`, `velocity`) |
| `pedal` | `preset`, `channel`, `source_channel`, `mode`, `cursor_shape`, `verbose`, `presets` (`style`, `change`, `chord_window_ms`, `min_gap_ms`, `offset_ms`, `dip_ms`, `down_value`, `up_value`, `shape`, `transition_ms`, `start`, `close`, `lift_first` opcional) |

En `cc_curve`, `gliss` y `pedal`, `verbose` imprime en la consola lo que escribió
el one-shot.

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
- **Pedal: presets completos y plan puro:** cada preset lista todos los campos
  aunque `bar` no use la ventana de acorde, para que el panel cambie de modo sin
  inventar valores; `resolve` falla con el campo que falta. El plan no toca el
  take y alimenta la vista previa, Aplicar y En vivo.
- **Pedal: medio pedal como valor, no como estilo:** es legato con `up_value`
  intermedio. Pianoteq y Keyscape leen el CC64 como continuo, por eso también
  hay forma gradual.
- **Pedal: `dip_ms` es el tiempo total del levantado:** las rampas van adentro,
  así el recorte contra el siguiente punto es uno solo.
- **Pedal: el cierre escribe 0:** con medio pedal, escribir `up_value` dejaba el
  pedal medio presionado después de la selección.
- **Pedal: `min_gap_ms` en 150:** con 350 se fundían acordes a corcheas a 120
  BPM; 150 deja pasar corcheas y funde semicorcheas.
- **Pedal: el primer punto de `chord` no levanta, salvo `lift_first`:** al
  aplicar sobre un tramo del medio de una canción hay un acorde anterior que
  cortar. En `bar` siempre levanta porque el compás anterior sigue sonando.
- **Pedal: lectura de notas propia:** el pedal copia la lectura y agrupación de
  Strum en vez de extraerla, para no tener que volver a probar Strum.
- **Pedal: la escritura de CC es un módulo compartido** (`MidiGenCc_common_logic.lua`),
  extraído de las curvas cuando el pedal fue el segundo consumidor.
- **Pedal en el cursor: forma heredada:** cada evento CC guarda la forma del
  tramo que arranca en él, así que insertar un punto dentro de una rampa cambia
  la clase del tramo siguiente. Heredar la forma del evento anterior conserva la
  clase; la pendiente no se puede conservar porque los extremos de una rampa son
  los eventos mismos. `"square"` es la alternativa para un corte seco.

## 5. Pendientes

- Glissando: con una sola nota seleccionada y sin time selection siempre llega a
  ella (ancla de llegada); falta un ancla de salida para el glissando que parte
  de una nota.
- Pedal: punto de cambio por armonía o marcadores de MusicState. Pide leer sus
  datos desde Lua; el plan ya recibe los puntos como lista de ticks, así que es
  una función más que produzca esa lista.
- Pedal: el evento anterior al rango. Aplicar y En vivo escriben su primer
  evento sin mirar la forma del CC64 anterior al rango: si era gradual, su tramo
  pasa a terminar en el pedal nuevo. Presionar y soltar en el cursor ya lo
  resuelven con `cursor_shape`.
- Replicar `cursor_shape` y la herencia de forma en lo que escriba un punto CC con
  un evento anterior: el punto en el cursor de las curvas (`insert_point`), el
  primer evento de Aplicar del pedal y cualquier panel futuro que aplique un
  cambio sobre una lane con eventos antes del rango. Con el segundo consumidor,
  mover la decisión de forma (heredar o cuadrar, y reescribir el anterior) de
  `cursor_point` a `MidiGenCc_common_logic.lua`.
- Pedal: la vista previa dibuja las rampas rectas aunque `shape` sea de 2 a 5.
- Módulos comunes: el pedal copia la lectura de notas y la agrupación en
  acordes de Strum (`read_notes`, `group_chords`) y el glissando tiene la suya
  (`selected_notes`); extraer a `_Shared/MidiTake_common_logic.lua` cuando haya
  un tercer consumidor o se toque Strum. Además, el glissando sigue con su propio
  pseudoaleatorio determinista y su escritura de notas (Strum duplica
  `ms_to_ticks` y el pseudoaleatorio).
- Pedal: `resolve_range` se toma del módulo de curvas; si el acoplamiento
  molesta, moverlo a `MidiGenCc_common_logic.lua`. `decode` y `value_before`
  siguen en las curvas.
- Curvas CC: una curva por nota con varias seleccionadas (hoy una sola sobre
  todo el rango). Es el caso natural de los bends consecutivos y pide varios
  rangos en la sesión de En vivo.
- Curvas CC: lanes de CC de 14 bits, program change y channel pressure.
- Curvas CC: la forma bézier (`shape = 5`, con `tension`) solo se escribe desde
  el config; el panel no la ofrece y la vista previa la dibuja lineal.
- Alta en ReaPack si MidiGen llega a otras PCs.