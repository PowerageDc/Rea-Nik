# IMPL — Seek relativo "N compases antes" en popup de markers

Doc transitorio de sesión. Registra lo implementado, decisiones tomadas y
pendientes para la consolidación posterior en `remote_control.md` /
`01_CONVENCIONES.md`. Descartar este archivo una vez volcado.

Corresponde al **punto 3** de `PENDING_optionsbar_markers.md` (compases
pre-marker) — punto cerrado end-to-end en esta sesión.

## Contexto / objetivo original

Flujo pedido: reproduciendo un proyecto, con el mínimo de taps posible,
saltar a N compases antes de una sección determinada. Restricción
explícita: no relegar UX en una interfaz ya poblada (control remoto web).

## Estado final (implementado y probado end-to-end en REAPER)

- **Popup de markers, header rediseñado**: pill `"Nc"` a la derecha del
  título "Markers" (siempre visible, toca para expandir/colapsar). Al
  tocarla despliega un stepper apilado: número grande arriba, caption
  ("compases antes") debajo, y dos botones `−`/`+` bien separados entre sí
  en una fila propia (para que el pulgar sobre el botón nunca tape el
  número — problema del primer layout en fila única, corregido).
- **Rango de N**: 1 a 8 compases, clamped en `nikPreMarkerBarsStep()`.
- **Long-press sobre una fila de marker** (umbral 450ms — mismo valor que
  el long-press timeout default de Android/iOS, gesto "pre-entrenado"):
  dispara el seek a N compases antes de ese marker. Barra de progreso
  animada (CSS `transition` de `width`, sin JS de por medio) da feedback
  visual durante el hold. Tap corto (sin hold) sigue funcionando exacto
  igual que antes: seek directo al marker (`SET/POS_STR/m<id>`, nativo,
  sin Lua).
- **Fade de scroll** al pie de la lista de markers: aparece solo cuando
  hay contenido sin scrollear, desaparece al llegar al final. No es
  exclusivo del stepper — cubre el caso general de listas largas de
  markers, que hasta ahora no avisaban que había más para scrollear.
- **Persistencia de N por proyecto/tab**: clave `preMarkerBars` sumada al
  objeto de `nikTabMemorySnapshot()`/`nikTabMemoryRestore()` en
  `tab-ui-memory.js`, mismo mecanismo que `loopRecExpanded`. Default `2`
  cuando no hay valor guardado para ese proyecto.
- **Seek implementado con acción nativa** (`41043` — Move edit cursor back
  one measure), NO con cálculo manual de compases sobre `TimeMap`. Ver
  decisión abajo.

## Decisiones de diseño

- **`#optionsBar` descartado para este punto**: el espacio libre de esa
  barra está reservado para el toggle "Solo in front" (punto 1 del
  pendiente). Este punto 3 es scoped al popup de markers, no es una
  preferencia global de transporte — todo el control vive contenido
  dentro de `modals/marker-browser/` (ya "Confirmado con Nico" en el doc
  de pendientes original).
- **Pill con formato `"Nc"`** en vez de un ícono nuevo (ej. engranaje):
  reusa el mismo formato que ya usan los badges de compases por fila
  (`barsValSpan`), consistencia visual sin diseñar un asset nuevo. Doble
  función: readout permanente del valor actual + control de expandir.
- **Stepper colapsado por default, sin persistir su estado
  expandido/colapsado** (a diferencia de `loopRecExpanded`, que sí
  persiste) — decisión deliberada: se usa "una vez y se olvida", no vale
  la pena otra clave en `tab-ui-memory.js` para eso. Lo que persiste es
  solo el valor de N.
- **Paleta de color**: primera versión heredó el celeste `#00D0FF` del
  título del popup — feedback de Nico: "brilloso", mal contraste para
  mirar fijo un rato (a diferencia del título, que se lee de pasada).
  Cambiado a `#EDEDED` (número/texto), `#A8A8A8` (caption, ajustado dos
  veces — la primera pasada con `#808080`/`0.7em` seguía ilegible),
  `#4A8C99` (borde de la pill, acento apagado). **Pendiente**: Nico va a
  evaluar esta paleta en uso real y, si funciona, propagarla a los
  popups de Playrate/ReaPitch, que sufren el mismo problema de color
  brillante — NO HECHO en esta sesión, solo mencionado como intención.
- **Seek: acción nativa (`41043`) en vez de cálculo manual sobre
  `TimeMap`**: la primera implementación calculaba el QN de "N compases
  antes" a mano (`TimeMap_QNToMeasures` + epsilons, encadenando el
  `qnStart` de cada compás). Nico propuso usar la acción nativa "Move
  edit cursor back one measure" en su lugar — más determinístico porque
  reusa la lógica de tempo/time-signature que REAPER ya resuelve
  internamente, sin depender de una convención de indexado
  (0/1-based) de `TimeMap_QNToMeasures` que nunca se confirmó
  empíricamente. Overhead de hasta 8 llamadas a `Main_OnCommand`
  encadenadas: despreciable (llamadas internas, sin render ni red).
  Función `qn_start_bars_before` que se había agregado a
  `MarkerBars_common_logic.lua` fue **revertida/nunca commiteada** —
  solo quedó `find_marker_pos()`.
- **`SetEditCurPos` en dos pasos**: primero posiciona el edit cursor en
  el marker sin tocar playback (`seekplay=false`), retrocede compases con
  `41043`, lee la posición final, y recién ahí hace el `SetEditCurPos`
  con `seekplay=true` que efectivamente mueve la reproducción en vivo.
  Necesario porque `41043` mueve el edit cursor pero no garantiza que la
  reproducción salte ahí (depende de la preferencia "Link edit and play
  cursors while playing", que no se puede asumir activada).

## Gotchas encontrados en esta sesión

- **Desfasaje diff↔archivo real, varias veces en esta sesión**: se
  entregaron diffs contra una versión mental del archivo que ya no
  coincidía con lo que Nico tenía aplicado (`nikTogglePreMarkerStepper`,
  y luego el header completo de `marker-browser.html` — el diff de
  color/apilado de dos vueltas atrás nunca se había aplicado, y las
  vueltas siguientes se armaron igual "como si" sí lo estuviera). Lección
  para sesiones largas de diffs iterativos: pedir confirmación del
  contenido real del archivo antes de asumir que un diff previo quedó
  aplicado, en vez de asumirlo por el número de turnos pasados.
- **`position:sticky` no saca el elemento del flujo de scroll de su
  contenedor**: el primer intento de fade (`#nikMarkerScrollFade` como
  `sticky` hijo directo del panel que scrollea) sumaba sus propios 28px
  al `scrollHeight` del contenedor para siempre, así que el chequeo
  `scrollHeight - scrollTop - clientHeight` nunca bajaba lo suficiente y
  el fade quedaba pisando el final de la lista de forma permanente. Fix:
  separar "contenedor que scrollea" de "contenedor que se ve" — el fade
  pasa a `position:absolute` sobre un panel exterior fijo, con un wrapper
  interno nuevo (`#nikMarkerBrowserScroll`) como único elemento con
  `overflow-y:auto`. Candidato a sumar como gotcha general en
  `01_CONVENCIONES.md` — aplica a cualquier overlay/fade futuro sobre una
  lista scrolleable, no es exclusivo de este popup.
- **`pointer-events:none` obligatorio en el fade**: sin eso, el overlay
  tapa el tap/long-press de la última fila visible de la lista.
- **`nikUpdatePreMarkerBarsDisplay()` con `id` obsoleto tras un rediseño
  de HTML**: al pasar del layout en fila única (`nikPreMarkerBarsLabel`)
  al apilado (`nikPreMarkerBarsNumber`/`nikPreMarkerBarsCaption`), la
  función JS se quedó buscando el `id` viejo — el `if (label) {...}`
  fallaba en silencio (elemento no existe, no tira error) y la función
  no actualizaba nada visualmente aunque el estado sí cambiaba
  correctamente por detrás (por eso la pill sí reflejaba el valor nuevo
  pero el número grande no). Recordatorio de por qué estos `if (el)
  {...}` guards, aunque defensivos y necesarios, pueden esconder
  desincronizaciones HTML↔JS durante iteración rápida de diseño.

## Archivos tocados

- `config.js` — entrada `preMarkerSeek` en `NIK_LUA_COMMANDS` (Command ID
  ya reemplazado por Nico en su PC tras registrar el script; no
  registrado en este doc, confirmar el valor final contra el repo real).
- `modals/marker-browser/marker-browser.html` — header reestructurado
  (pill + stepper apilado), nuevo wrapper `#nikMarkerBrowserScroll`
  (separado del panel exterior, ver gotcha del fade), `#nikMarkerScrollFade`.
- `modals/marker-browser/marker-browser.js` — funciones nuevas:
  `nikUpdatePreMarkerBarsDisplay`, `nikTogglePreMarkerStepper`,
  `nikPreMarkerBarsStep`, `nikFirePreMarkerSeek`,
  `nikAttachMarkerLongPress`, `nikUpdateMarkerScrollFade`. Modificado
  `nikOpenMarkerBrowser` (attach long-press por fila, listener de scroll
  del fade, llamada a `nikUpdatePreMarkerBarsDisplay` al abrir) y el
  `onclick` de cada fila (chequeo de `_nikSuppressClick`).
- `core/tab-ui-memory.js` — `preMarkerBars` sumado a
  `nikTabMemorySnapshot()` / `nikTabMemoryRestore()`.
- `RemoteControl/MarkerBars_common_logic.lua` — función nueva
  `M.find_marker_pos(proj, markerId)`.
- `RemoteControl/Nik_Markers_SeekRelative.lua` — **archivo nuevo**. Lee
  `preseek_marker_id`/`preseek_bars` de ExtState, usa `find_marker_pos` +
  acción nativa `41043` (N veces) + `SetEditCurPos` en dos pasos.

## Pendiente para la consolidación en docs permanentes

- Confirmar y registrar el Command ID real de `Nik_Markers_SeekRelative.lua`
  (generado en la PC de Nico, no llegó a este chat).
- Evaluar la paleta `#EDEDED`/`#4A8C99`/`#A8A8A8` en uso real y, si
  funciona, propagarla a Playrate/ReaPitch (mencionado, no hecho).
- Marcar el punto 3 de `PENDING_optionsbar_markers.md` como resuelto (o
  eliminarlo, si se prefiere que ese archivo solo liste lo que sigue
  pendiente: puntos 1 y 2).
- Sumar a `01_CONVENCIONES.md` el gotcha de `position:sticky` +
  `scrollHeight` de contenedor scrolleable (aplica más allá de este
  popup).
- Evaluar si `nikAttachMarkerLongPress` (umbral 450ms + tolerancia de
  movimiento 10px + progreso animado vía CSS transition) vale la pena
  documentarse como patrón reutilizable en `remote_control.md`, para el
  caso de que otra fila del remoto necesite un gesto de long-press a
  futuro.

## No probado / a verificar en uso real

- Comportamiento con N=8 en secciones de compases muy cortos o con
  cambios de time signature densos cerca del marker elegido (no
  testeado explícitamente, solo el caso general).
- Uso prolongado en sala de ensayo real (conexión WiFi, con el issue ya
  conocido de freezes correlacionados con WiFi — no debería interactuar
  con este feature, pero no se probó bajo esas condiciones en esta
  sesión).
