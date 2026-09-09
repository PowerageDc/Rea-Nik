# Feature — Control Remoto Web (`nsaudio_remote_control.html`)

Interfaz web para controlar REAPER desde el celular durante ensayos.
Complementa `01_CONVENCIONES.md` (nomenclatura de scripts, patrón `dofile`).
Este doc es referencia viva del estado actual + patrones a seguir/evitar,
no un historial de sesiones.

**Sub-domain docs** (dominios grandes, detalle completo ahí, no acá):
- `remote_control_markers.md` — seeker de markers, popup de markers
  (rediseño, indicador de posición, autoscroll, scroll persistente),
  colores/traducción de nombres, compases por sección, seek relativo
  "N compases antes" (long-press).
- `remote_control_faders.md` — fader vertical modular, knob SVG calcado,
  Playrate (tempo map variable, BPM bidireccional), ReaPitch (Stem Bus).

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
│   ├── vertical-fader.js          ← fader vertical modular (Playrate/ReaPitch)
│   ├── fader-knob-svg.js          ← knob SVG calcado, capa visual sobre <input>
│   ├── long-press.js              ← helper genérico de long-press (touch+mouse)
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

`marker-browser.js` tiene su propia implementación de long-press (con
barra de progreso animada vía CSS transition) — **no** usa
`core/long-press.js`, que hoy no soporta barra de progreso. Candidato de
unificación en un cleanup futuro, no bloqueante.

## Estilos: inline vs. clases en `styles.css`

Criterio: un bloque de estilo **repetido en más de un elemento** (ej. los
6 botones de `nikCursorNav`, los 2 de `nikTabBar`) va como clase en
`styles.css` — evita desalinear instancias al ajustar. Layout puntual y
no reutilizado, y cualquier valor pisado dinámicamente por JS, quedan
inline.

Cuando una clase mezcla layout (flex/padding/tamaño) y apariencia
(background/color) y se anticipa que la apariencia va a variar por
grupo, separar en dos clases combinables — una de layout, una de
apariencia. Caso real: `.nikCursorNavBtn` (base) +
`.nikCursorNavEdge`/`.nikCursorNavWide`/`.nikCursorNavTight` (layout por
grupo).

**Paleta de popups (Playrate/ReaPitch/marker-browser)**: blancos/grises
sobre negro — `#FFFFFF` (readouts numéricos grandes), `#D0D0D0`
(títulos/labels), `#4A4A4A` (líneas divisorias/bordes), `#EDEDED` (texto
del pill/stepper de pre-marker). Reemplaza al cyan `#00D0FF` original
(bajo contraste sostenido, "brilloso" según feedback de uso real). Estos
valores están **inline en cada `.html`**, no hay clase compartida de
paleta — al sumar un popup nuevo, replicar estos valores a mano. El cyan
del indicador de "parado en marker" y el de estado ON de toggles (ej.
`#nikReaPitchEnableToggle`) se dejaron a propósito sin tocar: son
indicadores que se miran de refilón, no readouts que se sostienen la
mirada.

## Cómo agregar un popup nuevo

1. Crear `modals/<nombre>/<nombre>.html` + `<nombre>.js`.
2. Sumar la ruta del `.html` a `NIK_MODAL_FRAGMENTS` en `modal-loader.js`.
3. Sumar `<script src="modals/<nombre>/<nombre>.js">` en
   `nsaudio_remote_control.html`, después de `core/init.js`.

**Criterio de qué va en el JS del modal vs. en `core/`:** si es lógica de
dominio del modal (aunque toque un elemento del DOM que vive fuera del
modal, ej. el botón que lo abre en la UI principal), va en el JS del
modal. Lo que sí queda en `core/`: helpers usados por **más de un** modal
y el estado/dispatch central.

Las funciones de `wwr_onreply` que tocan elementos de un modal por ID
deben ir guardadas con `if (elemento) {...}` — el `fetch` async de
`modal-loader.js` es seguro aunque un poll llegue antes de que el modal
esté inyectado en el DOM.

## Arquitectura del patrón — dos variantes

### A) Script Lua + `ExtState` + polling desde la web (default)
1. Un script Lua (o módulo consumido por varios) lee/escribe estado real
   de REAPER hacia `ExtState` (`persist=false`, sección `"NikRemote"`).
2. La web dispara ese script como acción custom (`_RS...`, Command ID
   único por PC — **hay que re-registrar al cambiar de máquina**).
3. La web lee el resultado con `GET/EXTSTATE/NikRemote/<key>`, encadenado
   en la misma request que el `_RS`.

`reaper.GetExtState(section, key)` devuelve **un solo string** (`""` si no
existe), no un par `(ok, valor)` — confundir el patrón corta el script en
silencio sin aplicar nada.

### B) `CMDSTATE` nativo encadenado al click (sin ExtState, sin Lua propio)
Para preferencias/toggles ya expuestos como Command ID nativo de REAPER:
el click dispara la acción + un `GET/<commandId>` encadenado en la misma
request (mismo round-trip, sin esperar el poll de fondo), y además se
suma `;GET/<commandId>` al final de `NIK_SLOW_POLL` (`config.js`) como
respaldo/resync periódico. No es `EXTSTATE`, así que **no** aplica el
gotcha "hay que sumarlo también a `Nik_RemoteState_Poll.lua`". El
feedback visual se resuelve cambiando el atributo `fill` de elementos SVG
por `id` directo desde `wwr-dispatch.js` case `"CMDSTATE"` — preferido
sobre alternar visibilidad de grupos duplicados por índice de
`childNodes` (frágil, depende de whitespace del markup). Casos reales:
`buttonMetro` (`40364`), `buttonSoloInFront` (`40745`, ver OptionsBar).

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

**Para escalar (agregar una lectura nueva a futuro):** sumar una sección
dentro de este script (o del módulo `common_logic` correspondiente) — **y
agregar el `GET/EXTSTATE/NikRemote/<key>` correspondiente a
`NIK_SLOW_POLL` en `config.js`** (error más común al escalar esto). Nunca
un `_RS` nuevo encadenado — ver gotcha de parpadeo del menú.

### Patrón de agregación en los módulos (`common_logic`)
Cada dominio que necesita agregar estado de múltiples instancias expone
`read_aggregated_state()` (lógica pura) + `write_aggregated_state()`
(llama al anterior y escribe ExtState). El script `Nik_*_Read.lua`
standalone (si se mantiene) queda como wrapper delgado de una línea sobre
`write_aggregated_state()`.

### Lecturas on-demand fuera del poll consolidado
Cuando el costo no justifica sumarlo al tick de 1000ms, se dispara
puntual, encadenado a un evento concreto (abrir popup, boot, cambio de
proyecto) en vez de vivir en `Nik_RemoteState_Poll`. Casos:
`Nik_ProjectTabs_Read.lua` (al abrir el popup de tabs),
`Nik_Playrate_ReadTempoMap.lua` (boot + cambio de proyecto + apertura del
popup de Playrate — ver `remote_control_faders.md`).

## Memoria de UI por proyecto — `core/tab-ui-memory.js`

Mecanismo para recordar parámetros de UI **por proyecto activo (tab)**,
puramente en cliente — sin ExtState, sin poll adicional. Existe porque
los arrays de `core/state.js` (`trackHeightsAr`, `trackColoursAr`, etc.)
están indexados por número de track de REAPER, que es una *posición*, no
un track fijo: el track 3 del proyecto A no tiene relación con el track 3
del proyecto B.

- `nikTabUiMemory[projectName]` — objeto por proyecto, hoy:
  `{ expandedTracks: {3:1, 5:1}, scrollTop: 240, loopRecExpanded: false,
  preMarkerBars: 2, markerScrollTop: 0 }`. **Cualquier parámetro custom
  nuevo que necesite persistir por proyecto se suma como clave nueva
  acá**, sin tocar el resto del mecanismo.
- `nikTabMemorySnapshot()` — arma el objeto a partir del estado vivo.
  **Para sumar un parámetro nuevo: agregarlo al objeto que devuelve esta
  función.**
- `nikTabMemorySave(projectName)` / `nikTabMemoryRestore(projectName)` —
  guardar/aplicar. Restauración **instantánea, sin animación**.
  **Para aplicar un parámetro nuevo: sumar su lógica de restore acá.**
- `nikTabMemoryResetRenderCaches()` — limpia los arrays usados como gate
  de diff para forzar redraw completo contra el proyecto nuevo.
- **Único punto de enganche**: el handler de EXTSTATE
  `"active_project_name"` en `core/wwr-dispatch.js`.
- **`nikTabMemoryPendingRestore` + `nikTabMemoryApplyPending(id)`** —
  cubren el caso en que el proyecto de destino tiene *más* tracks que los
  que existen en el DOM al momento del restore. `nikTabMemorySnapshot()`/
  `nikTabMemoryRestore()` **no iteran por `nTrack`**, sino por
  `document.getElementsByClassName("trackRow2").length` (conteo real de
  shells ya presentes) — cualquier índice guardado por encima de ese
  conteo queda pendiente hasta que su shell se cree, en el punto exacto
  donde el contenido SVG de cada `trackRow2` se puebla por primera vez.
  **Para parámetros nuevos que dependan de shells todavía no creados,
  sumar su aplicación en ese mismo punto de enganche, no solo en
  `nikTabMemoryRestore()`.**
- **`markerScrollTop` es un caso especial**: a diferencia del resto (que
  viven en un elemento siempre presente y visible en el DOM), pertenece a
  un modal que se abre bajo demanda — el snapshot no puede leerse en vivo
  si el popup está cerrado (ver gotcha de `scrollTop` oculto, abajo).
  Detalle completo del fix en `remote_control_markers.md`.
- **`preMarkerBars` no persiste el estado expandido/colapsado del
  stepper** (decisión deliberada, "se usa una vez y se olvida") — solo el
  valor de N.
- **Pendiente, no bloqueante**: el scroll vertical de `#tracks` no se
  recuerda por proyecto — candidato natural para sumarse como clave
  nueva (`document.getElementById("tracks").scrollTop`).

## Gotchas confirmados (lecciones, no repetir)

- **Correr un ReaScript como acción hace parpadear brevemente el menú
  superior de REAPER** (cosmético, no corrompe Undo). Escala con la
  cantidad de `_RS` empaquetados en el mismo tick — por eso las lecturas
  de background van consolidadas en un solo script.
- **`wwr_req_recur` con el mismo intervalo se empaqueta en una sola
  request HTTP**, aunque estén registrados en llamadas separadas.
  Desfasar intervalos es la única forma de partir un bundle.
- **`SET/TRACK/x/B_SHOWINTCP/valor` no refresca el TCP visualmente** —
  salta `TrackList_AdjustWindows()`. Fix: `Nik_TrackVis_Refresh.lua`.
- **Sumar una key nueva a `Nik_RemoteState_Poll.lua` no alcanza**:
  también hay que agregar su `GET/EXTSTATE/NikRemote/<key>` a
  `NIK_SLOW_POLL` en `config.js`.
- **`TimeMap_QNToMeasures` puede resolver al compás anterior** en
  markers que caen una fracción de float antes del downbeat real. Fix:
  sumar un épsilon chico (`+1e-6` QN) antes de convertir.
- **Estado de UI heredado entre proyectos (tabs)**: los arrays de
  `core/state.js` son globales, indexados por número de track — sin
  reset explícito, contaminan al track de mismo índice del proyecto
  nuevo. Resuelto con `core/tab-ui-memory.js`.
- **Ids de `<linearGradient>` duplicados en templates SVG clonados por
  track**: el navegador resuelve `fill="url(#id)"` contra la **primera**
  ocurrencia de ese id en el documento — si ese track queda oculto
  (`display:none`), todos los clones que dependían de esa definición
  pierden el fill. Fix: `nikUniquifyGradientIds(cloneRoot, suffix)`,
  llamada una vez por clon con el índice del track como sufijo. Extensión
  del mismo problema, otra causa: assets SVG *nuevos* que no son
  templates clonados por track sino instancias por popup (ej. el knob de
  fader, más de una instancia posible en la misma página) — usar un
  contador incremental como sufijo de `id` de gradiente al crear cada
  instancia.
- **El propio wrapper de template (`id="trackRow2Svg"`, ídem
  `trackRow1Svg`/`trackSendSvg`) también se duplica al clonar**, y como
  `getElementById()` devuelve el primer match en orden de documento, un
  clon insertado antes que la plantilla original pasa a ser lo que
  devuelve cualquier `getElementById()` posterior. Fix: `removeAttribute
  ("id")` inmediatamente después de cada `cloneNode(true)`, antes de
  insertarlo. **Regla general: todo `cloneNode(true)` de un elemento con
  `id` debe limpiar ese `id` antes de insertar el clon**, salvo que vaya
  a reemplazar por completo al original (ver también `01_CONVENCIONES.md`).
- **No asumir que todo `wwr_onreply` sigue el patrón `if (elemento)
  {...}`** — verificar caso por caso antes de sacar markup referenciado
  desde `wwr-dispatch.js`.
- **`scrollTop` de un elemento oculto (`display:none` propio o de un
  ancestro) siempre lee `0`** por spec CSSOM View, aunque exista una
  posición de scroll real pendiente de restaurar. Hay que leerlo mientras
  está visible, o guardarlo en el momento exacto en que se oculta — no en
  un snapshot genérico posterior. Aplica a cualquier modal que persista
  su propio scroll.
- **`position:sticky` no saca al elemento del flujo de scroll de su
  contenedor** — un fade `sticky` hijo directo de un panel que scrollea
  suma su propio alto al `scrollHeight` para siempre, rompiendo cualquier
  chequeo de "cuánto falta para el final". Fix general: separar
  "contenedor que se ve" (fijo) de "contenedor que scrollea"
  (`overflow-y:auto`, único), con el fade en `position:absolute` sobre el
  panel exterior. Aplica a cualquier overlay/fade sobre lista
  scrolleable.
- **`min-width` no alinea texto left-aligned entre filas** — solo evita
  que el elemento se achique, no fija dónde arranca el texto. Para
  columnas alineadas hace falta ancho fijo + `text-align`, o spans con
  anchos propios.
- **`<input type="range">` rotado con `transform:rotate(-90deg)`**: el
  thumb custom necesita `-webkit-appearance:none` tanto en el
  pseudo-elemento como en el `<input>` base — si falta en el base, Chrome
  acepta color/background del thumb pero ignora su `width`/`height`.
- **Centrado de thumb custom contra el runnable-track**: `margin-top =
  (trackHeight - thumbHeight) / 2`, recalcular cada vez que cambia
  cualquiera de los dos — no se auto-ajustan entre sí.
- **Desalineo visual entre un slider y controles fijos alrededor no es
  necesariamente bug de CSS** — si el valor actual no coincide con el
  punto medio matemático del rango (`(min+max)/2`), el thumb se ve
  corrido de ese centro por diseño. Confirmar el rango/default antes de
  sospechar de la rotación/CSS.
- **Contra-escalado de íconos dentro de un grupo SVG con `scale`
  no-uniforme**: con `sx≠sy`, escalar el `<g>` completo distorsiona todo
  el contenido, íconos incluidos. Fix: envolver los `<path>` de ícono en
  un `<g>` hijo con `transform="translate(cx,cy) scale(1, sx/sy)
  translate(-cx,-cy)"` (cx,cy = centro del ícono en coordenadas locales)
  — cancela la distorsión relativa. Aplica a cualquier grupo SVG
  reescalado de forma no-uniforme con sub-elementos que deban mantener
  proporción.
- **Tap-highlight de Android/WebView (Fully Kiosk / Chromium)**: pinta un
  recuadro celeste translúcido por default en cualquier elemento tocable
  sin `-webkit-tap-highlight-color` explícito. Desactivado global en
  `styles.css` (`html, body` + `button, input`) — gotcha del entorno, no
  de una feature puntual.
- **`flex-basis: auto` (default) en un `<span>` flex con contenido de
  largo variable puede angostar a sus hermanos** — el ancho "hipotético"
  del algoritmo de flex se calcula sobre el contenido sin truncar;
  `overflow:hidden`/`text-overflow:ellipsis` son solo efectos de
  pintado, no achican ese cálculo. Fix: `flex:1 1 0` (básis fijo en 0)
  en el elemento de texto variable + `flex:0 0 auto` y
  `white-space:nowrap` en los vecinos de ancho fijo.

## Watchdog de "proyecto desconectado" (`core/init.js`)

`nikCheckProjectNameWatchdog()` compara `Date.now()` contra el timestamp
de la última respuesta recibida con `active_project_name`. Corre siempre,
vía su propio `setInterval` independiente del poll — única señal posible
de "REAPER cerró del todo". Al dispararse, resetea a `null`/placeholder
cualquier estado leído on-demand que dependa de una conexión viva (ej.
`nikPlayrateTempoMap`, ver `remote_control_faders.md`) — mismo criterio
en todos los casos, sin reintento activo mientras sigue desconectado.

## OptionsBar — Loop/Rec/Tracks armadas + Solo in front

`#transport_r3` (loop, tracks armadas, botón de record) se despliega o
colapsa con `nikToggleLoopRecSection()`, disparado desde `#buttonLoopRec`
— reemplaza al botón de Snap (sin uso en contexto remoto). Colapsado se
ve como línea fina de 4px (`#1a1a1a`), sin texto. Ícono recicla el
círculo rojo de record (`iconLoopRecOn`/`iconLoopRecOff`), estado
"prendido" con clase `.nikToggledOn`.
- `nikApplyLoopRecState(expanded)` — separado del toggle para que
  `tab-ui-memory.js` pueda aplicarlo directo (clave `loopRecExpanded`).
- Default: colapsado, tanto en tab nunca visto como al perder conexión.

**Solo in front** (5° botón, patrón B de arriba): Command ID nativo
`40745`, reemplaza a `ClipClear` (sin uso, mismo lugar/tamaño, sin tocar
el `viewBox`). Ícono spotlight con 3 elementos de `id` propio para cambiar
`fill` directo por JS: `iconSoloInFrontSource`, `iconSoloInFrontBeam`,
`iconSoloInFrontSpot`. Apagado `#808080`, prendido `#FFC107` (ámbar,
color nuevo, no pisa otro botón). Fondo del botón oscurecido con regla
propia:
```css
#buttonSoloInFront.nikToggledOn .iconBg { fill: #4a3a14; }
```
Deliberadamente **no** reutiliza la `.nikToggledOn` genérica de LoopRec
(rojo) — evita mezclar el lenguaje visual de "grabación" con el de
"solo". Variable `last_soloinfront` en `core/state.js`, mismo bloque que
`last_metronome`. Es preferencia **global de REAPER** (no per-track ni
per-proyecto), no pasa por `tab-ui-memory.js`.

## Selector de proyectos (tabs) — `modals/project-tabs/project-tabs.js`

Tap en `#nikActiveProjectName` abre un popup con los proyectos abiertos.

- **Lectura on-demand**, fuera de `Nik_RemoteState_Poll`:
  `ProjectTabs_common_logic.lua` enumera con `EnumProjects(i)`, compara
  contra `EnumProjects(-1)` (activo), escribe `NikRemote/project_tabs`
  como `"idx:nombre:esActivo;..."`, disparado solo al abrir el popup.
- **Selección**: tap en un ítem distinto al activo escribe
  `project_tabs_target_idx` y dispara `Nik_ProjectTabs_Select.lua`.
  `Nik_ProjectTabs_Select.lua` encadena `Main_OnCommand(40667, 0)`
  ("Transport: Stop, save all recorded media") **antes** de
  `SelectProjectInstance()` — resuelto del lado Lua (un solo lugar) en
  vez de duplicar el patrón que ya usan `tabPrev`/`tabNext` en JS. Tap en
  el activo solo cierra el popup.
- **Sin parpadeo al abrir**: cada ítem guarda `data-name` (nombre
  completo con extensión) además de `data-idx`/`data-active`; al abrir el
  popup se repinta el resaltado contra `nikCurrentProjectName` (ya fresco
  por el poll de fondo, 1000ms) antes de esperar la respuesta on-demand —
  no-opea sola en la primera apertura de la sesión (lista vacía).
- **Color**: activo `#00FF99`, resto `#A8A8A8` — **sin negrita**: el bold
  condicional en la fila activa generaba salto de layout entre filas, el
  color solo alcanza para diferenciar.
- **Display del nombre activo** (`#nikActiveProjectName`, en
  `nikTabBar`): el texto visible saca la extensión `.rpp`
  (`.replace(/\.rpp$/i, "")` aplicado solo sobre el `textContent`) —
  `nikCurrentProjectName` conserva el string completo con extensión.
  Trunca en una sola línea con `text-overflow:ellipsis` +
  `white-space:nowrap` (ver gotcha de `flex-basis` arriba).

## Transporte — toggle de formato de posición (long-tap en `#status`)

Long-tap sobre el readout de posición alterna entre `measures.beats`
(`tok[5]` de `TRANSPORT`) y `min:seg` (`nikFormatMinSec(tok[2])`) —
**sticky** (no hold-to-preview), **2 estados fijos, sin "auto"**: ignora
deliberadamente el ruler real de REAPER, así el comportamiento del remoto
es autónomo y predecible.

- `core/state.js`: `nikPositionDisplayMode` (`"measures"` | `"minsec"`),
  arranca en `"measures"`.
- `core/long-press.js` (genérico, touch+mouse, sin barra de progreso):
  `nikAttachLongPress(el, {ms, moveTolerance, onLongPress, onStart,
  onCancel})`. Marca `el._nikSuppressClick = true` al disparar.
- `core/init.js`: `nikStatusAreaClick(el)` — wrapper del `onclick` de
  `#status` que respeta `_nikSuppressClick` (si vino de un long tap, no
  dispara `prompt_seek()`). `nikTogglePositionDisplayMode()` — toggle
  simple. Registro de `nikAttachLongPress` sobre `#status` en `init()`.
- `core/wwr-dispatch.js`, case `TRANSPORT`: `if/else` sobre
  `nikPositionDisplayMode` reemplaza al auto-sniff anterior (basado en la
  forma de `tok[4]`).
- **Dato de protocolo reutilizable**: `TRANSPORT` siempre trae `tok[5]`
  (`measures.beats.hundredths`) y `tok[2]` (`position_seconds`) sin
  importar cómo esté seteado el ruler del proyecto — no hace falta leer
  `BEATPOS` ni sniffear el formato para tener ambas representaciones en
  cualquier feature futura.
- **Cleanup pendiente**: `statusPositionAr` (`core/state.js`) quedó sin
  uso tras este cambio, no se sacó para no tocar ese archivo de más.

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

## Funcionalidades activas (resumen)

| Función | Estado | Notas |
|---|---|---|
| Ciclar tabs (proyectos abiertos) | Cerrado | `EnumProjects` + wraparound |
| Selector de proyectos (popup de tabs) | Cerrado | Stop antes de cambiar (`40667`), sin parpadeo, sin bold |
| Semitonos ReaPitch (Stem Bus) | Cerrado | Ver `remote_control_faders.md` |
| Playrate + preserve pitch | Cerrado | BPM bidireccional sobre mapa de tempo variable, ver `remote_control_faders.md` |
| Fader vertical modular + knob SVG | Cerrado | `core/vertical-fader.js` + `core/fader-knob-svg.js`, ver `remote_control_faders.md` |
| Doble-tap fader → 0dB | Cerrado, bug menor abierto | Rebote ocasional post-reset — ver pendientes |
| Toggle de formato de posición (long-tap) | Cerrado | `core/long-press.js`, ver sección Transporte |
| Browser de markers | Cerrado | Rediseño, indicador+autoscroll, scroll persistente — ver `remote_control_markers.md` |
| Seek relativo "N compases antes" (popup markers) | Cerrado | Long-press por fila, ver `remote_control_markers.md` |
| Colores + traducción de markers (popup + transporte) | Cerrado | Fix de color `xN` (markerChainMap) — ver `remote_control_markers.md` |
| Compases por sección (popup markers) | Cerrado | `Nik_RemoteState_Poll` — ver `remote_control_markers.md` |
| Seeker de markers (`#nextPrev`), rediseño | Cerrado | Ver `remote_control_markers.md` |
| Nombre de proyecto activo (background) | Cerrado | + watchdog; display truncado (ellipsis, sin extensión `.rpp`) |
| Visibilidad de tracks en TCP (popup) | Cerrado | `modals/tracksvis/` |
| Indicador de color semitonos/playrate | Cerrado | `nikDeviationColor`/`nikLerpColor` |
| Achicar bloque play/pause/stop | Cerrado | `NIK_TRANSPORT_SCALE` en `config.js` |
| Memoria de UI por proyecto | Cerrado | `core/tab-ui-memory.js` — ver sección dedicada |
| Toggle Loop/Rec/Tracks armadas (`#optionsBar`) | Cerrado | Reemplaza a Snap — ver OptionsBar |
| Toggle Solo in front (`#optionsBar`) | Cerrado | `40745`, ver OptionsBar |
| Ids de gradiente/template únicos al clonar SVG | Cerrado | `nikUniquifyGradientIds()` + `removeAttribute("id")` — ver gotchas |

## Pendientes activos

- **Cambio de proyecto (abrir/cerrar) desde el remoto**: mismo patrón
  (script Lua lee `ExtState` con ruta, `Main_openProject`). No
  implementado.
- **Loop de sección**: `reaper.GoToRegion(proj, index, true)` + preferencia
  "Loop points linked to time selection". Requiere regiones (no solo
  markers) para las secciones.
- **Rebote ocasional del doble-tap de faders** — candidato: bloqueo por
  track individual (`mouseDownAr[id]`) en vez del flag global
  `mouseDown`.
- **Precisión del cálculo Playrate→BPM equivalente**: reportado como "a
  veces no muy preciso" *antes* del fix de mapa de tempo variable (ver
  `remote_control_faders.md`). Está centralizado en una sola función, así
  que un fix aplica a los dos displays (popup + readout principal) sin
  tocar dos lugares — a re-observar si reaparece, puede ya estar resuelto
  por el fix del mapa de tempo.
- **Metrónomo**: research de qué parámetros son controlables vía
  scripting además de on/off (volumen primario/secundario, ruteo de
  salida, click pattern) — pospuesto, sin sesión asignada.

## Limpieza pendiente (menor, no bloqueante)

- **Borrar `Nik_Playrate_ReadBaseTempo.lua` del repo** si sigue
  físicamente ahí — reemplazado por `Nik_Playrate_ReadTempoMap.lua`
  (ver `remote_control_faders.md`); el Command ID viejo
  (`playrateBaseTempoRead`) también debería salir de `config.js` si
  quedó.
- **`statusPositionAr`** (`core/state.js`) sin uso tras el toggle de
  formato de posición.
- **Migrar `marker-browser.js` a `core/long-press.js`** en vez de su
  propia implementación duplicada de long-press — solo si en algún
  momento se agrega soporte de barra de progreso al helper genérico.

## Convención de scripts (recordatorio, fuente de verdad en `01_CONVENCIONES.md`)
- Ejecutables: `Nik_<Dominio>_<Acción>.lua`. Módulos: `<Dominio>_common_logic.lua`
  (sin prefijo `Nik_`), cargados vía `dofile` con ruta resuelta desde el
  propio script — nunca `require`.
- Familia `NikRemote_*` preexistente no sigue el prefijo `Nik_` todavía —
  aplica solo a scripts nuevos, sin apuro de rename.
