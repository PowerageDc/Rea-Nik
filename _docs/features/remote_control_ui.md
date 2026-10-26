# Feature — Control Remoto Web: UI, estilos y popups

Capa de interfaz del control remoto: shell HTML, estilos, cómo se agrega un
popup, gotchas de CSS/SVG/DOM y los controles de la UI principal sin doc
propio. Índice y arquitectura general: `remote_control.md`. Lectura de
estado y dispatch: `remote_control_protocol.md`.

## 1. Shell y estilos

`nsaudio_remote_control.html` es shell puro: markup y `<script src>` en
orden, sin lógica de negocio inline.

**Inline vs clases en `styles.css`.** Un bloque de estilo repetido en más
de un elemento (los 6 botones de `nikCursorNav`, los 2 de `nikTabBar`) va
como clase, para no desalinear instancias al ajustar. El layout puntual y
cualquier valor que JS pise dinámicamente quedan inline.

Si una clase mezcla layout (flex, padding, tamaño) y apariencia
(background, color) y la apariencia va a variar por grupo, se separa en dos
clases combinables. Ejemplo: `.nikCursorNavBtn` (base) más
`.nikCursorNavEdge`, `.nikCursorNavWide` y `.nikCursorNavTight` (layout
por grupo).

**Paleta de popups** (Playrate, ReaPitch, marker-browser): blancos y
grises sobre negro.

| Valor | Uso |
|---|---|
| `#FFFFFF` | Readouts numéricos grandes |
| `#D0D0D0` | Títulos y labels |
| `#4A4A4A` | Líneas divisorias y bordes |
| `#EDEDED` | Texto del pill y del stepper de pre-marker |

Los valores están inline en cada `.html`; no hay clase compartida de
paleta. Un popup nuevo los replica a mano. Quedan en cyan a propósito el
indicador de "parado en marker" y el estado ON de toggles (por ejemplo
`#nikReaPitchEnableToggle`): se miran de refilón, no son readouts que se
sostienen la mirada.

## 2. Cómo agregar un popup

1. Crear `modals/<nombre>/<nombre>.html` y `<nombre>.js`.
2. Sumar la ruta del `.html` a `NIK_MODAL_FRAGMENTS` en `modal-loader.js`.
3. Sumar `<script src="modals/<nombre>/<nombre>.js">` en
   `nsaudio_remote_control.html`, después de `core/init.js`.

**Qué va en el JS del modal y qué en `core/`:** la lógica de dominio del
modal va en su JS, aunque toque un elemento fuera del modal (por ejemplo el
botón que lo abre). En `core/` queda solo lo usado por más de un modal y el
estado y dispatch central.

Las funciones de `wwr_onreply` que tocan elementos de un modal llevan
guard; ver `remote_control_protocol.md` §5.

## 3. Gotchas de CSS, SVG y DOM

- **Todo `cloneNode(true)` de un elemento con `id` limpia ese `id`
  (`removeAttribute("id")`) antes de insertar el clon**, salvo que
  reemplace por completo al original. La regla general y el motivo están
  en `01_CONVENCIONES.md` ("Clonar elementos DOM con `id`"). Caso de este
  proyecto: los wrappers de template `trackRow1Svg`, `trackRow2Svg` y
  `trackSendSvg` en `core/wwr-dispatch.js`.
- **Ids de `<linearGradient>` duplicados en templates SVG clonados por
  track:** el navegador resuelve `fill="url(#id)"` contra la primera
  ocurrencia del id en el documento. Si ese track queda oculto
  (`display:none`), todos los clones que dependían de esa definición
  pierden el fill. `nikUniquifyGradientIds(cloneRoot, suffix)` se llama
  una vez por clon, con el índice del track como sufijo. Los assets SVG que
  son instancias por popup, no templates por track (el knob de fader), usan
  un contador incremental como sufijo (`remote_control_faders.md` §2).
- **`position:sticky` no saca al elemento del flujo de scroll** de su
  contenedor: un fade `sticky` hijo directo de un panel que scrollea suma
  su alto al `scrollHeight` para siempre y rompe cualquier chequeo de
  "cuánto falta para el final". Se separa el contenedor que se ve (fijo)
  del que scrollea (`overflow-y:auto`, único), con el fade en
  `position:absolute` sobre el panel exterior. Aplica a cualquier overlay o
  fade sobre una lista scrolleable.
- **`min-width` no alinea texto left-aligned entre filas:** solo evita que
  el elemento se achique. Para columnas alineadas hacen falta ancho fijo y
  `text-align`, o spans con anchos propios.
- **`flex-basis: auto` en un `<span>` flex con contenido de largo
  variable puede angostar a sus hermanos:** el ancho hipotético del
  algoritmo se calcula sobre el contenido sin truncar, y
  `overflow:hidden` y `text-overflow:ellipsis` son solo efectos de pintado.
  Se usa `flex:1 1 0` en el elemento de texto variable, más
  `flex:0 0 auto` y `white-space:nowrap` en los vecinos de ancho fijo.
- **Contra-escalado de íconos dentro de un grupo SVG con `scale`
  no-uniforme:** con `sx≠sy`, escalar el `<g>` distorsiona también los
  íconos. Los `<path>` de ícono van en un `<g>` hijo con
  `transform="translate(cx,cy) scale(1, sx/sy) translate(-cx,-cy)"`
  (`cx,cy` = centro del ícono en coordenadas locales), que cancela la
  distorsión relativa.
- **Tap-highlight de Android/WebView (Fully Kiosk):** pinta un recuadro
  celeste translúcido en todo elemento tocable sin
  `-webkit-tap-highlight-color` explícito. Está desactivado global en
  `styles.css` (`html, body` y `button, input`).
- **`:hover` queda pegado en táctil tras un toque:** el overlay de
  `.button:hover .mouseover` seguía sobre el botón recién apagado y su
  letra se veía lavada. La regla de hover va dentro de
  `@media (hover: hover)`, para cualquier efecto de hover de la UI.

## 4. OptionsBar

**Loop, tracks armadas y record** (`#transport_r3`): se despliega o
colapsa con `nikToggleLoopRecSection()`, disparado desde `#buttonLoopRec`.
Colapsado es una línea fina de 4px (`#1a1a1a`), sin texto. El ícono usa el
círculo rojo de record (`iconLoopRecOn`, `iconLoopRecOff`) y el estado
prendido lleva la clase `.nikToggledOn`.

- `nikApplyLoopRecState(expanded)` está separado del toggle para que
  `tab-ui-memory.js` lo aplique directo (clave `loopRecExpanded`, ver
  `remote_control_projects.md` §1).
- Default: colapsado, tanto en un tab nunca visto como al perder conexión.

**Solo in front** (5° botón, patrón B de `remote_control_protocol.md` §2):
Command ID nativo `40745`. El ícono es un spotlight con tres elementos de
`id` propio, para cambiar `fill` directo por JS: `iconSoloInFrontSource`,
`iconSoloInFrontBeam` e `iconSoloInFrontSpot`. Apagado `#808080`, prendido
`#FFC107` (ámbar). El fondo del botón se oscurece con una regla propia:

```css
#buttonSoloInFront.nikToggledOn .iconBg { fill: #4a3a14; }
```

No reutiliza la `.nikToggledOn` genérica de LoopRec (rojo) para no mezclar
el lenguaje visual de "grabación" con el de "solo". La variable
`last_soloinfront` está en `core/state.js`, junto a `last_metronome`. Es
una preferencia global de REAPER (ni por track ni por proyecto), así que no
pasa por `tab-ui-memory.js`.

## 5. Formato de posición del transporte (long-tap en `#status`)

Un long-tap sobre el readout de posición alterna entre `measures.beats`
(`tok[5]` de `TRANSPORT`) y `min:seg` (`nikFormatMinSec(tok[2])`). Es
sticky, con 2 estados fijos y sin modo "auto": ignora el ruler real de
REAPER, así el comportamiento es autónomo y predecible. Los campos de
`TRANSPORT` que lo habilitan: `remote_control_protocol.md` §6.

- `core/state.js`: `nikPositionDisplayMode` (`"measures"` | `"minsec"`),
  arranca en `"measures"`.
- `core/long-press.js` (genérico, touch y mouse, sin barra de progreso):
  `nikAttachLongPress(el, {ms, moveTolerance, onLongPress, onStart,
  onCancel})`. Al disparar marca `el._nikSuppressClick = true`.
- `core/init.js`: `nikStatusAreaClick(el)` envuelve el `onclick` de
  `#status` y respeta `_nikSuppressClick` (si vino de un long tap, no
  dispara `prompt_seek()`). `nikTogglePositionDisplayMode()` hace el
  toggle. El registro de `nikAttachLongPress` sobre `#status` está en
  `init()`.
- `core/wwr-dispatch.js`, case `TRANSPORT`: un `if/else` sobre
  `nikPositionDisplayMode` elige qué mostrar.

## 6. Visibilidad de tracks en TCP (`modals/tracksvis/tracksvis.js`)

Lee los datos que ya están en memoria; no pide nada al abrir.

- **Entrada:** `trackNamesAr`, `trackFlagsAr` (bit `512` = oculto en TCP,
  bit `4` = tiene FX) y `trackColoursAr`, llenados por el poll recurrente
  de `TRACK`.
- **Aplicar:** solo los tracks que cambiaron respecto del snapshot tomado
  al abrir disparan `SET/TRACK/x/B_SHOWINTCP/valor`, seguido de
  `SET/UNDO` y `Nik_TrackVis_Refresh.lua` (el motivo del refresco está en
  `remote_control_protocol.md` §7).
- **Trigger:** `tracksVisButton` en la UI principal.

## 7. Pendientes

- **`manifest.json` e íconos para PWA instalable:** el HTML referencia
  `manifest.json` al boot y el archivo no existe (404 sin impacto
  funcional). `sw.js` y `apple-touch-icon` tampoco tienen efecto hoy.
- **Rebote ocasional del doble-tap de faders de volumen** tras el reset a
  0 dB. Candidato: bloqueo por track individual (`mouseDownAr[id]`) en vez
  del flag global `mouseDown` en `core/faders.js`.
- **Metrónomo:** investigar qué parámetros son controlables por scripting
  además de on/off (volumen primario y secundario, ruteo de salida, click
  pattern).
- **`statusPositionAr`** (`core/state.js`) sin uso: borrar.