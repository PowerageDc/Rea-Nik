# Feature — MusicState: motor de sincronización del cliente

Cómo una UI web convierte la posición del transporte y los datos
publicados en "qué toca ahora": ancla, posición efectiva, adelantos,
polls, conexión inestable y ciclo de vida por proyecto. Lo leen quien toca
el timing, `ms-dispatch.js` o el cambio de proyecto.

Fuera de este doc: formato de keys y protocolo (`musicstate_data_model.md`),
consultas y transposición (`musicstate_client.md`), módulos visuales
compartidos (`musicstate_shared_ui.md`), pantalla de instrumentista
(`musicstate_instrumentista.md`), pantalla de cantante
(`musicstate_cantante.md`), Monitor Mix (`monitor_mix.md`,
`monitor_mix_ui.md`), pruebas (`musicstate_testing.md`).

## 1. Dispatchers

| Dispatcher | Lo usan | Notas |
|---|---|---|
| `musicstate-ui/shared/ms-dispatch.js` | instrumentista, cantante, Monitor Mix (`monitor.js`) | `wwr_onreply` propio; atiende solo lo que estas UIs necesitan |
| `core/wwr-dispatch.js` | control remoto general | tiene `case`s sin guard `if (elemento)` que asumen DOM de tracks/faders/sends; no sirve para las UIs de MusicState |

Opt-ins de `ms-dispatch.js` (cada UI activa lo suyo):

- `NIK_MS_LYRICS_ENABLED` (default `false`): habilita el re-pedido de letra
  en el cambio de proyecto. Lo activa `cantante.js`. Mecanismo y bucle de
  `lyrics_version`: `musicstate_bridge.md` §5; API: `musicstate_client.md`
  §1.6.
- Ganchos de Monitor Mix, con guard `typeof`: no-op si la UI no carga
  `monitor.js`. `nikMmOnExtState` atiende el EXTSTATE de `NikMonitorMix`,
  `nikMmOnLine` el `default:` del switch (líneas `TRACK` y `SEND`),
  `nikMmRequestList` se dispara desde `nikMsHandleProjectSwitch` y
  `nikMmReset` desde `nikMsResetProjectState` (§11). Contrato de la
  lista: `monitor_mix.md` §5.

`nikMusicState*` (consultas) no depende del dispatcher: usa las globales de
§12; si una UI no define las de adelanto, el adelanto es 0.

## 2. Fuentes de datos

Formato de cada key: `musicstate_data_model.md` §4. Acá solo qué se lee y
cómo se consume.

| Dato | Fuente | Consumo |
|---|---|---|
| Posición y estado | `TRANSPORT` (`main.js`) | `tok[1]` playstate (0 detenido, 1 reproduciendo, 2 pausado, 5 grabando, 6 grabación pausada), `tok[2]` segundos, `tok[5]` `compás.beat.centésimas` |
| Secciones | `g_markers` (poll `MARKER`) + `ms-section.js` | último marker con posición ≤ efectiva (épsilon 1 ms); nombre/color vía `nikResolveMarkerDisplay()` (incluye cadenas `x2/x3...`) |
| Tempo | `NikRemote/tempo_map` vía `nikMsTempoAt(pos)` (`ms-tempo.js`) | BPM del mapa, sin playrate |
| Compases | `NikRemote/timesig_map` | lo consume `music-state.js` |
| Playrate | `NikRemote/playrate` | §7 |
| Semitono | `NikRemote/reapitch_semitone` | `nikReaPitchLastSemitone`; `"none"` y `"mixed"` son sentinels válidos |
| Nombre de canción | `NikRemote/active_project_name` | con `.rpp`; sin esa extensión (pestaña sin guardar, literal según idioma de REAPER) el nombre se muestra vacío (`U+00A0`) |
| Armonía, tonalidad, roles, cues, `publish_version` | `NikMusicState/*` | puenteadas por `Bridge.bridgeAll`; ver `musicstate_bridge.md` |
| Letra y `lyrics_version` | `NikMusicState/lyrics_*` | solo UIs con `NIK_MS_LYRICS_ENABLED` |

`tempo_map` y `timesig_map` las publica `Nik_Playrate_ReadTempoMap.lua`
(un script, dos keys; formato en `data_model` §4.5).

## 3. Archivos y orden de carga

```
web/musicstate-ui/
├── shared/
│   ├── ms-dispatch.js    wwr_onreply, ancla, ciclo de proyecto
│   ├── ms-tempo.js       lookup de tempo puro
│   ├── ms-section.js     sección actual y posición efectiva en segundos
│   ├── ms-beat.js        pulso (solo instrumentista)
│   ├── ms-section-row.js, ms-header.js, ms-stale.js, ms-base.css   ver musicstate_shared_ui.md
├── instrumentista/   cantante/   monitor/
```

Orden de carga del shell (cada archivo depende de los anteriores):
`main.js`, `config.js`, `config.local.js` (XHR síncrono + `eval`; se ignora
si no existe), `core/utils.js` (`nikLerpColor`, dependencia de
`markers.js`), `markers/markers.js`, `core/music-transpose.js`,
`core/music-state.js`, `ms-tempo.js`, [`ms-beat.js`], `ms-section.js`,
`ms-section-row.js`, `ms-header.js`, `ms-stale.js`, `ms-dispatch.js`, JS
de la UI. Después cada UI arranca su bootstrap.

`config.local.js` es imprescindible en cada PC (Command IDs); sin él los
pedidos Lua fallan en silencio. Detalle y generador: `05_REAPACK_DEPLOY.md`.

`nikInstrumentistaInit()` (polls y pedidos on-demand) no asume IDs de DOM;
el render lo arranca solo el shell que tiene la estructura visual.

## 4. Flujo y ancla

```
REAPER (servidor web embebido)
   │  main.js: un request a la vez, sin solapar
   ▼
wwr_onreply(results, sentAtMs)                      [ms-dispatch.js]
   ├─ TRANSPORT ─► nikTransportPlayState, playPosSeconds,
   │               nikLastPositionBeatsStr, nikTransportAnchorMs
   ├─ EXTSTATE  ─► playrate, semitono, tempo_map, timesig_map,
   │               NikMusicState/*, active_project_name
   └─ MARKER_*  ─► g_markers ─► nikMsSectionOnMarkersUpdated()

render loop de la UI (50 ms)
   ├─ indicador de datos viejos (§9)
   ├─ segundos efectivos ─► sección, BPM
   └─ compás/beat efectivo ─► acordes, ventana, cues
```

**Ancla.** Al procesar cada `TRANSPORT`: `nikTransportAnchorMs =
performance.now() - min(RTT/2, 250 ms)`, con `RTT = Date.now() - sentAtMs`
(`sentAtMs` es el segundo parámetro que `main.js` pasa a `wwr_onreply`).
Dice "hace cuánto era cierta esta posición", ya compensada la ida de la
respuesta.

## 5. Posición efectiva

```
adelanto = (lookahead + extraLeadSec + min(tiempo desde el ancla, 8 s)) × playrate
```

- `extraLeadSec` es 0 salvo lyrics (§6). El 8 es
  `NIK_MUSIC_STATE_MAX_EXTRAPOLATION_SEC`.
- Solo con `playstate` 1 o 5 (`nikMusicStateIsPlaying()`). Detenido o
  pausado: posición cruda, sin adelanto ni extrapolación.
- Un seek durante el play se corrige con la muestra siguiente (sin lógica
  de snap).

Dos formas del mismo adelanto (`nikMusicStateAdvanceSongSec()`):

- **En segundos:** `nikMusicStateEffectiveSec() = playPosSeconds +
  adelanto`. La consumen secciones (`nikMsEffectivePosSeconds()`, con
  fallback a la cruda) y BPM.
- **En compás/beat:** `nikMusicStateCurrentPos()` toma
  `nikLastPositionBeatsStr`, suma `adelanto × bpm / 60` beats con el BPM
  vigente y cruza de compás con el timesig map. La consumen acordes,
  `ChordWindow`, cues y lyrics.

Acordes y secciones cambian en el mismo instante porque comparten el
adelanto. Los acordes se buscan por tupla (compás, `qn_offset`): no hace
falta tiempo absoluto para ordenar.

## 6. Lookahead y leads

| Constante | Valor | Rol |
|---|---|---|
| `nikMusicStateLookaheadSec` | 0.4 | latencia de red y de dibujado, más un anticipo deliberado para acordes y secciones |
| `nikMusicStateLyricsLeadSec` | 1.0 (sin calibrar) | adelanto **extra, sobre** el lookahead, solo lyrics (`extraLeadSec`, `musicstate_client.md` §1.6) |
| `nikBeat.LATENCY_SEC` | 0.4 | latencia propia del indicador de pulso (`musicstate_instrumentista.md` §3) |

- Es una constante porque la parte variable de la latencia (antigüedad de
  la muestra) ya la absorbe la extrapolación.
- Ajuste en caliente desde la consola (`nikMusicStateLookaheadSec = 0.5`,
  efecto en el siguiente render). `config.local.js` solo trae Command IDs
  y lo regenera el generador: no es lugar para overrides.
- Los dos valores 0.4 son independientes en código; hoy coinciden.

## 7. Playrate

`NikRemote/playrate` viaja en el slow poll (1 s): un cambio tarda hasta
1 s en reflejarse. `nikMsSetTransportPlayRate()` lo guarda en
`nikTransportPlayRate` (default 1) y acepta factor (`0.75`) o porcentaje
(`75`; un valor mayor a 5 se interpreta como porcentaje). Afecta:

- el adelanto (una latencia en tiempo real recorre menos canción a menor
  velocidad);
- el BPM mostrado, que es el **equivalente** (tempo del mapa × playrate),
  mismo criterio que `nikPlayrateComputeEquivalentBpm` del remoto.

## 8. Polls

| Poll | Intervalo | Contenido |
|---|---|---|
| `TRANSPORT` | 100 ms | posición y estado |
| `MARKER` | 500 ms | markers de la timeline |
| Slow | 1000 ms | instrumentista: script `statePoll`, `active_project_name`, `playrate`, `reapitch_semitone`, `publish_version`. Cantante: `active_project_name`, `reapitch_semitone`, `playrate`, `lyrics_version` (`nikCantanteBuildSlowPoll()`). Monitor Mix: `active_project_name`, `reapitch_semitone`, `NikMonitorMix/list_version` |
| Sends (Monitor Mix) | 200 ms | `GET/TRACK/x/SEND/y` de la lista (`monitor_mix_ui.md` §4) |
| On-demand | boot / cambio de proyecto | `tempo_map`, `timesig_map`, `NikMusicState/*`, letra y lista de Monitor Mix (§10) |

- `g_wwr_timer_freq = 20`: espera del loop de `main.js` cuando no hay nada
  vencido. Con `TRANSPORT` a 100 ms, todos los dispositivos consultan a
  ~10 por segundo. `main.js` no solapa requests y el intervalo nominal no
  es el real: se fijan ambos valores para igualar PC y celulares.
- **Backoff de `main.js`:** cada request fallido o abortado (timeout 3 s)
  incrementa `g_wwr_errcnt`; con más de 2, el reintento espera
  `100 << (errcnt - 3)` ms, hasta 3200. Una respuesta con contenido lo
  pone en 0.
- Índice 0 de `g_wwr_req_recur` es `TRANSPORT` (registrado primero).

## 9. Conexión inestable

`nikMsUpdateStaleIndicator(screenEl)` (`ms-stale.js`) corre al inicio de
cada render:

- Más de `NIK_MS_STALE_MS` (1500 ms) sin `TRANSPORT` nuevo: `.ms-screen`
  recibe `is-stale` (efecto visual: `musicstate_shared_ui.md`); se quita al
  llegar el siguiente `TRANSPORT`.
- Mientras `is-stale` está activo limita `g_wwr_errcnt` a 2: los reintentos
  quedan cada ~100 ms y la recuperación al volver la red es de ~100–150 ms
  (medido en dev).
- La extrapolación sigue (hasta 8 s): un corte breve no congela la
  pantalla. El aviso existe porque, si alguien hace stop o seek durante el
  corte, la pantalla no lo refleja hasta reconectar.
- Antes del primer `TRANSPORT` el ancla vale 0 y también marca stale
  (correcto si el servidor no responde; en un arranque normal no llega a
  verse).
- La tira de acordes queda fuera del atenuado: su fade de salto usa
  `opacity` y espera el `transitionend`; pisarla podría trabar la tira.

Requisitos de red de la sala: `07_RED_SALA_ENSAYO.md`.

## 10. Quién pide qué

`nikMusicStateRequestAll()` (qué pide: `musicstate_client.md` §1.5). No
vive en el poll de fondo: `NikMusicState` es independiente de
`NIK_SLOW_POLL`. `publish_version` llega por el slow poll.

| UI | Dispatcher | Cuándo pide |
|---|---|---|
| Control remoto general | `core/wwr-dispatch.js` | al conectar y al cambiar de proyecto |
| Instrumentista | `ms-dispatch.js` | al conectar, al cambiar de proyecto y cuando cambia `publish_version` |
| Cantante | `ms-dispatch.js` + `cantante.js` | letra (`RequestLyrics`) al conectar y al cambiar de proyecto; solo `GET` (`FetchLyrics`) cuando cambia `lyrics_version` |
| Monitor Mix | `ms-dispatch.js` + `monitor.js` | lista (`nikMmRequestList`, dispara el script) al conectar, al cambiar de proyecto y desde Actualizar; solo `GET` (`nikMmFetchList`) cuando cambia `list_version` |

`tempo_map` y `timesig_map` se piden juntos: `nikMsRequestTempoAndTimesig()`
(prompter), `nikPlayrateRequestTempoMap()` y `nikOpenPlayrateModal()`
(remoto). En el remoto, `nikLastPositionBeatsStr` (`core/state.js`) se
cachea en cada `TRANSPORT` (no depende de `nikPositionDisplayMode`);
`music-transpose.js` y `music-state.js` cargan después de `state.js` y
antes de `wwr-dispatch.js`.

## 11. Ciclo de vida por proyecto

- **Punto único:** `nikMsHandleProjectSwitch(source)`. Dos disparadores:
  - `"name"`: cambio de `active_project_name` (slow poll, hasta ~1 s
    después del cambio real de tab).
  - `"markers"`: cambio de la firma de la lista de markers en
    `MARKER_LIST_END` (ciclo de 500 ms; suele llegar antes y deja acordes
    y secciones sincronizados). La primera lista tras el boot solo guarda
    la firma (`nikMsMarkersSig`, `null` hasta entonces).
  - Dedupe: si el otro camino actuó hace menos de
    `NIK_MS_SWITCH_DEDUPE_MS` (2000 ms) se saltea. `nikMsLastSwitchAtMs`
    arranca en `-Infinity`.
  - Falso positivo inocuo: editar markers a mano con la UI abierta dispara
    `"markers"` (un reset y una recarga).
- **Reset:** `nikMsResetProjectState()` limpia armonía, cues, tonalidad,
  roles, letra, tempo map, semitono, `publish_version` y `lyrics_version`
  **antes** de re-pedir (si el proyecto nuevo no tiene `ProjExtState`, el
  puente no tiene qué puentear y quedarían los valores del anterior). No
  vacía `g_markers`: se reemplaza entera en cada `MARKER_LIST` (también
  llega vacía en un tab sin markers).
- **Re-pedido diferido:** además del inmediato, se repite a los 400 ms. Una
  respuesta on-demand rezagada del proyecto anterior puede llegar después
  del reset y el protocolo no etiqueta el proyecto; la mitigación asume
  orden FIFO del servidor (no garantizado formalmente).
- **Refresco de armonía:** el Helper incrementa `publish_version` en cada
  guardado (`musicstate_bridge.md` §3, §5). El cliente guarda el último
  valor (`nikMsLastKnownPublishVersion`, `null` tras cada cambio de
  proyecto) y dispara `nikMusicStateRequestAll()` ante cualquier cambio.
- **Lyrics:** el reset vacía la letra y `nikMsLastKnownLyricsVersion`; el
  re-pedido es opt-in (§1). Un valor vacío de `lyrics_version` cuenta como
  cambio a `null`.
- **Monitor Mix:** el cambio de proyecto dispara `nikMmRequestList()` y el
  reset llama a `nikMmReset()` (§1).
- **Secciones:** `nikMsSectionOnMarkersUpdated()` reordena y resuelve la
  cadena de colores en cada `MARKER_LIST_END`, sobre toda la timeline, para
  que una cadena `x2/x3...` herede el color correcto aunque su ancla no
  sea el marker actual.

## 12. Contrato de globales

Índice de nombres (el comportamiento está en la sección indicada).

| Nombre | Archivo | § |
|---|---|---|
| `playPosSeconds` (string), `nikLastPositionBeatsStr` (nombre fijo, igual al del remoto), `nikTransportPlayState`, `nikTransportAnchorMs` | ms-dispatch.js | 4 |
| `nikTransportPlayRate`, `nikMsSetTransportPlayRate()` | ms-dispatch.js | 7 |
| `nikReaPitchLastSemitone`, `nikCurrentProjectName`, `g_markers` | ms-dispatch.js | 2 |
| `nikMsHandleProjectSwitch`, `nikMsResetProjectState`, `nikMsMarkersSig`, `nikMsLastSwitchAtMs`, `NIK_MS_SWITCH_DEDUPE_MS`, `nikMsLastKnownPublishVersion`, `nikMsLastKnownLyricsVersion` | ms-dispatch.js | 11 |
| `NIK_MS_LYRICS_ENABLED` | ms-dispatch.js | 1 |
| `NIK_MS_DEBUG`, `nikMsLog(tag, extra)` | ms-dispatch.js | `musicstate_testing.md` |
| `nikMusicStateLookaheadSec`, `NIK_MUSIC_STATE_MAX_EXTRAPOLATION_SEC`, `nikMusicStateLyricsLeadSec`, `nikMusicStateAdvanceSongSec()`, `nikMusicStateEffectiveSec()`, `nikMusicStateCurrentPos()` | music-state.js | 5, 6 |
| `nikMsEffectivePosSeconds()`, `nikMsCurrentSection()`, `nikMsSectionAt(pos)` | ms-section.js | 2, 5 |
| `nikMsTempoAt(pos)` | ms-tempo.js | 2 |
| `NIK_MS_STALE_MS`, `nikMsUpdateStaleIndicator(screenEl)` | ms-stale.js | 9 |

## 13. Gotchas

- **`main.js` es de REAPER y no se modifica.** Las UIs dependen de
  detalles internos (`g_wwr_errcnt`, `g_wwr_timer_freq`, el segundo
  parámetro de `wwr_onreply`) que podrían cambiar entre versiones.
- **`timesig_map` mal formado** desactiva el adelanto en beats y rompe las
  cues (`nikMusicStateCurrentPos` nunca cruza de compás;
  `nikMusicStateBarStartQn` calcula mal). Reglas de generación:
  `musicstate_data_model.md` §4.5.
- **`tempo_map` sin flag de rampa:** en un cambio gradual se usa el BPM del
  marker de inicio durante toda la rampa; error menor para el adelanto.
- **Tempo por defecto:** un proyecto sin markers de tempo muestra 120 BPM
  (default de REAPER); `nikMsTempoAt` no distingue ese caso.
- **RTT inflado periódicamente (sin medir):** una vez por segundo el
  request lleva también el script del slow poll; esa muestra puede tener
  RTT mayor y desfasar la compensación unos ms (acotada a 250 ms).
- **`performance.now()` mide desde la carga de la página:** un timestamp
  inicial en `0` hace que un dedupe por ventana de tiempo saltee el primer
  evento durante los primeros segundos.
- **Caché del navegador:** recarga forzada tras editar scripts
  (`musicstate_testing.md` §1).
- **Clonado de elementos con `id`:** regla general en `01_CONVENCIONES.md`.

## 14. Pendientes

- Escalar el lookahead según el tempo (evaluar tras varios ensayos con el
  valor fijo).
- Validar la conversión adelanto → beats en compases no x/4 (6/8, etc.):
  solo verificada en 4/4.
- Dots del pulso desfasados con mapas de tempo extensos
  (`musicstate_instrumentista.md` §3): causa sin investigar; puede
  relacionarse con el uso de BPM vigente fijo en la conversión.
- `nikBeat.currentPos()` reimplementa la fórmula de
  `nikMusicStateCurrentPos()`; unificar con `CurrentPos(LATENCY_SEC -
  lookahead)` (hoy equivale a `CurrentPos(0)`).
- `music-state.js` depende de `nikMsTempoAt` (definida en
  `musicstate-ui/shared/`) y esta duplica `nikPlayrateTempoAt`
  (`playrate.js` mezcla DOM del popup): extraer un módulo de tempo
  compartido por el remoto y MusicState. En el remoto general sin
  `nikMsTempoAt` no hay adelanto ni lead de lyrics.
- Portar al control remoto general: indicador de datos viejos, tope de
  `g_wwr_errcnt`, compensación por RTT, frecuencia de poll unificada. La
  extrapolación solo sirve para lo que avanza con el tiempo (posición,
  markers, cursor), no para faders ni meters. Antes, inventariar qué pide
  `core/wwr-dispatch.js` y a qué frecuencia.
- Quitar los guards `typeof` redundantes de `ms-dispatch.js`. Las cuatro
  páginas que lo cargan (prompter, cantante, monitor y test) cargan antes
  `music-state.js`, `ms-section.js` y `ms-tempo.js`, así que esas funciones
  siempre existen. Candidatos: setters, pedidos y resets de `nikMusicState*`,
  `nikMsTempoSetMap` y `nikMsSectionOnMarkersUpdated`. Se mantienen el
  opt-in `NIK_MS_LYRICS_ENABLED` y los ganchos `nikMm*` (solo los define
  monitor). Cuidado: sin guard, un nombre mal escrito aborta el
  procesamiento de `wwr_onreply` en lugar de ignorarse. Verificar cada
  función en las cuatro páginas antes de quitarla.
- Refresco de `tempo_map`/`timesig_map` editados en vivo con la UI abierta
  (no los cubre `publish_version`); caso raro en ensayo.
- Semitono `"mixed"` del Stem Bus: manejo escrito, sin probar con datos
  reales.
- Datos parciales al cambiar de proyecto: la armonía puede llegar antes que
  tonalidad/semitono/nombre y se ven unos ms sin transponer. Idea: pintar
  recién con todos los datos; interactúa con el reset (§11).
- Token de generación por cambio de proyecto, solo si reaparece el bug de
  datos colgados (§11).
- Formato exacto de `NikRemote/playrate` en el valor publicado (el parser
  acepta factor y porcentaje): verificar.
