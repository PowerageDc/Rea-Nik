# Sub-feature — Markers (Control Remoto Web)

Doc de dominio, referenciado desde `remote_control.md`. Cubre: seeker de
markers sobre el transporte, popup de markers completo, colores/traducción
de nombres, compases por sección, seek relativo "N compases antes".
Gotchas generales de CSS de listas scrolleables: `remote_control_ui.md`
§3. `scrollTop` de un elemento oculto: `remote_control_projects.md` §1.

## 1. Seeker de markers (`#nextPrev`)

`viewBox` `0 0 266 36`, sin regiones. El alto es padding + texto + badge +
padding (3 / 14.6 / 15 / 3.4).

- `#markerSecBg` contiene solo la muesca central (indicador del marker
  actual).
- `#prevButton`/`#nextButton`: los paths (pill + gradiente `mrg1`/`mrg2`)
  se reposicionan y escalan con `transform="translate(tx,ty) scale(sx,sy)"` 
  sobre el `<g>` completo. El bbox de referencia para calcular `sx`/`sy`/
  `tx`/`ty` sale del path de **relleno** (`fill="#1A1A1A"`), no del 
  `shadow` (el shadow sobresale más abajo por el offset de sombra e infla 
  el bbox). El contra-escalado de íconos dentro de estos botones sigue el 
  patrón general documentado en `remote_control_ui.md` §3 (grupo SVG con 
  `scale` no-uniforme).
- Markers extremos (prev/next) separados simétricamente del centro
  (±62), con un área de texto de 62 cada uno para nombres largos.

### Color de markers `xN` en el seeker

Un marker `xN` (cadena) hereda el color del último marker categorizado
anterior, que puede no estar entre los 3 visibles (prev/this/next). Por
eso, en `core/wwr-dispatch.js`, dentro del bloque `if ((pos != newPos ||
mrMapAr.length != newMrMapLength) && nextPrevSvg)`, se resuelve **toda la
timeline de markers una sola vez** por redraw (recorriendo `mrMapAr` ya
ordenado) y se arma `markerChainMap[markerId] → {displayName,
resolvedColor}`. prev/this/next consultan ese mapa en vez de llamar a
`nikResolveMarkerDisplay()` directo. El popup recorre `g_markers`
completo en orden al armar la lista, así que no necesita el mapa.

## 2. Colores y traducción de markers (`NIK_MARKER_COLOR_MAP`, en `config.js`)

Diccionario editable — fuente de verdad de colores por sección (ver
`01_CONVENCIONES.md` para nombres de sección). Cada categoría define
`label`, `color`, `tint` (reservado, sin uso hoy), `words` (formas
completas) y `abbrev` (formas abreviadas). Resolución compartida vía
`nikResolveMarkerDisplay()` en `markers/markers.js`, usado tanto por el
popup como por los indicadores de transporte.

- **Palabras completas** (`words`): match por *prefijo* sobre el nombre
  normalizado — solo cambia el color.
- **Abreviaturas** (`abbrev`): match *exacto* — cambia el color y además
  traduce el texto mostrado al `label` completo (+ número si tenía).
- **Cadena `x<número>`** (`NIK_MARKER_CHAIN_PATTERN`/`_STEP`): hereda el
  color del último marker categorizado encontrado antes en la lista,
  aclarando hacia blanco un paso fijo por eslabón sucesivo. En el seeker
  se resuelve con `markerChainMap` (§1); el popup no lo necesita.
- Colores auditados con contraste WCAG AA (≥4.5:1) contra `#1a1a1a`.

En los **indicadores de transporte** (prev/actual/next), mismo
diccionario pero con `chainState` propio e independiente por redibujo
(no comparte estado con el popup). Colorea tanto el fondo del badge como
el texto. Casos HOME/END resetean el `fill` a gris explícitamente.

## 3. Compases por sección

`MarkerBars_common_logic.lua` calcula, para cada marker, cuántos compases
hay hasta el siguiente — vía `TimeMap2_timeToQN` + `TimeMap_QNToMeasures`
(ver la precisión del épsilon abajo). Escribe `NikRemote/marker_bars`,
agregado al poll consolidado (`remote_control_protocol.md` §3). Mismo
módulo expone `find_marker_pos(proj, markerId)`, usado por el seek
relativo (§4).

**Precisión:** `TimeMap_QNToMeasures` puede resolver al compás anterior en
markers que caen una fracción de float antes del downbeat real. Se suma un
épsilon chico (`+1e-6` QN) antes de convertir.

## 4. Popup de markers (`modals/marker-browser/marker-browser.js`)

### Diseño visual

- **Filas**: dos líneas apiladas — nombre del marker arriba (1.22em,
  weight 600), metadata (tiempo + compases) abajo, más chica y en gris.
- **Separadores**: `#3A3A3A`.
- **Paleta**: la neutra de popups (`remote_control_ui.md` §1). El cyan
  del indicador de "parado en marker" (borde izquierdo + fondo) y el de la
  barra de long-press se conservan a propósito.
- **Metadata tiempo + compases**: anchos fijos + `text-align:right` en
  los valores numéricos (`min-width` no alcanza para alinear texto
  left-aligned entre filas, ver `remote_control_ui.md` §3). Formato
  `"Compases: N"` (label `#9A9A9A`, número `#C4C4C4` negrita).
  Separador `|` como **span propio** dentro del flex de `posSpan` (no
  texto concatenado — rompe centrado, baseline, y color), color `#5A5A5A`.
- **Fades de scroll** (`#nikMarkerScrollFade` / `#nikMarkerScrollFadeTop`):
  abajo 28px de alto / opacidad pico 0.55; arriba 20px / opacidad pico
  0.75 — valores distintos a propósito para verse parejos (el más alto
  "pesa" más visualmente por cubrir más área a igual opacidad). Requieren
  `pointer-events:none` — sin eso tapan el tap/long-press de la última
  fila visible.

### Indicador "parado en marker" + tiempo real

**Criterio:** el marker cuyo tiempo es el último `<=` a la posición
actual — cubre en un solo criterio estar exactamente en el marker o
estar entre ese marker y el próximo.

- `nikMarkerBrowserSorted` — lista ordenada por tiempo, guardada como
  global al abrir el popup (evita re-sortear en cada tick).
- `nikMarkerBrowserFindCurrentId(pos)` — resuelve el id según el criterio
  de arriba.
- `nikMarkerBrowserHighlightCurrent()` — compara contra
  `nikMarkerBrowserCurrentId` (solo toca el DOM si cambió), pinta borde
  izquierdo + fondo del ítem actual, dispara autoscroll (ver abajo). Es
  **segura de llamar siempre** (abierto o cerrado) — chequea
  `overlay.style.display` al principio y no-opea si está cerrado.
- **Gancho de tiempo real**: se llama desde el mismo bloque de
  `core/wwr-dispatch.js` que ya recalcula prev/this/next del seeker
  (gated por `pos != newPos`) — reutiliza ese debounce existente, sin
  listener/timer nuevo.

### Auto-scroll en vivo

Extensión de `nikMarkerBrowserHighlightCurrent()`: cuando el marker
actual cambia, si el ítem no está dentro del viewport del scroller
(`#nikMarkerBrowserScroll`), se centra con `scrollIntoView({block:
"center", behavior:"smooth"})` (con chequeo previo de visibilidad para no
re-centrar de más). El parámetro `skipAutoScroll` en `true` suprime el
autoscroll (open "silencioso").

### Scroll persistente por proyecto (tab)

Integrado a `core/tab-ui-memory.js` con la key `markerScrollTop` (mismo
mecanismo que el resto de las keys, ver `remote_control_projects.md` §1).

- **Save**: `nikMarkerBrowserSaveScroll()`, llamada tanto al cerrar el
  popup (`nikCloseMarkerBrowser()`) como en el snapshot de cambio de tab
  — hace falta en ambos puntos, cerrar/reabrir en la misma tab también
  necesita persistir.
- **Snapshot en cambio de tab**: `scrollTop` de un elemento oculto
  siempre lee `0` (`remote_control_projects.md` §1) y el popup casi
  siempre está cerrado en ese momento. Por eso `nikTabMemorySnapshot()`
  solo lee `scrollTop` en vivo si `nikMarkerBrowserOverlay.style.display
  == "flex"` (visible); si no, conserva el valor ya persistido para ese
  proyecto.
- **Restore**: no puede pasar en el cambio de tab (la lista se arma
  recién en `nikOpenMarkerBrowser()`) — se lee
  `nikTabUiMemory[nikCurrentProjectName].markerScrollTop` ahí mismo.
- **Marker actual fuera del scroll restaurado**: al abrir, se restaura el
  scroll guardado y *después* se llama a
  `nikMarkerBrowserHighlightCurrent()` sin `skipAutoScroll`; si el marker
  actual ya cae dentro del scroll restaurado no pasa nada, si no, el
  autoscroll lo trae a la vista.

### Seek relativo "N compases antes" (pre-marker)

Objetivo: long-press sobre una fila de marker → seek a N compases antes
de ese marker, mínimo de taps posible.

- **Header**: pill `"Nc"` a la derecha del título "Markers" (siempre
  visible, toca para expandir/colapsar) — reusa el mismo formato que ya
  usan los badges de compases por fila, doble función (readout + control
  de expandir). Al tocarla despliega un stepper apilado: número grande
  arriba (`#EDEDED`), caption abajo, y botones `−`/`+` en fila propia
  bien separados entre sí (para que el pulgar sobre el botón nunca tape
  el número).
- **Rango**: 1 a 8 compases, clamped en `nikPreMarkerBarsStep()`.
- **Paleta**: la neutra de popups (`remote_control_ui.md` §1), con
  `#EDEDED` para el número.
- **Persistencia de N por proyecto/tab**: key `preMarkerBars` en
  `tab-ui-memory.js`, default `2`. El estado expandido/colapsado del
  stepper **no** persiste (deliberado, "se usa una vez y se olvida").
- **Long-press por fila** (`nikAttachMarkerLongPress`, implementación
  propia del popup: no usa `core/long-press.js`, que no soporta barra de
  progreso, ver `remote_control_ui.md` §5): umbral 450ms (gesto 
  pre-entrenado, default de Android/iOS), tolerancia de movimiento 10px, 
  barra de progreso animada vía CSS `transition` de `width` (sin JS de 
  por medio). Tap corto sigue igual que siempre: seek directo al marker 
  (`SET/POS_STR/m<id>`, nativo, sin Lua).
- **Seek con acción nativa (`41043`, "Move edit cursor back one
  measure")** en vez de cálculo manual sobre `TimeMap` — más
  determinístico porque reusa la lógica de tempo/time-signature que
  REAPER ya resuelve internamente, sin depender de una convención de
  indexado (0/1-based) de `TimeMap_QNToMeasures` nunca confirmada
  empíricamente. Hasta 8 llamadas `Main_OnCommand` encadenadas —
  overhead despreciable (llamadas internas, sin render ni red).
- **`SetEditCurPos` en dos pasos**: primero posiciona el edit cursor en
  el marker sin tocar playback (`seekplay=false`), retrocede compases con
  `41043` (N veces), lee la posición final, y recién ahí hace el
  `SetEditCurPos` con `seekplay=true` que mueve la reproducción en vivo.
  Necesario porque `41043` mueve el edit cursor pero no garantiza que la
  reproducción salte ahí (depende de la preferencia "Link edit and play
  cursors while playing", no asumible activada).
- **Script**: `RemoteControl/Nik_Markers_SeekRelative.lua` — lee
  `preseek_marker_id`/`preseek_bars` de ExtState, usa `find_marker_pos` +
  `41043` (N veces) + `SetEditCurPos` en dos pasos.
- **Command ID**: entrada `preMarkerSeek` en `NIK_LUA_COMMANDS`
  (`config.js`, ver `remote_control_protocol.md` §8).

## 5. Gotchas específicos de este dominio

- Los guards `if (elemento)` pueden esconder un `id` obsoleto tras
  rediseñar el markup (en este popup: `nikPreMarkerBarsNumber` y
  `nikPreMarkerBarsCaption`): `remote_control_protocol.md` §5.
- Los gotchas generales de listas scrolleables (`position:sticky` y
  `scrollHeight`, `min-width` que no alinea texto) están en
  `remote_control_ui.md` §3; el de `scrollTop` de un elemento oculto, en
  `remote_control_projects.md` §1. El `pointer-events:none` de los fades
  está en §4, "Diseño visual".

## 6. Funciones/variables de referencia

| Nombre | Archivo | Qué hace |
|---|---|---|
| `markerChainMap` (local) | `wwr-dispatch.js` | Mapa id→display resuelto para toda la timeline, por redraw del seeker |
| `nikMarkerBrowserSorted` | `marker-browser.js` | Lista de markers ordenada por tiempo, global al abrir el popup |
| `nikMarkerBrowserCurrentId` | `marker-browser.js` | Id del marker "actual" resuelto la última vez, gatea repintados |
| `nikMarkerBrowserFindCurrentId(pos)` | `marker-browser.js` | Resuelve qué marker corresponde a una posición dada |
| `nikMarkerBrowserHighlightCurrent(skipAutoScroll)` | `marker-browser.js` | Pinta el marker actual + dispara autoscroll (`skipAutoScroll=true` lo suprime) |
| `nikMarkerBrowserSaveScroll()` | `marker-browser.js` | Persiste el scroll actual en `nikTabUiMemory` (al cerrar) |
| `nikUpdatePreMarkerBarsDisplay()` | `marker-browser.js` | Refresca el número/caption del stepper |
| `nikTogglePreMarkerStepper()` | `marker-browser.js` | Expande/colapsa el stepper de la pill "Nc" |
| `nikPreMarkerBarsStep(delta)` | `marker-browser.js` | Suma/resta N, clamp 1-8 |
| `nikFirePreMarkerSeek(markerId)` | `marker-browser.js` | Dispara el seek relativo (ExtState + `_RS`) |
| `nikAttachMarkerLongPress(el, ...)` | `marker-browser.js` | Long-press con barra de progreso, propio de este popup |
| `nikUpdateMarkerScrollFade()` | `marker-browser.js` | Muestra/oculta los fades según scroll |
| `find_marker_pos(proj, markerId)` | `MarkerBars_common_logic.lua` | Posición de un marker por id |
| `markerScrollTop` | `tab-ui-memory.js` (key) | Scroll del popup, por proyecto |
| `preMarkerBars` | `tab-ui-memory.js` (key) | Valor de N, por proyecto |

## 7. Pendiente / no probado

- N=8 en secciones de compases muy cortos o con cambios de time
  signature densos cerca del marker elegido — no testeado explícitamente,
  solo el caso general.
- Uso bajo el issue ya conocido de freezes correlacionados con WiFi en
  sala de ensayo — no debería interactuar con este feature, pero no
  probado bajo esas condiciones.
- **Loop de sección:** `reaper.GoToRegion(proj, index, true)` más la
  preferencia "Loop points linked to time selection". Requiere regiones
  (no solo markers) para las secciones.
- **Long-press propio del popup:** migrar `nikAttachMarkerLongPress` a
  `core/long-press.js`, solo si el helper genérico suma soporte de barra
  de progreso.
