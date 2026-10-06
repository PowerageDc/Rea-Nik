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
| Capa cliente (setter, consultas) | **Pendiente** — próximo paso |
| UI de cantante (`musicstate-ui/cantante/`) | Pendiente, diseño conceptual en §5 |
| Registro del script (`NIK_LUA_COMMANDS`, `config.local.js`, ReaPack) | Pendiente |

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

## 5. Diseño de UI acordado (conceptual, sin implementar)

- **Estados de la línea:** intro (antes de la primera línea: las primeras
  se muestran como "próximas", análogo al preludio de la fila de sección),
  cantando, silencio entre líneas (la actual se apaga y la siguiente queda
  "armada", con énfasis intermedio) y carry-over (sin marcador de fin, la
  actual se mantiene).
- **Ventana de 5 slots** (2 anteriores, actual, 2 siguientes), con la
  técnica FLIP de `01_CONVENCIONES.md` (escala uniforme por centros).
- **Lookahead propio de lyrics:** un cantante necesita leer antes que un
  instrumentista; no reusar el de los acordes.
- **Líneas que envuelven en 2 renglones** cambian de alto por contenido y
  no solo por `font-size`: fijar un tope de renglones antes de construir.
- **Cuenta regresiva en pausas largas:** `nikBeat` calcula la distancia al
  próximo evento de armonía; se podría generalizar.
- **Control remoto general:** acceso a lyrics y acordes en paneles
  activables, a mediano plazo. Por eso la capa de consultas no debe
  depender de globales del prompter, y el pedido de lyrics es propio (no
  entra en `nikMusicStateRequestAll()`).

## 6. Pendientes, en orden

1. **Capa cliente** (`musicstate_client.md`): `nikMusicStateSetLyricsData`
   con el des-escape de barras, reuso de `nikMusicStateFlattenBarKeyed`,
   estado cacheado, y consultas (ventana, línea actual o `null`, si la
   actual ya terminó, distancia al próximo evento). Primero se define la
   API de consultas, después el código.
2. **`01_CONVENCIONES.md`:** el nombre del track `🎤 Lyrics`; revisar que
   AutoColor y los snapshots lo ignoren.
3. **Registro del script:** entrada en `NIK_LUA_COMMANDS`, generador de
   `config.local.js` y metapaquete de ReaPack (`05_REAPACK_DEPLOY.md`,
   `@provides`).
4. **Verificar el tamaño** con una letra larga real: la prueba midió 318
   bytes con 6 líneas; el tope de `EXTSTATE` no está documentado.
5. **Emparejamiento lyric↔nota MIDI** (duración o progreso por sílaba a
   futuro): no verificado, la prueba se hizo sin notas.
6. **`cues_data` y el escape de barras:** revisar si el Helper y
   `nikMusicStateSetCuesData` lo manejan (`data_model` §6).
7. **UI de cantante** (`musicstate-ui/cantante/`): filtro por rol
   (`cantantes`) o letra para todos, estados de §5, refresco por
   republicación (acción de `PublishLyrics`, porque nada incrementa
   `lyrics_version` solo al editar en el editor MIDI).
8. Actualizar el SPEC original (`lyrics` figura fuera de alcance según
   `musicstate_instrumentista.md`) e `IMPL_MusicState.md`.

## 7. Archivos

- `MusicState/Nik_MusicState_PublishLyrics.lua` — publicador one-shot.
- `Tests-Debug/Nik_Tests_LyricsProbe.lua` — volcado de los eventos lyric
  y de `GetTrackMIDILyrics` a consola.
- Docs tocados: `musicstate_data_model.md` (§2, §3, §4, §4.7, §6),
  `musicstate_bridge.md` (§1, §2, §5).
