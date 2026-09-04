# IMPL — Fader SVG calcado en popups (Playrate/ReaPitch) + legibilidad

Doc transitorio de sesión. Destino final: fusionar a `features/remote_control.md`
(sección de arquitectura de archivos + tabla de "Funcionalidades activas" +
posible entrada nueva de gotchas). No reemplaza al doc — es insumo para
cuando se una con los IMPL de las otras sesiones en paralelo.

## Qué se hizo

Los dos popups con fader vertical (`modals/playrate/`, `modals/reapitch/`)
usaban un `<input type="range">` rotado por CSS con el thumb/track nativos
del navegador (círculo cyan liso). Se reemplazó la capa visual por un calco
del knob de fader nativo de la UI principal (el de `trackRow2Svg`, fila de
volumen de track), sin tocar la lógica de arrastre existente. De paso se
corrigieron problemas de legibilidad (cyan saturado) y de layout (botones
+/- tapando el fader, bloques no centrados contra su referencia).

## Archivo nuevo

**`core/fader-knob-svg.js`** — módulo reutilizable, calco del `<g class="fader">`
de `trackRow2Svg` (los 5 `linearGradient` + 2 paths de outline). Expone
`nikCreateFaderKnobSvg({ mountEl, orientation })` → `{ setFraction(f) }`
(`f` entre 0 y 1, mueve el `translate` del grupo a lo largo del recorrido).

- Geometría lógica fija, `viewBox="0 0 320 72"` (mismo box que ya usaba
  `.nikVFaderTrack` para el `<input>` antes de rotarlo):
  - pista: `x` 20→300 (280 de largo, margen simétrico de 20 a cada lado),
    alto 8, centrada en `y` (32→40).
  - knob: 46 de ancho × 36 de alto, centrado en `y` (18→54).
  - recorrido del knob: `x` 20→254 (234 = 280 − 46).
- **Un solo asset sirve para horizontal y vertical**: la variante vertical
  no redibuja paths, envuelve el `<svg>` en `rotate(-90deg)` vía la clase
  `.nikFaderKnobSvg--vertical` (mismo truco que ya usaba `.nikVFaderTrack`
  sobre el `<input>` nativo).
- **Gradientes simplificados**: el original usa `gradientUnits="userSpaceOnUse"`
  con matrices por pieza; acá se usa `objectBoundingBox` (default, `x1/y1/x2/y2`
  en 0–1) — mismo degradé visual dentro de cada shape, sin la matriz.
- **IDs de gradiente con sufijo único por instancia** (`nikFaderKnobSvgSeq`,
  contador incremental) — mismo motivo que `nikUniquifyGradientIds()` en
  `core/wwr-dispatch.js` (ver `01_CONVENCIONES.md`, sección de clonado de
  templates con `id`): más de un fader knob en la misma página duplicaría
  `<linearGradient id>` si no se sufija.
- **Track del knob**: color sólido `#262626` (el mismo gris que ya usan los
  botones del popup, `.nikVFaderStepBtn`/reset) — el original usa `#1A1A1A`
  con opacidad 0.5 sobre fondo `#333333` (fila de track); ese valor queda
  casi invisible sobre el fondo `#1a1a1a` del popup, por eso se resolvió
  distinto acá en vez de copiar el original tal cual.

## Arquitectura de la integración (decisión clave)

**El `<input type="range">` nativo se mantiene como única capa de
interacción** (drag, touch, teclado, doble-tap — toda la lógica ya provista
por `nikCreateVerticalFader` en `core/vertical-fader.js`). Se vuelve
invisible (`background:transparent`, thumb transparente) pero sigue
capturando el gesto. El SVG del knob se monta **encima**, en el mismo
`.nikVFaderWrap`, con `pointer-events:none` — capa puramente visual,
sincronizada con el valor real del input.

Se descartó reimplementar el drag a mano sobre el SVG (al estilo
`core/faders.js`, con `mousemove`/`touchmove` propios) por duplicar lógica
ya probada sin necesidad — el único requisito nuevo era visual.

### `core/vertical-fader.js` — hook agregado

`nikCreateVerticalFader(config)` acepta ahora dos claves opcionales:
- `knobMountId`: id del elemento donde montar el knob SVG (típicamente el
  mismo `.nikVFaderWrap`).
- `knobOrientation`: `"vertical"` (default si se omite y hay `knobMountId`)
  o `"horizontal"`.

Si `knobMountId` no se pasa, el fader sigue funcionando exactamente como
antes (compatible con cualquier instancia futura que no necesite el knob
visual). El knob se resincroniza en los tres puntos donde ya se tocaba
`display.textContent`: init, listener `"input"` (drag en vivo), y
`handle.setValue()` (usado tanto por el poll de servidor como por
`stepBy`/`reset`, que llaman a `setValue` internamente — no hizo falta
tocarlos).

## Cambios de layout en los popups

Mismo patrón aplicado en ambos: **sacar el elemento acompañante del flujo
normal (`position:absolute`) para que el elemento principal sea el único
que participa del centrado del contenedor**, en vez de centrar el bloque
conjunto.

- **Botones +/−** (Playrate y ReaPitch): antes en fila a los costados del
  fader (tapaban el drag con el dedo, sobre todo el "+"). Ahora en columna
  a la izquierda del fader (+ arriba, − abajo, gap 16px entre ambos),
  sacados del flujo con `position:absolute; right:100%` dentro del
  `.nikVFaderWrap` (que pasa a `position:relative`) — así el fader queda
  centrado contra el readout numérico de arriba, no contra el bloque
  botones+fader. Tamaño de `.nikVFaderStepBtn` subido de 44px a 52px
  (mejor agarre, menos roce con el fader).
- **Input de BPM + label "BPM"** (solo Playrate): mismo patrón — el label
  "BPM" pasa a `position:absolute; left:100%` respecto de un wrapper
  `position:relative` alrededor del `<input>`, que ahora es el único
  elemento centrado por el contenedor flex.

## Legibilidad (readouts, título)

- Readouts numéricos grandes (`#nikPlayrateBpm`, `#nikReaPitchValue`):
  `#00D0FF` (cyan saturado) → `#FFFFFF`.
- Título del popup ("Playrate" / "Semitonos (Stem Bus)") y su línea
  inferior: `#00D0FF` → `#D0D0D0` (texto) / `#4A4A4A` (línea) — mismos
  grises ya usados en otras partes de la UI (texto secundario, borde de
  gradientes de `nikTabBtn`).
- **Dejado afuera a propósito**: el cyan del botón `#nikReaPitchEnableToggle`
  en estado "ON" (`reapitch.js`, `nikReaPitchUpdateEnabledDisplay`) — es un
  indicador de estado que se mira de refilón, no un readout que se sostiene
  la mirada. Si en uso real también molesta, queda pendiente de revisar.

## Gotcha nuevo: tap-highlight de Android/WebView

Fully Kiosk Browser (Chromium) pinta un recuadro celeste translúcido por
default en cualquier elemento tocable sin `-webkit-tap-highlight-color`
explícito — se notaba en botones y en el fader (drag). No es específico de
esta feature, aplica a toda la UI; se desactivó global en `styles.css`
(`html, body` + `button, input`). Candidato a documentar como gotcha general
del entorno Fully Kiosk, no solo de los popups.

## Archivos tocados

```
core/fader-knob-svg.js        ← nuevo
core/vertical-fader.js        ← hook knobMountId/knobOrientation
modals/playrate/playrate.html ← knobMountId, layout botones, layout BPM/label, colores
modals/playrate/playrate.js   ← knobMountId/knobOrientation en config del fader
modals/reapitch/reapitch.html ← knobMountId, layout botones, colores
modals/reapitch/reapitch.js   ← knobMountId/knobOrientation en config del fader
nsaudio_remote_control.html   ← <script src="core/fader-knob-svg.js">
styles.css                    ← input transparente, .nikFaderKnobSvg(--vertical),
                                 .nikVFaderStepBtn 52px, tap-highlight global
```

## Estado

Cerrado y probado en dispositivo (celular, Fully Kiosk). Sin pendientes
abiertos de esta sub-feature — candidato a subir el estado de "Playrate +
preserve pitch" y "Semitonos ReaPitch" en la tabla de funcionalidades
activas si corresponde mencionar el knob SVG ahí, o sumar una fila nueva
("Fader SVG calcado en popups") según cómo se prefiera organizar al fusionar.

## Mensaje de commit sugerido (ya usado)

```
feat(remote-control): calco de fader SVG nativo en popups + legibilidad

- Nuevo módulo core/fader-knob-svg.js: knob de fader calcado del track
  row nativo (trackRow2Svg), reutilizable en horizontal/vertical como
  capa visual sobre el <input type="range"> existente (sin reemplazar
  su lógica de drag/touch/teclado/doble-tap).
- core/vertical-fader.js: hook opcional (knobMountId/knobOrientation)
  para montar y sincronizar el knob SVG con el valor del fader.
- Playrate y ReaPitch: fader nativo reemplazado visualmente por el
  knob calcado (orientación vertical), track recalcado con medidas
  reales y color visible sobre el fondo del popup.
- Botones +/-: reposicionados en columna a la izquierda del fader
  (antes en línea, tapaban el drag), agrandados, y sacados del flujo
  para no descentrar el fader respecto al readout numérico.
- Input de BPM (Playrate): centrado real respecto al display; "BPM"
  pasa a elemento satélite a su derecha.
- Readouts y label de título: cyan saturado reemplazado por blanco
  (valores) y gris neutro (título + línea inferior), mejor legibilidad
  sostenida.
- Tap-highlight de Android/WebView desactivado globalmente
  (-webkit-tap-highlight-color) — sacaba el recuadro celeste al tocar
  botones y fader.
```
