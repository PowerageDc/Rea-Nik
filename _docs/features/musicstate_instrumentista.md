# Feature — UI de Instrumentista (MusicState)

Referencia del estado actual del prompter de celular para instrumentistas.
Primera de las UIs por perfil planteadas en `IMPL_MusicState.md` (sección
8, punto 4). Perfil cubierto: instrumentistas en general (guitarra,
teclados, bajo, etc.). Cantantes y panel coordinador/Helper quedan como
perfiles futuros con el mismo esquema de archivos.

Este doc describe **cómo está hecho hoy**, no cómo se llegó ahí (para eso,
`git log`). Convenciones generales (nomenclatura, carpetas, modo de
trabajo) en `01_CONVENCIONES.md` y `00_CONTEXTO_GENERAL.md`; no se
duplican acá.

## 1. Objetivo y alcance

Pantalla de celular, standalone (no parte del control remoto general),
que muestra casi en tiempo real: acorde actual y vecinos, sección actual
(con la previa y la próxima), tonalidad, tempo, nombre de canción e
indicaciones (`cues`) filtradas por rol. Pensada para mirarse de reojo
mientras se toca; no requiere interacción táctil.

Los músicos se conectan por Wi-Fi al servidor web embebido de REAPER
(`reaper_www_root`, servido vía junction, ver `00_CONTEXTO_GENERAL.md`).
La UI tiene que seguir siendo utilizable con red inestable: la sala tiene
señal débil (ver §9, requisitos de red).

Fuente de verdad de los datos musicales: `IMPL_MusicState.md`.

## 2. Fuentes de datos

No hace falta ningún script Lua propio de esta UI: todo se resuelve
consumiendo mecanismos existentes.

| Dato | Fuente | Notas |
|---|---|---|
| Posición, estado de transporte | `TRANSPORT` (nativo de REAPER, `main.js`) | Campos: `tok[1]` playstate (0 detenido, 1 reproduciendo, 2 pausado, 5 grabando, 6 grabación pausada), `tok[2]` segundos, `tok[5]` posición `compás.beat.centésimas` |
| Acorde actual / próximo / ventana | `nikMusicStateCurrentChord` / `NextChord` / `ChordWindow` (`core/music-state.js`) | Deciden por tupla (compás, `qn_offset`), no por segundos |
| Transposición en vivo | `nikMusicStateTransposeChordIfNeeded` + `nikTranspose` (`core/music-transpose.js`) | Semitonos de ReaPitch (`NikRemote/reapitch_semitone`, slow poll). Se aplica al leer, nunca sobre el array cacheado |
| Tonalidad | `nikMusicStateCurrentProjectKey` | `{tonic, mode}` |
| Indicaciones por rol | `nikMusicStateActiveCues` | Soporta `"todos"` + rol específico |
| Sección actual / previa / próxima | `g_markers` (poll `MARKER`) + `ms-section.js` | Criterio: último marker con posición `<=` la efectiva (con épsilon de 1 ms) |
| Nombre/color de sección | `nikResolveMarkerDisplay()` (`markers/markers.js`) | Reuso directo; incluye cadenas `x2/x3...` |
| Tempo vigente | `nikMsTempoAt(pos)` (`ms-tempo.js`) sobre `NikRemote/tempo_map` | Duplicación deliberada de `nikPlayrateTempoAt` (`playrate.js` mezcla DOM del popup). Candidato a módulo compartido |
| Playrate | `NikRemote/playrate` (slow poll) | Ver §4.5 |
| Compases | `NikRemote/timesig_map` | Consumido por `music-state.js` |
| Nombre de canción | `NikRemote/active_project_name` | Se recorta `.rpp` del lado cliente |
| Armonía, tonalidad, roles, cues | `NikMusicState/harmony_data`, `project_key`, `project_roles`, `cues_data`, `publish_version` | Publicadas por `Nik_MusicState_PublishAll.lua` |

`tempo_map` y `timesig_map` los publica `Nik_Playrate_ReadTempoMap.lua`
(un solo script, dos keys). Las cuatro keys de `NikMusicState` (más
`publish_version`) las puentea `Bridge.bridgeAll(proj)` desde el estado
que guarda el Helper, que es la única fuente de verdad de esos datos.

## 3. Arquitectura de archivos

```
reaper_www_root/
├── nsaudio_remote_control.html            control remoto general (no se toca)
├── nsaudio_prompter.html                  shell de esta UI
├── nsaudio_musicstate_test.html           panel de debug crudo (diagnóstico)
├── main.js                                de REAPER, NO modificar
├── config.js                              Command IDs (fuente única, sin fork)
├── config.local.js                        Command IDs de esta PC (ver abajo)
├── core/  markers/  modals/               existentes
└── musicstate-ui/
    ├── shared/
    │   ├── ms-dispatch.js    wwr_onreply propio, ancla de transporte
    │   ├── ms-tempo.js       lookup de tempo puro
    │   ├── ms-beat.js        pulso por compás + distancia a próximo evento de armonía
    │   └── ms-section.js     sección actual y posición efectiva en segundos
    └── instrumentista/
        ├── instrumentista.js   bootstrap de polls + render
        └── instrumentista.css  estilos del perfil
```

**Orden de carga del shell** (importa: cada archivo depende de los
anteriores): `main.js`, `config.js`, `config.local.js` (por XHR síncrono
+ `eval`, se ignora si no existe), `core/utils.js`, `markers/markers.js`,
`core/music-transpose.js`, `core/music-state.js`, `ms-tempo.js`,
`ms-beat.js`, `ms-section.js`, `ms-dispatch.js`, `instrumentista.js`.
Después el shell llama `nikInstrumentistaInit()` y
`nikInstrumentistaStartRenderLoop(50)`.

`config.local.js` es imprescindible en cada PC: sin él los Command IDs
de `config.js` quedan con el default (de otra PC) y los pedidos Lua
fallan en silencio, sin error en consola.

**Dispatcher propio, no `wwr-dispatch.js`:** el del control remoto tiene
`case`s sin guard `if (elemento)` que asumen DOM de tracks/faders/sends
que esta UI no tiene. `ms-dispatch.js` atiende solo lo necesario.

**Separación bootstrap/render:** `nikInstrumentistaInit()` (polls y
pedidos on-demand) no asume IDs de DOM, así que puede correr sin la
estructura visual; el render lo arranca solo el shell que sí la tiene.

Reuso sin fork: `core/music-state.js`, `core/music-transpose.js`,
`markers/markers.js`, `config.js`, `core/utils.js` (`nikLerpColor`,
dependencia real de `markers.js`).

## 4. Modelo de sincronización

Es el corazón de la UI: cómo un dato que viaja por una red inestable se
convierte en algo que se ve a tiempo.

### 4.1 Flujo

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

nikInstrumentistaRender()  cada 50 ms               [instrumentista.js]
   ├─ indicador de datos viejos (§4.6)
   ├─ segundos efectivos ─► sección, sección previa/próxima, BPM
   └─ compás/beat efectivo ─► acordes, ventana de acordes, cues
```

### 4.2 Ancla

Al procesar cada `TRANSPORT`, `nikTransportAnchorMs` se fija en
`performance.now() - min(RTT/2, 250 ms)`, con `RTT = Date.now() -
sentAtMs`. `sentAtMs` es el segundo parámetro que `main.js` pasa a
`wwr_onreply` (hora de envío del request). El ancla dice "hace cuánto
era cierta esta posición", ya compensando la ida de la respuesta.

### 4.3 Posición efectiva

```
adelanto = (lookahead + min(tiempo desde el ancla, 8 s)) × playrate
```

Solo se aplica si `playstate` es 1 o 5 (`nikMusicStateIsPlaying()`);
detenido o pausado se usa la posición cruda, sin adelanto ni
extrapolación. Un seek durante el play se corrige solo con la muestra
siguiente (no hay lógica de snap).

Dos formas de aplicar el mismo `adelanto` (`nikMusicStateAdvanceSongSec()`):

- **En segundos:** `nikMusicStateEffectiveSec() = playPosSeconds +
  adelanto`. Lo consumen secciones (vía `nikMsEffectivePosSeconds()`) y
  BPM.
- **En compás/beat:** `nikMusicStateCurrentPos()` toma
  `nikLastPositionBeatsStr`, suma `adelanto × bpm / 60` beats con el BPM
  vigente y cruza de compás usando el timesig map. Lo consumen acordes,
  `ChordWindow` y cues. Acordes y secciones cambian en el mismo instante
  porque comparten el mismo `adelanto`.

Los acordes se buscan por tupla (compás, `qn_offset`): no hace falta
convertir a tiempo absoluto para ordenar.

### 4.4 Lookahead

`nikMusicStateLookaheadSec`: latencia de red y de dibujado que se
compensa, más un pequeño anticipo deliberado (el prompter gana con
mostrar el acorde un poco antes de que suene). Es una constante porque la
parte variable de la latencia (antigüedad de la muestra) ya la absorbe la
extrapolación. El default es 0.18 s; en las pruebas (PC y celular por
Wi-Fi a la vez) el valor cómodo fue 0.4 s. Con tempos muy rápidos o muy
lentos puede convenir escalarlo (pendiente, §11).

Se ajusta sin recargar desde la consola del navegador
(`nikMusicStateLookaheadSec = 0.4`, toma efecto en el siguiente render)
o, para dejarlo fijo, definiéndolo en `config.local.js`: el `var` de
`music-state.js` respeta un valor previo (override no verificado todavía).

### 4.5 Playrate

`NikRemote/playrate` viaja en el slow poll (1 s), así que un cambio de
velocidad tarda hasta 1 s en reflejarse. `nikMsSetTransportPlayRate()` lo
guarda en `nikTransportPlayRate` (default 1) y acepta tanto factor
(`0.75`) como porcentaje (`75`): un valor mayor a 5 se interpreta como
porcentaje. El playrate afecta:

- el adelanto (una latencia en tiempo real recorre menos canción a
  velocidad menor);
- el BPM mostrado, que es el **equivalente** (tempo del mapa × playrate),
  igual criterio que `nikPlayrateComputeEquivalentBpm` del remoto.

### 4.6 Indicador de datos viejos

`nikInstrumentistaUpdateStaleIndicator()` corre al inicio de cada render.
Si pasan más de 1500 ms sin `TRANSPORT` nuevo, `.ms-screen` recibe la
clase `is-stale`: se atenúa el bloque superior y la fila de sección, y
aparece un cartel "SIN SEÑAL". Se desmarca sola al llegar el siguiente
`TRANSPORT`. Mientras tanto la extrapolación sigue estimando la posición
(hasta 8 s), así que un corte breve no congela los acordes; el aviso
existe para que el músico sepa que ve una estimación (si alguien hace
stop o seek durante el corte, la pantalla no lo refleja hasta reconectar).

**La tira de acordes queda fuera del atenuado a propósito:** su fade de
salto (`is-jumping`) usa `opacity` y espera el `transitionend` de esa
propiedad. Pisarla podría trabar la actualización de la tira.

Al arrancar, antes del primer `TRANSPORT`, el ancla vale 0 y también
muestra el aviso (correcto si el servidor no responde; en un arranque
normal no llega a verse).

### 4.7 Polls y reintentos

| Poll | Intervalo | Contenido |
|---|---|---|
| `TRANSPORT` | 100 ms | posición y estado |
| `MARKER` | 500 ms | markers de la timeline |
| Slow | 1000 ms | script `statePoll` + `active_project_name`, `playrate`, `reapitch_semitone`, `publish_version` |
| On-demand | boot / cambio de proyecto | `tempo_map`, `timesig_map`, `NikMusicState/*` |

`g_wwr_timer_freq = 20`: es la espera del loop de `main.js` cuando no hay
nada vencido. Con `TRANSPORT` a 100 ms y espera de 20 ms, todos los
dispositivos consultan al mismo ritmo (~10 por segundo).

**Backoff de `main.js`:** cada request fallido o abortado (timeout de
3 s) incrementa `g_wwr_errcnt`; con más de 2, el reintento espera
`100 << (errcnt - 3)` ms, hasta 3200 ms. Una respuesta con contenido lo
pone en 0. Mientras `is-stale` está activo, la UI limita `g_wwr_errcnt`
a 2, con lo que los reintentos quedan cada ~100 ms y la recuperación al
volver la red es de ~100–150 ms (medido en dev).

### 4.8 Indicador de pulso

Puntos por pulso del compás vigente + barra de progreso hacia el próximo
evento de armonía, pegados debajo de la tira de acordes. Cálculo puro en
`musicstate-ui/shared/ms-beat.js` (`nikBeat`, wrapper de objeto único, ver
01_CONVENCIONES.md); detección de cruce y DOM en
`nikInstrumentistaRenderBeat()` (instrumentista.js), llamada desde el
mismo render loop de 50 ms que todo lo demás.

**Dos posiciones efectivas distintas, a propósito:**
- Los **dots** usan `nikBeat.currentPos()` -- misma fórmula de
  extrapolación que `nikMusicStateCurrentPos()`, pero con `nikBeat.LATENCY_SEC`
  en vez de `nikMusicStateLookaheadSec`: el pulso no debe llevar el
  anticipo deliberado de los acordes (§4.4), solo compensar latencia real.
  Fijado en 0.4 tras prueba de escritorio (empíricamente iguala la
  sensación de sincronía contra el strip y el audio) -- no es un valor de
  latencia de red medido, pendiente de validar en sala (ver §11).
- La **barra de progreso** usa `nikMusicStateCurrentPos()` sin modificar:
  tiene que quedar sincronizada con el instante exacto en que la tira de
  acordes shiftea, no con el pulso real.

**Pulsos por compás:** `nikBeat.pulsesInBar(num, den)` -- simple (den=4):
un pulso por unidad del denominador. Compuesto (den=8, num múltiplo de 3,
num>3): agrupa de a 3 corcheas (6/8→2 pulsos, 12/8→4). No cubre hoy den=2
ni den=8 no compuesto (ej. 3/8) -- no confirmado contra un caso real. El
timesig map se relee en cada render (`nikMusicStateTimesigAt(bar)`, sin
cachear el compás), igual criterio que `nikMsTempoAt` -- necesario para
los cambios de compás ocasionales (4/4→2/4→4/4) confirmados en la sesión
de prueba.

**Disparo del fill (una sola vez por evento):** `nikInstrumentistaRenderBeat()`
detecta el cruce de evento de armonía comparando la key del evento vigente
(`bar_qn_offset`, mismo criterio que `nikInstrumentistaChordKey` de la
tira) contra la última vista. Al cruzar, `nikBeat.secUntilNextChordEvent()`
calcula la duración del fill **una sola vez** (mismo criterio anti-tirón
que la tira de acordes) y `nikInstrumentistaStartChordRing()` dispara una
transición CSS (`transform: scaleX()`, no `stroke-dashoffset` -- se
descartó el anillo SVG original por simplicidad de ajuste de tamaño).

**Gate de `stopped`:** ambos elementos (dots y barra) dependen de
`nikMusicStateIsPlaying()`. Los dots no tienen problema porque no animan
en el tiempo (solo prenden/apagan por posición). La barra sí: sin un
guard explícito, saltar de sección estando detenido dispara un fill
igual (la posición sigue siendo válida aunque no haya reproducción), y
una transición CSS ya iniciada sigue corriendo en el navegador aunque
REAPER se detenga a mitad de camino. `nikInstrumentistaRenderBeat()`
corta y resetea la barra (`nikInstrumentistaResetBeatProgress()`, sin
transición) apenas `nikMusicStateIsPlaying()` es falso, antes de mirar
el evento de armonía.

## 5. Contrato de variables y funciones

Globales sueltas con prefijo (patrón de `core/music-state.js`, no
wrapper de objeto: hay estado propio cacheado).

| Nombre | Archivo | Rol |
|---|---|---|
| `playPosSeconds` | ms-dispatch.js | segundos crudos del último `TRANSPORT` (string) |
| `nikLastPositionBeatsStr` | ms-dispatch.js | `compás.beat.centésimas` crudo (mismo nombre que en el remoto general, no renombrar) |
| `nikTransportPlayState` | ms-dispatch.js | playstate del `TRANSPORT` |
| `nikTransportAnchorMs` | ms-dispatch.js | ancla local del último `TRANSPORT` |
| `nikTransportPlayRate` | ms-dispatch.js | playrate como factor (default 1) |
| `nikReaPitchLastSemitone` | ms-dispatch.js | semitono; `"none"` y `"mixed"` son sentinels válidos, no se colapsan a 0 |
| `nikCurrentProjectName` | ms-dispatch.js | con extensión `.rpp` |
| `g_markers` | ms-dispatch.js | tokens completos de cada marker |
| `nikMusicStateLookaheadSec` | music-state.js | adelanto (§4.4) |
| `NIK_MUSIC_STATE_MAX_EXTRAPOLATION_SEC` | music-state.js | tope de extrapolación (8) |
| `nikMusicStateAdvanceSongSec()` | music-state.js | adelanto en segundos de canción |
| `nikMusicStateEffectiveSec()` | music-state.js | posición efectiva en segundos |
| `nikMusicStateCurrentPos()` | music-state.js | posición efectiva `{bar, qn_offset}` |
| `nikMsEffectivePosSeconds()` | ms-section.js | atajo con fallback a la cruda |
| `nikMsCurrentSection()` / `nikMsSectionAt(pos)` | ms-section.js | sección vigente |
| `nikMsTempoAt(pos)` | ms-tempo.js | BPM del mapa (sin playrate) |
| `NIK_INSTRUMENTISTA_STALE_MS` | instrumentista.js | umbral de datos viejos (1500) |
| `nikInstrumentistaBeatLastKey` | instrumentista.js | key (`bar_pulseIndex`) del último pulso marcado, para detectar cruce |
| `nikInstrumentistaChordEventLastKey` | instrumentista.js | key del evento de armonía vigente, para detectar cruce y recalcular la duración del fill una sola vez |
| `nikInstrumentistaBeatDotCount` | instrumentista.js | cantidad de dots ya dibujados, para repoblar solo si cambia (4↔2 en cambios de compás) |
| `nikInstrumentistaBeatProgressFilling` | instrumentista.js | si la barra está en medio de un fill, para saber si hace falta resetear al detenerse |
| `nikBeat.LATENCY_SEC` | ms-beat.js | latencia propia del pulso (§4.8), separada de `nikMusicStateLookaheadSec` |

## 6. Ciclo de vida por proyecto

- **Cambio de proyecto:** al cambiar `active_project_name`,
  `nikMsResetProjectState()` limpia todo el estado por-proyecto (armonía,
  cues, tonalidad, roles, tempo map, markers, semitono, versión
  publicada) **antes** de re-pedir. Es necesario porque, si el proyecto
  nuevo no tiene `ProjExtState` (pestaña "sin guardar"), el puente Lua no
  tiene nada que puentear y quedarían colgados los valores del anterior.
- **Re-pedido diferido:** además del pedido inmediato, se repite a los
  400 ms. Una respuesta on-demand rezagada del proyecto anterior puede
  llegar después del reset, y el protocolo no etiqueta a qué proyecto
  corresponde. La mitigación asume orden FIFO del servidor (no
  garantizado formalmente). Si el problema reaparece, la solución robusta
  (no implementada) es un token de generación por cambio de proyecto.
- **Refresco automático de armonía:** el Helper incrementa
  `publish_version` en cada `nikMusicStateSaveAndPublish()` y se puentea
  como las otras keys (`Bridge.KEYS`). El cliente guarda el último valor
  visto (`nikMsLastKnownPublishVersion`, en `null` tras cada cambio de
  proyecto) y dispara `nikMusicStateRequestAll()` siempre que cambie; un
  pedido redundante ocasional es inocuo, perder un refresco no.
- **Secciones:** `nikMsSectionOnMarkersUpdated()` reordena y resuelve la
  cadena de colores en cada `MARKER_LIST_END` (500 ms). Se resuelve toda
  la timeline de una vez para que una cadena `x2/x3...` herede el color
  correcto aunque su ancla no sea el marker actual.

## 7. Pantalla

Layout vertical único, estático. De arriba hacia abajo:

- **Bloque superior:** nombre de canción; fila con rol, tempo
  (equivalente, redondeado, `NNN BPM`) y tonalidad (`♪` + tónica con
  alteración; sufijo `m` si es menor, nada si es mayor).
- **Fila de sección:** previa, actual (color de familia de
  `nikResolveMarkerDisplay()`) y próxima. Los slots sin dato quedan
  vacíos, no `—`.
- **Tira de acordes:** 5 slots (offsets -2..2, `nikMusicStateChordWindow(2,2)`),
  jerarquía tipográfica decreciente desde el actual.
- **Indicador de pulso:** pegado debajo de la tira -- puntos por pulso del
  compás vigente (2/4/6/8 según el timesig) + barra de progreso hacia el
  próximo evento de armonía. Mecanismo completo en §4.8.
- **Banda de cue:** solo visible si hay indicación activa para el rol;
  varias cues activas se unen con ` · `.

**Animación de la tira:** si la estructura no cambia, solo se actualiza
el texto en el lugar (cambio de transposición en caliente). Si la ventana
se desplazó ±1, se reetiquetan los `data-offset` de los nodos existentes
(la transición CSS hace el movimiento) y entran/salen por offsets
fantasma ±3. En cualquier otro caso (salto de posición) se reconstruye
con fade (`is-jumping`).

**Rol:** vive en `localStorage` (`nikInstrumentistaRole`), por
dispositivo (el eje es "de quién es este celular", no el proyecto de
REAPER, por eso no se usa `tab-ui-memory.js`). `"todos"` es válido
siempre; sin rol se muestra `(sin rol)`. Para filtrar cues, `"todos"` o
sin rol equivalen a no filtrar. **No hay selector en la UI todavía**: hoy
se setea por consola con `nikInstrumentistaSetRole("...")`.

## 8. Gotchas

- **`main.js` es de REAPER y no se modifica.** Esta UI depende de detalles
  internos (`g_wwr_errcnt`, `g_wwr_timer_freq`, el segundo parámetro de
  `wwr_onreply`) que podrían cambiar entre versiones de REAPER.
- **El intervalo nominal no es el real.** `main.js` no solapa requests: un
  comando "vence" solo cuando pasó su intervalo, y si la respuesta vuelve
  antes, el loop espera `g_wwr_timer_freq`. Con `TRANSPORT` a 10 ms, la PC
  (respuesta casi instantánea) consultaba cada ~100 ms y el celular tan
  rápido como permitía la red. Se fijan ambos valores para igualar.
- **`timesig_map` mal formado desactiva el adelanto y rompe las cues.**
  `GetProjectTimeSignature2` devuelve `(bpm, bpi)`, no `(num, den)`; el
  script usa `TimeMap_GetTimeSigAtTime` y siempre siembra una entrada en
  el compás 1 (también cuando el primer marker con cambio de compás está
  más adelante). Con un mapa erróneo, `nikMusicStateCurrentPos()` nunca
  cruza de compás y los acordes que cambian por compás no se ven
  adelantados; las cues calculan mal su inicio y duración
  (`nikMusicStateBarStartQn`).
- **`tempo_map` no lleva flag de rampa:** en un cambio gradual se usa el
  BPM del marker de inicio durante toda la rampa. Error menor para el
  adelanto.
- **Caché del navegador:** el servidor de REAPER no manda cabeceras
  anti-caché y `config.local.js` se carga por XHR síncrono. Tras editar
  scripts, recargar forzado (Ctrl+F5; en el celular, borrar caché del
  sitio o pestaña privada) antes de concluir que un cambio "no funciona".
- **RTT inflado periódicamente (sin medir):** una vez por segundo el
  request lleva también el script Lua del slow poll; es posible que esa
  muestra tenga un RTT mayor y desfase la compensación unos ms (acotada a
  250 ms).
- **Clonado de elementos con `id`:** aplica la regla general de
  `01_CONVENCIONES.md` si algún día se clonan nodos con `id` en esta UI.

## 9. Cómo testear y requisitos de red

### En dev (misma PC + celular por Wi-Fi)

Abrir el prompter en el navegador de la PC y en el celular a la vez,
con el celular al lado del monitor. Chequeos en la consola de la PC:

- `nikTransportPlayState` da `1` en play.
- `JSON.stringify(nikMusicStateTimesigMap)` en un proyecto 4/4 sin markers
  da `[{"bar":1,"num":4,"den":4}]`.
- `nikTransportPlayRate` refleja el playrate ~1 s después de cambiarlo.
- `nikMusicStateLookaheadSec = X` para ajustar de oído.

**Poll lento (la extrapolación debe sostener los acordes):**
`g_wwr_req_recur[0][1] = 500` (el índice 0 es `TRANSPORT`, registrado
primero). Restaurar con `g_wwr_req_recur[0][1] = 100`.

**Ritmo real de respuestas** (mide 10 s y se restaura solo):

```js
(function(){var t=[],o=wwr_onreply;wwr_onreply=function(r,d){t.push(performance.now());return o(r,d)};setTimeout(function(){wwr_onreply=o;var g=t.slice(1).map(function(x,i){return Math.round(x-t[i])});console.log("intervalos ms:",g.join(","))},10000)})()
```

**Corte de red:** DevTools → Network → Offline con la canción en play.
Esperado: a los ~1,5 s aparecen el cartel y el bloque atenuado; los
acordes siguen avanzando hasta ~8 s y ahí se detienen (tope); al volver a
"No throttling" el cartel desaparece en ~100–150 ms y la tira salta a la
posición real. Variante: hacer stop o seek en REAPER durante el corte y
verificar que al reconectar la pantalla muestra la posición nueva.

**Diagnóstico de recuperación** (recargar la página antes para no duplicar
listeners; imprime `errcntAlVolver`, `primerReplyMs` y `cartelMs`):

```js
(function(){var o=wwr_onreply;window.addEventListener("online",function(){var t0=performance.now(),e0=g_wwr_errcnt,tr=null,el=document.querySelector(".ms-screen");wwr_onreply=function(r,d){if(tr===null)tr=Math.round(performance.now()-t0);return o(r,d)};var iv=setInterval(function(){if(!el.classList.contains("is-stale")){clearInterval(iv);wwr_onreply=o;console.log({errcntAlVolver:e0,primerReplyMs:tr,cartelMs:Math.round(performance.now()-t0)})}},10)})})()
```

### Prueba de estrés física (pendiente)

En la sala, con la puerta cerrada y el celular en el peor punto: dejar una
canción entera en play; cortar el Wi-Fi del celular durante 3, 5 y 10 s;
hacer un stop/seek en REAPER durante el corte largo; repetir con 2–3
celulares conectados. Mirar: que el cartel aparezca solo en cortes reales,
que la recuperación sea rápida, que tras un stop/seek la pantalla corrija
y que los acordes sigan alineados con los de la PC.

### Requisitos de red

La red institucional (con firewall y Wi-Fi propio) más las paredes de la
sala degradan la señal, y el web control es HTTP plano y tráfico local que
igualmente pasa por los equipos de la red — resiliencia de software (§4)
que no reemplaza una red que funcione. Diagnóstico, solución (router
propio para la sala) y guía de configuración: `07_RED_SALA_ENSAYO.md`.

## 10. Guía para extender

Ideas ya evaluadas, apoyadas en primitivas existentes:

- **Animaciones según tiempo restante.** Tiempo hasta el próximo cambio =
  `beats restantes × 60 / bpm / playrate`. Calcular la duración **una sola
  vez** al disparar el shift, porque cada ancla nueva corrige la
  estimación y recalcular en cada render provocaría tirones. Una tira
  que se desplace de forma continua con la posición implica rediseñar el
  movimiento de los slots.
- **Aplicar el patrón al control remoto general.** Portable: indicador de
  datos viejos, tope de `g_wwr_errcnt`, compensación por RTT con el
  segundo parámetro de `wwr_onreply`, frecuencia de poll unificada. La
  extrapolación solo sirve para lo que avanza con el tiempo (posición,
  markers, cursor), no para faders ni meters. Antes, inventariar qué pide
  `core/wwr-dispatch.js` y a qué frecuencia.

## 11. Pendientes y fuera de alcance

**Pendientes (ninguno bloqueante):**

- Selector de rol en la UI (hoy solo por consola + `localStorage`).
- Layout horizontal. Diseño previsto: conmutación por proporción de
  viewport (no por `orientation`) con debounce de 150–200 ms, fila de 4
  slots `anterior · ACTUAL · próximo1 · próximo2`; decidir si la banda
  terciaria queda en dos filas o en una.
- Cantidad de slots de acorde en vertical, a validar en dispositivo real.
- Prueba de estrés física en la sala (§9). Router propio para la sala:
  ver `07_RED_SALA_ENSAYO.md` (pendiente de armar, §4 de ese doc).
- Escalar el lookahead según el tempo (idea a evaluar tras varios
  ensayos con el valor fijo).
- Calibrar `nikBeat.LATENCY_SEC` (fijado en 0.4 tras prueba de
  escritorio, §4.8) contra la prueba física en sala -- red y dispositivo
  reales pueden pedir otro valor.
- Validar la conversión adelanto → beats en compases no x/4 (6/8, etc.):
  hoy solo verificada en 4/4.
- Verificar el override del lookahead vía `config.local.js` y el formato
  exacto del valor de `NikRemote/playrate` (el parser acepta factor y
  porcentaje).
- Gesto de refresco de `tempo_map`/`timesig_map` editados en vivo con la
  UI abierta (no los cubre `publish_version`); caso raro en ensayo.
- Semitono `"mixed"` del Stem Bus: manejo escrito, sin probar con datos
  reales.
- String exacto que reporta REAPER para un proyecto sin guardar (afecta
  el recorte de `.rpp`).
- Token de generación por cambio de proyecto, solo si reaparece el bug de
  datos colgados (§6).
- Extraer `ms-tempo.js` a un módulo compartido si `playrate.js` se
  refactoriza.
- `IMPL_MusicState.md`, secciones 10-11: falta `publish_version` en la
  lista de keys de `Bridge.KEYS`.

**Fuera de alcance:** exploración manual con scroll táctil de acordes
pasados/futuros; perfiles de cantante y coordinador/Helper (mismo esquema,
`musicstate-ui/<perfil>/`, en sesiones propias); lo declarado fuera de
alcance en `SPEC` §18 e `IMPL_MusicState.md` (Regions, escalas, roman
numerals, lyrics, edición de armonía desde el celular).
