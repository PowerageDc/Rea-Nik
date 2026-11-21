# TempoTap — mapeo de tempo por taps

Mapeo de tempo de una canción tocando el pulso en vivo (markers) y convirtiendo
los taps en tempo markers, con alineación del contenido y snap opcional a los
ataques del audio. Alternativa a ReaBeat más edición manual (ver
`features/tempo_mapping.md`). Dominio: `TempoTools/`.

## 1. Flujo

```
taps en vivo (TAP / TAP1)
        │
        ▼
Read.group   → compases (modo bar o beat, compás declarado o inferido)
        │
        ▼
Snap.run     → ajusta a los ataques del audio (en memoria)
        │
        ▼
Vista previa → revisión del resultado: bloqueos, política y casillas (ReaImGui)
        │
        ▼
Plan.build   → tempo inicial, pre-roll, desplazamiento y tempo markers
        │
        ▼
Apply        → mueve stems y taps, ajusta el click, mapa de tempo, verificación
```

`Nik_TempoTools_Apply.lua` corre el snap y abre la vista previa; al aplicar,
`Plan.build` recibe los compases resultantes y siguen el diálogo de pre-roll y la
confirmación. Cancelar cualquiera de los dos reabre la vista previa con el mismo
estado; cancelar o cerrar la ventana termina el script sin tocar el proyecto.

## 2. Taps

Markers del proyecto con nombre fijo y color propio (no se mezclan con los
markers de sección):

| Nombre | Qué es | Color |
|---|---|---|
| `TAP` | beat | azul |
| `TAP1` | downbeat (el uno del compás) | naranja |
| `TAP1 6/8` | downbeat que declara el compás desde ahí | naranja |

- El tramo es por beat o por compás según lo que se toque entre dos downbeats:
  taps de beat en medio dan un tempo marker por beat; solo downbeats, uno por compás.
- Sin compás declarado, el compás de un tramo por beat se infiere por conteo de
  taps (un 3/4 suelto dentro de un 4/4 vuelve solo a 4/4 en el compás siguiente).
  En un tramo por compás el compás se hereda hasta que se declare otro.
- Una pasada termina con un downbeat: los taps antes del primero y después del
  último se ignoran; `Read.group` devuelve el aviso, que `Apply` no muestra.

## 3. Archivos

| Archivo | Rol |
|---|---|
| `TempoTools/TempoTools_common_logic.lua` | nombres y colores de los taps, alta, borrado (`clear_taps` con su bloque de deshacer, `delete_taps` sin él) y `shift_taps` |
| `TempoTools/Nik_TempoTools_TapBeat.lua`, `Nik_TempoTools_TapDownbeat.lua` | acciones de tap, asignables a teclas |
| `TempoTools/Nik_TempoTools_TapClear.lua` | borra todos los taps tras confirmar |
| `TempoTools/TempoTapRead_common_logic.lua` | `read_taps`, `group` (compases y avisos), `pulses` |
| `TempoTools/TempoTapPlan_common_logic.lua` | `build`: tempo inicial, pre-roll, desplazamiento y markers |
| `TempoTools/TempoTapItems_common_logic.lua` | `collect`, `evaluate`, `apply` y `fit_click` sobre los items |
| `TempoTools/TempoTapMap_common_logic.lua` | `apply` y `verify` del mapa de tempo |
| `TempoTools/TempoTapOnset_common_logic.lua` | detector de ataques: `candidates`, `resolve` |
| `TempoTools/TempoTapSnap_common_logic.lua` | `run`: snap en memoria, con regla de rechazo, puntos bloqueados y caché de detección |
| `TempoTools/TempoTapPreview_common_logic.lua` | modelo de la vista previa, sin ImGui: `new`, `recompute`, `toggle_lock`, `set_policy`, `set_interp_max`, `set_inner_beats`, `go_to`, `measures` |
| `TempoTools/TempoTapPreviewUi_common_logic.lua` | ventana ReaImGui de la vista previa: `run` |
| `TempoTools/Nik_TempoTools_Apply.lua` | acción principal: snap, vista previa, plan y aplicación |
| `TempoTools/TempoTools_config.lua` | config en código |
| `_Shared/ImGuiButtonStyle_common_logic.lua`, `_Shared/ImGuiEditorFocus_common_logic.lua` | botones de la ventana y foco de vuelta a REAPER |
| `Tests-Debug/Nik_TempoTools_Probe*.lua` | sondas de solo lectura (Read, Plan, Items, Map, SigBpm, Onset, Snap, Preview); `ProbePreviewUi` abre la ventana sin aplicar y solo mueve el cursor |

## 4. Plan de tempo

- Tempo inicial: mediana de la duración de los primeros 4 compases con el mismo
  compás que el primero.
- Pre-roll: cantidad de compases del count-in. `Apply` la pide en un diálogo,
  cargada con `preroll_bars_default` si los stems están recién importados (en 0)
  o deducida de la posición actual si ya están alineados.
- Desplazamiento: lo que hay que mover el contenido para que el primer downbeat
  caiga tras el pre-roll a la duración de compás del tempo inicial.
- El compás se anota solo en el marker donde cambia; un marker de cierre en el
  último downbeat sostiene el último tempo.
- Compases omitidos con aviso: sin conversión validada (solo denominador 4 y
  compuestos ternarios sobre 8) o con cantidad de beats distinta de la esperada.

## 5. REAPER: compás y BPM (medido)

`Nik_TempoTools_ProbeSigBpm.lua` en un proyecto vacío, a 120 bpm: el BPM va en
negras por minuto aunque el denominador sea 8.

| Compás | Duración | Negras |
|---|---|---|
| 4/4 | 2,00 s | 4,0 |
| 3/4 | 1,50 s | 3,0 |
| 2/4 | 1,00 s | 2,0 |
| 6/8 | 1,50 s | 3,0 |
| 9/8 | 2,25 s | 4,5 |
| 12/8 | 3,00 s | 6,0 |
| 5/8 | 1,25 s | 2,5 |
| 2/2 | 2,00 s | 4,0 |

Un pulso compuesto ternario es una negra con puntillo (1,5 negras), por lo que el
BPM de un marker compuesto es 1,5 × pulsos por minuto (`COMPOUND_FACTOR`). Con
0,75 el compás duraba el doble de lo tapeado (visto con 6/8 en `Nik_TempoTools_ProbeMap.lua`).
Con 1,5 el 6/8 quedó alineado (grilla, metrónomo nativo y oído).

## 6. Aplicación

Un solo bloque de deshacer; una segunda corrida sobre un proyecto ya alineado da
desplazamiento cero.

- **Stems:** items de los tracks hijos del Stem Bus (`StemBus_common_logic.lua`) y
  el track de instrumental (`Mvsep.is_instrumental`, hermano del folder). Se mueven
  por el desplazamiento, igual que los taps.
- **Click:** track `Beep`, primer item. Cambia solo su largo: el final anterior más
  el desplazamiento, fijado con `Items.fit_click` después de aplicar el mapa de
  tempo. Un item en timebase beats guarda su largo en beats y lo recalcula con cada
  cambio del mapa; fijarlo antes lo deformaba (de 2:23.293 a 1:52.090 en una
  canción rápida).
- **Taps:** se mueven con el contenido. Con "Borrar los taps al aplicar"
  (`clear_taps_after`, apagado por defecto) se borran al final con `delete_taps`,
  dentro del mismo bloque de deshacer; sin taps no hay segunda corrida, y un
  Ctrl+Z los devuelve.
- **Count-in:** track `COUNT IN`. Se pasa a timebase beats si no lo está y se avisa
  si su largo no coincide con los compases del pre-roll. No se mueve.
- **Otros items:** no se tocan.
- **Mapa de tempo:** se borran los markers entre el inicio y el último downbeat,
  se fija el tempo inicial en un marker en 0, se insertan los del plan y se
  restituye en una segunda pasada la posición de los markers posteriores
  (restitución sin probar).
- **Verificación:** posiciones contra el plan, downbeats en inicio de compás y
  numeración de compases consecutiva. Validado con pasadas por downbeats y por
  beat, 6/8 declarado y 3/4 inferido antes del snap, y con el snap integrado en un
  12/8 de una canción real, un 6/8 declarado y un 3/4 suelto sin declarar.

## 7. Snap a transientes

- **Detector** (`TempoTapOnset_common_logic.lua`): amplitud por bloques de 2 ms
  desde un `AudioAccessor` solo en la ventana de cada tap; el ataque es la subida
  de amplitud contra los bloques previos, normalizada por la amplitud mediana
  local (`ratio`). Se acepta desde `snap_min_ratio`.
- **Referencias** (`snap_references`): lista en orden de prioridad de nombres de
  track, `@instrumental` o `@all` (suma de todos los stems). Para cada tap gana la
  primera con un ataque en la ventana, aunque el item exista y esté en silencio.
- **Ventana:** `snap_window_ratio` por el intervalo local, entre `snap_window_min`
  y `snap_window_max`. Se elige el ataque más cercano al tap, no el más fuerte.
- **Orden de pasos** (`Snap.run`): downbeats, reparto uniforme de los beats
  interiores de los compases por compás, beats, e interpolación de tramos cortos
  sin ataque entre dos anclas (`snap_unanchored`, `snap_interp_max`). Un compás
  por compás pasa a un marker por beat si algún beat interior se ancla
  (con `snap_inner_beats` activo, el valor por defecto).
- **Marcas:** baja confianza (ratio menor a `snap_high_ratio`) y dudoso (desvío
  mayor a `snap_outlier_k` veces la mediana de desvíos). Marcan, salvo un caso: un 
  punto de baja confianza y dudoso a la vez no se ancla (regla de rechazo, abajo).
- **Regla de rechazo:** el "dudoso" depende de la mediana de desvíos de toda la
  corrida, así que se decide en dos pasadas. En la primera se calculan las marcas y
  los puntos de baja confianza y dudosos a la vez pasan a un conjunto de rechazados;
  en la segunda se tratan como puntos sin ataque y siguen la política de interpolar
  o dejar el tap. Conservan la posición y el ratio del ataque descartado
  (`rejected_pos`, `rejected_ratio`) y las marcas finales se recalculan sobre la
  segunda pasada. En una canción de tempo medio rechazó dos puntos (x2,7 con −35,6 ms
  y x3,1 con −33,9 ms); en la rápida no había ninguno dudoso.
- **Puntos bloqueados:** `opts.locked` (índices de `points`) deja un punto como se
  tocó; no se interpola y sirve de ancla para sus vecinos. El índice es estable
  mientras los compases de entrada no cambien.
- **Caché:** `opts.cache` conserva la detección entre corridas (clave: referencia,
  posición y ventana). La corrida inicial tarda de 1,2 s a 3,0 s en las canciones
  probadas y los recálculos, milisegundos; cambiar la política de sin ataque no
  vuelve a detectar.
- **Beats internos** (`snap_inner_beats`, `true` por defecto): apagado, todos los
  compases se tratan como compases por compás. Los beats interiores, tocados o no,
  no se ajustan ni se interpolan (`inert`), quedan en el reparto uniforme entre los
  downbeats ya ajustados y el plan da un solo tempo por compás. La interpolación
  cuenta entonces downbeats seguidos sin ataque, no puntos. Permite comparar una
  pasada por beat contra un tempo por compás.
- **Resultados de las sondas:** el ruido de los taps ronda los 15 a 20 ms. En una
  canción rápida por beat la irregularidad de intervalos bajó de 39,5 a 10,8 ms
  con mediana de desplazamiento de −0,4 ms; en otra con taps solo de downbeats se
  ancló el 82 % de los downbeats y el 85 % de los beats. No hay sesgo global que
  corregir con un offset: cambia de canción a canción.
- **La irregularidad** solo es comparable en pasadas por beat; en una pasada por
  compás los beats interiores ya estaban repartidos y la métrica "antes" sale baja.
- Sin ataque en ninguna referencia hay canciones enteras de tramos (acordes
  sostenidos, intro de guitarra sola): el detector no inventa uno y el punto queda
  como tap o se interpola.

### Vista previa

`Nik_TempoTools_Apply.lua` abre la ventana antes de calcular el plan
(`TempoTapPreviewUi_common_logic.lua`, con el estado en
`TempoTapPreview_common_logic.lua`). La corrida inicial del snap va antes de abrirla.

- **Resumen:** conteos de ajustados, interpolados, sin cambio y sin marker; baja
  confianza, dudosos, rechazados y bloqueados (en gris los que están en cero);
  mediana del desvío, irregularidad de intervalos antes y después, y compases que
  pasan a un marker por beat.
- **Controles:** política de los puntos sin ataque (interpolar o dejar el tap),
  largo máximo de tramo (1 a 16) y la casilla de los beats internos. Cada cambio
  recalcula la vista sobre la caché.
- **Tabla:** una fila por punto con compás y beat, tipo (`down`, `beat` o `beat*`, un
  beat sin tap propio), posición tocada y nueva, desvío, estado, referencia, ratio,
  marca (bloqueado, rechazado con el ataque descartado, dudoso, baja confianza, o
  "sin marker" en los beats ignorados) y la casilla "Sin snap". Clic en una fila
  mueve el cursor de edición a la posición resultante.
- **Sin snap:** deja el punto como se tocó y no se interpola. En un beat sin tap
  propio, de un compás por compás, vuelve al reparto uniforme. No está disponible
  para los beats ignorados.
- **Borrar los taps al aplicar:** casilla con estado inicial `clear_taps_after`.
- **Foco:** al soltar un control y al sacar el mouse de la ventana, el foco vuelve a
  la ventana principal (`ImGuiEditorFocus_common_logic.lua`), para usar los atajos de
  REAPER mientras se revisa; no mientras hay un control activo o un popup abierto.
- **Aplicar y cancelar:** Aplicar entrega `Preview.measures` a `Plan.build`;
  cancelar o cerrar con la X termina el script. La ventana recuerda posición y
  tamaño para reabrirse donde estaba (ver §1).
- Los bloqueos y las casillas no se guardan en el proyecto.

## 8. Pendientes

- Seguir la reproducción en la vista previa: la fila del punto que corresponde a la
  posición de reproducción se resalta y la tabla se desplaza para mantenerla a la
  vista. Falta decidir contra qué posición se compara (la nueva o la tocada), si el
  desplazamiento se pausa cuando se usa el scroll de la tabla, y que funcione con el
  foco devuelto a la ventana principal.
- Mostrar en la vista previa los avisos de lectura de `Read.group` (compás inferido
  por conteo, taps ignorados antes del primer y después del último downbeat, dobles
  pulsaciones, nombres de compás inválidos), que `Apply` hoy descarta.
- Pre-roll y confirmación dentro de la ventana, en lugar de cuadros nativos, y Esc y
  Enter para cancelar y aplicar.
- Mediana local para la marca de dudoso: la mediana global marca tramos enteros de
  ataques reales cuando el tap venía tarde (seis puntos seguidos de +54 a +69 ms con
  ratio de x12 a x18 en una canción de tempo medio).
- Marca de "sin snap" en el propio tap (nombre o color): los bloqueos de la vista
  previa no se guardan y una segunda corrida los pierde.
- Anticipaciones sistemáticas (acordes que entran antes del downbeat): offset
  constante por tramo, o snap desactivado en ese tramo.
- Variante de una sola tecla con anclas (taps de beat y downbeat solo como ancla):
  no implementada.
- Probar un count-in de un compás (`PREROLL_OVERRIDE` en la sonda de items).
- Proyectos con más items, markers o regiones; restitución de tempo markers
  posteriores al último downbeat.
- Generalizar el factor de BPM a todos los denominadores (negras por pulso: 4/den,
  1,5 para compuestos).
- Revisar la fórmula de `features/tempo_mapping.md` y `convert_simple_to_compound.lua`
  contra la medición de la sección 5 con un caso real de ReaBeat.
- Mover `is_instrumental` a `_Shared/`: hoy `TempoTools` carga el módulo del importador.
- Actualizar el item de click source de la plantilla (el regenerado sigue tempo y compás).
- Umbrales del detector (`snap_min_ratio`, `snap_abs_floor`): estimados con pocas canciones.

## 9. Qué adjuntar según la tarea

Ver "Qué adjuntar según la tarea (TempoTap)" en `00_CONTEXTO_GENERAL.md`.