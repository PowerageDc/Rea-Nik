# Feature — MusicState: lyrics para cantantes (estado y decisiones)

Estado y decisiones de la feature de lyrics: qué está decidido, qué se
descartó, qué se verificó y qué falta. La UI de cantante vive en
`musicstate_cantante.md`; el ingreso de letras y la tab Lyrics del Helper,
en `musicstate_lyrics_helper.md`. Este doc conserva las decisiones de la
feature y el publicador.

El contrato de datos (formato JSON, protocolo) vive en
`musicstate_data_model.md` §4.7 y no se repite acá. El puente está en
`musicstate_bridge.md` §1.

## 1. Estado

| Pieza | Estado |
|---|---|
| Contrato de datos (`lyrics_data`, `lyrics_version`) | Documentado en `data_model` §4.7 |
| Publicador `Nik_MusicState_PublishLyrics.lua` | Implementado (§4) |
| Ingreso de letras y tab Lyrics del Helper | Implementado; falta publicar desde la tab. Detalle en `musicstate_lyrics_helper.md` §1 |
| Capa cliente (setter, consultas, lead propio) | Implementada (§4); detalle en `musicstate_client.md` §1.6 |
| Cableado (`ms-dispatch.js`: pedidos, versión, reset, opt-in) | Implementado |
| UI de cantante (`musicstate-ui/cantante/`) | Implementada; pendientes de afinado, cues y rol en `musicstate_cantante.md` §6 |
| Registro (`NIK_LUA_COMMANDS`, generador de `config.local.js`, `@provides` del metapaquete, manifiesto `.www`) | Hecho |

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
- **Formato** (`qn_offset` libre sin grilla, evento = línea completa en
  v1, marcador `·` publicado como `"text": null`, carry-over sin
  marcador): `musicstate_data_model.md` §4.7. El marcador es un símbolo
  porque el editor MIDI no acepta texto vacío.
- **`lyrics_version` propio**, independiente de `publish_version`
  (motivo: `musicstate_bridge.md` §5).
- **Lead propio, en segundos, sobre el lookahead de acordes**, para que
  playrate y mapa de tempo se resuelvan donde ya se resolvían
  (`musicstate_client.md` §1.6, `musicstate_sync.md` §6).
- **Dos pedidos de lyrics: uno dispara el script, otro es solo lectura**
  (evita un bucle: `musicstate_bridge.md` §5).
- **Lyrics es opt-in por UI** (`NIK_MS_LYRICS_ENABLED`,
  `musicstate_sync.md` §1).
- **Ingreso de letras y tab del Helper** (por API, upsert, lógica sin UI,
  tab sin `H`, publicación desde la tab): decisiones en
  `musicstate_lyrics_helper.md` §2.

## 3. Descartado, y por qué

- **WebSocket y "Web Control como servidor/puente"** (del spec original de
  ChatGPT): el servidor web de REAPER es HTTP con polling. La sincronización
  con el transporte ya está resuelta (`musicstate_sync.md`).
- **`GetTrackMIDILyrics`:** posición truncada a centésimas de beat y texto
  mezclado con tabs. Se usa `MIDI_GetTextSysexEvt` filtrando tipo 5.
- **Comando nativo `LYRICS/<n>` del web control (camino A):** obligaba a
  descubrir el índice del track en el cliente y parsear `beat_position`.
- **Posiciones en segundos:** incompatibles con el modelo de datos.
- **Reusar `publish_version`:** ver `musicstate_bridge.md` §5.
- **Texto vacío o espacio como marcador de fin de línea:** el editor no
  acepta el vacío, y el espacio es invisible y frágil.
- **Lead de lyrics en QN:** el lookahead existente está en segundos y se
  convierte a compás con el tempo y el playrate; un lead en QN no
  resolvía ninguna de las dos cosas.
- **Re-disparar `PublishLyrics` al detectar un cambio de `lyrics_version`:**
  bucle (`musicstate_bridge.md` §5).
- **Descartes del ingreso y de la tab del Helper** (diálogo nativo del
  editor MIDI, edición de posición con `RowInputs`, línea en blanco como
  `·`): `musicstate_lyrics_helper.md` §2.

## 4. Comportamiento verificado

Publicador y datos (`Tests-Debug/Nik_Test_LyricsProbe.lua`):

- Los lyrics sin notas son válidos y se leen con `MIDI_GetTextSysexEvt`.
- Acentos, `¿`, `ñ` llegan intactos como UTF-8 (con `fetch().text()`; la
  barra de direcciones muestra mojibake por falta de charset, no es un
  problema de datos).
- `TimeMap_QNToMeasures` devuelve el compás **1-indexed**, y un evento
  fuera de grilla conserva su posición (resolución real: 1/960 de negra).
- `lyrics_version` sube en cada publicación.

Cliente:

- Con play real, la línea pasa a vigente ~1,4 s antes de su posición con
  los valores por defecto (0,4 s de lookahead más 1,0 s extra), y ~0,4 s
  con `extraLeadSec = 0`.
- Tras ejecutar `PublishLyrics`, el panel se actualiza en ~1 s y
  `lyrics_version` queda estable (sin bucle).
- Casos de consulta y des-escape: `musicstate_client.md` §3. Cambio de
  proyecto con y sin track de lyrics: `musicstate_sync.md` §11.

## 5. Control remoto general (mediano plazo)

Lyrics y acordes llegarían al control remoto general en paneles
activables. Restricciones de diseño: la capa de consultas no debe depender
de globales del prompter, el pedido de lyrics es propio (no entra en
`nikMusicStateRequestAll()`) y su dispatcher tiene que definir
`nikMsTempoAt`, sin la cual el lead no se aplica (`musicstate_sync.md`
§14).

## 6. Pendientes

- **`01_CONVENCIONES.md`, track de letra:** el nombre ya está documentado;
  falta verificar que AutoColor y los snapshots ignoren el track `🎤 Lyrics`
  y anotar el resultado ahí.
- **Verificaciones de datos** (tope de `EXTSTATE`, emparejamiento
  lyric↔nota MIDI, `cues_data` y escape de barras):
  `musicstate_data_model.md` §6.
- **UI de cantante:** `musicstate_cantante.md` §6. Nada incrementa
  `lyrics_version` al editar en el editor MIDI: hay que ejecutar la acción de
  `PublishLyrics` (publicar desde la tab lo automatiza,
  `musicstate_lyrics_helper.md` §9).
- Actualizar el SPEC original: `SPEC` §18 declara lyrics fuera de alcance.
- A futuro, sin decidir: que "Guardar y Publicar" del Helper también
  guarde la letra (editar el track con el Helper abierto). Se define
  después de usar el flujo actual con `PublishLyrics`.
- **Probar el alta con un fin pendiente de la cola** (sin probar): subir el
  gap de la cola (`lyrics_tap_gap_ms`), tapear con hold de al menos 250 ms,
  soltar y apretar "Agregar" antes de que venza. Esperado: el `·` pendiente
  se inserta antes del alta (el alta llama al mismo `flush` que las
  ediciones, antes de `PlanLine`), el tap queda con su fin y la cola no
  cambia. Verificado aparte: un "Reemplazar todo" que borra tres líneas con
  la cola cargada no mueve la cola.
- **Ctrl+Z tras agregar con selección de tiempo activa:** el Ctrl+Z deshace
  la línea pero la selección de tiempo queda en el arrange, porque la tab
  solo limpia `S.sel` cuando deja de resolverse, no el rango. Idea: en
  `refresh`, limpiar el rango solo si empieza en el tiempo de la línea
  que desapareció, para no pisar una selección armada a mano.

## 7. Archivos

- `MusicState/Nik_MusicState_PublishLyrics.lua` — publicador one-shot.
- Ingreso y módulos de la tab Lyrics del Helper
  (`Nik_MusicState_LyricsInput.lua`, `MusicStateLyrics*_common_logic.lua`,
  probes de edición): `musicstate_lyrics_helper.md` §3.
- `Tests-Debug/Nik_Test_LyricsProbe.lua` — volcado de los eventos lyric
  y de `GetTrackMIDILyrics` a consola.
- `core/music-state.js` — bloque de lyrics (setter, consultas, pedidos).
- `musicstate-ui/shared/ms-dispatch.js` — handlers, reset y opt-in.
- `config.js` — `musicStatePublishLyrics`.
- `musicstate-ui/cantante/cantante.js`, `cantante.css` y
  `nsaudio_cantante.html` — UI de cantante; ver `musicstate_cantante.md`.
