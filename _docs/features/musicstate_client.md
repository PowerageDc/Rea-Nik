# Feature — MusicState: capa cliente (JS)

Cómo el cliente convierte los datos publicados (ver
`musicstate_data_model.md`) más la posición del transporte en respuestas
concretas: qué acorde suena, qué sección, qué tonalidad. Es lo que
necesita leer quien construye o extiende una UI (hoy: instrumentista y
cantante; mañana: coordinador). Leer antes `musicstate_data_model.md` para
el contrato de datos — no se duplica acá.

Este doc describe **cómo está hecho hoy**, no cómo se llegó ahí. Modelo
de sincronización con el transporte (ancla, extrapolación, playrate,
indicador de datos viejos): `musicstate_instrumentista.md` §4, específico
de esa UI y no de esta capa.

## 1. Capa cliente

`core/music-state.js` convierte los datos publicados (`musicstate_data_model.md`
§4) más la posición
del transporte en respuestas concretas: qué acorde está vigente, cuál
sigue, qué indicaciones están activas. Es un módulo de **consultas sin
efectos secundarios**: las UIs lo llaman en cada render.

**Patrón:** variables y funciones sueltas en el scope global con prefijo
`nikMusicState*`, no un wrapper de objeto. Tiene estado propio cacheado,
a diferencia de `core/music-transpose.js` (puro cálculo, ver
`01_CONVENCIONES.md`, "Patrón de módulos JS de puro cálculo").

**Dependencias globales** (las define el dispatcher de cada UI):
`nikLastPositionBeatsStr` (posición cruda del `TRANSPORT`, `tok[5]`;
nombre fijo, no renombrar), `nikReaPitchLastSemitone`, `nikTranspose`
(`core/music-transpose.js`, debe cargarse antes) y `NIK_LUA_COMMANDS`.
Para el adelanto de posición (`nikTransportPlayState`,
`nikTransportAnchorMs`, `nikTransportPlayRate`, `nikMsTempoAt`) el módulo
verifica que existan; en una UI que no las define, el adelanto es 0 y la
posición es la cruda. Cómo se calcula la posición efectiva está en
`features/musicstate_instrumentista.md` §4.

### 1.1. Estado cacheado y setters

Cada key publicada tiene un setter que recibe el string crudo del
`EXTSTATE` y reemplaza el estado cacheado. Un valor vacío, `null` o JSON
inválido deja el estado en vacío sin lanzar error (así el reset por cambio
de proyecto reutiliza los mismos setters, ver
`musicstate_bridge.md` §4).

| Estado | Setter | Contenido |
|---|---|---|
| `nikMusicStateHarmonyFlat` | `nikMusicStateSetHarmonyData` | array ordenado `{bar, qn_offset, chord}`, ya expandido (§1.2) |
| `nikMusicStateCuesFlat` | `nikMusicStateSetCuesData` | array ordenado `{bar, qn_offset, roles, text, duration_qn}` |
| `nikMusicStateTimesigMap` | `nikMusicStateSetTimesigMap` | array ordenado `{bar, num, den}` |
| `nikMusicStateProjectKey` | `nikMusicStateSetProjectKey` | `{tonic, mode}` o `null` |
| `nikMusicStateProjectRoles` | `nikMusicStateSetProjectRoles` | array de strings, sin `"todos"` |
| `nikMusicStateLyricsFlat` | `nikMusicStateSetLyricsData` | array ordenado `{bar, qn_offset, text, lastLine}`, **con** marcadores de fin de línea (`text: null`); el setter des-escapa las barras antes del `JSON.parse` (§1.6) |
| `nikMusicStateLyricsLines` | `nikMusicStateSetLyricsData` | solo las líneas (eventos con texto), con `index` absoluto; sin marcadores |

`nikMusicStateFlattenBarKeyed` aplana `harmony_data`, `cues_data` y
`lyrics_data` por igual (todos keyed por compás): anota `bar` en cada evento y ordena por la
tupla `(bar, qn_offset)`. No hace falta QN absoluto para ordenar porque el
número de compás ya es monótono.

### 1.2. Expansión de repeticiones (solo armonía)

Como `harmony_data` es sparse (`musicstate_data_model.md` §4.1),
`nikMusicStateExpandHarmonyRepeats`
inserta una entrada virtual (`isRepeat: true`, `qn_offset: 0`) por cada
compás intermedio sin evento, repitiendo el acorde anterior (o `null` si
era un silencio). Motivo: `nikMusicStateChordWindow` camina por índice de
evento; sin las entradas virtuales, un acorde sostenido durante muchos
compases dejaría la tira del prompter estática.

No expande antes del primer evento ni después del último: no hay acorde
previo del cual copiar. Depende de la convención de autoría de
`musicstate_data_model.md` §4.1.

### 1.3. Posición y compases

- `nikMusicStateCurrentPos(extraLeadSec)` devuelve `{bar, qn_offset}` a partir de
  `nikLastPositionBeatsStr`, con la fórmula de `musicstate_data_model.md`
§4.6. Devuelve `null` si la
  posición todavía no se pudo parsear. `extraLeadSec` (opcional, en
  segundos, default 0) se suma al adelanto de `nikMusicStateAdvanceSongSec`;
  sin argumento el comportamiento es el de siempre. Lo usa lyrics (§1.6).
- `nikMusicStateTimesigAt(bar)`: búsqueda hacia atrás en el
  `timesig_map`; sin mapa cargado asume 4/4.
- `nikMusicStateBarDurationQn(bar)` y `nikMusicStateBarStartQn(bar)`
  (suma las duraciones de todos los compases anteriores). Solo las usan
  las cues, que necesitan posición absoluta para cruzar compases; el
  lookup de acordes compara tuplas `(bar, qn_offset)` directo.

### 1.4. Consultas

| Función | Devuelve |
|---|---|
| `nikMusicStateCurrentChord()` | acorde vigente (transpuesto); `null` antes del primer evento o en silencio |
| `nikMusicStateNextChord()` | acorde del siguiente elemento del array; `null` si no hay |
| `nikMusicStateChordWindow(lookBack, lookForward)` | ventana de `{bar, qn_offset, chord, isCurrent}` alrededor del vigente |
| `nikMusicStateCurrentProjectKey()` | tonalidad del proyecto, transpuesta |
| `nikMusicStateActiveCues(roleFilter)` | cues activas en la posición actual |

Detalles de comportamiento:

- **`NextChord` y `ChordWindow` cuentan elementos del array expandido**, no
  acordes distintos: en un acorde sostenido, el "siguiente" es la
  repetición del mismo acorde en el compás siguiente. `lookBack` y
  `lookForward` son cantidades de elementos, no de tiempo.
- **Antes del primer evento**, `ChordWindow` devuelve los primeros
  elementos sin ninguno marcado `isCurrent`, y `NextChord` devuelve el
  primer acorde. Devuelve vacío si no hay posición o no hay armonía
  cargada.
- **`ActiveCues(roleFilter)`:** una cue está activa si la posición
  absoluta en QN cae en `[inicio, inicio + duration_qn)`. Con
  `roleFilter` nulo devuelve todas las activas; con un rol, las que lo
  incluyen o incluyen `"todos"`.
- **La transposición se aplica al leer**, nunca sobre los arrays
  cacheados: un cambio de semitonos en caliente no obliga a re-aplanar
  nada (detalle en §2).

### 1.5. Carga de datos y cableado por UI

`nikMusicStateRequestAll()` pide, en un solo request, la publicación y las
cuatro keys de `NikMusicState` (dispara el Command ID
`NIK_LUA_COMMANDS.musicStatePublishAll` y agrega los `GET/EXTSTATE`).
`publish_version` no va en ese pedido: llega por el poll lento de la UI.
No vive en el poll de fondo porque el namespace `NikMusicState` es
independiente de `NIK_SLOW_POLL`.

| UI | Dispatcher | Cuándo pide los datos |
|---|---|---|
| Control remoto general | `core/wwr-dispatch.js` | al conectar y al cambiar de proyecto |
| Prompter | `musicstate-ui/shared/ms-dispatch.js` | al conectar, al cambiar de proyecto y cuando cambia `publish_version` |
| Cantante | `musicstate-ui/shared/ms-dispatch.js` (compartido; la UI aporta su bootstrap, `musicstate-ui/cantante/cantante.js`) | pedido de lyrics propio (§1.6): al conectar y al cambiar de proyecto; solo `GET` cuando cambia `lyrics_version` |

En el control remoto general, `nikLastPositionBeatsStr` (`core/state.js`)
se cachea incondicionalmente en cada `TRANSPORT`, a diferencia de
`statusPosition[0]`, que solo recibe `tok[5]` cuando
`nikPositionDisplayMode == "measures"`. `core/music-transpose.js` y
`core/music-state.js` cargan después de `core/state.js` y antes de
`core/wwr-dispatch.js`. `nikPlayrateRequestTempoMap()` y
`nikOpenPlayrateModal()` piden `timesig_map` junto con `tempo_map`; el
prompter hace lo mismo con `nikMsRequestTempoAndTimesig()`.

### 1.6. Lyrics

Bloque de `core/music-state.js` para `lyrics_data` (contrato en
`musicstate_data_model.md` §4.7). Mismo patrón que el resto: globales
sueltas con prefijo `nikMusicState*`.

**Vocabulario.** "Línea" es un evento con texto; "marcador" es un evento
con `text: null` (fin de línea explícito). Sin marcador, carry-over: la
línea vigente se mantiene hasta el próximo evento.

**Setter.** `nikMusicStateSetLyricsData(raw)` des-escapa las barras
invertidas (`raw.replace(/\\\\/g, "\\")`, `musicstate_data_model.md` §3)
antes del `JSON.parse`, y deja el estado vacío ante un valor vacío,
`null` o JSON inválido (así el reset por cambio de proyecto reusa el
setter). Ordena con `nikMusicStateCompareLyricPos`: a igual
`(bar, qn_offset)` el marcador va antes que la línea, así que **la línea
gana el desempate** sin depender del orden en que emita el publicador.
Cada evento lleva `lastLine`, el índice de la última línea en o antes de
él, calculado una sola vez en el setter.

**Consultas.**

| Función | Devuelve |
|---|---|
| `nikMusicStateCurrentLyric(extraLeadSec)` | `{index, bar, qn_offset, text}`: la última línea con inicio ≤ posición, **aunque ya haya terminado**; `null` en intro o sin datos |
| `nikMusicStateLyricEnded(extraLeadSec)` | `true` si hay línea vigente y el último evento ≤ posición es un marcador; `false` en carry-over, en intro o sin datos |
| `nikMusicStateLyricsWindow(lookBack, lookForward, extraLeadSec)` | líneas `{index, bar, qn_offset, text, isCurrent}`; en intro, las primeras `lookForward` líneas, ninguna con `isCurrent` |
| `nikMusicStateLyricsNextDistance(extraLeadSec)` | `{qn, line}`: QN hasta el inicio de la próxima línea, medido desde la misma posición que decide la línea vigente; `null` si no hay próxima |

- **Cuentan líneas, no elementos expandidos.** Diferencia con
  `ChordWindow` (§1.4): en lyrics cada evento ya es una línea y no hay
  repeticiones virtuales.
- **Devuelven copias**, no el estado cacheado (la UI no lo toca).
- **`qn` de `NextDistance` trae ruido de punto flotante**
  (`4.3759999999999994`): redondear o comparar con tolerancia, nunca con
  igualdad exacta.

**Lead propio.** `nikMusicStateLyricsLeadSec` (default 1.0, sin
calibrar) es un adelanto **extra, sobre** `nikMusicStateLookaheadSec`: el
cantante necesita leer antes de cantar. Un `extraLeadSec` numérico (0
incluido) se usa tal cual; sin argumento rige la constante. Con `0` la
posición es la de los acordes, no la cruda. Se aplica en
`nikMusicStateAdvanceSongSec(extraLeadSec)` y
`nikMusicStateCurrentPos(extraLeadSec)`; sin argumento esas funciones se
comportan como antes, así que acordes, secciones y pulso no cambian. Es
tiempo real: se multiplica por el playrate, y con el transporte detenido
no hay adelanto. Se ajusta en caliente desde la consola.

**Pedidos.** Son dos y no se pueden unificar:

- `nikMusicStateRequestLyrics()`: **dispara** `PublishLyrics`
  (`NIK_LUA_COMMANDS.musicStatePublishLyrics`) y pide `lyrics_data` y
  `lyrics_version`. Con guard: sin `commandId` avisa por consola y no
  sale.
- `nikMusicStateFetchLyrics()`: solo `GET` de `lyrics_data`.

Cada ejecución de `PublishLyrics` incrementa `lyrics_version`
(`musicstate_bridge.md` §5). Si la detección de un cambio de versión
volviera a disparar el script, cada disparo subiría la versión y
dispararía otro: un bucle. Por eso el camino por versión usa solo `GET`.
No entra en `nikMusicStateRequestAll()`: lo recibiría el control remoto
general sin usarlo.

**Cableado en `ms-dispatch.js`:**

- Handler de `lyrics_data` hacia el setter, y de `lyrics_version` contra
  `nikMsLastKnownLyricsVersion`: si cambió, `nikMusicStateFetchLyrics()`.
  Un valor vacío (el script borró la key: proyecto sin track de lyrics)
  cuenta como cambio a `null`, así una letra que desaparece se refresca.
- Reset por cambio de proyecto: vacía la letra y deja la versión en
  `null`.
- **Opt-in por UI:** el re-pedido en el cambio de proyecto (inmediato y a
  los 400 ms, mismo criterio FIFO que `RequestAll`) solo corre si
  `NIK_MS_LYRICS_ENABLED` es `true`. Su default es `false`, así que
  instrumentista no dispara `PublishLyrics`; `cantante.js` lo activa. Cada
  cambio de proyecto sube `lyrics_version` dos veces: inocuo, es un
  contador.
- `lyrics_version` viaja en el slow poll de cada UI que muestra letra
  (`nikCantanteBuildSlowPoll()`), no en el de instrumentista.

## 2. Transposición

La transposición por semitonos de ReaPitch se resuelve 100 % en el
cliente: el servidor publica los datos sin transponer
(`musicstate_data_model.md` §1) y cada consulta
de §1 aplica el delta vigente al leer. No hay script Lua ni pedido
adicional.

### 2.1. Módulo `nikTranspose` (`core/music-transpose.js`)

Wrapper de objeto único (puro cálculo, sin estado ni DOM). Debe cargar
antes de `core/music-state.js`. El delta de semitonos no vive acá: lo lee
quien consuma el módulo (`nikReaPitchLastSemitone`).

| Función | Devuelve |
|---|---|
| `nikTranspose.key(tonic, mode, semitones)` | `{tonic, mode, useSharps}`: la tonalidad resultante y la grafía que se usa para toda la transposición. Con una tónica no reconocida devuelve la tónica intacta y `useSharps: true` |
| `nikTranspose.chord(chord, semitones, useSharps)` | acorde transpuesto; un formato no reconocido vuelve intacto |
| `nikTranspose.note(name, semitones, useSharps)` | una nota suelta (fundamental o bajo) |
| `nikTranspose.getKeySpelling(tonic, mode)` | `"sharps"` o `"flats"` para una tonalidad sin transponer |

Ejemplos verificados: `nikTranspose.chord("C/E", 1, false)` devuelve
`"Db/F"`; `nikTranspose.key("F#", "major", 0)` resuelve a sostenidos.

**Parseo de acordes.** Un acorde se separa en raíz (letra A-G más
accidental opcional `#`/`b`), calidad (todo lo que sigue, hasta un `/`) y
bajo opcional (misma forma que la raíz). Solo la raíz y el bajo se
transponen; la calidad y las tensiones (`maj7`, `m7`, `sus4`, `9`,
`add9`, `dim`, `aug`, alteraciones) se copian tal cual. El bajo con slash
(`C/E`) se transpone con el mismo criterio que la raíz.

### 2.2. Criterio de grafía (sostenidos o bemoles)

No hay una tabla fija de 12 posiciones. La grafía la decide la
**tonalidad resultante**, con el criterio del círculo de quintas: dos
tablas (`MAJOR_USES_SHARPS`, `MINOR_USES_SHARPS`), indexadas por la
posición cromática de la tónica ya transpuesta, dicen si esa tonalidad se
escribe con sostenidos o con bemoles. El flag resultante se aplica de
forma **uniforme** a todas las fundamentales y bajos de la transposición,
incluidos los acordes no diatónicos. Se calcula una vez por
transposición (en `key()`), no por acorde.

Los dos empates enarmónicos reales están resueltos a mano hacia la grafía
más común en la práctica: F#/Gb mayor se escribe **F#** (sostenidos) y
D#/Eb menor se escribe **Eb** (bemoles). La salida siempre sale de las
listas de nombres con sostenidos o con bemoles, así que nunca produce
grafías teóricas raras (B#, Cb, E#, Fb) aunque el parser las reconoce como
entrada.

### 2.3. Integración en el cliente

- `nikMusicStateTransposeChordIfNeeded(chord)`: un `null` (silencio) pasa
  intacto. Calcula el delta con `parseInt(nikReaPitchLastSemitone)` y
  **devuelve el acorde sin tocar** si el delta no es un número (los
  sentinels `"none"` y `"mixed"` del Stem Bus, §2 de
  `features/musicstate_instrumentista.md`), si es 0, o si no hay
  `project_key` cargado. Si no, pide `nikTranspose.key()` con la
  tonalidad del proyecto y aplica `nikTranspose.chord()` con su
  `useSharps`.
- `nikMusicStateCurrentProjectKey()`: devuelve `null` sin `project_key`.
  Con un delta no numérico usa 0. Siempre pasa la tonalidad por
  `nikTranspose.key()`, incluso con delta 0.

Consecuencias de comportamiento:

| Situación | Acordes | Tonalidad mostrada |
|---|---|---|
| Delta distinto de 0 y hay `project_key` | transpuestos | transpuesta |
| Delta 0 | tal como se cargaron | re-escrita por la tabla de §2.2 (puede diferir de la grafía cargada, ver nota) |
| `"none"` o `"mixed"` | tal como se cargaron, sin aviso | como delta 0 |
| Sin `project_key` | tal como se cargaron, aunque el delta sea distinto de 0 | `null` |

Nota: la grafía de la tónica cargada (`musicstate_data_model.md` §4.2)
y la que devuelve
`nikMusicStateCurrentProjectKey()` con delta 0 pueden diferir cuando la
grafía elegida no es la que las tablas prefieren (por ejemplo, `C#`
mayor sale como `Db`).


### 2.4. Nota de consumo (`NextChord`)

`nikMusicStateNextChord()` (§1.4) hoy solo lo llama
`web/nsaudio_musicstate_test.html` (panel de debug). El prompter no lo
usa. Su comportamiento en un acorde sostenido (devuelve la repetición del
mismo acorde, no el próximo cambio real) está sin ejercitar por ningún
consumidor de producción. Si algún día un consumidor necesita el próximo
*cambio* real (por ejemplo, un contador de beats hasta el próximo
acorde), hay que saltear las entradas `isRepeat` con el mismo acorde, no
usar esta función tal cual.

## 3. Cómo testear

- **Transposición:** con delta ≠ 0 y `project_key` cargado, comparar
  `nikMusicStateCurrentChord()` contra el acorde esperado a mano. Con
  delta 0, verificar si la grafía devuelta coincide con la cargada (bug
  conocido, ver §4).
- **Carry-over y silencio:** un compás sin evento propio debe heredar el
  acorde anterior; una fila cargada con acorde vacío debe cortar esa
  herencia (`nikMusicStateCurrentChord()` da `null` en ese compás, no el
  acorde previo).
- **Lyrics:** con el transporte detenido, cargar una letra desde la
  consola con `nikMusicStateSetLyricsData(...)` y consultar
  `CurrentLyric`, `LyricEnded` y `NextDistance` en cada compás. Casos:
  intro, línea, marcador, carry-over tras la última línea, marcador sin
  línea previa, línea y marcador en la misma posición en ambos órdenes
  de emisión, des-escape de comillas y barras, y reset con `null`. El
  lead solo se ejercita con play real (parado no hay adelanto); para
  comparar `CurrentPos()` con y sin lead, usar una sola expresión: dos
  llamadas separadas incluyen el tiempo entre ellas y la diferencia
  crece. `nsaudio_cantante.html` sirve de prueba de punta a punta,
  incluida la republicación: tras ejecutar `PublishLyrics`, la versión
  debe subir una vez y quedar estable (si sigue subiendo, hay un bucle).

Pruebas de sincronización con el transporte (ancla, extrapolación,
lookahead, indicador de datos viejos) están en
`musicstate_instrumentista.md` §9, porque son específicas de esa UI y no
de esta capa.

## 4. Pendientes

- **Grafía con delta 0.** `nikMusicStateCurrentProjectKey()` siempre
  re-escribe la tónica con la tabla del círculo de quintas (§2.2), incluso
  sin transponer nada, así que una tonalidad cargada como `C#` mayor se
  muestra como `Db`. Confirmado por lectura de código, no ejecutado
  todavía (ver §2.3). Si se corrige para respetar la grafía cargada con
  delta 0, actualizar §2.3 y avisar a `musicstate_helper.md` §9 (la
  oferta de grafías del Helper depende de este comportamiento).
- **`nikMsTempoAt` en el control remoto general.** Sin esa función,
  `nikMusicStateCurrentPos` no aplica ningún adelanto (ni el de acordes),
  y el lead de lyrics no funciona. Cuando lyrics llegue al remoto general
  (paneles activables, `musicstate_lyrics.md` §5), su dispatcher tiene que
  definirla.
- **Calibrar `nikMusicStateLyricsLeadSec`** (1.0 s extra, sin calibrar)
  con una letra real y un cantante leyendo en la UI.
