# Sesión transitoria — fader vertical modular (Playrate + ReaPitch)

Trabajo **cerrado** en la sesión anterior. Este doc es materia prima para
que una sesión futura lo vuelque a la documentación permanente
(`features/remote_control.md`, y posiblemente `01_CONVENCIONES.md` para
los gotchas de CSS) — no es bootstrap de trabajo pendiente, es insumo
para actualizar docs y después descartarse.

## Qué se construyó

- **`core/vertical-fader.js`** (archivo nuevo): componente modular
  `nikCreateVerticalFader(config)`, reutilizado por `playrate.js` y
  `reapitch.js`.
- **Decisión de arquitectura:** `<input type="range">` nativo rotado
  -90° por CSS, no un componente de drag SVG custom desde cero — reusa
  el manejo de touch/mouse nativo del input, evita reinventar lo que
  `core/faders.js` ya resuelve para un caso distinto (faders de volumen,
  con geometría propia por color de track).
- Doble-tap-reset generalizado a partir del patrón ya existente en
  `core/faders.js` (`faderCheckDoubleTap`/`faderLastTapAr`), con key
  string en vez de track id.
- Botones de step (+/−) junto al fader, mismo `config.step`.
- Integrado en:
  - `modals/reapitch/reapitch.html` + `reapitch.js` — caso simple, sin BPM.
  - `modals/playrate/playrate.html` + `playrate.js` — suma traducción
    bidireccional playrate% ↔ BPM.

## Feature nueva: BPM bidireccional en Playrate

- **Tempo base:** primer marker de tempo (`GetTempoTimeSigMarker(0,0)`)
  si existe alguno; si no, `Master_GetTempo()`. **Confirmado
  empíricamente** (testing con proyectos sin markers / 1 marker / mapa
  completo): `Master_GetTempo()` depende de la posición del cursor de
  edición (toma el tempo del marker a su izquierda) — no es una
  referencia estable salvo en el caso sin ningún marker de tempo.
  `GetTempoTimeSigMarker(0,0)` sí es estable independientemente del
  cursor.
- **Nuevo script Lua:** `Nik_Playrate_ReadBaseTempo.lua` (`RemoteControl/`),
  on-demand — no vive en `Nik_RemoteState_Poll`/`NIK_SLOW_POLL` (mismo
  criterio ya usado para `projectTabsRead`: costo no justifica sumarlo al
  tick de fondo de 1000ms). Se encadena directo en el `wwr_req` de
  `nikOpenPlayrateModal()`.
- **Command ID:** `playrateBaseTempoRead` en `config.js` — quedó con
  placeholder `pending:true`, confirmar que se registró y se reemplazó
  por el Command ID real.
- **Traducción:** `bpm = baseTempo * (percent/100)`; inversa con clamp al
  rango del fader, redondeado a entero (paso del slider).
- **Rango del fader de Playrate: 50–150%** (no 40–150 como el slider
  original) — cambiado en esta sesión para que el punto medio matemático
  (100%) coincida con el `defaultValue`, evitando el desalineo visual
  círculo/botones-de-step que generó confusión (ver gotcha abajo).
  Confirmado con Nico que no usa playrate por debajo de 50% en la
  práctica.
- **Clamp visual:** flash breve de color/fondo (`.nikVFaderClampFlash`)
  cuando el BPM tipeado excede el rango y se corrige.
- **Campo BPM:** confirmación por `onchange` (blur/Enter) — no botón
  "Aplicar", por consistencia con el resto de la UI. Select-all al
  enfocar (`onfocus="this.select()"`). Enter fuerza `blur()` explícito
  (no depender de que el teclado virtual dispare blur solo).
- **Jerarquía visual:** BPM es el número protagonista (grande, color de
  acento), % es secundario (chico, gris) — decisión de UX confirmada,
  invertida respecto al diseño original donde el % era el protagonista.
- **Pendiente en observación, no confirmado como bug:** delta de -2/-3
  BPM contra medición manual de tap-tempo. Candidato más probable: margen
  de error de la medición humana (redondeo del % a entero introduce
  error de solo décimas de BPM, no unidades). Retomar si aparece una
  medición más dura (click grabado + software).

## Gotchas de CSS descubiertos (candidatos para `01_CONVENCIONES.md`)

- `<input type="range">` rotado con `transform:rotate(-90deg)` para
  verticalizarlo: el thumb custom (`-webkit-appearance:none` en el
  pseudo-elemento) necesita **también** `-webkit-appearance:none` en el
  `<input>` base — si falta, Chrome acepta el color/background del thumb
  pero ignora `width`/`height` (geometría nativa se mantiene aunque el
  pintado sea custom).
- Fórmula de centrado del thumb custom contra el runnable-track:
  `margin-top = (trackHeight - thumbHeight) / 2`. Hay que recalcularlo
  cada vez que cambia cualquiera de los dos valores (track o thumb) — no
  se auto-ajustan entre sí.
- El desalineo aparente entre el thumb y controles fijos alrededor (ej.
  botones de step centrados en el wrap) **no es necesariamente un bug de
  CSS** — si el valor actual del slider no coincide con el punto medio
  matemático del rango (`(min+max)/2`), el thumb va a aparecer corrido
  de ese centro por diseño. Antes de sospechar un bug de centrado,
  confirmar si el rango tiene su default en el punto medio (caso real:
  se sospechó un bug de rotación/CSS durante varias rondas, y terminó
  siendo esto).
- Margins asimétricos en un wrapper que después pasa a integrarse dentro
  de un layout flex con otros elementos (ej. botones al lado) pueden
  generar desalineos que en realidad vienen de un margin que sobró de
  una versión anterior del layout, no de la geometría del componente en
  sí.

## Archivos tocados esta sesión

- `core/vertical-fader.js` (nuevo)
- `styles.css` (`.nikVFaderWrap`, `.nikVFaderTrack` + pseudo-elementos,
  `.nikVFaderStepBtn`, `.nikVFaderClampFlash`)
- `modals/reapitch/reapitch.html`, `modals/reapitch/reapitch.js`
- `modals/playrate/playrate.html`, `modals/playrate/playrate.js`
- `core/wwr-dispatch.js` (caso `EXTSTATE`/`playrate` refactorizado a
  delegar en `nikPlayrateUpdateDisplay()`, nuevo caso `base_tempo`)
- `config.js` (`playrateBaseTempoRead` agregado a `NIK_LUA_COMMANDS`)
- `Nik_Playrate_ReadBaseTempo.lua` (nuevo, `RemoteControl/`)
