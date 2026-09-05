# IMPL — Seeker de markers + Popup de markers (colores, indicador de posición, rediseño, scroll persistente)

Doc transitorio de sesión. No reemplaza a `remote_control.md` — se cotejará
junto con otros `IMPL_*.md` en una conversación aparte para actualizar ese
doc de forma consolidada.

## Pendientes que dispararon la sesión (no documentados en remote_control.md)

1. Markers grises (`xN`) en el seeker de arriba del transporte, cuando el
   marker que le da color no está en el trío visible (prev/this/next).
2. Indicación visual de "parado en marker" en el popup de markers,
   incluyendo el caso de estar entre ese marker y el próximo, actualizado
   en tiempo real si el popup está abierto y la reproducción cruza un
   marker nuevo.
3. (Quedó sin resolver esta sesión, no se llegó a tocar: long-tap
   Minutos/Segundos en el seeker de posición.)

Sobre la marcha, con el flujo más cerrado, surgieron y se resolvieron
además: rediseño visual del popup de markers, y persistencia del scroll de
la lista del popup por proyecto (tab).

---

## 1. Color de markers `xN` en el seeker — causa raíz y fix

**Síntoma:** un marker `xN` (cadena, hereda color del último marker
categorizado anterior) se mostraba gris en el seeker cuando ese marker
"ancla" no estaba entre los 3 markers visibles (prev/this/next).

**Causa:** `nikTransportChainState = { color: null, step: 0 }` se
reseteaba en cada redraw y solo se llamaba `nikResolveMarkerDisplay()` para
los 3 markers visibles, en orden. Si el ancla quedaba fuera de esa ventana
de 3, `chainState.color` nunca se seteaba antes de llegar al `xN`.

**Fix:** en vez de resolver prev/this/next con un chainState que arranca
vacío, se resuelve **toda la timeline de markers una sola vez** por redraw
(recorriendo `mrMapAr`, ya ordenado por tiempo) armando un mapa
`markerChainMap[markerId] → {displayName, resolvedColor}`. prev/this/next
pasan a consultar ese mapa en vez de llamar a `nikResolveMarkerDisplay()`
directamente.

- **Archivo:** `core/wwr-dispatch.js`, dentro del bloque
  `if ((pos != newPos || mrMapAr.length != newMrMapLength) && nextPrevSvg)`.
- El popup de markers (`marker-browser.js`) **no sufría este bug** — ya
  recorre `g_markers` completo en orden al armar la lista, así que su
  chainState siempre tiene el ancla disponible.
- `markers.js` / `config.js` no se tocaron — `nikResolveMarkerDisplay()`
  queda igual, solo cambia quién y cuántas veces se lo llama.

---

## 2. Indicador "parado en marker" en el popup + tiempo real

**Criterio de "parado en marker":** el marker cuyo tiempo es el último
`<=` a la posición actual (no exige igualdad exacta) — cubre en un solo
criterio tanto estar exactamente en el marker como estar entre ese marker
y el próximo.

**Implementación** (`modals/marker-browser/marker-browser.js`):
- `nikMarkerBrowserSorted`: la lista ordenada por tiempo se guarda como
  global al abrir el popup (antes se armaba localmente y se descartaba),
  para no tener que re-sortear en cada tick.
- `nikMarkerBrowserFindCurrentId(pos)`: recorre `nikMarkerBrowserSorted` y
  devuelve el id del marker que cumple el criterio de arriba.
- `nikMarkerBrowserHighlightCurrent()`: compara contra
  `nikMarkerBrowserCurrentId` (solo toca el DOM si cambió), pinta borde
  izquierdo + fondo del item actual, y (ver sección 3) dispara autoscroll.
  **Es seguro llamarla siempre**, esté el popup abierto o cerrado — chequea
  `overlay.style.display` al principio y no hace nada si está cerrado.

**Gancho de tiempo real:** en vez de sumar un listener/timer nuevo, se
llama a `nikMarkerBrowserHighlightCurrent()` desde el mismo bloque de
`core/wwr-dispatch.js` que ya recalcula prev/this/next del seeker (gated
por `pos != newPos`) — reutiliza ese debounce existente.

---

## 3. Auto-scroll en vivo siguiendo el marker actual

Extensión de `nikMarkerBrowserHighlightCurrent()`: cuando el marker actual
cambia, si el item correspondiente no está dentro del viewport del
scroller (`#nikMarkerBrowserScroll`), se centra con
`scrollIntoView({block:"center", behavior:"smooth"})`. Chequeo previo de
visibilidad para no re-centrar de más si el item ya se ve.

La función quedó con un parámetro `skipAutoScroll` (usado brevemente
durante el desarrollo del punto 5 y luego retirado de los callers — hoy no
tiene ningún caller que lo pase en `true`, pero se dejó en la firma por si
hace falta a futuro un open "silencioso").

---

## 4. Rediseño visual del popup de markers

Cambios en `modals/marker-browser/marker-browser.html` y
`modals/marker-browser/marker-browser.js`:

- **Filas de la lista:** de una sola línea (`space-between`) a dos líneas
  apiladas — nombre del marker arriba (1.22em, weight 600), metadata
  (tiempo + compases) abajo, más chica y en gris.
- **Separadores:** `#262626` sobre fondo `#1a1a1a` no hacía contraste
  suficiente → `#3A3A3A`.
- **Espaciado header/lista:** más padding abajo del header + margin-top en
  el contenedor de la lista, para evitar clicks accidentales en el primer
  marker al tocar el pill de compases. Padding del pill también se agrandó
  un poco.
- **Paleta de color:** el cyan (`#00D0FF`) del header/línea/borde del pill
  distraía con tantos colores de marker ya en juego → se alineó con la
  paleta neutra que ya usa `playrate.html` (`#D0D0D0` label, `#4A4A4A`
  línea y borde). El cyan del indicador de "parado en marker" (borde
  izquierdo + fondo) y el de la barra de long-press **no se tocaron**
  (pedido puntual era solo header/línea/pill).
- **Metadata de tiempo + compases:**
  - Bamboleo de la columna de compases: `min-width` no alinea texto
    left-aligned — fija el ancho mínimo pero no el punto de arranque del
    texto. Se resolvió con anchos fijos + `text-align:right` en los
    valores numéricos (no en el tiempo, que quedó left-aligned pegado al
    margen del nombre de arriba — un intento de alinearlo a la derecha
    también rompió esa lectura visual y se revirtió).
  - Display cambiado de `"Nc"` a `"Compases: N"` (con label en gris medio
    `#9A9A9A`, número en `#C4C4C4` negrita) — el formato corto generaba
    confusión visual con el número de sección en el nombre de arriba.
  - Separador `|` entre tiempo y compases: implementado como **span propio**
    dentro del flex de `posSpan` (no como texto concatenado en el label —
    eso rompía el centrado y heredaba color/baseline equivocados). Color
    `#5A5A5A`, más oscuro que el label para no competir con los datos.
- **Fade de scroll** (`#nikMarkerScrollFade` / `#nikMarkerScrollFadeTop`):
  ya existía el de abajo; se sumó el de arriba (ausente hasta ahora) y se
  calibraron ambos a simple vista con varias iteraciones:
  - El fade de arriba se comía el borde del header al principio — el
    `bottom` negativo no compensaba el grosor del borde (2px), quedaba
    pintado encima de la línea en vez de arrancar debajo. Se corrigió el
    offset.
  - Balance final: fade de abajo 28px de alto / opacidad pico 0.55; fade
    de arriba 20px / opacidad pico 0.75 — a igual opacidad, el más alto
    "pesa" más visualmente por cubrir más área, así que quedaron con
    valores distintos a propósito para verse parejos.

---

## 5. Scroll de la lista persistente por proyecto (tab)

Se integró al mecanismo ya existente en `core/tab-ui-memory.js`
(`nikTabUiMemory[projectName]`, snapshot/save/restore enganchado al
handler de `active_project_name` en `wwr-dispatch.js`) sumando una key
nueva, `markerScrollTop`, al objeto de snapshot — sin tocar el resto del
mecanismo genérico (mismo patrón que ya usa para `scrollTop` de tracks,
`expandedTracks`, `loopRecExpanded`, `preMarkerBars`).

**Complicación (a diferencia del resto de las keys de tab-ui-memory):**
el scroller de tracks vive siempre en el DOM y visible; el popup de
markers es un modal que se abre bajo demanda, así que:
- El *restore* no puede pasar en el momento del cambio de tab (la lista se
  arma recién en `nikOpenMarkerBrowser()`) — tiene que aplicarse ahí,
  leyendo `nikTabUiMemory[nikCurrentProjectName].markerScrollTop`.
- El *snapshot* (`nikTabMemorySnapshot()`, se llama en cada cambio de tab)
  necesitaba el valor del scroll del popup en ese momento — pero el popup
  normalmente está **cerrado** cuando cambiás de tab.

**Bugs encontrados en el camino (importante para no reintroducirlos):**

1. Primera versión solo guardaba en `nikTabMemorySave()` (cambio de tab).
   Cerrar y reabrir el popup **en la misma tab** siempre mostraba scroll
   en 0, porque nunca se guardaba en ese momento. → se agregó
   `nikMarkerBrowserSaveScroll()`, llamada también desde
   `nikCloseMarkerBrowser()`.

2. Con eso arreglado, el cambio de tab seguía perdiendo el valor. Causa:
   `nikTabMemorySnapshot()` leía `document.getElementById
   ("nikMarkerBrowserScroll").scrollTop` en vivo, y ese elemento **existe
   en el DOM aunque el popup esté oculto** (por eso un primer intento de
   fallback por "elemento no encontrado" no servía — el elemento sí se
   encuentra, el valor leído es el problema).

3. **Causa raíz real:** un elemento con `display:none` (o dentro de un
   ancestro con `display:none`) no tiene caja de layout, y por spec CSSOM
   View, leer `scrollTop` en ese estado devuelve `0` — independientemente
   de la posición de scroll "real" que el navegador vaya a restaurar
   cuando se vuelva a mostrar el elemento. Como el popup casi siempre está
   cerrado en el momento del cambio de tab, el snapshot pisaba
   sistemáticamente el valor bueno (guardado al cerrar) con `0`.
   → **Fix definitivo:** en `nikTabMemorySnapshot()`, solo leer
   `scrollTop` en vivo del popup si `nikMarkerBrowserOverlay.style.display
   == "flex"` (visible); si no, conservar el valor que ya estaba
   persistido para ese proyecto (`nikTabUiMemory[nikCurrentProjectName]
   .markerScrollTop`), en vez de asumir 0.

4. Caso final de UX: con el scroll restaurado, el marker actual podía
   quedar fuera de la vista restaurada (ej.: lista scrolleada al fondo,
   cursor movido al principio del tema, se abre el popup). Se resolvió
   **sin código nuevo**: al abrir, se restaura el scroll guardado y
   *después* se llama a `nikMarkerBrowserHighlightCurrent()` **sin**
   `skipAutoScroll` — si el marker actual ya cae dentro del scroll
   restaurado no pasa nada; si no, el autoscroll del punto 3 lo trae a la
   vista. El restore queda como punto de partida, no como algo forzado.

---

## Archivos tocados en esta sesión

- `core/wwr-dispatch.js` — fix de color xN (markerChainMap), gancho de
  `nikMarkerBrowserHighlightCurrent()`.
- `modals/marker-browser/marker-browser.js` — indicador de marker actual,
  autoscroll, rediseño de filas, guardado/restore de scroll por proyecto.
- `modals/marker-browser/marker-browser.html` — rediseño (espaciado,
  colores, fades de scroll top/bottom).
- `core/tab-ui-memory.js` — key nueva `markerScrollTop` en el snapshot de
  UI por proyecto.

## Funciones/variables nuevas

| Nombre | Archivo | Qué hace |
|---|---|---|
| `markerChainMap` (local) | `wwr-dispatch.js` | Mapa id→display resuelto para toda la timeline de markers, por redraw del seeker |
| `nikMarkerBrowserSorted` | `marker-browser.js` | Lista de markers ordenada por tiempo, guardada como global al abrir el popup |
| `nikMarkerBrowserCurrentId` | `marker-browser.js` | Id del marker "actual" resuelto la última vez, para gatear repintados |
| `nikMarkerBrowserFindCurrentId(pos)` | `marker-browser.js` | Resuelve qué marker corresponde a una posición dada |
| `nikMarkerBrowserHighlightCurrent(skipAutoScroll)` | `marker-browser.js` | Pinta el marker actual y dispara autoscroll si hace falta (sin caller hoy que pase `true`) |
| `nikMarkerBrowserSaveScroll()` | `marker-browser.js` | Persiste el scroll actual del popup en `nikTabUiMemory` (llamada al cerrar) |
| `markerScrollTop` | `tab-ui-memory.js` (key en el objeto de snapshot) | Scroll del popup de markers, por proyecto |

## Gotchas para tener presentes (candidatos a sumar a 01_CONVENCIONES.md o remote_control.md)

- **`scrollTop` de un elemento oculto siempre lee `0`**, aunque el
  elemento exista en el DOM y tenga una posición de scroll real pendiente
  de restaurar — hay que leerlo mientras está visible, o guardarlo en el
  momento en que se oculta (no después). Puede afectar a cualquier otro
  modal que quiera persistir su propio scroll a futuro (hoy solo aplica al
  popup de markers, pero el patrón es reutilizable).
- **`min-width` no alinea texto left-aligned entre filas** — solo evita
  que el elemento se achique, no fija dónde arranca el texto. Para
  columnas alineadas hace falta ancho fijo + `text-align`, o separar en
  spans con sus propios anchos.
- El popup de markers ya recorre la lista completa en orden al armarse —
  cualquier otro consumidor futuro de `nikResolveMarkerDisplay()` que solo
  procese una ventana acotada de markers (como hacía el seeker antes del
  fix) puede pisar el mismo bug de "ancla fuera de rango".

## Pendiente relacionado, no resuelto esta sesión

- Long-tap Minutos/Segundos en el seeker de posición (implementación
  existe en archivo transitorio/código aparte, no revisado todavía en esta
  sesión).
- Actualización de `remote_control.md` — se hará en conversación nueva,
  cotejando este doc con otros `IMPL_*.md`.
