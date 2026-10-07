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
- `Tests-Debug/Nik_Tests_LyricsProbe.lua` — volcado de los eventos lyric
  y de `GetTrackMIDILyrics` a consola.
- `core/music-state.js` — bloque de lyrics (setter, consultas, pedidos).
- `musicstate-ui/shared/ms-dispatch.js` — handlers, reset y opt-in.
- `config.js` — `musicStatePublishLyrics`.
- `musicstate-ui/cantante/cantante.js` y `nsaudio_cantante.html` —
  bootstrap y panel de debug temporal.
- Docs tocados: `musicstate_data_model.md` (§2, §3, §4, §4.7, §6),
  `musicstate_bridge.md` (§1, §2, §5), `musicstate_client.md` (§1.6).
