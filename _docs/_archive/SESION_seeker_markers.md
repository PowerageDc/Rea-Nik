# Contexto para sesión nueva — Rediseño del seeker de markers (`#nextPrev`)

Doc liviano de arranque, no reemplaza a `features/remote_control.md`
(fuente de verdad del estado general del control remoto — este doc solo
trae el contexto puntual para no repetir el diagnóstico ya hecho).

## Modo de trabajo (recordatorio, igual que siempre)
- Resolver por pasos, esperando confirmación antes de avanzar.
- Advertir antes de escribir más de 300 líneas de código.
- Diffs en formato listo para buscar/copiar/pegar — código en el bloque,
  indicaciones fuera. **Excepción esperada en esta tarea puntual**: al ser
  un rediseño de coordenadas SVG interdependientes (mover un elemento
  obliga a recalcular otros), es probable que el bloque `#nextPrev`
  completo necesite regenerarse de una vez en vez de diffs parciales —
  confirmar este punto explícitamente antes de escribir código, no
  asumirlo.

## Objetivo
Dos pedidos fusionados en un mismo rediseño (mismo bloque, tocan las
mismas coordenadas):
1. **Sacar la visualización de regiones** del seeker — no hace falta
   verlas en este contexto.
2. **Comprimir el alto del bloque**, para ganar espacio vertical (el
   plan general es liberar alto para más tracks visibles + lugar para
   nuevos readouts/UI — mismo motivo que ya llevó a colapsar
   `#transport_r3` esta sesión pasada).
3. (Pendiente previo, fusionado acá) **Achicar horizontalmente** los
   botones prev/next.

## Por qué esto no es un cambio chico
El SVG `#nextPrev` tiene `viewBox="0 0 318.9 87.8"` **fijo**, y todo el
contenido está en coordenadas absolutas dentro de ese lienzo. Ocultar
elementos (`visibility:hidden` o sacarlos del DOM) **no reduce el alto
renderizado** — el contenedor sigue escalando el viewBox completo. Para
comprimir de verdad hace falta:
- Reducir el `viewBox` (o recalcular todas las coordenadas Y a un lienzo
  más chico).
- **`prevButton`/`nextButton` ocupan casi todo el alto actual** (de
  y≈5.6 a y≈83.5) — no se pueden dejar como están si se achica el
  viewBox; hay que reposicionarlos Y achicarlos (pedido 3, ya fusionado).
- `markerSecBg` (polígono de fondo) y `locTriangles` (chevrons arriba/
  abajo) también atraviesan casi todo el alto — revisar si siguen
  teniendo sentido con las nuevas proporciones o si cambian de forma.

## Ubicación en el código
- **HTML**: `nsaudio_remote_control.html`, bloque `<svg id="nextPrev">`
  dentro de un `<div onclick="nikMarkerAreaClick(event)">` (estaba en la
  línea 238 antes de esta sesión — puede haber corrido con los cambios
  de `#buttonLoopRec`, revalidar).
  - A eliminar: `#regionStrip` (rect) y los 4 grupos `#region1`-`#region4`
    (cada uno con stalk izq/der, rect redondeado, texto — mismo patrón
    repetido x4).
  - A conservar pero reposicionar: `#marker1`-`#marker3` (prev/actual/
    next marker, con sus textos `#prevMarkerName`/`#atMarkerName`/
    `#nextMarkerName`), `#markerStrip`, `#locTriangles`, `#dropMarker`.
  - A achicar + reposicionar: `#prevButton` (acción `40172`), `#nextButton`
    (acción `40173`).
- **JS — sin revisar todavía esta sesión**: `core/wwr-dispatch.js` parsea
  la respuesta de `MARKER;REGION` (pedida en `init()`, poll de 500ms) y
  llena los grupos `region1`-`region4`. Si se elimina el markup de
  regiones del HTML, **hay que revisar ese parser** — probablemente
  queda escribiendo sobre elementos que ya no existen (no debería romper
  nada gracias al patrón `if (elemento) {...}` documentado en
  `remote_control.md`, pero es código muerto a limpiar).
  - Optimización posible (no bloqueante): si ya no se usa nada de
    `REGION`, sacarlo del poll (`wwr_req_recur("MARKER;REGION", 500)` →
    `wwr_req_recur("MARKER", 500)` en `core/init.js`) — mismo criterio ya
    aplicado con `GET/1157` esta sesión.
- **Colores/texto de markers**: `nikResolveMarkerDisplay()` en
  `markers/markers.js`, consume `NIK_MARKER_COLOR_MAP` de `config.js` —
  no debería necesitar cambios, solo las coordenadas donde se pintan.

## Archivos a pedir al arrancar la sesión
- `nsaudio_remote_control.html` (actualizado, post cambios de hoy)
- Fragmento de `core/wwr-dispatch.js` que parsea `MARKER;REGION` y pinta
  `#nextPrev` (no revisado todavía — pedir completo si no se sabe acotar)
- `styles.css` (por si el contenedor del seeker tiene reglas propias)

## Estado del resto del control remoto (no relacionado, solo para orientarse)
Ver `features/remote_control.md` — sesión anterior cerró: memoria de
scroll de `#tracks` por tab, toggle de `#transport_r3` movido a
`#optionsBar` (reemplaza a Snap), limpieza de `snapState`/`buttonSnap`.
