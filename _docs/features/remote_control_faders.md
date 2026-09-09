# Sub-feature — Playrate & ReaPitch (Control Remoto Web)

Doc de dominio, referenciado desde `remote_control.md` (tabla de
funcionalidades). Cubre: fader vertical modular, knob SVG calcado,
Playrate (mapa de tempo variable, BPM bidireccional, readout principal),
ReaPitch (semitonos, Stem Bus). Gotchas de CSS transversales (input range
rotado, centrado de thumb, ids de gradiente, tap-highlight) viven en el
doc master — acá solo lo específico de este dominio.

## Fader vertical modular (`core/vertical-fader.js`)

Componente `nikCreateVerticalFader(config)`, reutilizado por
`reapitch.js` (caso simple, sin BPM) y `playrate.js` (suma traducción
bidireccional playrate% ↔ BPM).

- **Decisión de arquitectura**: `<input type="range">` nativo rotado
  -90° por CSS, no un componente de drag SVG custom desde cero — reusa el
  manejo de touch/mouse nativo del input, evita reinventar lo que
  `core/faders.js` ya resuelve para un caso distinto (faders de volumen,
  con geometría propia por color de track).
- **Doble-tap-reset** generalizado a partir del patrón ya existente en
  `core/faders.js` (`faderCheckDoubleTap`/`faderLastTapAr`), con key
  string en vez de track id.
- Botones de step (+/−) junto al fader, `config.step`.
- Gotchas de CSS del `<input>` rotado (appearance del thumb, fórmula de
  centrado, desalineo no necesariamente bug) — ver `remote_control.md`.

## Knob SVG calcado (`core/fader-knob-svg.js`)

Módulo reutilizable, calco del `<g class="fader">` de `trackRow2Svg` (fila
de volumen nativa de la UI principal) — reemplaza visualmente al thumb
nativo del `<input type="range">` (círculo cyan liso) sin tocar su lógica
de drag existente. Expone `nikCreateFaderKnobSvg({mountEl, orientation})`
→ `{setFraction(f)}` (`f` entre 0 y 1, mueve el `translate` del grupo a lo
largo del recorrido).

- **Geometría lógica fija**, `viewBox="0 0 320 72"` (mismo box que ya
  usaba `.nikVFaderTrack` antes de rotarlo): pista `x` 20→300 (280 de
  largo), alto 8, centrada en `y` (32→40); knob 46×36, centrado en `y`
  (18→54); recorrido del knob `x` 20→254 (234 = 280−46).
- **Un solo asset sirve para horizontal y vertical**: la variante
  vertical no redibuja paths, envuelve el `<svg>` en `rotate(-90deg)` vía
  la clase `.nikFaderKnobSvg--vertical` (mismo truco que ya usaba
  `.nikVFaderTrack` sobre el `<input>` nativo).
- **Gradientes simplificados**: el original de `trackRow2Svg` usa
  `gradientUnits="userSpaceOnUse"` con matrices por pieza; acá se usa
  `objectBoundingBox` (default, `x1/y1/x2/y2` en 0–1) — mismo degradé
  visual dentro de cada shape, sin la matriz.
- **IDs de gradiente con sufijo único por instancia** (`nikFaderKnobSvgSeq`,
  contador incremental) — mismo motivo que `nikUniquifyGradientIds()` en
  `wwr-dispatch.js` (ver gotcha general en `remote_control.md`): más de
  un fader knob en la misma página duplicaría `<linearGradient id>` si no
  se sufija.
- **Track del knob**: color sólido `#262626` (mismo gris que
  `.nikVFaderStepBtn`/reset) — el original usa `#1A1A1A` con opacidad 0.5
  sobre fondo `#333333` (fila de track), valor casi invisible sobre el
  fondo `#1a1a1a` del popup, por eso se resolvió distinto acá.

### Integración con el `<input>` existente

**El `<input type="range">` nativo se mantiene como única capa de
interacción** (drag, touch, teclado, doble-tap — toda la lógica ya
provista por `nikCreateVerticalFader`). Se vuelve invisible
(`background:transparent`, thumb transparente) pero sigue capturando el
gesto. El SVG del knob se monta **encima**, en el mismo `.nikVFaderWrap`,
con `pointer-events:none` — capa puramente visual, sincronizada con el
valor real del input. Se descartó reimplementar el drag a mano sobre el
SVG (al estilo `core/faders.js`) por duplicar lógica ya probada sin
necesidad — el único requisito nuevo era visual.

**Hook en `core/vertical-fader.js`**: `nikCreateVerticalFader(config)`
acepta dos claves opcionales — `knobMountId` (id del elemento donde
montar el knob, típicamente el mismo `.nikVFaderWrap`) y
`knobOrientation` (`"vertical"` por default si hay `knobMountId`, o
`"horizontal"`). Sin `knobMountId`, el fader funciona exactamente como
antes (compatible con instancias futuras que no necesiten el knob
visual). El knob se resincroniza en tres puntos: init, listener
`"input"` (drag en vivo), y `handle.setValue()` (usado tanto por el poll
de servidor como por `stepBy`/`reset`, que llaman a `setValue`
internamente).

## Layout de los popups

Patrón aplicado en ambos (Playrate y ReaPitch): **sacar el elemento
acompañante del flujo normal (`position:absolute`) para que el elemento
principal sea el único que participa del centrado del contenedor**, en
vez de centrar el bloque conjunto.

- **Botones +/−**: de fila a columna a la izquierda del fader (+ arriba,
  − abajo, gap 16px), sacados del flujo con `position:absolute;
  right:100%` dentro de `.nikVFaderWrap` (que pasa a
  `position:relative`) — así el fader queda centrado contra el readout
  numérico de arriba, no contra el bloque botones+fader. Tamaño de
  `.nikVFaderStepBtn` subido de 44px a 52px (mejor agarre, menos roce con
  el fader).
- **Input de BPM + label "BPM"** (solo Playrate): mismo patrón — el
  label pasa a `position:absolute; left:100%` respecto de un wrapper
  `position:relative` alrededor del `<input>`, que queda como único
  elemento centrado por el contenedor flex.

## Legibilidad / paleta

- Readouts numéricos grandes (`#nikPlayrateBpm`, `#nikReaPitchValue`):
  `#00D0FF` → `#FFFFFF`.
- Título del popup y línea inferior: `#00D0FF` → `#D0D0D0` (texto) /
  `#4A4A4A` (línea) — misma paleta neutra que el resto del proyecto (ver
  "Paleta de popups" en `remote_control.md`).
- Dejado afuera a propósito: el cyan de `#nikReaPitchEnableToggle` en
  estado ON — indicador de estado que se mira de refilón, no un readout
  que se sostiene la mirada.

## Rango y comportamiento del fader de Playrate

- **Rango 50–150%** (no 40–150 del slider original) — el punto medio
  matemático (100%) coincide con el `defaultValue`, evitando el
  desalineo visual círculo/botones-de-step (ver gotcha general
  "desalineo no es necesariamente bug de CSS"). Confirmado que no se usa
  playrate por debajo de 50% en la práctica.
- **Clamp visual**: flash breve de color/fondo (`.nikVFaderClampFlash`)
  cuando el BPM tipeado excede el rango y se corrige.
- **Campo BPM**: confirmación por `onchange` (blur/Enter) — no botón
  "Aplicar", consistencia con el resto de la UI. Select-all al enfocar
  (`onfocus="this.select()"`). Enter fuerza `blur()` explícito (no
  depender de que el teclado virtual dispare blur solo).
- **Jerarquía visual**: BPM protagonista (grande, color de acento), % es
  secundario (chico, gris) — invertido respecto al diseño original donde
  el % era protagonista.

## Playrate → Tempo: mapa de tempo variable (no un BPM fijo)

**Problema resuelto**: el BPM equivalente mostrado "desviaba" en
proyectos con mapa de tempo variable (correcciones de tempo a lo largo de
toda la canción, típico de temas grabados sin metrónomo, con intro
atípica) — no en proyectos de tempo estable, donde el cálculo era
correcto.

**Causa raíz**: `base_tempo` estaba diseñado como un tempo de referencia
fijo por proyecto, leído una sola vez. En un proyecto con mapa de tempo
variable no existe tal cosa — cada sección tiene su propio tempo
original, y el BPM equivalente correcto depende de en qué sección está la
posición de reproducción en cada momento.

**Solución**: en vez de leer un solo BPM, se lee **el mapa de tempo
completo** del proyecto (todas las posiciones de tempo/time-sig marker +
su bpm), con los mismos triggers on-demand de antes — boot, abrir popup,
cambio de proyecto/tab (**no** entra al poll rápido). Del lado cliente,
en cada tick del poll de `TRANSPORT` (10ms, ya existente) se busca el
tempo vigente en la posición actual (`playPosSeconds`, ya se actualiza en
ese mismo poll) mediante lookup "último marker con `pos <= posición
actual`" — sin interpolación, porque los cambios de tempo son saltos
discretos, no rampas. Cero llamadas Lua adicionales en el loop rápido:
todo el costo extra es un `for` liviano sobre un array ya en memoria.

- **Script**: `Nik_Playrate_ReadTempoMap.lua` (reemplaza y elimina a
  `Nik_Playrate_ReadBaseTempo.lua`) — itera
  `CountTempoTimeSigMarkers`/`GetTempoTimeSigMarker`, publica
  `NikRemote/tempo_map` como `"pos1:bpm1,pos2:bpm2,..."`. Sin markers,
  fallback a un único punto en `pos=0` con `Master_GetTempo()`.
- **`config.js`**: `playrateTempoMapRead` reemplaza a
  `playrateBaseTempoRead`.
- **`playrate.js`**: `nikPlayrateTempoMap` (array `{pos, bpm}`)
  reemplaza a `nikPlayrateBaseTempo` (número fijo).
  `nikPlayrateTempoAt(positionSeconds)` — lookup nuevo.
  `nikPlayrateComputeEquivalentBpm` y `nikPlayrateBpmCommit` resuelven el
  tempo vigente en la posición actual en vez de un valor fijo.
  `nikPlayrateSetTempoMap`/`nikPlayrateRequestTempoMap` reemplazan a sus
  equivalentes de `base_tempo`.
- **`wwr-dispatch.js`**: case `TRANSPORT` refresca el readout principal
  de Playrate en cada tick (antes solo en el poll lento
  `EXTSTATE/playrate`, 1000ms) — necesario para que el BPM equivalente
  siga en vivo la sección que está sonando. Case `EXTSTATE` escucha
  `tempo_map` en vez de `base_tempo`.
- **`init.js`**: boot y watchdog de desconexión actualizados al nuevo
  nombre/tipo de variable — al desconectar, `nikPlayrateTempoMap` se
  resetea a `null` y el readout cae al placeholder `—`.

**Casos borde cubiertos** (verificar que se mantengan ante cualquier
refactor futuro): 1 solo tempo marker (comportamiento idéntico a antes
del fix); tempo estable + cambios de métrica (no afecta, el cálculo solo
mira bpm, no time signature); sin tab activa/proyecto sin guardar (el
script opera sobre `proj = 0`, no depende de que el proyecto esté
guardado); REAPER cerrado (reutiliza el watchdog existente).

**Dato de fallback que sigue vigente**: el tempo base de un solo punto
(caso sin markers) usa `GetTempoTimeSigMarker(0,0)` si existe, si no
`Master_GetTempo()` — confirmado empíricamente que `Master_GetTempo()`
depende de la posición del cursor de edición (toma el tempo del marker a
su izquierda), no es referencia estable salvo en el caso sin ningún
marker de tempo.

**Principio general reutilizable**: cuando un valor derivado necesita
reflejar algo que cambia con la posición de reproducción (no solo con el
tiempo real), conviene enviar los datos crudos necesarios una sola vez
(on-demand) y resolver el valor derivado del lado del cliente usando
campos que **ya llegan** en el poll rápido existente (acá,
`playPosSeconds` de `TRANSPORT`) — evita agregar polls o scripts Lua
nuevos al loop de 10ms.

## Readout principal de Playrate (fuera del popup)

`#nikPlayrateReadout` mostraba `%` de playrate — ahora muestra el tempo
equivalente en BPM, redondeado sin decimales, reusando el cálculo del
popup (no duplicado).

- `nikPlayrateComputeEquivalentBpm(percent)` — función pura en
  `playrate.js`, hoy resuelve el tempo vigente vía el mapa de tempo (ver
  arriba). Consumida tanto por `nikPlayrateUpdateBpmField()` (campo del
  popup, un decimal) como por `nikPlayrateRefreshMainReadout()` (readout
  principal, `Math.round()`, sin decimales) — un solo lugar para
  corregir precisión a futuro, el fix aplica a los dos displays.
- **Disponibilidad del mapa de tempo sin abrir el popup**: disparo
  on-demand (`nikPlayrateRequestTempoMap()`) en tres momentos — boot
  (`init()`), cambio de proyecto activo (handler `active_project_name`
  en `wwr-dispatch.js`), y reconexión implícita (el watchdog resetea a
  `null` al detectar desconexión; no hay reintento activo mientras sigue
  desconectado, se retoma solo con el próximo boot o cambio de proyecto).
- **Ícono** ♩ (negra musical, U+2669) a la izquierda del número, en
  `<span>` propio (`#nikPlayrateNoteIcon`). Contenedor
  `display:inline-flex; align-items:center` — el centrado por `baseline`
  (default de texto) rompía la alineación vertical al usar un glifo con
  `font-size` distinto al del número; con flex, el centrado es por altura
  real de cada hijo, no por baseline.
- **Espaciado** de los tres readouts del bloque superior (métrica /
  ReaPitch / posición / Playrate / menú): `#nikReaPitchReadout` `left:16%`
  → `left:20%`; `#nikPlayrateReadout` `right:16%` → `right:18%`. El ancho
  de "posición" (centro del bloque) varía según el formato mostrado
  (`measures.beats` vs `min:seg`, ver toggle de posición en
  `remote_control.md`) — estos porcentajes son un punto medio razonable
  contra el peor caso, no un centrado matemático exacto.

## Pendiente

- **Precisión del cálculo Playrate→BPM**: reportada como "a veces no muy
  precisa" *antes* del fix del mapa de tempo variable — a re-observar si
  reaparece; puede que ya esté resuelta por el fix de arriba. Centralizado
  en una sola función, así que cualquier corrección futura aplica a
  ambos displays sin tocar dos lugares.
- **Limpieza**: borrar `Nik_Playrate_ReadBaseTempo.lua` del repo si sigue
  físicamente ahí, y `playrateBaseTempoRead` de `config.js` si quedó (ver
  también `remote_control.md` → Limpieza pendiente).

## Archivos de este dominio

```
core/vertical-fader.js
core/fader-knob-svg.js
modals/playrate/playrate.html, playrate.js
modals/reapitch/reapitch.html, reapitch.js
RemoteControl/Nik_Playrate_ReadTempoMap.lua
core/wwr-dispatch.js   (case TRANSPORT, case EXTSTATE)
core/init.js           (boot + watchdog)
config.js              (playrateTempoMapRead)
styles.css             (.nikVFaderWrap, .nikVFaderTrack, .nikFaderKnobSvg(--vertical),
                         .nikVFaderStepBtn, .nikVFaderClampFlash)
```
