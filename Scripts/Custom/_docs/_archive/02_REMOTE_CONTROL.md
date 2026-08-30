# Contexto — Remoto REAPER (`nsaudio_remote_control.html`) para ensayos

Continuación de trabajo sobre la interfaz web de control remoto de REAPER,
usada desde el celular durante ensayos. Puntos 1 y 3 de la lista de
prioridades original quedaron cerrados hace tiempo; esta sesión sumó tres
funcionalidades nuevas (doble-tap de faders, browser de markers, control de
playrate) más un ajuste de contraste. Este doc es el contexto para retomar
con el punto 2 (cambio de proyecto), el punto 4 (loop de sección) y los
pendientes menores que quedaron anotados.

## Setup técnico
- REAPER v7.79, SWS/S&M Extensions, Windows 10.
- Servidor web integrado de REAPER (Preferences > Control/OSC/web > Web
  browser interface). Puerto probado en 80 y 8080, sin diferencia para el
  problema de la barra de URL (ver sección PWA más abajo).
- Control desde celular Android vía **Fully Kiosk Browser** (no Chrome
  instalado como PWA — ver por qué en "Descartado por ahora").
- **Archivo renombrado**: el update a REAPER v7.79 pisó `fancier.html` con
  el default de la carpeta "User pages". El archivo de trabajo ahora se
  llama **`nsaudio_remote_control.html`**, ubicado en
  `AppData/Roaming/REAPER/reaper_www_root`. Con el nuevo nombre,
  `manifest.json`, `sw.js` y `apple-touch-icon` quedan sin efecto por ahora
  (no se usa como PWA instalada — se abre a través de Fully Kiosk Browser).
- `main.js` sin modificar — librería de REAPER, protocolo documentado en
  comentarios del propio archivo.

## Punto 1 — CERRADO: ciclar tabs + mejoras de interfaz

### Scripts Lua nuevos
- `NikRemote_TabNext.lua` / `NikRemote_TabPrev.lua`: enumeran proyectos
  abiertos con `EnumProjects`, calculan el índice siguiente/anterior con
  wraparound (primera↔última tab), cambian con `SelectProjectInstance`, y
  escriben el nombre del proyecto activo a
  `SetExtState("NikRemote", "active_project_name", name, false)`
  (`persist=false`, vive en RAM, sin desgaste de disco).
- Command IDs en la **PC de casa**: Next = `_RS79a5039f063b462669b016ebf0823f03a8052e8e`,
  Prev = `_RS52cba9bdca3f15af61b2ac08fd1d21ead999b803`.
  **Recordar re-registrar en la PC del estudio** (Command ID cambia por PC,
  se genera a partir de la ruta absoluta del script).

### Cambios en la UI
- Barra superior custom (`#nikTabBar`, HTML plano, no SVG) con botones
  Prev/Next tab + nombre de proyecto activo (leído vía polling de
  `GET/EXTSTATE/NikRemote/active_project_name`, más lectura inmediata
  encadenada en el mismo click). Antepone `wwr_req(40667)` (Stop) antes de
  cambiar de tab.
- Layout reestructurado: `body`/`#colWrap` con altura fija (`100dvh`),
  `#col1` fijo (`flex-shrink:0`), `#tracks` scrolleable
  (`overflow-y:auto`). Master quedó dentro de la zona fija (decisión
  consciente, para simplificar — no se movió el DOM).
- Sección Loop/Rec/contador de tracks armadas (`#transport_r3`) colapsada
  por defecto, con botón toggle simple (`#nikLoopRecToggle`).
- Rueda (`#jogger`) **eliminada por completo** (HTML + JS de
  `joggerHandler`/`joggerRotate`) y reemplazada por una fila de 6 botones
  estilo reproductor de medios: `⏮ | ◀◀ Comp | ◀ Beat | Beat ▶ | Comp ▶▶ | ⏭`
  (`#nikCursorNav`). Esto también resolvió de raíz el bug de "cursor
  avanzando indefinidamente" (era un problema de listeners de
  mouseup/touchend que no siempre se disparaban al interrumpir el gesto,
  típico al abrir el menú de Fully Kiosk a mitad de un swipe).
  - Command IDs usados: `40042`/`40043` (ir a inicio/fin de proyecto),
    `41041`/`41040` (compás anterior/siguiente), `41045`/`41044` (beat
    anterior/siguiente).

### Descartado / resuelto por ahora
- **PWA nativa de Chrome (sin barra de URL)**: no se logró. Causa raíz:
  Chrome en Android genera apps standalone reales ("WebAPK") vía un
  servidor de Google que necesita alcanzar el sitio — una IP LAN privada
  (`192.168.x.x`) no es alcanzable desde afuera, así que Chrome degrada
  silenciosamente a un shortcut con barra de URL visible aunque se elija
  "Instalar". Se probó puerto 80 sin éxito. **Parqueado**, no bloqueante —
  Fully Kiosk Browser cumple la función.
- **Fully Kiosk Browser — colores invertidos**: WebView aplica "Force Dark"
  automático a páginas que no declaran su propio esquema de color. Se
  resolvió agregando `<meta name="color-scheme" content="dark">` +
  desactivando dark mode del sistema.
- **Ícono/nombre "ERROR" en el launcher de Fully**: pendiente de confirmar
  si se resolvió — última indicación fue usar la función de "App Launcher"
  de Fully con ícono/nombre manuales en vez del atajo automático.

## Punto 3 — CERRADO: semitonos de ReaPitch en hijos del Stem Bus

Necesidad: ajustar (y activar/desactivar) todas las instancias de ReaPitch
en los hijos del track folder del Stem Bus desde el control remoto, sin
depender de cantidad fija de hijos ni de que todos tengan la instancia.

### Scripts Lua
- `NikRemote_ReaPitch_Read.lua`: recorre los hijos del Bus, busca ReaPitch
  por nombre de FX (no por índice), y escribe dos valores agregados a
  ExtState:
  - `NikRemote/reapitch_semitone`: valor numérico si todos coinciden,
    `"mixed"` si difieren, `"none"` si no hay Bus o ningún hijo tiene
    ReaPitch.
  - `NikRemote/reapitch_enabled`: `"on"` / `"off"` / `"mixed"` / `"none"`,
    basado en `TrackFX_GetEnabled` (bypass real por instancia, no el
    parámetro interno "1: Enabled" del plugin — ese no refleja el bypass).
- `NikRemote_ReaPitch_SetSemitones.lua`: lee
  `NikRemote/reapitch_semitone_target` (seteado por la web antes de invocar
  el script) y aplica ese valor a **todas** las instancias encontradas via
  `TrackFX_SetParamNormalized`, con la fórmula `normalizado = 0.5 +
  semitonos / 36` (rango real de ReaPitch confirmado empíricamente: ±18
  semitonos → 0.0–1.0 normalizado, centro 0.5 = 0 semitonos).
- `NikRemote_ReaPitch_ToggleEnable.lua`: toggle global sin parámetros —
  si no todas las instancias están encendidas, las enciende todas; si ya
  estaban todas encendidas, las apaga todas. Usa `TrackFX_SetEnabled`
  (bypass individual del FX, no afecta el resto de la cadena del track).
- Refactor cerrado: lógica común extraída a `StemBus_common_logic.lua`
  (discovery genérico del Bus/hijos) + `ReaPitchBus_common_logic.lua`
  (específico de ReaPitch). Los tres scripts consumen el módulo vía
  `dofile`. Ver convención general en `01_CONVENCIONES.md`.

### Detección del Stem Bus — alias configurable
```lua
local BUS_ALIASES = {
  ["stem bus"] = true,
  ["stems bus"] = true,
}
```
Agregar un alias nuevo = una línea, sin tocar el resto del script.

### UI (sección colapsable, patrón original)
- Readout de semitono agregado ("Semitonos: 3" / "mixed" / "—").
- Input numérico + botón "Aplicar".
- Botón toggle único de ReaPitch ON/OFF/mixed.
- Polling de 2000ms solo mientras la sección está abierta (`wwr_req_recur`/
  `wwr_req_recur_cancel` sobre `REAPITCH_POLL`).
- Command IDs como constantes editables al tope del script (`REAPITCH_CMD_READ`,
  `REAPITCH_CMD_SET`, `REAPITCH_CMD_TOGGLE`).

### Pendiente de este punto (no bloqueante)
- Sin probar: un hijo con ReaPitch bypasseado desde antes de correr el
  toggle, y el caso de un hijo con más de una instancia de ReaPitch en la
  cadena (hoy el script toma la primera que encuentra por nombre).
- **Candidato a migración** (ver sección nueva más abajo): pasar esta
  sección del formato colapsable actual al patrón readout-chico + modal
  que se usó hoy para playrate, probablemente ubicado a la izquierda del
  transport.

## Punto (nuevo) — CERRADO: doble-tap en faders → 0.0dB

Necesidad: volver cualquier fader (tracks y Master) a unity gain (0.0dB)
con un gesto rápido, sin tener que arrastrar a mano.

- **Fix previo necesario**: el fader del track Master
  (`<div class="trackRow2">` dentro de `#track0`) no tenía `id` seteado, a
  diferencia de los tracks normales — el comando armado con `this.id`
  quedaba `SET/TRACK//VOL/...` (inválido). Se fijó `masterTrackRow2Content.id
  = "0"` al crear el clon.
- Detección de doble-tap por timestamp (`faderLastTapAr`, keyed por
  `content.id`, umbral `FADER_DBLTAP_MS = 300`) en el `mousedown`/
  `touchstart` del thumb — no se usa `dblclick` nativo por confiabilidad en
  Fully Kiosk.
- Al detectar el segundo tap dentro del umbral: no arranca drag, mueve el
  thumb a `translate(194.68 0)` (posición de unity gain) y manda
  `SET/TRACK/<id>/VOL/1e`.
- **Bug de rebote encontrado y mitigado (no 100% resuelto)**: como el
  doble-tap no pasa por `mouseDownHandler`, el flag global `mouseDown`
  quedaba en `0`, y el próximo poll de `TRACK` con el valor viejo pisaba la
  posición visual antes de que REAPER aplicara el cambio — el fader volvía
  a su posición anterior por un instante y luego saltaba a unity de nuevo.
  Mitigado reusando el mismo flag `mouseDown` (igual que durante un drag
  real) con un `window.setTimeout` de 400ms tras el reset. Funciona la
  mayoría de las veces; ocasionalmente todavía rebota.
  - **Pendiente**: si en la sala molesta seguido, subir el timeout, o
    reemplazar el flag global `mouseDown` por un bloqueo por track
    individual (`mouseDownAr[id]`) para no afectar otros faders mientras
    dura el bloqueo de uno solo.

## Punto (nuevo) — CERRADO: browser de markers del proyecto

Necesidad: ir a un marker lejano sin depender del seek incremental
(lento, con delay de refresh en pantalla).

- El tap se engancha por **delegación de evento** en el `<div>` que envuelve
  `<svg id="nextPrev">` (`onclick="nikMarkerAreaClick(event)"`), no en un
  rect nuevo — así funciona tanto si se toca el fondo vacío del display
  como si se toca directamente el nombre de un marker/región ya
  renderizado (evita problemas de z-order en SVG con elementos sin
  handler propio).
- `nikMarkerAreaClick(event)` sube por los ancestros del elemento tocado;
  si encuentra `prevButton`, `nextButton` o `dropMarker` (el botón "+" de
  agregar marker), no hace nada — esos ya tienen su propio `onclick`, que
  dispara igual por el mismo evento sin interferencia.
- `nikOpenMarkerBrowser()` arma la lista desde `g_markers` (array global ya
  poblado por el poll existente de `MARKER;REGION` cada 500ms — no hace
  falta pedir nada nuevo), ordenado por posición, mostrando nombre (o
  "unnamed (ID)") + posición en segundos.
- Tap en un ítem: `SET/POS_STR/m<ID>` (usa el addressing por ID de marker
  documentado en `main.js`, evita convertir a segundos a mano) y cierra el
  popup.
- Cierre: tap fuera del panel, o al elegir un marker.
- Título del popup ("Markers") con `position:sticky; top:0`, color
  `#00D0FF` (mismo celeste que ya se usa para estados "on" en el resto de
  la UI), en mayúsculas con borde inferior grueso, para diferenciarlo
  claramente de las filas de la lista.
- **Pendiente**: comportamiento del sticky sin confirmar con lista larga
  con scroll real (se probó con 15 markers, entraron sin necesidad de
  scrollear). Si no queda pegado con listas largas, sospechar del
  `overflow-y:auto` del panel interactuando con el `border-radius`
  recortando el sticky.

## Punto (nuevo) — CERRADO: control de playrate

Necesidad: cambiar el playrate rápido a valores lejos del 100% (rango de
práctica), sin agregar una sección desplegable nueva ni otro botón en
`#nikCursorNav`.

### Scripts Lua nuevos
- `NikRemote_PlayRate_Read.lua`: lee `reaper.Master_GetPlayRate(0)` (→
  porcentaje entero) y el estado de la acción nativa **"Preserve pitch in
  audio items when changing master playrate"** (Command ID `40671`, vía
  `reaper.GetToggleCommandStateEx`). Escribe `NikRemote/playrate` y
  `NikRemote/preservepitch` (`"on"`/`"off"`) a ExtState.
- `NikRemote_PlayRate_Set.lua`: lee `NikRemote/playrate_target`, clampea a
  **40%–150%**, aplica con `reaper.CSurf_OnPlayRateChange(rate)` (notifica
  a superficies de control, a diferencia de escribir el playrate directo
  en el chunk).
- `NikRemote_PlayRate_TogglePreservePitch.lua`: `reaper.Main_OnCommand(40671,
  0)` — toggle de la acción nativa (no hay set-on/set-off directo, solo
  toggle).
- Command IDs (**PC de casa**, recordar re-registrar en la PC de la sala,
  como con los de Puntos 1 y 3): Read = `_RSdd1a9bf0554e64560435dee6a8ad8e6c13a56b73`,
  Set = `_RS13d25002f7b337b1a5cdfb7edb1fc0ba61e3756f`, Toggle preserve pitch
  = `_RSac8c16831942abaa0d0567e5a656b98a6aadecb3`. `40671` es nativo de
  REAPER, no debería cambiar entre PCs (a diferencia de los `_RS...` que sí
  cambian por instalación).

### UI
- Readout compacto "100%" superpuesto (HTML `position:absolute`, no SVG)
  sobre la fila de `status`/reloj grande, alineado antes del ícono ⚙
  (`right:16%`, `top:50%; transform:translateY(-50%)` para centrado
  vertical real independiente del alto renderizado de la fila). Tap abre
  el modal.
- Modal (mismo patrón visual que el browser de markers: overlay +
  panel oscuro): slider `<input type="range">` de 40 a 150, número grande
  arriba que se actualiza en vivo mientras se arrastra (`oninput`), commit
  real al soltar (`onchange` → `SET/EXTSTATE/.../playrate_target` +
  comando Set), botón "Reset 100%", checkbox de preserve pitch (arranca
  `checked`, se resincroniza con el estado real apenas llega el primer
  poll).
- El checkbox compara el valor deseado contra el último estado conocido
  del servidor (`nikPreservePitchServerState`) antes de mandar el toggle,
  para no desincronizarse con doble-tap accidental.
- Poll **siempre activo** (no gateado por apertura/cierre de modal, a
  diferencia del patrón de ReaPitch) a **1000ms** — se decidió así porque
  el costo es despreciable (dos `GET/EXTSTATE` de texto chico enganchados
  al ciclo de polling de 100ms base) y simplifica el código al no
  necesitar `wwr_req_recur_cancel`.
- Bloqueo de "no pisar mientras se arrastra" con flag `nikPlayrateDragging`
  + timeout de 400ms tras el commit, mismo criterio que el fix de rebote
  de faders.

### Candidato a modelo para otra sesión
Validado el patrón "readout chico siempre visible + modal con slider",
queda como candidato para migrar la sección colapsable de semitonos de
ReaPitch (Punto 3) al mismo formato — posiblemente ubicado a la izquierda
del transport, simétrico al readout de playrate.

## Ajuste de contraste — CERRADO

Color `#545454` (gris muy oscuro, poco legible sobre fondo `#1a1a1a`)
reemplazado por `#A8A8A8` (mismo gris claro que ya usan `tsNum`/`tsDen`) en:
- `#timeUnits` ("Hours:Minutes:Seconds:Frames", debajo del reloj grande).
- El readout de playrate nuevo.

Si aparecen más elementos con `#545454` en uso real (no se hizo un barrido
completo del archivo, solo se corrigieron los dos reportados), agregarlos
a esta lista.

## Ajuste cosmético — Seeker de marcadores/regiones — reevaluado

El ajuste documentado en sesiones previas (recorte de `viewBox`, subir
filas 4 unidades, etc.) **no está aplicado en el archivo actual**
(`nsaudio_remote_control.html` sigue con `viewBox="0 0 318.9 87.8"`) —
probablemente no sobrevivió al update de REAPER 7.79 / rename del archivo.

Al revisarlo esta sesión, lo que parecía "espacio muerto" (la fila
superior del display, la de **regiones**) resultó ser simplemente una fila
sin uso porque el proyecto no tenía regiones creadas todavía. Con regiones
de prueba agregadas, la fila se ve y ocupa su espacio con normalidad. **No
hace falta compactar el SVG** — se deja como está.

### Pendiente (sin resolver, no bloqueante)
- Achicar los botones prev/next horizontalmente para ganar ancho para
  nombres de marcador largos (clip de texto fijo ~56.8 unidades). Sigue
  anotado de sesiones anteriores, sin repriorizar todavía.

## Pendiente — orden de prioridad

### 2. Cambiar de proyecto (abrir/cerrar, con feedback de nombre)
Sin tocar esta sesión. Mecanismo pensado (no implementado):
- Script Lua genérico que lee una ruta desde `ExtState` (seteada previamente
  por la web vía `SET/EXTSTATE/...`) y hace `reaper.Main_openProject(ruta)`.
- Cierre vía acción nativa "File: Close project" (buscar Command ID exacto
  en Action List, no confirmado todavía).
- Nombre de proyecto activo: mismo mecanismo ya construido en el punto 1
  (`active_project_name` en ExtState) — reutilizable tal cual.

### 4. Loop de sección específica
Sin tocar esta sesión.
- `reaper.GoToRegion(proj, index, true)` — el `true` setea también la
  selección de tiempo al rango de la región en el mismo paso.
- Requiere la preferencia de REAPER "Loop points linked to time selection"
  activada para que el loop respete ese rango.
- Requiere que las secciones existan como **regiones** (no solo markers).
  Dato nuevo de esta sesión: el proyecto de prueba ya tiene regiones
  cargadas (usadas para validar que la fila de regiones del seeker no
  era "espacio muerto"), así que este prerequisito puede estar más cerca
  de cumplirse de lo que parecía — revisar si esas regiones sirven como
  base o si hace falta el enfoque de lane oculto mencionado en
  `01_CONVENCIONES.md`.
- Un script por sección, o uno genérico driven por `ExtState` (mismo patrón
  que los puntos 2 y playrate).

### Pendientes menores acumulados (no bloqueantes)
- Rebote ocasional del reset de faders a unity — ajustar timeout o pasar a
  bloqueo por track individual (ver sección del punto de faders).
- Sticky del título del browser de markers sin confirmar con lista larga.
- Migrar sección de semitonos de ReaPitch al patrón readout+modal (ver
  sección de playrate).
- Achicar horizontalmente botones prev/next del seeker.

## Notas técnicas transversales
- Arquitectura repetida en Puntos 3, playrate, y (a futuro) 2 y 4:
  **script Lua + `ExtState` + polling desde la web**.
- Protocolo web documentado en los comentarios de `main.js`.
- Convención de trabajo: pasos chicos, confirmación antes de avanzar, diffs
  en formato buscar/reemplazar (código puro dentro del bloque, indicaciones
  afuera), avisar antes de +300 líneas.
- **`reaper.GetExtState(section, key)` devuelve un solo valor (string, o
  `""` si no existe)** — no un par `(ok, valor)` como otras funciones de la
  API que reciben un buffer de salida (`TrackFX_GetFXName`,
  `TrackFX_GetFormattedParamValue`, etc.). Confundir el patrón causa que el
  script corte en silencio sin aplicar nada — bug real encontrado y
  corregido durante el punto 3.
- **Delegación de eventos en SVG**: cuando varios elementos hermanos se
  superponen y solo algunos tienen `onclick`, un click en un elemento sin
  handler propio *no* burbujea hacia un hermano — solo hacia ancestros. Si
  se necesita que un área compuesta por muchos elementos (con y sin
  handler) sea tapeable como un todo, hay que poner el `onclick` en un
  ancestro común y filtrar en el handler (visto en el browser de markers),
  en vez de agregar un rect transparente como hermano de último orden.
