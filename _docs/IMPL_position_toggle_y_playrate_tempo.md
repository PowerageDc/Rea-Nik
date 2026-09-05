# IMPL — Toggle de posición (long tap) + fix Playrate→Tempo

Doc transitoria de sesión. No reemplaza a `remote_control.md` — sirve como
insumo crudo para actualizarlo en una conversación aparte, junto con otros
`IMPL_*.md`. Incluye decisiones tomadas, por qué, y cómo enganchan las
piezas entre sí, no solo el diff final.

---

## 1. Long tap en el readout de posición (compases.beats ↔ min:seg)

### Motivación
Pendiente no documentado que surgió con el uso: el readout de posición
(`#status` / `#timeUnits`) siempre mostraba el formato que REAPER tuviera
seteado en el ruler del proyecto (auto-detectado por la forma del string
recibido). No había forma de verlo en el otro formato sin cambiar el ruler
real del proyecto en REAPER.

### Arquitectura descubierta en el camino (relevante para otros features)
- `main.js` es **puramente capa de transporte** (polling `wwr_req`/
  `wwr_req_recur`, manejo del XHR) — no toca el DOM. El `wwr_onreply` que
  documenta en sus comentarios es solo un ejemplo ilustrativo; la
  implementación real (parseo de `TRANSPORT`/`BEATPOS`/etc. y escritura al
  DOM) vive en `core/wwr-dispatch.js`, código propio. Confirma lo que ya
  decía `remote_control.md`: "`main.js` nunca se modifica" — y agrega el
  dato de que su propio `wwr_onreply` de ejemplo no es el que corre.
- **Dato nuevo útil**: la respuesta de `TRANSPORT` ya trae en `tok[5]`
  (`position_string_beats`) el formato `measures.beats.hundredths`
  **siempre**, sin importar cómo esté seteado el ruler del proyecto. Y
  `tok[2]` (`position_seconds`) también está siempre disponible. Esto
  significa que **no hace falta leer `BEATPOS` ni sniffear el formato**
  para tener ambas representaciones de la posición — alcanza con lo que ya
  trae `TRANSPORT` en cada poll de 10ms. Útil para cualquier feature futura
  que necesite posición en ambos formatos sin pedirle más al poll.

### Decisiones tomadas (y por qué)
- **Sticky, no hold-to-preview**: el toggle cambia el formato y se queda
  así hasta el próximo long tap — no es un "mantener presionado para ver".
  Coincide con la descripción original del pendiente ("long tap again
  vuelve a...").
- **2 estados (minsec ↔ measures), sin estado "auto"**: se decidió
  ignorar por completo el auto-sniff del ruler real de REAPER. Un tercer
  estado "auto" haría que el resultado del long tap dependiera de cómo
  esté configurado el ruler en ese momento (menos predecible). Con 2
  estados fijos, el comportamiento del remoto es autónomo del ruler del
  proyecto.
- **Sin feedback visual** durante el long press (sin barra de progreso) —
  a diferencia del long-press de pre-seek en el popup de markers, acá no
  hay ambigüedad de "qué se va a disparar" ni riesgo de scroll accidental,
  así que no hacía falta el indicador.

### Piezas y cómo enganchan
| Pieza | Rol |
|---|---|
| `core/long-press.js` (**nuevo**) | Helper genérico de long-press (touch+mouse), extraído del patrón de `nikAttachMarkerLongPress` (`marker-browser.js`), sin la barra de progreso. Firma: `nikAttachLongPress(el, {ms, moveTolerance, onLongPress, onStart, onCancel})`. Marca `el._nikSuppressClick = true` al disparar. |
| `core/state.js` | `nikPositionDisplayMode` ("measures" \| "minsec"), sticky, arranca en "measures". |
| `core/init.js` | `nikStatusAreaClick(el)` — wrapper del `onclick` de `#status` que respeta `_nikSuppressClick` (si vino de un long tap, no dispara `prompt_seek()`). `nikTogglePositionDisplayMode()` — toggle simple. En `init()`, registro de `nikAttachLongPress` sobre `#status`. |
| `nsaudio_remote_control.html` | `onClick` de `#status` pasa de `prompt_seek()` a `nikStatusAreaClick(this)`. |
| `core/wwr-dispatch.js` | `case "TRANSPORT"`: el bloque de auto-sniff de formato (basado en la forma de `tok[4]`) se reemplazó por un `if/else` sobre `nikPositionDisplayMode`, usando `nikFormatMinSec(tok[2])` (helper ya existente, compartido con el popup de markers) o `tok[5]` directo. El resto del pipeline (jogger, etc.) sigue funcionando sin cambios porque ya consulta `statusPosition[1]` en vez de re-derivar el formato. |

### Nota de diseño reutilizable
`marker-browser.js` **no fue migrado** al nuevo `core/long-press.js` —
sigue con su propia implementación de long-press (con barra de progreso,
que el helper genérico no soporta hoy). Queda como candidato de
unificación en un cleanup futuro, no bloqueante.

### Cabo suelto conocido
`statusPositionAr` (declarada en `core/state.js`) quedó sin uso tras este
cambio — no se sacó de `state.js` para no tocar ese archivo de más en esta
sesión. Cleanup pendiente.

### Commit
```
remote-control: toggle long-tap en posición (compases.beats <-> min:seg)
```
(5 archivos: `core/long-press.js` nuevo, `core/state.js`, `core/init.js`,
`nsaudio_remote_control.html`, `core/wwr-dispatch.js` — detalle de cada uno
en el mensaje de commit real.)

---

## 2. Fix: cálculo de Playrate→Tempo no robusto en proyectos con mapa de tempo variable

### Síntoma reportado
El BPM equivalente mostrado en el popup de Playrate "desviaba" en algunos
proyectos — no de forma constante, sino específicamente en temas con mapa
de tempo variable (correcciones de tempo a lo largo de toda la canción,
típico de temas grabados sin metrónomo, con intro atípica).

### Diagnóstico (proceso, útil si vuelve a aparecer algo parecido)
1. Se descartó el cálculo del lado del cliente (`baseTempo * percent/100`)
   como sospechoso — es una multiplicación simple, poco margen de error.
2. Se revisó `Nik_Playrate_ReadBaseTempo.lua` (ahora eliminado): ya tenía
   una corrección previa documentada — usaba `GetTempoTimeSigMarker` del
   primer marker de tempo en vez de `Master_GetTempo()`, precisamente
   porque `Master_GetTempo()` depende de la posición del cursor de edición
   (bug ya conocido y evitado).
3. Prueba de aislamiento pedida a Nik: comparar BPM calculado vs. tap
   tempo manual (referencia confiable) en un proyecto de **tempo estable**
   primero. Resultado: coincide. Esto confirmó que el cálculo básico y la
   lectura on-demand de un tempo fijo son correctos **cuando hay un solo
   tempo real en todo el proyecto**.
4. Confirmado con Nik: los proyectos problemáticos sí tienen mapa de tempo
   con correcciones a lo largo de toda la canción, y los cambios son
   **saltos discretos** (no rampas lineales) — dato que simplificó la
   solución (no hace falta interpolar, alcanza con "último marker antes de
   la posición actual").

### Causa raíz real
No era un bug de cálculo — era un problema conceptual: `base_tempo` estaba
diseñado como "un" tempo de referencia fijo por proyecto, leído una sola
vez (al abrir el popup / boot / cambio de proyecto). En un proyecto con
mapa de tempo variable **no existe tal cosa** — cada sección tiene su
propio tempo original, y el BPM equivalente correcto depende de en qué
sección está la posición de reproducción en cada momento.

### Solución
En vez de leer un solo BPM, se lee **el mapa de tempo completo** del
proyecto (todas las posiciones de tempo/time-sig marker + su bpm) con los
mismos triggers de antes (on-demand: boot, abrir popup, cambio de
proyecto/tab — **no** entra al poll rápido). Del lado del cliente, en cada
tick del poll de `TRANSPORT` (10ms, ya existente) se busca el tempo
original vigente en la posición actual (`playPosSeconds`, ya se actualiza
en ese mismo poll) mediante lookup "último marker con `pos <= posición
actual`" — sin interpolación, porque los cambios son discretos. Cero
llamadas Lua adicionales en el loop rápido: todo el costo extra es un
`for` liviano sobre un array ya en memoria.

### Casos borde cubiertos (pedidos explícitamente por Nik, verificar que se
mantengan si se refactoriza esto a futuro)
- **1 solo tempo marker**: el mapa tiene un único punto, el lookup siempre
  devuelve ese bpm — comportamiento idéntico al de antes del fix.
- **Tempo estable + cambios de métrica** (2+ markers, mismo bpm repetido):
  no afecta el cálculo, que solo mira bpm, no time signature.
- **Sin tab activa / proyecto sin guardar**: el script Lua opera sobre
  `proj = 0` (proyecto activo) — no depende de que el proyecto esté
  guardado ni de la tab.
- **REAPER cerrado**: reutiliza el watchdog ya existente
  (`nikCheckProjectNameWatchdog` en `core/init.js`) — al cortarse la
  conexión, `nikPlayrateTempoMap` se resetea a `null` y el readout cae al
  placeholder `—`, mismo criterio que ya existía para `nikPlayrateBaseTempo`.

### Piezas y cómo enganchan
| Pieza | Rol |
|---|---|
| `Nik_Playrate_ReadTempoMap.lua` (**nuevo**, reemplaza a `Nik_Playrate_ReadBaseTempo.lua`, **eliminado**) | Itera `CountTempoTimeSigMarkers`/`GetTempoTimeSigMarker`, publica `NikRemote/tempo_map` en formato `"pos1:bpm1,pos2:bpm2,..."`. Sin markers, fallback a un único punto en `pos=0` con `Master_GetTempo()`. |
| `config.js` | Nueva entrada `playrateTempoMapRead` (reemplaza a `playrateBaseTempoRead`). Requirió re-registrar el script en el Action List (Command ID nuevo por ser archivo nuevo) — paso manual hecho por Nik. |
| `playrate.js` | `nikPlayrateTempoMap` (array `{pos, bpm}`) reemplaza a `nikPlayrateBaseTempo` (número fijo). `nikPlayrateTempoAt(positionSeconds)` — nueva función de lookup. `nikPlayrateComputeEquivalentBpm` y `nikPlayrateBpmCommit` ahora resuelven el tempo vigente en la posición actual en vez de usar un valor fijo. `nikPlayrateSetTempoMap` / `nikPlayrateRequestTempoMap` reemplazan a sus equivalentes de `base_tempo`. |
| `core/wwr-dispatch.js` | `case "TRANSPORT"`: se agregó refresco del readout principal de Playrate en cada tick (antes solo se refrescaba en el poll lento de `EXTSTATE/playrate`, 1000ms) — necesario para que el BPM equivalente siga en vivo la sección que está sonando. `case "EXTSTATE"`: escucha `tempo_map` en vez de `base_tempo`. |
| `core/init.js` | Boot (`init()`) y watchdog de desconexión actualizados al nuevo nombre/tipo de variable. |

### Principio general (reutilizable a futuro)
Cuando un valor derivado necesita reflejar algo que cambia con la posición
de reproducción (no solo con el tiempo real), conviene enviar los datos
crudos necesarios una sola vez (on-demand) y resolver el valor derivado
del lado del cliente usando campos que **ya llegan** en el poll rápido
existente (acá, `playPosSeconds` de `TRANSPORT`) — evita agregar polls o
scripts Lua nuevos al loop de 10ms.

### Commit
```
remote-control: playrate→tempo sigue el mapa de tempo variable (no un bpm fijo)
```
(Detalle de los 5 archivos tocados en el mensaje de commit real — incluye
la eliminación vía `git rm` de `Nik_Playrate_ReadBaseTempo.lua`.)

---

## 3. Pendientes que quedaron abiertos tras esta sesión
- `statusPositionAr` sin uso en `core/state.js` (cleanup menor, item 1).
- Migrar `marker-browser.js` a usar `core/long-press.js` en vez de su
  propia implementación duplicada (cleanup opcional, no bloqueante).
- Metrónomo: research de qué parámetros son controlables vía scripting
  además de on/off (volumen primario/secundario, ruteo de salida, click
  pattern) — **pospuesto explícitamente a otra sesión**, no se tocó nada
  en esta.
