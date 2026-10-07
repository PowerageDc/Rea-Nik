# Feature — MusicState: lyrics para cantantes (estado y decisiones)

**Doc liviano, en construcción.** Registra qué está decidido, qué se
descartó, qué se verificó y qué falta, para poder retomar la feature en
otra sesión sin reconstruir el contexto. Cuando la UI de cantante esté
implementada, este doc se expande al formato de
`musicstate_instrumentista.md`.

El contrato de datos (formato JSON, protocolo) vive en
`musicstate_data_model.md` §4.7 y no se repite acá. El puente está en
`musicstate_bridge.md` §1.

## 1. Estado

| Pieza | Estado |
|---|---|
| Contrato de datos (`lyrics_data`, `lyrics_version`) | Documentado en `data_model` §4.7 |
| Publicador `Nik_MusicState_PublishLyrics.lua` | Implementado y verificado (ver §4) |
| Ingreso `Nik_MusicState_LyricsInput.lua` | MVP con `GetUserInputs` implementado y verificado: línea en cursor o selección, marcador `·` de fin, upsert, aviso ante eventos dentro de la selección. Ventana persistente: ver la tab del Helper (fila siguiente) |
| Tab Lyrics del Helper (`MusicStateLyricsTab_common_logic.lua`) | Paso 3a implementado y verificado (visor de solo lectura: click → cursor y duración de la línea). Pasos 3b a 3d pendientes (§8) |
| Doc del puente | Actualizado (lyrics fuera de `Bridge.KEYS`) |
| Capa cliente (setter, consultas, lead propio) | Implementada y verificada en dev (ver §4); detalle en `musicstate_client.md` §1.6 |
| Cableado (`ms-dispatch.js`: pedidos, versión, reset, opt-in) | Implementado y verificado en dev |
| UI de cantante (`musicstate-ui/cantante/`) | Bootstrap y panel de debug temporales (`cantante.js`, `nsaudio_cantante.html`); UI real pendiente, diseño conceptual en §5 |
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

## 5. Diseño de UI acordado (conceptual, sin implementar)

- **Estados de la línea:** intro (antes de la primera línea: las primeras
  se muestran como "próximas", análogo al preludio de la fila de sección),
  cantando, silencio entre líneas (la actual se apaga y la siguiente queda
  "armada", con énfasis intermedio) y carry-over (sin marcador de fin, la
  actual se mantiene).
- **Ventana de 5 slots** (2 anteriores, actual, 2 siguientes), con la
  técnica FLIP de `01_CONVENCIONES.md` (escala uniforme por centros).
- **Lookahead propio de lyrics:** un cantante necesita leer antes que un
  instrumentista; implementado como adelanto extra sobre el de los
  acordes (`musicstate_client.md` §1.6). Falta calibrar el valor con una
  letra real.
- **Líneas que envuelven en 2 renglones** cambian de alto por contenido y
  no solo por `font-size`: fijar un tope de renglones antes de construir.
- **Cuenta regresiva en pausas largas:** `nikBeat` calcula la distancia al
  próximo evento de armonía; se podría generalizar.
- **Control remoto general:** acceso a lyrics y acordes en paneles
  activables, a mediano plazo. Por eso la capa de consultas no debe
  depender de globales del prompter, y el pedido de lyrics es propio (no
  entra en `nikMusicStateRequestAll()`). Ahí también tendría que existir
  `nikMsTempoAt`, sin la cual el lead no se aplica
  (`musicstate_client.md` §4).
- **Datos de boot de la UI real:** hoy `cantante.js` pide solo tempo,
  timesig y lyrics. La UI real va a necesitar secciones
  (`ms-section.js`), casi seguro cues, y posiblemente la tonalidad
  (transpuesta o no); el pulso (`ms-beat.js`) depende de cómo se sienta
  con el preludio de la línea siguiente. Cada dato suma su pedido de
  boot y su script en el shell (`musicstate_client.md` §1.5).

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
6. **UI de cantante real** (`musicstate-ui/cantante/`): filtro por rol
   (`cantantes`) o letra para todos, estados de §5, datos de boot (§5) y
   calibrar el lead. El refresco por republicación ya llega por
   `lyrics_version`, pero nada lo incrementa solo al editar en el editor
   MIDI: hay que ejecutar la acción de `PublishLyrics`.
7. Actualizar el SPEC original (`lyrics` figura fuera de alcance según
   `musicstate_instrumentista.md`).
8. A futuro, sin decidir: que "Guardar y Publicar" del Helper también
   guarde la letra (editar el track con el Helper abierto). Se define
   después de usar el flujo actual con `PublishLyrics`.

## 7. Archivos

- `MusicState/Nik_MusicState_PublishLyrics.lua` — publicador one-shot.
- `MusicState/Nik_MusicState_LyricsInput.lua` — ingreso de líneas (UI mínima sobre el módulo).
- `MusicState/MusicStateLyrics_common_logic.lua` — descubrimiento del track y lógica de edición (`PlanLine`/`ApplyLine`), sin diálogos ni ImGui.
- `MusicState/MusicStateLyricsTab_common_logic.lua` — tab Lyrics del Helper (`M.draw(ctx, H, helpers)`).
- `Tests-Debug/Nik_Tests_LyricsProbe.lua` — volcado de los eventos lyric
  y de `GetTrackMIDILyrics` a consola.
- `core/music-state.js` — bloque de lyrics (setter, consultas, pedidos).
- `musicstate-ui/shared/ms-dispatch.js` — handlers, reset y opt-in.
- `config.js` — `musicStatePublishLyrics`.
- `musicstate-ui/cantante/cantante.js` y `nsaudio_cantante.html` —
  bootstrap y panel de debug temporal.
- Docs tocados: `musicstate_data_model.md` (§2, §3, §4, §4.7, §6),
  `musicstate_bridge.md` (§1, §2, §5), `musicstate_client.md` (§1.6).

## 8. Ingreso de lyrics y tab del Helper (en construcción)

### 8.1 Estado por paso

| Paso | Estado |
|---|---|
| Módulo `MusicStateLyrics_common_logic.lua` + `Nik_MusicState_LyricsInput.lua` (MVP con `GetUserInputs`) | Hecho, 6 pruebas verificadas |
| Refactor: `PlanLine`/`ApplyLine` al módulo, script como capa de UI | Hecho, verificado |
| 3a. Tab Lyrics del Helper, solo lectura | Hecho, 7 pruebas verificadas |
| 3b. Cola de tap-to-sync | Pendiente |
| 3c. Edición (inline, nudge, mover al cursor, borrar, agregar línea) | Pendiente |
| 3d. `Lyrics.Publish`, botón Publicar y auto-publicar | Pendiente |

### 8.2 API del módulo

Constantes: `END_MARK` (`·`), `DEFAULT_TRACK_NAME` (`🎤 Lyrics`),
`EPS_TIME` (0.01 s, tolerancia para "misma posición"), `PAD_TIME` (5 s,
margen al crear o extender el item).

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
  selección. Devuelve `false, "end_occupied"` si el texto es vacío y ya
  hay un evento en la posición del marcador; si no, `true, track`.

### 8.3 Gotchas verificados

- `GetUserInputs` con un solo campo: se usa
  `extrawidth=350,separator=\n` para que las comas de la letra no
  partan el valor.
- Los archivos que contienen `·`, `🎤` o `→` tienen que guardarse en
  UTF-8; si no, el `·` se inserta mal y el publicador no lo reconoce.
- Para limpiar la selección de tiempo: `GetSet_LoopTimeRange(true, false,
  0, 0, false)`.

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

### 8.5 Plan restante

- **3b. Cola de tap-to-sync.** Pegar la letra: cada línea es un ítem, una
  línea en blanco es un `·`. Cada tap inserta el siguiente ítem en la
  posición de reproducción, con compensación de latencia ajustable (por
  ejemplo −150 ms) y "deshacer último tap". La tecla no puede ser Enter,
  Space ni las flechas (globales en el contenedor); revisar
  `globalKeyPressed` en `ImGuiInputCommit_common_logic.lua` antes de
  elegirla, y no dispararla si un `InputText` tiene foco. Un script satélite
  (flag en `ExtState`, mapeable a footswitch) queda aplazado.
- **3c. Edición.** Texto inline con commit al terminar de editar (patrón de
  transición de `active`, `08_REAIMGUI_PATTERNS.md` §3), nudge de ±1/16 de
  beat o ms, mover inicio y fin al cursor, borrar línea o marcador, y
  agregar línea en cursor o selección (reemplaza al diálogo).
- **3d. Publicación.** Extraer `Lyrics.Publish(proj)` de
  `Nik_MusicState_PublishLyrics.lua` (el script queda como cáscara de pocas
  líneas), que devuelva versión, cantidad de líneas y tamaño en bytes. Botón
  Publicar y toggle de auto-publicar con debounce. No hay bucle: el cliente
  usa `FetchLyrics` al detectar el cambio de versión. Aprovechar para
  probar el pendiente 3 de §6 (tope de `EXTSTATE`) con una letra larga.
- Al cerrar el paso 3: actualizar este doc y `musicstate_helper.md`.

### 8.6 Para retomar en otra sesión

Adjuntar: este doc, `musicstate_helper.md`, `Nik_MusicState_Helper.lua`,
`MusicStateLyricsTab_common_logic.lua`, `MusicStateLyrics_common_logic.lua`,
`08_REAIMGUI_PATTERNS.md`. Para 3b, además `ImGuiInputCommit_common_logic.lua`; para
3d, `Nik_MusicState_PublishLyrics.lua`.
