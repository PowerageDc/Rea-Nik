# Sub-feature — Markers (Control Remoto Web)

Doc de dominio, referenciado desde `remote_control.md` (tabla de
funcionalidades). Cubre: seeker de markers sobre el transporte, popup de
markers completo, colores/traducción de nombres, compases por sección,
seek relativo "N compases antes". Gotchas transversales (CSS de listas
scrolleables, `scrollTop` oculto, etc.) viven en el doc master — acá solo
lo específico de este dominio.

## Seeker de markers (`#nextPrev`)

Rediseño cerrado: `viewBox` `0 0 318.9 87.8` → `0 0 266 36` — sin
regiones, alto comprimido a padding + texto + badge + padding
(3 / 14.6 / 15 / 3.4).

- Sacados del HTML: `#regionStrip`, `#region1`-`#region4`,
  `#locTriangles`, los 3 `markerStalk`. `#markerSecBg` conserva solo la
  muesca central (indicador del marker actual), recalculada al nuevo
  alto y ancho.
- `#prevButton`/`#nextButton`: los paths (pill + gradiente `mrg1`/`mrg2`)
  **no se redibujaron** — se reposicionan/escalan con
  `transform="translate(tx,ty) scale(sx,sy)"` sobre el `<g>` completo. El
  bbox de referencia para calcular `sx`/`sy`/`tx`/`ty` sale del path de
  **relleno** (`fill="#1A1A1A"`), no del `shadow` (el shadow sobresale
  más abajo por el offset de sombra e infla el bbox). El contra-escalado
  de íconos dentro de estos botones sigue el patrón general documentado
  en `remote_control.md` (gotchas → grupo SVG con `scale` no-uniforme).
- Markers extremos (prev/next) separados simétricamente del centro
  (antes ±56.85, ahora ±62) + área de texto ensanchada (56.8→62 cada una)
  para nombres largos.

### Fix: color de markers `xN` en el seeker

**Síntoma:** un marker `xN` (cadena, hereda color del último marker
categorizado anterior) se mostraba gris cuando ese marker "ancla" no
estaba entre los 3 markers visibles (prev/this/next).

**Causa:** `nikTransportChainState = {color:null, step:0}` se reseteaba
en cada redraw y solo se resolvían los 3 markers visibles, en orden — si
el ancla quedaba fuera de esa ventana, el `chainState.color` nunca se
seteaba a tiempo.

**Fix:** en `core/wwr-dispatch.js`, dentro del bloque `if ((pos != newPos
|| mrMapAr.length != newMrMapLength) && nextPrevSvg)`, se resuelve **toda
la timeline de markers una sola vez** por redraw (recorriendo `mrMapAr`
ya ordenado) armando `markerChainMap[markerId] → {displayName,
resolvedColor}`. prev/this/next consultan ese mapa en vez de llamar a
`nikResolveMarkerDisplay()` directo. El popup de markers **no sufría este
bug** — ya recorre `g_markers` completo en orden al armar la lista.
`markers.js`/`config.js` no se tocaron.

## Colores y traducción de markers (`NIK_MARKER_COLOR_MAP`, en `config.js`)

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
  aclarando hacia blanco un paso fijo por eslabón sucesivo. Ver fix de
  color arriba (seeker) — el popup nunca tuvo este bug.
- Colores auditados con contraste WCAG AA (≥4.5:1) contra `#1a1a1a`.

En los **indicadores de transporte** (prev/actual/next), mismo
diccionario pero con `chainState` propio e independiente por redibujo
(no comparte estado con el popup). Colorea tanto el fondo del badge como
el texto. Casos HOME/END resetean el `fill` a gris explícitamente.

## Compases por sección

`MarkerBars_common_logic.lua` calcula, para cada marker, cuántos compases
hay hasta el siguiente — vía `TimeMap2_timeToQN` + `TimeMap_QNToMeasures`
(ver gotcha de precisión del épsilon en `remote_control.md`). Escribe
`NikRemote/marker_bars`, agregado al poll consolidado. Mismo módulo
expone `find_marker_pos(proj, markerId)` (agregado para el seek relativo,
ver abajo).

## Popup de markers (`modals/marker-browser/marker-browser.js`)

### Diseño visual

- **Filas**: dos líneas apiladas — nombre del marker arriba (1.22em,
  weight 600), metadata (tiempo + compases) abajo, más chica y en gris.
- **Separadores**: `#3A3A3A` (antes `#262626`, sin contraste suficiente
  sobre `#1a1a1a`).
- **Paleta**: alineada a la neutra general del proyecto (ver
  `remote_control.md` → "Paleta de popups") — `#D0D0D0` (título/label),
  `#4A4A4A` (línea/borde). El cyan del indicador de "parado en marker"
  (borde izquierdo + fondo) y el de la barra de long-press quedaron sin
  tocar a propósito.
- **Metadata tiempo + compases**: anchos fijos + `text-align:right` en
  los valores numéricos (`min-width` no alcanza para alinear texto
  left-aligned entre filas — ver gotcha general). Formato cambiado de
  `"Nc"` a `"Compases: N"` (label `#9A9A9A`, número `#C4C4C4` negrita).
  Separador `|` como **span propio** dentro del flex de `posSpan` (no
  texto concatenado — rompía centrado/baseline/color), color `#5A5A5A`.
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
re-centrar de más). La función tiene un parámetro `skipAutoScroll` sin
ningún caller hoy que lo pase en `true` — se dejó en la firma por si hace
falta a futuro un open "silencioso".

### Scroll persistente por proyecto (tab)

Integrado a `core/tab-ui-memory.js` con la key `markerScrollTop` (mismo
mecanismo genérico que `scrollTop` de tracks, `expandedTracks`, etc. —
ver `remote_control.md`).

- **Save**: `nikMarkerBrowserSaveScroll()`, llamada tanto al cerrar el
  popup (`nikCloseMarkerBrowser()`) como en el snapshot de cambio de tab
  — hace falta en ambos puntos, cerrar/reabrir en la misma tab también
  necesita persistir.
- **Root cause del bug de snapshot en cambio de tab**: `scrollTop` de un
  elemento oculto siempre lee `0` (ver gotcha general en
  `remote_control.md`) — el popup casi siempre está cerrado en el
  momento del cambio de tab, así que el snapshot pisaba sistemáticamente
  el valor bueno con `0`. Fix: en `nikTabMemorySnapshot()`, solo leer
  `scrollTop` en vivo si `nikMarkerBrowserOverlay.style.display ==
  "flex"` (visible); si no, conservar el valor ya persistido para ese
  proyecto en vez de asumir `0`.
- **Restore**: no puede pasar en el cambio de tab (la lista se arma
  recién en `nikOpenMarkerBrowser()`) — se lee
  `nikTabUiMemory[nikCurrentProjectName].markerScrollTop` ahí mismo.
- **UX del marker actual fuera del scroll restaurado**: resuelto sin
  código nuevo — al abrir, se restaura el scroll guardado y *después* se
  llama a `nikMarkerBrowserHighlightCurrent()` sin `skipAutoScroll`; si
  el marker actual ya cae dentro del scroll restaurado no pasa nada, si
  no, el autoscroll lo trae a la vista.
- **Confirmado en uso real**: testeado con lista larga (sticky header +
  fades) y con persistencia de scroll entre tabs — anda bien.

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
- **Paleta final**: unificada a la neutra general del proyecto
  (`#D0D0D0`/`#4A4A4A`, ver `remote_control.md`) con `#EDEDED` para el
  número — la propuesta original de esta feature (`#4A8C99` de borde de
  acento, `#A8A8A8` de caption) **no prevaleció**, quedó descartada al
  unificar paleta con el resto de los popups en una sesión posterior.
- **Persistencia de N por proyecto/tab**: key `preMarkerBars` en
  `tab-ui-memory.js`, default `2`. El estado expandido/colapsado del
  stepper **no** persiste (deliberado, "se usa una vez y se olvida").
- **Long-press por fila** (`nikAttachMarkerLongPress`, implementación
  propia del popup — no usa `core/long-press.js`, ver arquitectura en
  `remote_control.md`): umbral 450ms (gesto pre-entrenado, default de
  Android/iOS), tolerancia de movimiento 10px, barra de progreso animada
  vía CSS `transition` de `width` (sin JS de por medio). Tap corto sigue
  igual que siempre: seek directo al marker (`SET/POS_STR/m<id>`,
  nativo, sin Lua).
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
- **Script nuevo**: `RemoteControl/Nik_Markers_SeekRelative.lua` — lee
  `preseek_marker_id`/`preseek_bars` de ExtState, usa `find_marker_pos` +
  `41043` (N veces) + `SetEditCurPos` en dos pasos.
- **Command ID confirmado**: `_RS4a5dc1b0b6e91880cf9f2d469c1cb0bad2bc87b2`
  — entrada `preMarkerSeek` en `NIK_LUA_COMMANDS` (`config.js`).

## Gotchas específicos de este dominio

- **`id` obsoleto en JS tras un rediseño de HTML**: al pasar del layout
  en fila única (`nikPreMarkerBarsLabel`) al apilado
  (`nikPreMarkerBarsNumber`/`nikPreMarkerBarsCaption`), la función JS se
  quedó buscando el `id` viejo — el guard `if (label) {...}` fallaba en
  silencio (elemento no existe, sin error en consola) y la función no
  actualizaba nada visualmente aunque el estado sí cambiaba por detrás.
  Recordatorio: estos guards, aunque defensivos y necesarios, pueden
  esconder desincronizaciones HTML↔JS durante iteración rápida de
  diseño — confirmar el `id` real tras cada rediseño de markup.
- `pointer-events:none` obligatorio en los fades de scroll (ver arriba) —
  sin eso tapan tap/long-press de la última fila visible.
- El resto de gotchas de este dominio (`position:sticky` +
  `scrollHeight`, `scrollTop` de elemento oculto, `min-width` no alinea
  texto) son generales y ya viven en `remote_control.md` — se activaron
  primero acá pero aplican a cualquier lista scrolleable futura.

## Funciones/variables de referencia

| Nombre | Archivo | Qué hace |
|---|---|---|
| `markerChainMap` (local) | `wwr-dispatch.js` | Mapa id→display resuelto para toda la timeline, por redraw del seeker |
| `nikMarkerBrowserSorted` | `marker-browser.js` | Lista de markers ordenada por tiempo, global al abrir el popup |
| `nikMarkerBrowserCurrentId` | `marker-browser.js` | Id del marker "actual" resuelto la última vez, gatea repintados |
| `nikMarkerBrowserFindCurrentId(pos)` | `marker-browser.js` | Resuelve qué marker corresponde a una posición dada |
| `nikMarkerBrowserHighlightCurrent(skipAutoScroll)` | `marker-browser.js` | Pinta el marker actual + dispara autoscroll (sin caller que pase `true` hoy) |
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

## Pendiente / no probado

- N=8 en secciones de compases muy cortos o con cambios de time
  signature densos cerca del marker elegido — no testeado explícitamente,
  solo el caso general.
- Uso bajo el issue ya conocido de freezes correlacionados con WiFi en
  sala de ensayo — no debería interactuar con este feature, pero no
  probado bajo esas condiciones.
