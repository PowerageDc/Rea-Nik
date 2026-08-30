# Feature — Control Remoto Web (`nsaudio_remote_control.html`)

Interfaz web para controlar REAPER desde el celular durante ensayos.
Complementa `01_CONVENCIONES.md` (nomenclatura de scripts, patrón `dofile`).
Este doc es referencia viva del estado actual + patrones a seguir/evitar,
no un historial de sesiones — para eso quedan los `DEBUG_*.md` puntuales
cuando hagan falta.

## Setup técnico
- REAPER v7.79, SWS/S&M Extensions, Windows 10.
- Servidor web integrado de REAPER (Preferences > Control/OSC/web).
- Cliente: celular Android vía **Fully Kiosk Browser** (no PWA de Chrome —
  descartada, IP LAN no alcanzable por el servidor de Google que genera
  el WebAPK; no bloqueante, Fully cumple la función).
- Archivo: `AppData/Roaming/REAPER/reaper_www_root/nsaudio_remote_control.html`.
  `manifest.json`/`sw.js`/`apple-touch-icon` sin efecto actualmente (no se
  usa como PWA instalada).
- `main.js` es librería de REAPER — **nunca se modifica**. Protocolo
  documentado en sus propios comentarios (formato de comandos, `GET/`,
  `SET/`, `_RS...`, etc).

## Arquitectura del patrón (aplica a toda función nueva)

**Script Lua + `ExtState` + polling desde la web.** Tres piezas:
1. Un script Lua (o módulo consumido por varios) lee/escribe estado real
   de REAPER hacia `ExtState` (`persist=false`, sección `"NikRemote"`).
2. La web dispara ese script como acción custom (`_RS...`, Command ID
   único por PC — **hay que re-registrar al cambiar de máquina**).
3. La web lee el resultado con `GET/EXTSTATE/NikRemote/<key>`, encadenado
   en la misma request que el `_RS` (mismo round-trip, sin necesidad de
   dos pasadas) — ver ejemplo real en `Nik_RemoteState_Poll` más abajo.

`reaper.GetExtState(section, key)` devuelve **un solo string** (`""` si no
existe), no un par `(ok, valor)` — confundir el patrón corta el script en
silencio sin aplicar nada.

## Lectura de estado consolidada — `Nik_RemoteState_Poll.lua`

Todas las lecturas de background (proyecto activo, playrate/preserve
pitch, semitonos/enabled de ReaPitch) están unificadas en **un solo
script** con **un solo Command ID**, que hace todas las escrituras a
ExtState en una corrida:

```
Nik_RemoteState_Poll.lua
  ├─ ActiveProject_common_logic.write_active_project_name()
  ├─ lectura directa de Master_GetPlayRate + preserve pitch (40671)
  ├─ ReaPitchBus_common_logic.write_aggregated_state()
  └─ MarkerBars_common_logic.write_aggregated_state()
```

Usado tanto para el poll de fondo (`NIK_SLOW_POLL`, recurrente 1000ms)
como para refresco puntual (`NIK_ONDEMAND_READS`, hoy alias del mismo
comando) — no hay razón para mantenerlos separados, ambos casos quieren
"todo el estado, ahora".

**Para escalar (agregar una lectura nueva a futuro):** sumar una sección
dentro de este script (o del módulo `common_logic` correspondiente), no
un `_RS` nuevo encadenado en el HTML. Ver gotcha de parpadeo abajo — es
la razón concreta de por qué importa mantenerlo consolidado.

### Patrón de agregación en los módulos (`common_logic`)
Cada dominio que necesita agregar estado de múltiples instancias (ej.
ReaPitch en varios stems) expone `read_aggregated_state()` (lógica pura)
+ `write_aggregated_state()` (llama al anterior y escribe ExtState). El
script `Nik_*_Read.lua` standalone (si se mantiene, ej. para disparo
puntual fuera del remoto) queda como wrapper delgado de una línea sobre
`write_aggregated_state()` — evita duplicar la lógica de agregación entre
el standalone y el poll consolidado.

## Gotchas confirmados (de sesión de debug — no repetir)

- **Ejecutar un ReaScript como acción (por cualquier vía — manual, `_RS`
  puntual, o recurrente) hace parpadear brevemente el menú superior de
  REAPER.** Es cosmético, REAPER redibuja UI al correr la acción — **no
  indica corrupción de Undo ni de datos**. Confirmado con
  `reaper.GetProjectStateChangeCount()` + revisión manual de la pila de
  Undo real en varios escenarios (recurrente sostenido, manual repetido,
  no-op, intercalado con ediciones reales): en ningún caso se acumularon
  puntos de Undo fantasma — REAPER coalesce las corridas de
  "ReaScript: Run" en la entrada superior de la pila en vez de apilarlas.
- **El parpadeo escala con la cantidad de `_RS` empaquetados en el mismo
  tick** (1 → mínimo, 2 → notorio, 3 → bastante notorio). Es la razón de
  fondo para mantener las lecturas de background **consolidadas en un
  solo script** en vez de encadenar varios `_RS` sueltos en el mismo
  poll — no es un tema de seguridad de datos, es UX visual.
- **`wwr_req_recur` con el mismo intervalo declarado se empaqueta en una
  sola request HTTP**, aunque estén registrados en llamadas separadas en
  el código (ver `wwr_run_update()` en `main.js`). Desfasar intervalos
  entre sí es la única forma de partir un bundle en requests más chicas
  repartidas en el tiempo, si algún día hiciera falta.
- **`GetProjectStateChangeCount()` no es un proxy confiable de "puntos de
  Undo reales acumulados"** — sube en cada ejecución de script (incluso
  no-op), pero eso no se traduce 1:1 en entradas nuevas de la pila de
  Undo. Si hace falta instrumentar esto a futuro, comparar la pila real
  (`Undo_CanUndo2` + conteo de `Ctrl+Z` necesarios), no solo el contador.
- **Ningún cambio, corrida de script vía `_RS`, sea recurrente o puntual,
  demostró ser insegura para el proyecto** en los tests realizados. La
  arquitectura on-demand (disparo solo con interacción del usuario) sigue
  siendo la elegida por minimizar parpadeo, no por evitar un riesgo real
  de corrupción — vale la pena no reintroducir el miedo original si se
  revisita esto.
- **`SET/TRACK/x/B_SHOWINTCP/valor` cambia el flag pero no refresca el
  TCP visualmente** — al ir directo a `GetSetMediaTrackInfo` (vía el
  protocolo web genérico) se salta el paso de `TrackList_AdjustWindows()`
  que sí dispara un refresco nativo de REAPER. Sin eso, el cambio se ve
  en el Track Manager pero no en el TCP hasta que algo más (ej. cambiar
  la selección de track) fuerza un redraw. Fix: script dedicado
  `Nik_TrackVis_Refresh.lua` (`TrackList_AdjustWindows(false)` +
  `UpdateArrange()`), encadenado al final del batch de Aplicar.
- **Bug de caché de color de tracks (`trackColoursAr`), preexistente**:
  el handler de `TRACK` guardaba `tok[1]` (número de track) en vez de
  `tok[13]` (color) al cachear. No rompía el panel de faders — ese pinta
  siempre con el valor crudo de `tok[13]`, no con el caché — pero dejaba
  el caché inútil para reusar en otro lado (ej. nombre coloreado en el
  popup de tracks). Al arreglar el caché apareció un segundo bug latente:
  el `else` que pinta gris estaba colgado de la condición completa
  (`tok[13]>0 && tok[13]!=cache`), así que con el caché ya funcionando
  correctamente, pintaba gris apenas el color coincidía con lo cacheado
  — o sea, en la práctica siempre después del primer poll. Fix: separar
  el chequeo de "tiene color propio" del de "cambió desde el último
  poll"; el gris solo debe aplicar cuando no hay color custom
  (`tok[13]<=0`), nunca por color sin cambios.
- **Sumar una key nueva a `Nik_RemoteState_Poll.lua` no alcanza**: además
  de escribirla desde Lua, hay que agregar su
  `GET/EXTSTATE/NikRemote/<key>` correspondiente a la cadena
  `NIK_SLOW_POLL` en el HTML — si no, el Lua escribe la ExtState pero la
  request bundleada nunca la pide y el JS nunca la recibe. Pasó al sumar
  `marker_bars`: el consumidor (parseo + uso) estaba listo pero el pedido
  no viajaba.
- **`TimeMap_QNToMeasures` puede resolver al compás anterior al esperado**
  en markers que caen una fracción de float antes del downbeat real
  (precisión de punto flotante tras nudges/ediciones, no error de
  diseño). Fix: sumar un épsilon chico (`+1e-6` QN) antes de convertir,
  protege sin afectar posiciones genuinamente fuera de grid.

## Watchdog de "proyecto desconectado"

`nikCheckProjectNameWatchdog()` compara `Date.now()` contra el timestamp
de la última respuesta recibida con `active_project_name`. **Tiene que
correr siempre, vía su propio `setInterval` independiente del poll** — es
la única señal posible de "REAPER cerró del todo" (el servidor web muere
con REAPER, así que ninguna respuesta vuelve nunca más; nada que dependa
de una respuesta puede detectar ese caso). Costo despreciable (un `if`
por segundo, sin red).

## Popup de visibilidad de tracks en TCP (`nikOpenTracksVisModal`)

Excepción al patrón Script Lua + ExtState: acá el protocolo nativo de
`main.js` ya cubre todo lo necesario sin script intermedio para leer
datos (sí hace falta uno para el refresco, ver gotcha abajo).

- **Datos de entrada**: no se piden requests nuevos al abrir el popup —
  se lee directo de los arrays globales que ya llena el poll recurrente
  de `TRACK` (10ms): `trackNamesAr`, `trackFlagsAr` (bit `512` = oculto
  en TCP, bit `4` = tiene FX) y `trackColoursAr` (color nativo del
  track, mismo formato `0xaarrggbb` que usa el panel de faders).
- **Aplicar**: solo los tracks que cambiaron de estado respecto al
  snapshot tomado al abrir el popup disparan
  `SET/TRACK/x/B_SHOWINTCP/valor`, seguido de un `SET/UNDO` y de
  `Nik_TrackVis_Refresh.lua` (ver gotcha de refresco abajo).
- **Trigger**: ícono en `#optionsBar` (antes `transitionsButton`,
  repurpuseado — ver gotcha de la animación).

## Colores y traducción de markers en el popup (`NIK_MARKER_COLOR_MAP`)

Diccionario editable al principio del script — fuente de verdad de colores
por sección (ver `01_CONVENCIONES.md` para los nombres de sección del
proyecto). Cada categoría define `label`, `color`, `tint` (reservado, sin
uso hoy — pensado para un fondo tipo chip si se necesita más adelante),
`words` (formas completas) y `abbrev` (formas abreviadas).

- **Palabras completas** (`words`): match por *prefijo* sobre el nombre
  normalizado (sin acentos, sin espacios, minúsculas) — `"Verso"`,
  `"veRSO1"`, `"VERSO GUITARRA"` matchean la misma categoría. Solo cambia
  el color; el texto del marker no se toca.
- **Abreviaturas** (`abbrev`): match *exacto* (nombre completo, no
  prefijo) — `c` no matchea si el marker se llama `"cosa"`. Además del
  color, traduce el texto mostrado al `label` completo (+ número si lo
  tenía): `c2` → `"Coro 2"`.
- **Cadena `x<número>`** (`NIK_MARKER_CHAIN_PATTERN` + `NIK_MARKER_CHAIN_STEP`):
  hereda el color del último marker categorizado encontrado antes en la
  lista (no necesariamente el inmediato anterior — un marker sin
  categoría en el medio no corta la cadena), aclarando hacia blanco un
  paso fijo por cada eslabón sucesivo (`x2` = 1 paso, `x3` = 2 pasos...).
  El texto no se traduce.
- Colores auditados con contraste WCAG AA (≥4.5:1) contra el fondo del
  popup (`#1a1a1a`) — la paleta original (pensada para charts sobre fondo
  claro) no pasaba el mínimo sobre negro en la mayoría de los casos; se
  ajustó luminosidad/saturación manteniendo el matiz de cada familia.
- **Pendiente**: aplicar este mismo diccionario a los 3 indicadores de
  transporte (hoy solo corre en el popup) — ver Pendientes activos.

## Colores en los indicadores de transporte (prev/actual/next)

Mismo `NIK_MARKER_COLOR_MAP` que el popup, pero con un `chainState` propio
e independiente por redibujo (no comparte estado con el popup ni persiste
entre redibujos). La lógica de resolución quedó consolidada en un helper
compartido para no duplicar el criterio de cadena/categoría entre el
popup y estos tres indicadores:

- `nikResolveMarkerDisplay(rawName, chainState)` — dado un nombre crudo y
  el estado de cadena acumulado hasta el momento, devuelve
  `{displayName, resolvedColor}` y muta `chainState` in-place. Usado
  tanto por `nikOpenMarkerBrowser()` (popup) como por el bloque que
  redibuja `marker1`/`marker2`/`marker3` en cada cambio de posición.
- A diferencia del popup, acá se colorea tanto el **fondo del badge**
  (`markerXBg`, reemplaza el color nativo de REAPER cuando hay categoría)
  como el **texto del nombre** (`prevMarkerName`/`atMarkerName`/`nextMarkerName`).
- El `chainState` de los indicadores arranca en `null` en cada redibujo:
  si el marker `prev` visible es él mismo un `xN`, no hay contexto de qué
  vino antes (fuera de los 3 visibles) y queda sin colorear — ver
  pendiente al respecto más abajo.
- Los casos HOME/END (cuando no hay marker antes/después) resetean el
  `fill` del texto a gris (`#A8A8A8`) explícitamente, para que no quede
  pegado un color de categoría de un redibujo anterior.

## Compases por sección (popup de markers)

`MarkerBars_common_logic.lua` calcula, para cada marker, cuántos compases
hay hasta el siguiente — vía `TimeMap2_timeToQN` + `TimeMap_QNToMeasures`,
no división simple de segundos, para que el número sea correcto con tempo
map y cambios de compás en el medio (ver gotcha de precisión arriba).
Escribe `NikRemote/marker_bars` como `"id1:compases1;id2:compases2;..."`,
agregado al poll consolidado — sin script ni Command ID nuevo aparte.

## Selector de proyectos (tabs) — popup

Tap en el nombre del proyecto activo (`#nikActiveProjectName`, en
`#nikTabBar`) abre un popup con la lista de todos los proyectos (tabs)
abiertos en REAPER, mismo look que el popup de markers.

- **Lectura on-demand, deliberadamente fuera de `Nik_RemoteState_Poll`**:
  a diferencia de ReaPitch/Playrate/Markers (agregados al poll de fondo
  de 1000ms porque su costo es despreciable), enumerar proyectos abiertos
  solo se dispara al abrir el popup (`Nik_ProjectTabs_Read.lua`, Command
  ID propio `PROJECTTABS_CMD_READ`) — decisión tomada explícitamente para
  no sumar el recorrido de `EnumProjects` a cada tick del poll de fondo.
- **Lectura**: `ProjectTabs_common_logic.lua` (`read_aggregated_state()` +
  `write_aggregated_state()`, mismo patrón de agregación que
  `MarkerBars_common_logic.lua`) enumera con `reaper.EnumProjects(i)`,
  compara contra `reaper.EnumProjects(-1)` (proyecto activo) y escribe
  `NikRemote/project_tabs` como `"idx:nombre:esActivo;idx:nombre:esActivo;..."`.
  Proyecto sin guardar → nombre `"(sin guardar)"`. Wrapper delgado:
  `Nik_ProjectTabs_Read.lua`.
- **Selección**: tap en un ítem distinto al activo escribe
  `ExtState NikRemote/project_tabs_target_idx` con el índice destino y
  dispara `Nik_ProjectTabs_Select.lua` (Command ID propio
  `PROJECTTABS_CMD_SELECT`), que hace `reaper.SelectProjectInstance()`
  sobre el proyecto obtenido de `EnumProjects(target)` — mismo índice que
  usó la lectura, asumiendo que el orden de `EnumProjects` no cambió
  entre la lectura y el tap (ventana muy chica, no debería ser problema
  en uso normal). Tap en el ítem activo solo cierra el popup, sin acción.
- Encadenado después del select: `NIK_ONDEMAND_READS` (refresca el nombre
  de proyecto activo en `#nikActiveProjectName` sin esperar al próximo
  poll de fondo).
- **Color**: proyecto activo en `#00FF99` (mismo verde que ya usa el
  proyecto en el botón de play activo / `playLine`), negrita; resto en
  gris `#A8A8A8` — paleta aparte, no toca `NIK_MARKER_COLOR_MAP`.
- Fila de cada ítem con un `metaSpan` vacío a la derecha, reservado a
  futuro para BPM / métrica / tonalidad por proyecto — sin implementar
  hoy.
- Command IDs con placeholder obvio en el HTML
  (`PROJECTTABS_CMD_READ`/`PROJECTTABS_CMD_SELECT`) — pendiente de
  reemplazar al registrar los dos scripts en el Action List.

## Funcionalidades activas (resumen, sin detalle de implementación)

| Función | Estado | Notas |
|---|---|---|
| Ciclar tabs (proyectos abiertos) | Cerrado | `NikRemote_TabNext/Prev.lua`, `EnumProjects` + wraparound |
| Semitonos ReaPitch (Stem Bus) | Cerrado | Patrón readout + modal, vía `Nik_RemoteState_Poll` |
| Playrate + preserve pitch | Cerrado | Patrón readout + modal (modelo para futuras funciones) |
| Doble-tap fader → 0dB | Cerrado, bug menor abierto | Rebote ocasional post-reset — ver pendientes |
| Browser de markers | Cerrado, sin confirmar en listas largas | Sticky header, ver pendientes |
| Nombre de proyecto activo (background) | Cerrado | Vía `Nik_RemoteState_Poll` + watchdog |
| Visibilidad de tracks en TCP (popup) | Cerrado | Ícono repurpuseado en `#optionsBar`; sin script Lua para leer datos, solo para el refresh |
| Indicador de color semitonos/playrate (deviación del default) | Cerrado | Gradiente gris→verde/naranja, intensidad = distancia del default (`nikDeviationColor`/`nikLerpColor`) |
| Colores + traducción de markers por sección (popup) | Cerrado | `NIK_MARKER_COLOR_MAP` editable, ver sección dedicada arriba |
| Compases por sección (popup) | Cerrado | `MarkerBars_common_logic.lua`, vía `Nik_RemoteState_Poll` |
| Achicar bloque play/pause/stop | Cerrado | `NIK_TRANSPORT_SCALE` (constante editable), scale + `margin-bottom` negativo en `transport_r2` |
| Colores + traducción de markers en indicadores de transporte | Cerrado | Mismo `NIK_MARKER_COLOR_MAP`, vía helper compartido `nikResolveMarkerDisplay()`, ver sección dedicada |
| Selector de proyectos (tabs), popup | Cerrado | Lectura on-demand (`Nik_ProjectTabs_Read/Select.lua`), ver sección dedicada |

## Pendientes activos

- **Cambio de proyecto (abrir/cerrar) desde el remoto**: mismo patrón
  (script Lua lee `ExtState` con ruta, `Main_openProject`). No
  implementado.
- **Loop de sección**: `reaper.GoToRegion(proj, index, true)` + preferencia
  "Loop points linked to time selection" activada. Requiere regiones (no
  solo markers) para las secciones — el proyecto de prueba ya tiene
  regiones cargadas, evaluar si sirven tal cual o hace falta el enfoque
  de lane oculto.
- Rebote ocasional del doble-tap de faders — candidato: bloqueo por track
  individual (`mouseDownAr[id]`) en vez del flag global `mouseDown`.
- Sticky header del browser de markers sin confirmar con listas largas
  reales (>15 markers).
- Achicar horizontalmente los botones prev/next del seeker (espacio para
  nombres de marker largos).
- Popup de selección de proyecto: parpadeo cosmético al abrir — se ve
  brevemente el resaltado del tab anterior (o la lista vacía) hasta que
  llega la respuesta de `GET/EXTSTATE/NikRemote/project_tabs` y se
  renderiza recién ahí. No bloqueante, cosmético.
- Colores grisáceos en markers `xN` (cadena) cuando no hay referencia de
  color previo disponible — tanto en el popup como en los indicadores de
  transporte, si el primer marker visible en la ventana es un `xN` no hay
  contexto anterior para heredar color. Evaluar a futuro si conviene
  buscar hacia atrás en la lista completa de markers (no solo los 3
  visibles del transporte) para resolver este caso.

## Convención de scripts (recordatorio, fuente de verdad en `01_CONVENCIONES.md`)
- Ejecutables: `Nik_<Dominio>_<Acción>.lua`. Módulos: `<Dominio>_common_logic.lua`
  (sin prefijo `Nik_`), cargados vía `dofile` con ruta resuelta desde el
  propio script — nunca `require`.
- Familia `NikRemote_*` preexistente no sigue el prefijo `Nik_` todavía —
  aplica solo a scripts nuevos, sin apuro de rename.
