# Feature — MusicState: lyrics para cantantes (estado y decisiones)

**Doc liviano, en construcción.** Registra qué está decidido, qué se
descartó, qué se verificó y qué falta, para poder retomar la feature en
otra sesión sin reconstruir el contexto. La UI de cantante (layout,
módulos compartidos y decisiones de diseño del reel) vive en
`musicstate_cantante.md`; este doc conserva el contrato, el publicador, la
capa cliente y el ingreso de letras.

El contrato de datos (formato JSON, protocolo) vive en
`musicstate_data_model.md` §4.7 y no se repite acá. El puente está en
`musicstate_bridge.md` §1.

## 1. Estado

| Pieza | Estado |
|---|---|
| Contrato de datos (`lyrics_data`, `lyrics_version`) | Documentado en `data_model` §4.7 |
| Publicador `Nik_MusicState_PublishLyrics.lua` | Implementado y verificado (ver §4) |
| Ingreso `Nik_MusicState_LyricsInput.lua` | MVP con `GetUserInputs` implementado y verificado: línea en cursor o selección, marcador `·` de fin, upsert, aviso ante eventos dentro de la selección. Ventana persistente: ver la tab del Helper (fila siguiente) |
| Tab Lyrics del Helper (`MusicStateLyricsTab_common_logic.lua`) | Pasos 3a, 3b y 3c implementados y verificados (visor de solo lectura, cola de tap-to-sync y panel de edición: selección, texto, borrado, posición y agregar línea con confirmación, §8.6). Paso 3d pendiente (§8) |
| Doc del puente | Actualizado (lyrics fuera de `Bridge.KEYS`) |
| Capa cliente (setter, consultas, lead propio) | Implementada y verificada en dev (ver §4); detalle en `musicstate_client.md` §1.6 |
| Cableado (`ms-dispatch.js`: pedidos, versión, reset, opt-in) | Implementado y verificado en dev |
| UI de cantante (`musicstate-ui/cantante/`) | Shell, layout y cabecera validados en dev y Android. Reel de letra (slots, estados, barrido de proximidad y crossfade en seek) funcionando y validado en dev; pendientes de afinado, cues y rol en `musicstate_cantante.md` §6 |
| Registro (`NIK_LUA_COMMANDS`, generador de `config.local.js`, `@provides` del metapaquete, manifiesto `.www`) | Hecho en el repo; **pendiente de validar en una PC de destino** (§6) |

## 2. Decisiones tomadas

- **Fuente de verdad: eventos lyric MIDI dentro del `.rpp`**, en un track
  dedicado (`🎤 Lyrics`, descubierto por nombre, sin distinguir
  mayúsculas). Es la única key de MusicState que no sale del Helper ni de
  `ProjExtState`: excepción deliberada al principio "Helper = fuente de
  verdad". La letra viaja con el proyecto (renombrar o duplicar el `.rpp`
  no rompe nada).
- **Publicación por script one-shot propio** (`PublishLyrics`), no por
  `PublishAll` ni por el Bridge. Motivo: `bridgeAll` borraría las keys en
  cada llamada (no hay dato en `ProjExtState`), y `PublishAll` obligaría
  al control remoto general a recibir una letra que no usa.
- **Posición por (compás, `qn_offset`)**, igual que armonía y cues, no
  por segundos: no se rompe con mapas de tempo ni playrate, y se reusa el
  aplanado del cliente.
- **`qn_offset` libre, sin grilla de 0.25.** Deja abierta la granularidad
  de sílaba y el progreso de línea. El QN absoluto se redondea a 3
  decimales antes de partirlo en compás y offset.
- **Un evento = una línea completa (v1).** Una pausa dentro de una línea
  se carga como líneas distintas.
- **Fin de línea explícito y opcional:** el evento con texto `·` (U+00B7)
  se publica como `"text": null`. Sin marcador, carry-over. El editor MIDI
  no acepta texto vacío, por eso el símbolo.
- **`lyrics_version` propio**, independiente de `publish_version`: el
  Helper carga ese valor al abrirse, y si otro script lo incrementara, su
  siguiente guardado repetiría el número con datos distintos.
- **Higiene por proyecto:** sin track de lyrics, o sin eventos, el script
  borra las dos keys globales (mismo criterio que `bridgeKey`).
- **Lead propio, en segundos, sobre el lookahead de acordes.**
  `nikMusicStateLyricsLeadSec` (1.0 s extra, sin calibrar) se suma al
  adelanto existente, así que playrate y mapa de tempo se resuelven donde
  ya se resolvían. Detalle en `musicstate_client.md` §1.6.
- **Dos pedidos de lyrics: uno dispara el script, otro es solo lectura.**
  Cada ejecución de `PublishLyrics` incrementa `lyrics_version`; volver a
  disparar el script al detectar un cambio de versión sería un bucle. El
  camino por versión usa solo `GET`.
- **Lyrics es opt-in por UI.** `ms-dispatch.js` es compartido:
  `NIK_MS_LYRICS_ENABLED` (default `false`) evita que instrumentista
  dispare `PublishLyrics` en cada cambio de proyecto. `lyrics_version`
  viaja solo en el slow poll de la UI que muestra letra.
- **Sin karaoke fill en v1.** El modelo admite campos opcionales por
  evento (sílabas con offsets, duración tomada de una nota) sin romper
  nada: el cliente ignora los campos que no conoce.
- **Ingreso por API, no por el diálogo del editor MIDI.**
  `MIDI_InsertTextSysexEvt` (tipo 5) inserta el lyric directo en el take,
  sin editor abierto. La posición se convierte con
  `MIDI_GetPPQPosFromProjTime`, así que sigue al mapa de tempo y no se
  cuantiza. Un único item MIDI en el track cubre la posición: se crea
  (desde el inicio del proyecto) o se extiende (`MIDI_SetItemExtents`).
- **Edición idempotente (upsert).** El texto en el punto de inicio
  reemplaza al evento existente (el campo se precarga con él). Texto
  vacío = solo marcador de fin `·`. El `·` no se duplica ni se inserta si
  en esa posición ya hay un `·` o una línea real. Con eventos dentro de
  la selección de tiempo, aviso Sí (reemplazar) / No (conservar) /
  Cancelar. Todo en un solo bloque de undo.
- **Lógica sin UI en el módulo.** `PlanLine` lee el estado y `ApplyLine`
  lo aplica; ninguna abre diálogos, así que las usan por igual el script
  de ingreso (diálogos nativos) y la tab del Helper.
- **La tab de Lyrics no usa `H` para la letra.** La fuente de verdad son
  los eventos MIDI y cada edición se aplica directo, con su undo. La tab
  mantiene solo un cache de lectura (`H._lyrics`), recargado cuando
  cambia `GetProjectStateChangeCount` o el proyecto activo.
- **Publicación desde la tab vía `Lyrics.Publish(proj)`**, a extraer al
  módulo; `PublishLyrics` queda como cáscara fina y sigue siendo el
  punto de entrada del cliente web (§8, paso 3d). Decidido, no
  implementado.

## 3. Descartado, y por qué

- **WebSocket y "Web Control como servidor/puente"** (del spec original de
  ChatGPT): el servidor web de REAPER es HTTP con polling. La
  sincronización con el transporte ya está resuelta
  (`musicstate_instrumentista.md` §4).
- **`GetTrackMIDILyrics`:** posición truncada a centésimas de beat y texto
  mezclado con tabs. Se usa `MIDI_GetTextSysexEvt` filtrando tipo 5.
- **Comando nativo `LYRICS/<n>` del web control (camino A):** obligaba a
  descubrir el índice del track en el cliente y parsear `beat_position`.
- **Posiciones en segundos:** incompatibles con el modelo de datos.
- **Reusar `publish_version`:** ver §2.
- **Texto vacío o espacio como marcador de fin de línea:** el editor no
  acepta el vacío, y el espacio es invisible y frágil.
- **Lead de lyrics en QN:** el lookahead existente está en segundos y se
  convierte a compás con el tempo y el playrate; un lead en QN no
  resolvía ninguna de las dos cosas.
- **Re-disparar `PublishLyrics` al detectar un cambio de `lyrics_version`:** bucle (§2).
- **Diálogo nativo de texto del editor MIDI como vía de ingreso:** exige
  el editor abierto con su propio cursor, distinto del de arrange.
- **Editar la posición con `RowInputs` o las conversiones del Helper:**
  el redondeo a la grilla de 0.25 destruye el `qn_offset` libre, y
  editar la posición en vivo trae los bugs de reorden y foco de
  `musicstate_helper.md` §5. La posición se ajusta con nudge, "mover al
  cursor" y tap.
- **Línea en blanco de la letra pegada = `·` (primera versión de 3b):**
  obligaba a preparar el texto a mano antes de sincronizar, y la letra
  copiada de internet casi nunca trae esas líneas en blanco, mientras que
  cerrar casi cada línea es el caso común. El fin pasa a salir del gesto
  (mantener la tecla, §8.5) y las líneas en blanco se ignoran.

## 4. Verificado empíricamente

Con un proyecto de prueba (`Tests-Debug/Nik_Tests_LyricsProbe.lua` y
`PublishLyrics`):

- Los lyrics sin notas son válidos y se leen con `MIDI_GetTextSysexEvt`.
- Acentos, `¿`, `ñ` llegan intactos como UTF-8 (con `fetch().text()`; la
  barra de direcciones muestra mojibake por falta de charset, no es un
  problema de datos).
- `TimeMap_QNToMeasures` devuelve el compás **1-indexed**, y un evento
  fuera de grilla conserva su posición (resolución real: 1/960 de negra).
- **El web control duplica cada `\`:** `\"` llega como `\\"`. El cliente
  debe reemplazar `\\` por `\` antes del `JSON.parse` (`data_model` §3).
  Verificado con una línea con comillas y otra con barra.
- La versión sube en cada publicación (1, 2, 3).

Capa cliente y cableado (con `nsaudio_cantante.html` y la consola del
prompter):

- Consultas con el transporte detenido: intro, línea, marcador,
  carry-over tras la última línea, marcador sin línea previa, línea y
  marcador en la misma posición en ambos órdenes de emisión.
- Des-escape de comillas y barras, y reset con `null` sin errores.
- Lead con play real: la línea pasa a vigente ~1,4 s antes de su
  posición con el valor por defecto (0,4 s de lookahead más 1,0 s extra),
  ~0,4 s con `extraLeadSec = 0`.
- Republicación: tras ejecutar `PublishLyrics`, el panel se actualiza en
  ~1 s y `lyrics_version` queda estable (sin bucle).
- Cambio de proyecto con y sin track de lyrics: la letra se vacía y se
  recarga.
- Instrumentista no dispara `PublishLyrics` y no cambia de comportamiento.

## 5. Diseño de UI acordado (planteo original; implementado en `musicstate_cantante.md`)

**Actualización:** el diseño detallado (composición única, slots según
renglones, dos posiciones de lead, ancla, barrido de proximidad) pasó a
`musicstate_cantante.md` §4. Lo que sigue es el planteo original; donde
difiere, manda ese doc. Diferencias ya conocidas: el reel no usa FLIP
(`transition` de CSS sobre nodos reusados por posición) y la línea "armada"
se reemplazó por un barrido de proximidad sobre la siguiente.

- **Estados de la línea:** intro (antes de la primera línea: las primeras
  se muestran como "próximas", análogo al preludio de la fila de sección),
  cantando, silencio entre líneas (la actual se apaga y la siguiente queda
  "armada", con énfasis intermedio) y carry-over (sin marcador de fin, la
  actual se mantiene).
- **Ventana de hasta 5 slots** (2 anteriores, actual, 2 siguientes), con la
  técnica FLIP de `01_CONVENCIONES.md`. La cantidad real depende de los
  renglones de cada línea y del alto del escenario
  (`musicstate_cantante.md` §4.2).
- **Lookahead propio de lyrics:** un cantante necesita leer antes que un
  instrumentista; implementado como adelanto extra sobre el de los
  acordes (`musicstate_client.md` §1.6). Falta calibrar el valor con una
  letra real.
- **Líneas que envuelven en 2 renglones** cambian de alto por contenido y
  no solo por `font-size`: tope fijado en 2 renglones, sin ellipsis
  (`musicstate_cantante.md` §4.1).
- **Cuenta regresiva en pausas largas:** `nikBeat` calcula la distancia al
  próximo evento de armonía; se podría generalizar.
- **Control remoto general:** acceso a lyrics y acordes en paneles
  activables, a mediano plazo. Por eso la capa de consultas no debe
  depender de globales del prompter, y el pedido de lyrics es propio (no
  entra en `nikMusicStateRequestAll()`). Ahí también tendría que existir
  `nikMsTempoAt`, sin la cual el lead no se aplica
  (`musicstate_client.md` §4).
- **Datos de boot de la UI real:** `cantante.js` ya pide tempo, timesig y
  lyrics, y el shell carga secciones (`ms-section.js`) y la tonalidad
  transpuesta (`reapitch_semitone` en el poll lento). Quedan los cues y,
  según cómo se sienta el preludio de la línea siguiente, el pulso
  (`ms-beat.js`). Cada dato suma su pedido de boot y su script en el
  shell (`musicstate_client.md` §1.5).

## 6. Pendientes, en orden

1. **`01_CONVENCIONES.md`:** el nombre del track `🎤 Lyrics`; revisar que
   AutoColor y los snapshots lo ignoren.
2. **Validar el registro en una PC de destino** (hecho en el repo, sin
   probar): instalar el metapaquete de MusicState y el `.www`, volver a
   correr `Nik_RemoteControl_GenerateConfig.lua` (sin eso la UI usa el
   Command ID de dev y falla en silencio), comprobar que `config.local.js`
   trae `musicStatePublishLyrics`, que hay una sola entrada de
   `PublishLyrics` en el Action List y que `nsaudio_cantante.html` muestra
   la letra.
3. **Verificar el tamaño** con una letra larga real: la prueba midió 318
   bytes con 6 líneas; el tope de `EXTSTATE` no está documentado.
4. **Emparejamiento lyric↔nota MIDI** (duración o progreso por sílaba a
   futuro): no verificado, la prueba se hizo sin notas.
5. **`cues_data` y el escape de barras:** revisar si el Helper y
   `nikMusicStateSetCuesData` lo manejan (`data_model` §6).
6. **UI de cantante real** (`musicstate-ui/cantante/`; avance y pendientes
   en `musicstate_cantante.md` §6): el reel (slots, estados, barrido y salto
   en seek) está hecho. Quedan filtro por rol (`cantantes`) o letra para
   todos, cues, pulso si hace falta y calibrar el lead y el `PRELUDE`. El
   refresco por republicación ya llega por `lyrics_version`, pero nada lo 
   incrementa solo al editar en el editor MIDI: hay que ejecutar la acción 
   de `PublishLyrics`.
7. Actualizar el SPEC original (`lyrics` figura fuera de alcance según
   `musicstate_instrumentista.md`).
8. A futuro, sin decidir: que "Guardar y Publicar" del Helper también
   guarde la letra (editar el track con el Helper abierto). Se define
   después de usar el flujo actual con `PublishLyrics`.
9. **Probar el alta con un fin pendiente de la cola** (sin probar): subir el
   gap de la cola (`lyrics_tap_gap_ms`), tapear con hold de al menos 250 ms,
   soltar y apretar "Agregar" antes de que venza. Esperado: el `·` pendiente
   se inserta antes del alta (el alta llama al mismo `flush` que las
   ediciones, antes de `PlanLine`), el tap queda con su fin y la cola no
   cambia. Verificado aparte: un "Reemplazar todo" que borra tres líneas con
   la cola cargada no mueve la cola.
10. **Ctrl+Z tras agregar con selección de tiempo activa:** el Ctrl+Z deshace
    la línea pero la selección de tiempo queda en el arrange, porque la tab
    solo limpia `S.sel` cuando deja de resolverse, no el rango. Idea: en
    `refresh`, limpiar el rango solo si empieza en el tiempo de la línea
    que desapareció, para no pisar una selección armada a mano.
11. **Atajos de teclado globales del Helper** (ReaImGui, no el prompter web;
    diseño aparte): con el modal cerrado, `W` y `Fin` (ir al inicio o al fin
    del proyecto) y `Esc` (limpiar la selección de tiempo). Partir del guard
    de popup abierto de `globalKeyPressed` y `readHeld` (patrones §6), que es 
    lo que hoy impide que actúen con un modal abierto.

## 7. Archivos

- `MusicState/Nik_MusicState_PublishLyrics.lua` — publicador one-shot.
- `MusicState/Nik_MusicState_LyricsInput.lua` — ingreso de líneas (UI mínima sobre el módulo).
- `MusicState/MusicStateLyrics_common_logic.lua` — descubrimiento del track y lógica de edición (`PlanLine`/`ApplyLine`/`DecideAdd`, y para 3c `PairEvents`, `Resolve`, `SetText`, `DeleteLine`, `DeleteEnd`, `MoveEvent`, `AddEnd`), sin diálogos ni ImGui.
- `MusicState/MusicStateLyricsTab_common_logic.lua` — tab Lyrics del Helper (`M.draw(ctx, H, helpers)`).
- `MusicState/MusicStateLyricsSync_common_logic.lua` — cola de tap-to-sync (`M.draw(ctx, S, H, helpers)`), consumida por la tab vía `helpers.LyricsSync`. Expone también `flush` y `onEdit`, el contrato con las ediciones de 3c (§8.6).
- `MusicState/MusicStateLyricsEdit_common_logic.lua` — panel de edición de la fila seleccionada y alta de líneas (`M.draw(ctx, S, H, helpers)`; `M.drawAddOnly` dibuja solo la fila de alta cuando no hay track), consumido por la tab vía `helpers.LyricsEdit`.
- `Tests-Debug/Nik_Test_LyricsProbe.lua` — volcado de los eventos lyric
  y de `GetTrackMIDILyrics` a consola.
- `Tests-Debug/Nik_Test_LyricsEditProbe.lua` — probe de la API MIDI para
  3c (edición de texto en el lugar, PPQ fuera del item, `SetItemExtents`,
  casos de `EnsureTake`). Crea pistas `PROBE_*` en un solo bloque de undo.
- `Tests-Debug/Nik_Test_LyricsDecideAdd.lua` — test de consola de
  `DecideAdd` con eventos simulados (no toca el proyecto).
- `core/music-state.js` — bloque de lyrics (setter, consultas, pedidos).
- `musicstate-ui/shared/ms-dispatch.js` — handlers, reset y opt-in.
- `config.js` — `musicStatePublishLyrics`.
- `musicstate-ui/cantante/cantante.js`, `cantante.css` y
  `nsaudio_cantante.html` — UI de cantante; ver `musicstate_cantante.md`.
- Docs tocados: `musicstate_data_model.md` (§2, §3, §4, §4.7, §6),
  `musicstate_bridge.md` (§1, §2, §5), `musicstate_client.md` (§1.6).

## 8. Ingreso de lyrics y tab del Helper (en construcción)

### 8.1 Estado por paso

| Paso | Estado |
|---|---|
| Módulo `MusicStateLyrics_common_logic.lua` + `Nik_MusicState_LyricsInput.lua` (MVP con `GetUserInputs`) | Hecho, 6 pruebas verificadas |
| Refactor: `PlanLine`/`ApplyLine` al módulo, script como capa de UI | Hecho, verificado |
| 3a. Tab Lyrics del Helper, solo lectura | Hecho, 7 pruebas verificadas |
| 3b. Cola de tap-to-sync (hold con gap mínimo) | Hecho, verificado por etapas (cola, tap, fin por hold) |
| 3c. Edición (panel de la fila seleccionada: texto, nudge, mover al cursor, borrar; agregar línea) | Hecho, verificado (agregar línea con confirmación; falta probarlo con un fin pendiente de la cola, §6) |
| 3d. `Lyrics.Publish`, botón Publicar y auto-publicar | Pendiente |

### 8.2 API del módulo

Constantes: `END_MARK` (`·`), `DEFAULT_TRACK_NAME` (`🎤 Lyrics`),
`EPS_TIME` (0.01 s, tolerancia para "misma posición"), `PAD_TIME` (5 s,
margen al crear o extender el item), `MIN_SEP` (2 × `EPS_TIME`, separación
mínima entre eventos vecinos al mover).

- `FindLyricsTrack(proj)`, `CreateLyricsTrack()`.
- `CollectEvents(track)`: eventos lyric (tipo 5) de todos los items,
  ordenados por tiempo, con `take`, `idx`, `text` y `time`.
- `EventsNear(list, t)`, `EventsBetween(list, t1, t2)`: ambos con epsilon;
  `EventsBetween` es estricto en los dos bordes.
- `DeleteEvents(list)`: borra por take en índice descendente, en un solo
  lote (los índices se desfasan si se borra de a uno).
- `EnsureTake(track, t_from, t_to)`, `InsertAt(...)`, `CleanText(s)`,
  `GetTimeContext()` (selección de tiempo si mide más de 2×`EPS_TIME`; si
  no, el edit cursor y `nil`).
- `PlanLine(track, t1, t2)`: contexto con `prefill`, `at_start`, `at_end`,
  `inside` y `end_time`. No modifica nada.
- `ApplyLine(track, ctx, text, opts)`: con `track = nil` lo crea.
  `opts.replace_inside` decide si se borran los eventos dentro de la
  selección; si hay eventos dentro y no se reemplazan, no se inserta el `·`
  de `t2` (el par es posicional: quedaría huérfano después del fin de la
  última línea conservada). Devuelve `false, "end_occupied"` si el texto es
  vacío y ya hay un evento en la posición del marcador; si no, `true, track`.
- `DecideAdd(ctx, text)`: decisión pura para el alta, a partir del `ctx` de
  `PlanLine` y el texto ya limpio. Devuelve `{kind = "apply" |
  "confirm_line" | "confirm_inside" | "reject"}` más `n` (eventos dentro de
  la selección), `has_line` (hay una línea en `t1`) y `replaces_end` (hay un
  `·` en `t1`, que `ApplyLine` reemplaza sin modal). En `reject` trae
  `code`: `"reserved"` (el texto es `·`) o `"end_occupied"`.
- `PairEvents(events)`: marca `is_end` y deriva el par línea/fin por
  posición (`end_idx` en la línea, `owner` en el fin). En un grupo de
  eventos a menos de `EPS_TIME` entre sí, los fines cierran la línea
  anterior y las líneas abren una nueva. No se guarda: se recalcula en cada
  lectura.
- `Resolve(list, key)`: índice del evento que coincide con la clave
  `{time, is_end}` (tolerancia `EPS_TIME`).
- Edición (3c): `SetText`, `DeleteLine`, `DeleteEnd`, `MoveEvent`, `AddEnd`.
  Reciben una clave `{time, is_end}`, nunca `take`/`idx` (caducan con
  cualquier edición), y releen el track al ejecutarse. Devuelven
  `true, change` (descriptor para `LyricsSync.onEdit`) o `false, "<código>"`.
  Un bloque de undo por operación. Detalle en §8.6.
- `EnsureTake` (cambió en 3c, afecta también a los taps): sin item previo al
  destino y con items MIDI existentes, extiende el inicio del primero hasta 0
  en vez de crear uno solapado; la extensión hacia adelante no pasa del
  inicio del item siguiente.

### 8.3 Gotchas verificados

- `GetUserInputs` con un solo campo: se usa
  `extrawidth=350,separator=\n` para que las comas de la letra no
  partan el valor.
- Los archivos que contienen `·`, `🎤` o `→` tienen que guardarse en
  UTF-8; si no, el `·` se inserta mal y el publicador no lo reconoce.
- Para limpiar la selección de tiempo: `GetSet_LoopTimeRange(true, false,
  0, 0, false)`.
- `reaper.ImGui_GetKeyName` no existe en la versión instalada (error de
  `nil`): la etiqueta de la tecla de tap es un texto fijo
  (`KEY_TAP_LABEL`) junto a la constante `KEY_TAP`.
- Un botón que se deshabilita o se desplaza mientras se lo mantiene
  pierde el release o el click (patrón general en
  `08_REAIMGUI_PATTERNS.md` §4).
- `MIDI_SetTextSysexEvt` exige `typeIn = 5` explícito: con `nil` devuelve
  `true` pero ignora el mensaje. Con el tipo explícito y el resto en `nil`
  cambia el texto sin tocar la posición.
- `MIDI_SetItemExtents` moviendo el inicio de un item conserva el tiempo de
  proyecto de los eventos (cambia el PPQ, no la posición).
- Un evento insertado antes del inicio del item se acepta con PPQ negativo
  (corrido ~1 ms), y uno pasado el final también. No se usan: el destino de
  un movimiento siempre se resuelve con `EnsureTake`.
- `ev.take` y `ev.idx` caducan con cualquier edición (`MIDI_Sort`,
  borrados). Un `ctx` de `PlanLine` no debe sobrevivir a un frame ni a un
  modal: se vuelve a planear al confirmar.
- Lua: `a and b or c` cae en `c` cuando `b` es `nil`. Bug real en
  `MoveEvent` (el tope del último par del track); usar `if/else`.

### 8.4 Tab 3a: cómo está hecha

- Cache en `H._lyrics`: se relee la lista solo cuando cambia
  `GetProjectStateChangeCount(0)` o `H.last_proj`. El botón "Recargar"
  es la salida de emergencia.
- Fila vigente: sigue la posición de reproducción mientras suena y el edit
  cursor cuando está detenido. Mismo highlight que Armonía (verde sólido si
  coincide exacto, tenue por carry-over) y auto-scroll cuando cambia la
  fila vigente. Separadores de sección (fila gris, no `CollapsingHeader`).
- Click en una línea: mueve el edit cursor (`SetEditCurPos(t, true,
  false)`, sin seek en reproducción) y, con el toggle activo, selecciona el
  tiempo hasta el evento siguiente (línea o `·`). En la última línea, o en
  un `·`, limpia la selección. Toggle persistido con `SetExtState`
  (sección `NikMusicStateHelper`, clave `lyrics_autoselect`).
- Registrada en el contenedor del Helper: `dofile` del módulo y de la tab,
  `helpers.Lyrics` y un `BeginTabItem('Lyrics')`. Los dos archivos están
  en el `@provides` del Helper.

### 8.5 Tab 3b: cola de tap-to-sync

- **Dónde vive.** Módulo `MusicStateLyricsSync_common_logic.lua`, cargado
  por el contenedor (`helpers.LyricsSync`). La tab dibuja su panel
  colapsable ("Sincronizar (tap)") **antes** del `return` de "sin track
  de Lyrics", porque el primer tap puede crear el track. Estado en
  `S.sync` (`S = H._lyrics`), solo en memoria: se descarta al cambiar de
  proyecto, y la cola no sobrevive al cierre del Helper.
- **Dos fases.** Preparar: `InputTextMultiline` para pegar; cada línea
  con contenido es un ítem y las líneas en blanco y los `·` sueltos se
  ignoran (el fin sale del gesto, no del texto). Sincronizar: se muestra
  el siguiente ítem y los dos que siguen, con TAP, Saltar, Deshacer y
  Vaciar. Con la cola cargada no hay `InputText` activo, así que la
  tecla de tap no choca con ningún campo.
- **Tap.** Una sola señal `held` alimentada por la tecla (`KEY_TAP`, hoy
  `B`, con `KEY_TAP_LABEL` aparte) y por el botón TAP (`IsItemActive`).
  Los flancos salen de comparar con el frame anterior (`IsKeyDown`, no
  `IsKeyPressed`/`IsKeyReleased`, para unificar con el botón). La tecla
  exige ventana enfocada (`ChildWindows`) y ningún item activo; si la
  ventana pierde el foco, cuenta como soltada. Solo opera con
  reproducción activa. Inserta con `PlanLine`/`ApplyLine` en
  `GetPlayPosition()` (no `GetPlayPosition2`, que no descuenta la
  latencia de salida de audio) más la compensación.
- **Compensación.** Un valor en ms para inicio y fin (default −150,
  rango −500..+200, `DragInt`), persistido al soltar el control en
  `NikMusicStateHelper` / `lyrics_tap_latency_ms`. Se calibra tapeando
  3 o 4 líneas con ataques claros contra el stem de Vocals. Independiente
  de `nikMusicStateLyricsLeadSec`, que solo afecta al mostrar.
- **Fin por hold.** Al soltar, si el hold duró al menos 250 ms
  (`MIN_HOLD_S`, fijo) y el toggle está activo (`lyrics_tap_close`), el
  `·` queda **pendiente**. Se resuelve por frame (también con el header
  colapsado): se inserta si pasa el gap mínimo (`lyrics_tap_gap_ms`,
  default 400 ms, medido en tiempo de proyecto, o sea independiente del
  playrate), si se detiene la reproducción o si hay un seek hacia atrás;
  se descarta si llega un press dentro del gap (carry-over). "Vaciar
  cola" inserta el pendiente antes de vaciar; un cambio de proyecto lo
  descarta sin insertar.
- **Deshacer y reconciliación.** Cada entrada de `hist` es
  `{time, text, end_time}` o `{skip = true}`, con la invariante
  `pos == #hist + 1`. "Deshacer" borra por identidad (`EventsNear` sobre
  `time` y `end_time`), no con el undo de REAPER, y cancela el `·` si
  seguía pendiente. Si la cantidad de líneas del track baja (Ctrl+Z, borrado
  a mano), la cola retrocede hasta la última línea tapeada que todavía
  existe.
- **Layout estable.** El botón TAP no se deshabilita al completar la cola
  (pasa a "Cola completa"): deshabilitarlo con el botón apretado perdía
  el release de la última línea. La línea de aviso bajo el botón se
  reserva siempre: si aparece y desaparece, el layout se corre y se
  pierde el click de "Saltar" o "Deshacer".
- **Limitaciones conocidas.** (1) Redo (Ctrl+Shift+Z) devuelve la línea al
  track pero no a la cola, y volver a tapearla deja dos copias.
  (2) Borrar a mano la última línea y recuperarla con Ctrl+Z no refresca
  la cola: la reconciliación solo reacciona cuando la cantidad de líneas
  baja. (3) Los taps hacen upsert en su posición y no borran letra
  existente; para re-sincronizar desde cero se borra desde el panel de
  edición (§8.6) o a mano. (4) Un re-tap sobre una línea existente
  reemplaza el texto, y "Deshacer" no lo restaura. (5) Ctrl+Z o Redo de
  REAPER sobre una edición de 3c: ver §8.6.

### 8.6 Tab 3c: edición de la fila seleccionada y agregar línea

Hecho: selección y pares, texto, borrado, posición y agregar línea.

- **Dónde vive.** Panel `MusicStateLyricsEdit_common_logic.lua`
  (`helpers.LyricsEdit`, `M.draw(ctx, S, H, helpers)`), dibujado por la tab
  entre el panel de sync y la lista. Alto fijo: sin selección queda
  deshabilitado, no oculto, y la línea de aviso se reserva siempre. Estado
  en `S.edit`, con `S = H._lyrics`. La lógica sin UI está en
  `MusicStateLyrics_common_logic.lua` (§8.2).
- **Selección.** `S.sel = {time, is_end}`, identificada por tiempo y no por
  índice (refresh recarga todo): se resuelve en cada frame con `Resolve` y
  se limpia sola si deja de resolverse o cambia el proyecto. El click en una
  fila la selecciona, mueve el cursor y, con el toggle activo, aplica la
  selección de tiempo; un segundo click la deselecciona y limpia esa
  selección de tiempo. "Borrar línea" también la limpia (toggle activo).
  Tras mover un borde (nudge, al cursor, agregar fin, borrar solo el fin),
  la tab recalcula la selección de tiempo en el frame siguiente
  (`S.reselect`, `applyTimeRange`). "Ir al inicio" mueve el cursor sin tocar
  la selección.
- **Par línea/fin.** Derivado por posición en cada refresh (`PairEvents`),
  nunca guardado. La lista muestra la duración (`· X.XX s`) y marca los
  fines sin línea como "fin (sin linea)". Insertar una línea dentro del span
  de otra le corta el fin: el modelo es posicional, igual que el cliente.
- **Texto.** `InputText` con borrador atado a la clave del evento; commit al
  perder el foco (Enter, Tab o click afuera), Esc revierte; texto vacío o
  `·` rechazado con aviso. El commit usa la clave del borrador, no la
  selección actual. `SetText` edita en el lugar (§8.3). Los atajos globales
  del contenedor no chocan (patrón en `08_REAIMGUI_PATTERNS.md` §5).
- **Borrar.** "Borrar línea" borra la línea y su fin en un solo bloque de
  undo (un fin suelto pasaría a cerrar la línea anterior). "Borrar fin"
  (con un `·` seleccionado) y "Borrar solo el fin" (con la línea) dejan la
  línea en carry-over.
- **Posición.** Filas "Inicio" y "Fin": nudge de −100, −20, +20 y +100 ms y
  "Al cursor". El nudge se detiene en el tope; "Al cursor" rechaza si cae
  fuera de rango. Un evento nunca cruza ni pisa a un vecino (`MIN_SEP`): no
  hay reordenamiento ni colisiones por nudge. Mover el inicio deja el fin
  quieto; el check "El fin acompaña" (apagado por defecto, sin persistir)
  mueve el par conservando la duración. "Fin > Al cursor" en una línea sin
  fin lo crea (`AddEnd`). Mover = borrar + insertar por la ruta de los taps
  (`EnsureTake`), en un solo bloque de undo. Tras mover, la selección y el
  borrador siguen al evento y la lista hace scroll hasta la fila.
- **Agregar línea.** Fila "Agregar" al final del panel (campo y botón),
  siempre habilitada: no depende de la selección. Sin track de Lyrics la tab
  dibuja solo esa fila (`drawAddOnly`) y el alta crea el track. Agrega en el
  cursor o, con selección de tiempo, la línea en `t1` y el `·` en `t2`; con
  el campo vacío inserta solo el `·`. Enter en el campo agrega (también
  vacío); Tab o click afuera no. Orden: `LyricsSync.flush`,
  `GetTimeContext`, `PlanLine`, `DecideAdd` (el flush va antes: un `·`
  pendiente insertado después dejaría viejo el `ctx`). `apply` aplica
  directo, `reject` avisa, y `confirm_*` abre el modal.
- **Confirmación.** Se guarda en `Ed.add_pending` `(t1, t2, texto)` y una
  vista previa congelada de lo que se pisa (hasta 5 líneas con su posición,
  texto cortado a 50 caracteres, y la cantidad de `·` aparte); nunca el
  `ctx`. Al confirmar se vuelve a planear y, si `kind`, `n` o `has_line`
  cambiaron, se cancela con aviso. Un cambio de proyecto con el modal abierto
  lo descarta. Línea existente: Reemplazar / Cancelar. Eventos dentro de la
  selección: Reemplazar todo / Conservar / Cancelar (`opts.replace_inside`);
  si además hay una línea en `t1`, es el mismo modal de tres botones.
  Conservar no inserta el `·` de `t2` (§8.2). El título del modal es su ID:
  se usa `'Agregar linea###lyrics_add_confirm'` para que no se vea el
  identificador. Teclas: Esc cancela, leído a mano (el panel tiene `NoNav`
  y ImGui cierra los popups con Esc por la navegación); Enter ejecuta
  Reemplazar en el modal de un botón y Cancelar en el de tres (un Enter
  reflejo no borra varias líneas), evaluado después de los botones: si uno
  se activó con las flechas, manda ese. Ambas teclas se ignoran el primer
  frame y sin auto-repeat, para que el Enter que abre el modal desde el
  campo no lo confirme. Los atajos globales y la tecla de tap no actúan con
  un popup abierto (§8.3, patrones §6).
- **Después de agregar.** La selección pasa a la línea nueva (al `·` si el
  texto era vacío) y la lista hace scroll hasta ella; `S.state_count = -1`
  fuerza la recarga y, con el toggle activo, `S.reselect` hace que la
  selección de tiempo la siga. Una línea agregada no entra en `hist`, así
  que no hay `onEdit`. Relacionado: `applyTimeRange` ahora llega hasta el fin
  del item de Lyrics cuando una línea no tiene evento siguiente (incluye el
  margen de `PAD_TIME` que deja `EnsureTake`); vale también para el click en
  la última línea.
- **Contrato con la cola de tap.** Cada operación llama a
  `LyricsSync.flush` antes (inserta el fin pendiente) y a
  `LyricsSync.onEdit(S.sync, Lyrics, change)` después, con un descriptor
  `{kind = "move" | "endadd" | "delete" | "text", ...}`. `move` reescribe
  `time` y `end_time` de la entrada de `hist`; `endadd` anota el
  `end_time`; borrar una línea convierte la entrada en `skip` (conserva la
  posición de la cola y "Deshacer" la desapila sin borrar nada); borrar un
  fin limpia `end_time`. Los borrados reinician `seen_lines` para que
  `reconcile` no los tome por un Ctrl+Z. `S.sync` puede ser `nil` (cola
  nunca abierta). Si "Deshacer" no encuentra la línea, muestra `Sy.warn` con
  prioridad (también con el transporte detenido); se limpia con el
  siguiente tap, "Deshacer" o "Vaciar cola".
- **Refresh.** Las operaciones fuerzan la recarga del cache con
  `S.state_count = -1` (la tab recarga al inicio del frame siguiente) y
  parchean solo lo que la UI usa en el frame de transición.
- **Granularidad de undo.** Un bloque por operación: diez clicks de nudge
  son diez puntos de undo. Agruparlos (`Undo_OnStateChange` con flush por
  inactividad) queda como mejora opcional, con el riesgo de que un cierre
  inesperado deje cambios sin punto propio.
- **Limitaciones conocidas.** Un Ctrl+Z o Redo de REAPER sobre un nudge o
  movimiento deja la línea en su posición anterior mientras `hist` guarda la
  nueva: "Deshacer" retrocede la cola sin borrar la línea y avisa, y la
  línea se borra desde el panel. Mover a mano en el editor MIDI cae en el
  mismo caso. Un intento de reconocerla por posiciones previas se descartó
  por frágil: podía asignar un borrado o un movimiento a la entrada
  equivocada.

### 8.7 Plan restante

- **3c, agregar línea:** hecho, comportamiento final en §8.6. Motivo de que
  el modal de reemplazo sea obligatorio: con "Seleccionar duración al hacer
  click" activo, clickear una línea deja una selección de tiempo igual a su
  rango, y agregar sobre ella reemplazaría esa línea (upsert en `t1`).
  Pendiente menor: revisar si la agrupación de undo (§8.6) vale la pena.
- **3d. Publicación.** Extraer `Lyrics.Publish(proj)` de
  `Nik_MusicState_PublishLyrics.lua` (el script queda como cáscara de pocas
  líneas), que devuelva versión, cantidad de líneas y tamaño en bytes. Botón
  Publicar y toggle de auto-publicar con debounce. No hay bucle: el cliente
  usa `FetchLyrics` al detectar el cambio de versión. Aprovechar para
  probar el pendiente 3 de §6 (tope de `EXTSTATE`) con una letra larga.
  Disparar el auto-publicar por una firma del contenido (texto y tiempo de
  `S.events`, calculada en `refresh`) y no por
  `GetProjectStateChangeCount`, que cambia con cualquier edición del
  proyecto. El debounce tiene que superar la cadencia de nudges y taps
  (≥ 1,5 s). Verificar que publicar (ExtState global) no incrementa ese
  contador.
- Al cerrar el paso 3: actualizar este doc y `musicstate_helper.md`.

### 8.8 Para retomar en otra sesión

Adjuntar: este doc, `musicstate_helper.md`,
`MusicStateLyricsTab_common_logic.lua`, `MusicStateLyrics_common_logic.lua`,
`MusicStateLyricsSync_common_logic.lua`,
`MusicStateLyricsEdit_common_logic.lua`, `08_REAIMGUI_PATTERNS.md` e
`ImGuiInputCommit_common_logic.lua`. `Nik_MusicState_Helper.lua` solo si
hace falta (archivo grande: alcanzan las líneas de `dofile`, `helpers` y el
loop con los atajos globales). Para 3d, además
`Nik_MusicState_PublishLyrics.lua`.

Método de trabajo de 3c: análisis, plan de etapas y lista de tests antes de
codear; un diff por hunk en formato buscar/reemplazar; aviso de tamaño si una
etapa pasa de 300 líneas; un commit por unidad lógica.
