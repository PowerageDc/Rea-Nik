# Feature — Control Remoto Web: estado por proyecto (tabs)

Todo lo que depende de qué proyecto (tab) está activo: memoria de UI por
proyecto, selector de proyectos y detección de desconexión. Índice y
arquitectura general: `remote_control.md`. Lectura de estado y dispatch:
`remote_control_protocol.md`.

## 1. Memoria de UI por proyecto (`core/tab-ui-memory.js`)

Recuerda parámetros de UI por proyecto activo, puramente en cliente: sin
`ExtState` ni poll adicional. Existe porque los arrays de `core/state.js`
(`trackHeightsAr`, `trackColoursAr`, etc.) son globales y están indexados
por número de track, que es una posición y no un track fijo: el track 3
del proyecto A no tiene relación con el track 3 del proyecto B.

- `nikTabUiMemory[projectName]`: objeto por proyecto, con las claves
  `expandedTracks` (`{3:1, 5:1}`), `scrollTop`, `loopRecExpanded`,
  `preMarkerBars` y `markerScrollTop`.
- `nikTabMemorySnapshot()` arma el objeto a partir del estado vivo.
- `nikTabMemorySave(projectName)` y `nikTabMemoryRestore(projectName)`
  guardan y aplican. La restauración es instantánea, sin animación.
- `nikTabMemoryResetRenderCaches()` limpia los arrays usados como gate de
  diff, para forzar un redraw completo contra el proyecto nuevo.
- **Único punto de enganche:** el handler de `EXTSTATE`
  `"active_project_name"` en `core/wwr-dispatch.js`.
- **Shells todavía no creados:** `nikTabMemorySnapshot()` y
  `nikTabMemoryRestore()` no iteran por `nTrack` sino por
  `document.getElementsByClassName("trackRow2").length` (shells presentes).
  Los índices guardados por encima de ese conteo quedan en
  `nikTabMemoryPendingRestore` y los aplica `nikTabMemoryApplyPending(id)`
  en el punto donde el contenido SVG de cada `trackRow2` se puebla por
  primera vez.

Agregar un parámetro nuevo por proyecto:

1. Sumarlo al objeto que devuelve `nikTabMemorySnapshot()`.
2. Sumar su restore en `nikTabMemoryRestore()`.
3. Si depende de shells que pueden no existir todavía, aplicarlo también
   en el punto de enganche de `nikTabMemoryApplyPending(id)`.

Claves con semántica propia en otros docs:

- `loopRecExpanded`: `remote_control_ui.md` §4.
- `preMarkerBars` y `markerScrollTop`: `remote_control_markers.md` §4.

**`scrollTop` de un elemento oculto** (`display:none` propio o de un
ancestro) siempre lee `0`, por spec CSSOM View, aunque exista una posición
de scroll real pendiente de restaurar. Hay que leerlo mientras está
visible, o guardarlo en el momento exacto en que se oculta, no en un
snapshot genérico posterior. Aplica a cualquier modal que persista su
propio scroll (es el caso de `markerScrollTop`, cuyo snapshot solo lee en
vivo si el popup está visible).

## 2. Selector de proyectos (`modals/project-tabs/project-tabs.js`)

Tap en `#nikActiveProjectName` abre un popup con los proyectos abiertos.
`tabPrev` y `tabNext` ciclan por `EnumProjects` con wraparound.

- **Lectura on-demand**, fuera de `Nik_RemoteState_Poll` (ver
  `remote_control_protocol.md` §4): `ProjectTabs_common_logic.lua`
  enumera con `EnumProjects(i)`, compara contra `EnumProjects(-1)`
  (activo) y escribe `NikRemote/project_tabs` como
  `"idx:nombre:esActivo;..."`. Se dispara solo al abrir el popup.
- **Selección:** un tap en un ítem distinto del activo escribe
  `project_tabs_target_idx` y dispara `Nik_ProjectTabs_Select.lua`, que
  encadena `Main_OnCommand(40667, 0)` ("Transport: Stop, save all recorded
  media") antes de `SelectProjectInstance()`. El Stop vive del lado Lua,
  en un solo lugar. Un tap en el activo solo cierra el popup.
- **Resaltado sin parpadeo:** cada ítem guarda `data-name` (nombre
  completo con extensión), además de `data-idx` y `data-active`. Al abrir,
  el resaltado se repinta contra `nikCurrentProjectName` (ya fresco por el
  poll de fondo) antes de esperar la respuesta on-demand. En la primera
  apertura de la sesión no hace nada, porque la lista está vacía.
- **Color:** activo `#00FF99`, resto `#A8A8A8`, sin negrita. El bold
  condicional en la fila activa produce un salto de layout entre filas.
- **Nombre activo** (`#nikActiveProjectName`, en `nikTabBar`): el texto
  visible saca la extensión (`.replace(/\.rpp$/i, "")`, solo sobre el
  `textContent`); `nikCurrentProjectName` conserva el string completo.
  Trunca en una línea con `text-overflow:ellipsis` y
  `white-space:nowrap` (ver `remote_control_ui.md` §3, sobre
  `flex-basis`).

## 3. Watchdog de proyecto desconectado (`core/init.js`)

`nikCheckProjectNameWatchdog()` compara `Date.now()` contra el timestamp
de la última respuesta recibida con `active_project_name`. Corre por su
propio `setInterval`, independiente del poll, y es la única señal posible
de que REAPER cerró del todo.

Al dispararse resetea a `null` o placeholder todo estado leído on-demand
que dependa de una conexión viva (por ejemplo `nikPlayrateTempoMap`, ver
`remote_control_faders.md` §6). No hay reintento activo mientras sigue
desconectado: el estado se retoma con el próximo boot o cambio de
proyecto.

El handler de `active_project_name` es también el disparador de la
restauración de §1 y de la relectura del mapa de tempo.

## 4. Pendientes

- **Abrir y cerrar proyectos desde el remoto:** mismo patrón que el
  selector (script Lua que lee de `ExtState` una ruta y llama a
  `Main_openProject`).
- **Scroll vertical de `#tracks` por proyecto:** no se recuerda. Se
  resuelve con una clave nueva en `nikTabUiMemory`
  (`document.getElementById("tracks").scrollTop`), siguiendo los pasos de
  §1.
- **Manejo de conexión del prompter:** evaluar portar al remoto el
  indicador de datos viejos, el tope del backoff de `main.js` y la
  compensación por RTT (`musicstate_sync.md` §14).