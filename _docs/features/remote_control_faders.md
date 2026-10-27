# Sub-feature — Playrate & ReaPitch (Control Remoto Web)

Doc de dominio, referenciado desde `remote_control.md`. Cubre: fader
vertical modular, knob SVG calcado, Playrate (mapa de tempo variable, BPM
bidireccional, readout principal), ReaPitch (semitonos, Stem Bus).
Gotchas de CSS generales (ids de gradiente, tap-highlight):
`remote_control_ui.md` §3. Paleta de popups: `remote_control_ui.md` §1.

## 1. Fader vertical modular (`core/vertical-fader.js`)

Componente `nikCreateVerticalFader(config)`, reutilizado por
`reapitch.js` (caso simple, sin BPM) y `playrate.js` (suma traducción
bidireccional playrate% ↔ BPM).

- **Decisión de arquitectura**: `<input type="range">` nativo rotado
  -90° por CSS, no un componente de drag SVG custom desde cero — reusa el
  manejo de touch/mouse nativo del input, evita reinventar lo que
  `core/faders.js` ya resuelve para un caso distinto (faders de volumen,
  con geometría propia por color de track).
- **Doble-tap-reset:** mismo patrón que `core/faders.js`
  (`faderCheckDoubleTap`/`faderLastTapAr`), con key string en vez de
  track id.
- Botones de step (+/−) junto al fader, `config.step`.
- **`<input type="range">` rotado con `transform:rotate(-90deg)`:** el
  thumb custom necesita `-webkit-appearance:none` tanto en el
  pseudo-elemento como en el `<input>` base. Si falta en el base, Chrome
  acepta el color y el background del thumb pero ignora su `width` y
  `height`.
- **Centrado del thumb contra el runnable-track:** `margin-top =
  (trackHeight - thumbHeight) / 2`. Se recalcula cada vez que cambia
  cualquiera de los dos valores; no se auto-ajustan entre sí.
- **Desalineo visual entre el slider y los controles fijos de alrededor:**
  no es necesariamente un bug de CSS. Si el valor actual no coincide con
  el punto medio matemático del rango (`(min+max)/2`), el thumb se ve
  corrido de ese centro por diseño. Antes de sospechar de la rotación o
  del CSS, confirmar el rango y el default.

## 2. Knob SVG calcado (`core/fader-knob-svg.js`)

Módulo reutilizable, calco del `<g class="fader">` de `trackRow2Svg` (fila
de volumen nativa de la UI principal) — sustituye visualmente al thumb
nativo del `<input type="range">` sin tocar su lógica de drag. Expone
`nikCreateFaderKnobSvg({mountEl, orientation})`
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
  `wwr-dispatch.js` (ver `remote_control_ui.md` §3): más de un fader knob en
  la misma página duplicaría `<linearGradient id>` si no se sufija.
- **Track del knob**: color sólido `#262626` (mismo gris que
  `.nikVFaderStepBtn`/reset). El del original (`#1A1A1A` con opacidad 0.5
  sobre `#333333`) sería casi invisible sobre el fondo `#1a1a1a` del
  popup.

### Integración con el `<input>` existente

**El `<input type="range">` nativo se mantiene como única capa de
interacción** (drag, touch, teclado, doble-tap — toda la lógica ya
provista por `nikCreateVerticalFader`). Se vuelve invisible
(`background:transparent`, thumb transparente) pero sigue capturando el
gesto. El SVG del knob se monta **encima**, en el mismo `.nikVFaderWrap`,
con `pointer-events:none` — capa puramente visual, sincronizada con el
valor real del input. No reimplementa el drag sobre el SVG (como hace
`core/faders.js`): duplicaría lógica que el input ya resuelve.

**Hook en `core/vertical-fader.js`**: `nikCreateVerticalFader(config)`
acepta dos claves opcionales — `knobMountId` (id del elemento donde
montar el knob, típicamente el mismo `.nikVFaderWrap`) y
`knobOrientation` (`"vertical"` por default si hay `knobMountId`, o
`"horizontal"`). Sin `knobMountId` no se monta knob y el fader usa solo
el input nativo. El knob se resincroniza en tres puntos: init, listener
`"input"` (drag en vivo), y `handle.setValue()` (usado tanto por el poll
de servidor como por `stepBy`/`reset`, que llaman a `setValue`
internamente).

## 3. Layout de los popups

Patrón aplicado en ambos (Playrate y ReaPitch): **sacar el elemento
acompañante del flujo normal (`position:absolute`) para que el elemento
principal sea el único que participa del centrado del contenedor**, en
vez de centrar el bloque conjunto.

- **Botones +/−**: en columna a la izquierda del fader (+ arriba, −
  abajo, gap 16px), sacados del flujo con `position:absolute;
  right:100%` dentro de `.nikVFaderWrap` (`position:relative`) — así el
  fader queda centrado contra el readout numérico de arriba, no contra el
  bloque botones+fader. `.nikVFaderStepBtn` mide 52px (agarre, menos roce
  con el fader).
- **Input de BPM + label "BPM"** (solo Playrate): mismo patrón — el
  label pasa a `position:absolute; left:100%` respecto de un wrapper
  `position:relative` alrededor del `<input>`, que queda como único
  elemento centrado por el contenedor flex.

## 4. Paleta

Los readouts numéricos grandes (`#nikPlayrateBpm`, `#nikReaPitchValue`),
el título del popup y la línea inferior siguen la paleta de popups de
`remote_control_ui.md` §1, incluido el cyan que se conserva en
`#nikReaPitchEnableToggle`.

### Color por desviación de los readouts principales

`#nikPlayrateReadout` y `#nikReaPitchReadout` (fuera de los popups) se
colorean según cuánto se aleja el valor de su default.

- `nikDeviationColor(value, defaultVal, minVal, maxVal)` (`core/utils.js`):
  gris `#A8A8A8` en el default; hacia arriba interpola a verde `#00FF99` y
  hacia abajo a naranja `#FF9500`. La intensidad es la distancia al default
  normalizada contra el extremo del rango, así que el color es pleno en el
  extremo.
- `nikLerpColor(hexA, hexB, t)` (`core/utils.js`): interpolación entre dos
  colores `#rrggbb`, con `t` acotado a 0..1. También la usa
  `nikResolveMarkerDisplay` para aclarar las cadenas `xN`
  (`remote_control_markers.md` §2).
- **Playrate:** `nikPlayrateRefreshMainReadout(percent)` llama con
  `(100, 50, 150)`, el mismo rango de §5.
- **ReaPitch:** `nikRefreshReaPitchReadoutColor()` llama con `(0, -12, 12)`
  solo si el efecto está activo (`"on"`) y el semitono es numérico. Efecto
  apagado (`"off"`): `#5A5A5A`. Cualquier otro caso (estado distinto de
  `"on"`, semitono `null`, `"none"` o `"mixed"`): `#A8A8A8`.

## 5. Rango y comportamiento del fader de Playrate

- **Rango 50–150%**: el punto medio matemático (100%) coincide con el 
  `defaultValue`, evitando el desalineo visual círculo/botones-de-step (ver 
  §1, "Desalineo visual"). No se usa playrate debajo de 50% en la práctica.
- **Clamp visual**: flash breve de color/fondo (`.nikVFaderClampFlash`)
  cuando el BPM tipeado excede el rango y se corrige.
- **Campo BPM**: confirmación por `onchange` (blur/Enter) — no botón
  "Aplicar", consistencia con el resto de la UI. Select-all al enfocar
  (`onfocus="this.select()"`). Enter fuerza `blur()` explícito (no
  depender de que el teclado virtual dispare blur solo).
- **Jerarquía visual**: BPM protagonista (grande, color de acento), % es
  secundario (chico, gris).

## 6. Playrate → Tempo: mapa de tempo variable

El BPM equivalente depende de en qué sección del mapa de tempo está la
posición de reproducción. En proyectos con mapa variable (correcciones de
tempo a lo largo de toda la canción, típico de temas grabados sin
metrónomo, con intro atípica) cada sección tiene su propio tempo
original, y no existe un tempo de referencia fijo por proyecto.

Se lee **el mapa de tempo completo** (posición y bpm de cada tempo/time-sig
marker) on-demand: boot, abrir popup y cambio de proyecto/tab (**no**
entra al poll rápido). En el cliente, en cada tick del poll de
`TRANSPORT` (10ms) se busca el tempo vigente en la posición actual
(`playPosSeconds`, que ya se actualiza en ese poll): el último marker con
`pos <= posición actual`, sin interpolación porque los cambios de tempo
son saltos discretos, no rampas. No hay llamadas Lua adicionales en el
loop rápido: el costo extra es un `for` liviano sobre un array en
memoria.

- **Script**: `Nik_Playrate_ReadTempoMap.lua` — itera
  `CountTempoTimeSigMarkers`/`GetTempoTimeSigMarker`, publica
  `NikRemote/tempo_map` como `"pos1:bpm1,pos2:bpm2,..."`. Sin markers,
  fallback a un único punto en `pos=0` con `Master_GetTempo()`. En la
  misma corrida publica `NikRemote/timesig_map`, que consume
  `core/music-state.js` (contrato en `musicstate_data_model.md` §4.5);
  `nikPlayrateRequestTempoMap()` pide las dos keys juntas.
- **`config.js`**: `playrateTempoMapRead`.
- **`playrate.js`**: `nikPlayrateTempoMap` (array `{pos, bpm}`).
  `nikPlayrateTempoAt(positionSeconds)` resuelve el tempo vigente en una
  posición. `nikPlayrateComputeEquivalentBpm` y `nikPlayrateBpmCommit`
  usan ese tempo. `nikPlayrateSetTempoMap`/`nikPlayrateRequestTempoMap`
  guardan y piden el mapa.
- **`wwr-dispatch.js`**: case `TRANSPORT` refresca el readout principal
  de Playrate en cada tick, para que el BPM equivalente siga en vivo la
  sección que está sonando. Case `EXTSTATE` escucha `tempo_map`.
- **`init.js`**: el boot pide el mapa; al desconectar, el watchdog
  resetea `nikPlayrateTempoMap` a `null` y el readout cae al placeholder
  `—` (`remote_control_projects.md` §3).

**Casos borde** que el diseño cubre: 1 solo tempo marker (se comporta como
un tempo fijo); tempo estable con cambios de métrica (no afecta, el
cálculo solo mira bpm, no time signature); sin tab activa o proyecto sin
guardar (el script opera sobre `proj = 0`, no depende de que el proyecto
esté guardado); REAPER cerrado (lo cubre el watchdog,
`remote_control_projects.md` §3).

**Fallback**: el tempo base de un solo punto (caso sin markers) usa
`GetTempoTimeSigMarker(0,0)` si existe, si no `Master_GetTempo()`.
`Master_GetTempo()` depende de la posición del cursor de edición (toma el
tempo del marker a su izquierda), así que solo es referencia estable en el
caso sin ningún marker de tempo.

**Principio general reutilizable**: cuando un valor derivado necesita
reflejar algo que cambia con la posición de reproducción (no solo con el
tiempo real), conviene enviar los datos crudos necesarios una sola vez
(on-demand) y resolver el valor derivado del lado del cliente usando
campos que **ya llegan** en el poll rápido existente (acá,
`playPosSeconds` de `TRANSPORT`) — evita agregar polls o scripts Lua
nuevos al loop de 10ms.

## 7. Readout principal de Playrate (fuera del popup)

`#nikPlayrateReadout` muestra el tempo equivalente en BPM, redondeado sin
decimales, reusando el cálculo del popup (no duplicado).

- `nikPlayrateComputeEquivalentBpm(percent)` — función pura en
  `playrate.js` que resuelve el tempo vigente vía el mapa de tempo (ver
  arriba). La consumen `nikPlayrateUpdateBpmField()` (campo del popup, un
  decimal) y `nikPlayrateRefreshMainReadout()` (readout principal,
  `Math.round()`, sin decimales): un solo lugar para corregir la
  precisión de ambos displays.
- **Disponibilidad del mapa de tempo sin abrir el popup**: disparo
  on-demand (`nikPlayrateRequestTempoMap()`) en el boot (`init()`) y en el
  cambio de proyecto activo (handler `active_project_name` en
  `wwr-dispatch.js`). Tras una desconexión no hay reintento activo
  (`remote_control_projects.md` §3).
- **Ícono** ♩ (negra musical, U+2669) a la izquierda del número, en
  `<span>` propio (`#nikPlayrateNoteIcon`). Contenedor
  `display:inline-flex; align-items:center`: centra por altura real de
  cada hijo; el centrado por `baseline` (default de texto) desalinea
  verticalmente un glifo de `font-size` distinto al del número.
- **Espaciado** de los readouts del bloque superior (métrica / ReaPitch /
  posición / Playrate / menú): `#nikReaPitchReadout` `left:20%`;
  `#nikPlayrateReadout` `right:18%`. El ancho de "posición" (centro del 
  bloque) varía según el formato mostrado (`measures.beats` vs `min:seg`, 
  ver `remote_control_ui.md` §5) — estos porcentajes son un punto medio 
  razonable contra el peor caso, no un centrado matemático exacto.

## 8. Pendiente

- **Precisión del cálculo Playrate→BPM**: se reportó como "a veces no muy
  precisa" con un tempo base fijo; sin confirmar si persiste con el mapa
  de tempo. El cálculo está en una sola función
  (`nikPlayrateComputeEquivalentBpm`), así que una corrección aplica a
  ambos displays.

## 9. Archivos de este dominio

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
