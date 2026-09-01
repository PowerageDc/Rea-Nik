# Feature — Control Remoto Web (`nsaudio_remote_control.html`)

Interfaz web para controlar REAPER desde el celular durante ensayos.
Complementa `01_CONVENCIONES.md` (nomenclatura de scripts, patrón `dofile`).
Este doc es referencia viva del estado actual + patrones a seguir/evitar,
no un historial de sesiones — para eso quedan los `DEBUG_*.md` puntuales
cuando hagan falta. El historial de la migración a esta estructura de
archivos vive en `MODULARIZACION_CONTROL_REMOTO.md` — este doc no lo
duplica, solo referencia el resultado.

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

## Arquitectura de archivos

`nsaudio_remote_control.html` es shell puro (markup + `<script src>` en
orden, sin lógica de negocio inline). Toda la lógica vive en:

```
reaper_www_root/
├── config.js                     ← Command IDs + constantes (colores, timing)
├── modal-loader.js                ← inyecta modals/*/*.html en #modalsRoot
├── core/
│   ├── utils.js                   ← funciones puras sin estado
│   ├── state.js                   ← estado global consolidado
│   ├── faders.js                  ← arrastre de faders de volumen y sends
│   ├── tracks-render.js           ← hitbox() — expandir/colapsar filas
│   ├── tab-ui-memory.js           ← memoria de UI por proyecto (ver sección dedicada)
│   ├── wwr-dispatch.js            ← wwr_onreply() — parser central del feed de REAPER
│   └── init.js                    ← bootstrapping, watchdog, init()
├── markers/markers.js             ← parseo/color de nombres de marker (compartido)
└── modals/
    ├── playrate/, reapitch/, tracksvis/, marker-browser/, project-tabs/
    └── cada uno: <nombre>.html + <nombre>.js
```

Scripts clásicos, nunca `type="module"` — el HTML tiene `onclick="nikAlgo()"`
inline por todos lados; con módulos ES esas funciones quedarían scopeadas
al archivo y los onclick se romperían. Todo cuelga de `window`.

## Estilos: inline vs. clases en `styles.css`

Criterio: un bloque de estilo **repetido en más de un elemento** (ej. los
6 botones de `nikCursorNav`, los 2 de `nikTabBar`) va como clase en
`styles.css` — evita desalinear instancias al ajustar (pasó con
rewind/end antes de extraerlo). Layout puntual y no reutilizado (ej.
posicionamiento absoluto de los readouts de Playrate/ReaPitch) y
cualquier valor pisado dinámicamente por JS quedan inline.

Cuando una clase mezcla layout (flex/padding/tamaño) y apariencia
(background/color) y se anticipa que la apariencia va a variar por
grupo (ej. gradientes distintos para subconjuntos de botones), separar
en dos clases combinables — una de layout, una de apariencia — en vez de
una sola clase monolítica. Caso real: `.nikCursorNavBtn` (base) +
`.nikCursorNavEdge`/`.nikCursorNavWide`/`.nikCursorNavTight` (layout por
grupo), pensado para sumar después clases de apariencia sin tocar el
layout ya ajustado.

## Cómo agregar un popup nuevo

1. Crear `modals/<nombre>/<nombre>.html` + `<nombre>.js`.
2. Sumar la ruta del `.html` a `NIK_MODAL_FRAGMENTS` en `modal-loader.js`.
3. Sumar `<script src="modals/<nombre>/<nombre>.js">` en
   `nsaudio_remote_control.html`, después de `core/init.js`.

**Criterio de qué va en el JS del modal vs. en `core/`:** si es lógica de
dominio del modal (aunque toque un elemento del DOM que vive fuera del
modal, ej. el botón que lo abre en la UI principal), va en el JS del
modal. Lo que sí queda en `core/`: helpers usados por **más de un** modal
(ej. `markers/markers.js`, compartido por el shell y `marker-browser`) y
el estado/dispatch central.

Las funciones de `wwr_onreply` que tocan elementos de un modal por ID
deben ir guardadas con `if (elemento) {...}` — el `fetch` async de
`modal-loader.js` es seguro aunque un poll llegue antes de que el modal
esté inyectado en el DOM (no revienta, simplemente no-opea esa vez).

## Arquitectura del patrón (aplica a toda función nueva)

**Script Lua + `ExtState` + polling desde la web.** Tres piezas:
1. Un script Lua (o módulo consumido por varios) lee/escribe estado real
   de REAPER hacia `ExtState` (`persist=false`, sección `"NikRemote"`).
2. La web dispara ese script como acción custom (`_RS...`, Command ID
   único por PC — **hay que re-registrar al cambiar de máquina**).
3. La web lee el resultado con `GET/EXTSTATE/NikRemote/<key>`, encadenado
   en la misma request que el `_RS` (mismo round-trip) — ver
   `Nik_RemoteState_Poll` más abajo.

`reaper.GetExtState(section, key)` devuelve **un solo string** (`""` si no
existe), no un par `(ok, valor)` — confundir el patrón corta el script en
silencio sin aplicar nada.

## Lectura de estado consolidada — `Nik_RemoteState_Poll.lua`

Todas las lecturas de background (proyecto activo, playrate/preserve
pitch, semitonos/enabled de ReaPitch, compases por sección) están
unificadas en **un solo script** con **un solo Command ID**:

```
Nik_RemoteState_Poll.lua
  ├─ ActiveProject_common_logic.write_active_project_name()
  ├─ lectura directa de Master_GetPlayRate + preserve pitch (40671)
  ├─ ReaPitchBus_common_logic.write_aggregated_state()
  └─ MarkerBars_common_logic.write_aggregated_state()
```

Usado tanto para el poll de fondo (`NIK_SLOW_POLL` en `config.js`,
recurrente 1000ms) como para refresco puntual (`NIK_ONDEMAND_READS`, hoy
alias del mismo comando).

**Para escalar (agregar una lectura nueva a futuro):** sumar una sección
dentro de este script (o del módulo `common_logic` correspondiente) — **y
agregar el `GET/EXTSTATE/NikRemote/<key>` correspondiente a `NIK_SLOW_POLL`
en `config.js`** (ver gotcha abajo, es el error más común al escalar
esto). Nunca un `_RS` nuevo encadenado — ver gotcha de parpadeo.

### Patrón de agregación en los módulos (`common_logic`)
Cada dominio que necesita agregar estado de múltiples instancias (ej.
ReaPitch en varios stems) expone `read_aggregated_state()` (lógica pura)
+ `write_aggregated_state()` (llama al anterior y escribe ExtState). El
script `Nik_*_Read.lua` standalone (si se mantiene) queda como wrapper
delgado de una línea sobre `write_aggregated_state()`.

## Memoria de UI por proyecto — `core/tab-ui-memory.js`

Mecanismo para recordar parámetros de UI **por proyecto activo (tab)**,
puramente en cliente — sin ExtState, sin poll adicional. Existe porque
los arrays de `core/state.js` (`trackHeightsAr`, `trackColoursAr`, etc.)
están indexados por número de track de REAPER, que es una *posición*, no
un track fijo: el track 3 del proyecto A no tiene relación con el track 3
del proyecto B, pero sin este mecanismo la UI hereda estado entre ambos
(ver gotchas — es la causa de dos bugs ya cerrados).

- `nikTabUiMemory[projectName]` — objeto por proyecto,
  `{ expandedTracks: {3:1, 5:1}, scrollTop: 240, loopRecExpanded: false }`
  hoy; **cualquier parámetro custom nuevo que necesite persistir por
  proyecto (sin equivalente nativo en REAPER) se suma como clave nueva
  acá**, sin tocar el resto del mecanismo. `scrollTop` se reaplica también
  en `nikTabMemoryApplyPending()` (no solo en el restore inicial) porque
  depende de que el DOM ya tenga su alto final — mismo criterio a seguir
  para futuros parámetros que dependan del tamaño real del contenido.
- `nikTabMemorySnapshot()` — arma el objeto a partir del estado vivo.
  **Para sumar un parámetro nuevo: agregarlo al objeto que devuelve esta
  función.**
- `nikTabMemorySave(projectName)` / `nikTabMemoryRestore(projectName)` —
  guardar/aplicar. Restauración **instantánea, sin animación**
  (`nikSetTrackExpandedInstant`, variante no-animada de `hitbox()`).
  **Para aplicar un parámetro nuevo: sumar su lógica de restore acá.**
- `nikTabMemoryResetRenderCaches()` — limpia los arrays usados como gate
  de diff (`trackColoursAr`, `trackFlagsAr`, `trackNamesAr`,
  `trackNumbersAr`) para forzar redraw completo contra el proyecto nuevo.
- **Único punto de enganche**: el handler de EXTSTATE
  `"active_project_name"` en `core/wwr-dispatch.js` — ya es el único
  lugar donde se detecta cambio de proyecto activo, sin costo de red
  adicional (viaja en `NIK_SLOW_POLL`, 1000ms).
- **`nikTabMemoryPendingRestore` + `nikTabMemoryApplyPending(id)`** —
  cubren el caso en que el proyecto de destino tiene *más* tracks que
  los que existen en el DOM al momento del restore (shells todavía no
  creados). `nikTabMemorySnapshot()`/`nikTabMemoryRestore()` **no
  iteran por `nTrack`**, sino por `document.getElementsByClassName
  ("trackRow2").length` (conteo real de shells ya presentes) — cualquier
  índice guardado por encima de ese conteo queda en
  `nikTabMemoryPendingRestore` hasta que su shell se cree. El enganche
  vive en `core/wwr-dispatch.js`, en el punto exacto donde el contenido
  SVG de cada `trackRow2` se puebla por primera vez (`if
  (!trackRow2Content.innerHTML) {...}`, para track normal y para
  Master) — ahí se llama `nikTabMemoryApplyPending(idx)`. **Para
  parámetros nuevos que dependan de shells todavía no creados, sumar su
  aplicación en ese mismo punto de enganche, no solo en
  `nikTabMemoryRestore()`.**
- **Resuelto — nunca usar `nTrack` como límite de loop de
  snapshot/restore**: `nTrack` lo actualiza un poll independiente
  (10ms) del que detecta `active_project_name` (1000ms); en el instante
  del restore, `nTrack` reflejaba el proyecto que se estaba
  *abandonando*, no el de destino, dejando afuera del loop cualquier
  índice por encima de ese valor. Confirmado con logs — ver gotcha
  dedicado más abajo.
- **Pendiente, no bloqueante**: el scroll vertical de `#tracks` no se
  recuerda por proyecto (a diferencia de `expandedTracks`) — al volver a
  un tab, la posición de scroll queda la que tenía el proyecto anterior
  en vez de restaurarse. Candidato natural para sumarse como clave nueva
  del mismo mecanismo (`nikTabMemorySnapshot`/`nikTabMemoryRestore`),
  guardando `document.getElementById("tracks").scrollTop`.

## Gotchas confirmados (lecciones, no repetir)

- **Correr un ReaScript como acción hace parpadear brevemente el menú
  superior de REAPER** (cosmético, no corrompe Undo — confirmado con
  revisión manual de la pila). El parpadeo escala con la cantidad de
  `_RS` empaquetados en el mismo tick — por eso las lecturas de
  background van **consolidadas en un solo script** (`Nik_RemoteState_Poll`)
  en vez de encadenar varios `_RS` sueltos.
- **`wwr_req_recur` con el mismo intervalo se empaqueta en una sola
  request HTTP**, aunque estén registrados en llamadas separadas (ver
  `wwr_run_update()` en `main.js`). Desfasar intervalos es la única forma
  de partir un bundle, si algún día hiciera falta.
- **`SET/TRACK/x/B_SHOWINTCP/valor` no refresca el TCP visualmente** — ir
  directo a `GetSetMediaTrackInfo` vía el protocolo web se salta
  `TrackList_AdjustWindows()`. Fix: `Nik_TrackVis_Refresh.lua`
  (`TrackList_AdjustWindows(false)` + `UpdateArrange()`), encadenado al
  final del batch de Aplicar en `tracksvis.js`.
- **Sumar una key nueva a `Nik_RemoteState_Poll.lua` no alcanza**: además
  de escribirla desde Lua, hay que agregar su
  `GET/EXTSTATE/NikRemote/<key>` a `NIK_SLOW_POLL` en `config.js` — si
  no, el Lua escribe la ExtState pero la request bundleada nunca la pide.
- **`TimeMap_QNToMeasures` puede resolver al compás anterior al esperado**
  en markers que caen una fracción de float antes del downbeat real
  (precisión de punto flotante tras nudges/ediciones). Fix: sumar un
  épsilon chico (`+1e-6` QN) antes de convertir.
- **Estado de UI heredado entre proyectos (tabs)**: los arrays de
  `core/state.js` son globales, indexados por número de track — sin
  reset explícito, un track expandido o un color cacheado del proyecto
  anterior "contamina" al track de mismo índice del proyecto nuevo.
  Resuelto con `core/tab-ui-memory.js` (ver sección dedicada) — cualquier
  estado nuevo indexado por track debe pasar por ahí si tiene que
  sobrevivir un cambio de tab, o resetearse explícitamente si no.
- **Ids de `<linearGradient>` duplicados en templates SVG clonados por
  track**: `trackRow1Svg`/`trackRow2Svg`/`trackSendSvg` traen `id`s
  fijos; `cloneNode(true)` los duplica literalmente en cada track. El
  navegador resuelve `fill="url(#id)"` contra la **primera** ocurrencia
  de ese id en el documento — si ese track puntual queda oculto
  (`display:none` vía TracksVis), la definición deja de renderizarse y
  **todos** los clones que dependían de ella pierden el fill. Fix:
  `nikUniquifyGradientIds(cloneRoot, suffix)` en `core/wwr-dispatch.js`,
  llamada una vez por clon (al insertarlo, no en cada poll) con el índice
  del track como sufijo. Aplica a **cualquier** template SVG nuevo que se
  clone por track — sumar la llamada al insertarlo.
- **Un `<span>` flex con contenido de largo variable puede angostar a sus
  hermanos**: con `flex-basis: auto` (default), el ancho "hipotético" que
  usa el algoritmo de flex para repartir espacio se calcula sobre el
  contenido sin truncar — `overflow:hidden`/`text-overflow:ellipsis` son
  solo efectos de pintado, no achican ese cálculo. Con texto largo, ese
  básis infla el total y el motor le roba espacio a los vecinos si estos
  no tienen `flex-shrink:0`/`white-space:nowrap`. Pasó con
  `#nikActiveProjectName` en `nikTabBar`: un nombre de proyecto largo
  angostaba los botones ⏮/⏭ Tab hasta romper su label en 2 líneas,
  agrandando la barra entera. Fix: `flex:1 1 0` (básis fijo en 0) en el
  span + `flex:0 0 auto` y `white-space:nowrap` en los botones vecinos.
  Aplica a cualquier elemento flex con texto de largo variable + hermanos
  de ancho fijo.
- **El propio wrapper de template (`<element id="trackRow2Svg">`, ídem
  `trackRow1Svg`/`trackSendSvg`) también tiene `id` fijo, y
  `cloneNode(true)` lo copia igual que a los gradientes.** Al insertar el
  primer clon en el documento, queda duplicado el `id` de la plantilla —
  y como `getElementById()` siempre devuelve el primer match en **orden
  de documento**, si el clon insertado queda antes que la plantilla
  original (caso Master, que vive arriba en el HTML, antes que
  `#backLoad`), `getElementById("trackRow2Svg")` deja de apuntar a la
  plantilla limpia y pasa a apuntar al clon de Master — con el estado
  (`viewBox`) que Master tenga en ese momento. Todo track nuevo creado
  después clona, sin saberlo, el estado de Master en vez del default de
  la plantilla (causa real del bug "tracks nuevos nacen ya
  expandidos/colapsados según el estado de Master", ver
  `01_CONVENCIONES.md` para la lección general). Fix aplicado:
  `cloneTrackRow1/2/Send.removeAttribute("id")` inmediatamente después
  de cada `cloneNode(true)`, antes de insertarlo.

## Watchdog de "proyecto desconectado" (`core/init.js`)

`nikCheckProjectNameWatchdog()` compara `Date.now()` contra el timestamp
de la última respuesta recibida con `active_project_name`. **Corre
siempre, vía su propio `setInterval` independiente del poll** — es la
única señal posible de "REAPER cerró del todo" (el servidor web muere con
REAPER, ninguna respuesta vuelve nunca más). Costo despreciable.

## Toggle de sección Loop/Rec/Tracks armadas (`core/init.js`)

`#transport_r3` (loop, tracks armadas, botón de record) se despliega o
colapsa con `nikToggleLoopRecSection()`, disparado desde `#buttonLoopRec`
en `#optionsBar` — reemplaza al botón de Snap (sin uso en contexto
remoto, la barra de íconos funciona como el "menú" de funciones
secundarias). Colapsado se ve como línea fina de 4px (`#1a1a1a`), sin
texto. El ícono recicla el círculo rojo de record (`iconLoopRecOn`/
`iconLoopRecOff`), con estado "prendido" (color del ícono + fondo del
ítem resaltado, clase `.nikToggledOn`) cuando la sección está desplegada.

- `nikApplyLoopRecState(expanded)` — separado del toggle para que
  `core/tab-ui-memory.js` pueda aplicar el estado guardado por tab
  directamente (clave `loopRecExpanded`), sin pasar por el toggle.
- **Default**: colapsado, tanto en un tab nunca visto como al perder
  conexión con REAPER.
- Reemplaza al viejo botón `#nikLoopRecToggle` (texto "▾ Loop / Rec /
  Tracks armadas"), eliminado del HTML.
- Limpieza asociada: se sacó `GET/1157` del poll de 10ms, el bloque
  muerto que leía `#buttonSnap` en `core/wwr-dispatch.js`, y la variable
  `snapState` en `core/state.js` (Snap ya no es controlable desde acá).

## Popup de visibilidad de tracks en TCP (`modals/tracksvis/tracksvis.js`)

Excepción al patrón Script Lua + ExtState: el protocolo nativo de
`main.js` ya cubre todo lo necesario sin script intermedio para leer
datos (sí hace falta uno para el refresco).

- **Datos de entrada**: sin requests nuevas al abrir — se lee directo de
  `trackNamesAr`, `trackFlagsAr` (bit `512` = oculto en TCP, bit `4` =
  tiene FX) y `trackColoursAr`, ya llenados por el poll recurrente de
  `TRACK` (10ms).
- **Aplicar**: solo los tracks que cambiaron respecto al snapshot tomado
  al abrir disparan `SET/TRACK/x/B_SHOWINTCP/valor`, seguido de
  `SET/UNDO` y `Nik_TrackVis_Refresh.lua`.
- **Trigger**: `tracksVisButton` en la UI principal.

## Colores y traducción de markers (`NIK_MARKER_COLOR_MAP`, en `config.js`)

Diccionario editable — fuente de verdad de colores por sección (ver
`01_CONVENCIONES.md` para nombres de sección). Cada categoría define
`label`, `color`, `tint` (reservado, sin uso hoy), `words` (formas
completas) y `abbrev` (formas abreviadas). Resolución compartida vía
`nikResolveMarkerDisplay()` en `markers/markers.js`, usado tanto por el
popup (`marker-browser.js`) como por los indicadores de transporte.

- **Palabras completas** (`words`): match por *prefijo* sobre el nombre
  normalizado — solo cambia el color.
- **Abreviaturas** (`abbrev`): match *exacto* — cambia el color y además
  traduce el texto mostrado al `label` completo (+ número si tenía).
- **Cadena `x<número>`** (`NIK_MARKER_CHAIN_PATTERN`/`_STEP`): hereda el
  color del último marker categorizado encontrado antes en la lista,
  aclarando hacia blanco un paso fijo por eslabón sucesivo.
- Colores auditados con contraste WCAG AA (≥4.5:1) contra `#1a1a1a`.

En los **indicadores de transporte** (prev/actual/next), mismo
diccionario pero con `chainState` propio e independiente por redibujo
(no comparte estado con el popup). Colorea tanto el fondo del badge como
el texto. Casos HOME/END resetean el `fill` a gris explícitamente.

## Compases por sección (popup de markers)

`MarkerBars_common_logic.lua` calcula, para cada marker, cuántos compases
hay hasta el siguiente — vía `TimeMap2_timeToQN` + `TimeMap_QNToMeasures`
(ver gotcha de precisión arriba). Escribe `NikRemote/marker_bars`,
agregado al poll consolidado.

## Selector de proyectos (tabs) — `modals/project-tabs/project-tabs.js`

Tap en `#nikActiveProjectName` abre un popup con los proyectos abiertos.

- **Lectura on-demand, fuera de `Nik_RemoteState_Poll`**: enumerar
  proyectos solo se dispara al abrir el popup (`Nik_ProjectTabs_Read.lua`)
  — decisión explícita para no sumar `EnumProjects` a cada tick del poll
  de fondo.
- `ProjectTabs_common_logic.lua` enumera con `EnumProjects(i)`, compara
  contra `EnumProjects(-1)` (activo), escribe
  `NikRemote/project_tabs` como `"idx:nombre:esActivo;..."`.
- **Selección**: tap en un ítem distinto al activo escribe
  `project_tabs_target_idx` y dispara `Nik_ProjectTabs_Select.lua`
  (`SelectProjectInstance()`), asumiendo que el orden de `EnumProjects`
  no cambió entre lectura y tap (ventana chica, no debería importar en
  uso normal). Tap en el activo solo cierra el popup.
- **Color**: activo en `#00FF99` negrita, resto gris `#A8A8A8`.
- **Display del nombre activo** (`#nikActiveProjectName`, en
  `nikTabBar`): el texto visible saca la extensión `.rpp`
  (`wwr-dispatch.js`, case `EXTSTATE`/`active_project_name`,
  `.replace(/\.rpp$/i, "")` aplicado solo sobre el `textContent`) —
  `nikCurrentProjectName` (key de `tab-ui-memory.js`) conserva el string
  completo con extensión, no tocar eso. Además trunca en una sola línea
  con `text-overflow:ellipsis` (`white-space:nowrap`) — ver gotcha de
  `flex-basis` más abajo, necesario para que un nombre largo no rompa el
  alto de la barra.

## Funcionalidades activas (resumen)

| Función | Estado | Notas |
|---|---|---|
| Ciclar tabs (proyectos abiertos) | Cerrado | `EnumProjects` + wraparound |
| Semitonos ReaPitch (Stem Bus) | Cerrado | Patrón readout + modal |
| Playrate + preserve pitch | Cerrado | Patrón readout + modal (modelo de referencia) |
| Doble-tap fader → 0dB | Cerrado, bug menor abierto | Rebote ocasional post-reset — ver pendientes |
| Browser de markers | Cerrado, sin confirmar en listas largas | Sticky header, ver pendientes |
| Nombre de proyecto activo (background) | Cerrado | + watchdog en `core/init.js`; display truncado (ellipsis, sin extensión `.rpp`) |
| Visibilidad de tracks en TCP (popup) | Cerrado | `modals/tracksvis/` |
| Indicador de color semitonos/playrate | Cerrado | `nikDeviationColor`/`nikLerpColor` |
| Colores + traducción de markers (popup + transporte) | Cerrado | `markers/markers.js` |
| Compases por sección (popup) | Cerrado | `Nik_RemoteState_Poll` |
| Achicar bloque play/pause/stop | Cerrado | `NIK_TRANSPORT_SCALE` en `config.js` |
| Selector de proyectos (tabs), popup | Cerrado | `modals/project-tabs/` |
| Memoria de UI por proyecto | Cerrado (expandedTracks, scrollTop, loopRecExpanded) | `core/tab-ui-memory.js` — ver sección dedicada |
| Toggle Loop/Rec/Tracks armadas vía `#optionsBar` | Cerrado | `core/init.js` — reemplaza a Snap, ver sección dedicada |
| Ids de gradiente únicos por track clonado | Cerrado | `nikUniquifyGradientIds()` en `core/wwr-dispatch.js` |
| Ids de template SVG únicos al clonar | Cerrado | `removeAttribute("id")` post-clone — ver gotchas |

## Pendientes activos

- **Cambio de proyecto (abrir/cerrar) desde el remoto**: mismo patrón
  (script Lua lee `ExtState` con ruta, `Main_openProject`). No
  implementado.
- **Loop de sección**: `reaper.GoToRegion(proj, index, true)` + preferencia
  "Loop points linked to time selection". Requiere regiones (no solo
  markers) para las secciones.
- Rebote ocasional del doble-tap de faders — candidato: bloqueo por track
  individual (`mouseDownAr[id]`) en vez del flag global `mouseDown`.
- Sticky header del browser de markers sin confirmar con listas largas
  (>15 markers).
- **Seeker de markers (`#nextPrev`) — rediseño pendiente, sesión aparte**:
  sacar la visualización de regiones (`region1`-`region4`, `regionStrip`)
  y comprimir el alto del bloque. Ocultar solo por CSS no alcanza — el
  `viewBox` fijo (`0 0 318.9 87.8`) mantiene el alto reservado aunque el
  contenido esté oculto; hace falta recalcular coordenadas, incluyendo
  achicar/reposicionar `prevButton`/`nextButton` (hoy ocupan casi todo el
  alto del bloque). Incluye también achicar horizontalmente los botones
  prev/next (pendiente previo, mismo bloque, fusionado acá).
- Popup de selección de proyecto: parpadeo cosmético al abrir (se ve
  brevemente el resaltado del tab anterior hasta que llega la respuesta).
- Colores grisáceos en markers `xN` cuando no hay referencia de color
  previo disponible (ni en popup ni en indicadores de transporte).

## Convención de scripts (recordatorio, fuente de verdad en `01_CONVENCIONES.md`)
- Ejecutables: `Nik_<Dominio>_<Acción>.lua`. Módulos: `<Dominio>_common_logic.lua`
  (sin prefijo `Nik_`), cargados vía `dofile` con ruta resuelta desde el
  propio script — nunca `require`.
- Familia `NikRemote_*` preexistente no sigue el prefijo `Nik_` todavía —
  aplica solo a scripts nuevos, sin apuro de rename.
