# MODULARIZACIÓN — Control Remoto REAPER (nsaudio_remote_control)

**Propósito de este doc:** retomar la modularización del control remoto en
una conversación nueva sin perder criterio ni contexto. Sintético, sin
narrativa de sesión — hechos vivos y plan, nada más.

**Sirve leído junto con `remote_control.md`** (arquitectura Lua/ExtState,
convenciones de nombres, gotchas del crate/protocolo) — este doc es
específico de la modularización HTML/JS, no lo duplica.

---

## Estado actual (hecho)

Deploy: todo cuelga de la carpeta que sirve `reaper_www_root`, mismo nivel
que `main.js`/`sw.js` ya existentes.

```
reaper_www_root/
├── nsaudio_remote_control.html   ← shell: head, markup principal, <script src> en orden
├── styles.css                    ← <style> original, sin cambios de contenido
├── config.js                     ← Command IDs + constantes de customización
├── modal-loader.js               ← fetch + inyección de modals/*/*.html en #modalsRoot
├── core/
│   ├── utils.js                  ← funciones puras sin estado (setTextForObject, lumaOffset, nikLerpColor, nikDeviationColor, elAttribute, easeInOutCubic, BtoMB)
│   ├── state.js                  ← estado global consolidado (transporte/tracks, flags ReaPitch/Playrate/markers, faders/sends, escala UI)
│   ├── faders.js                 ← arrastre de faders de volumen y sends
│   └── tracks-render.js          ← hitbox() — expandir/colapsar filas de track
├── markers/
│   └── markers.js                ← parseo/resolución de nombres y colores de markers (compartido shell + marker-browser)
└── modals/
    ├── playrate/{playrate.html, playrate.js}
    ├── reapitch/{reapitch.html, reapitch.js}
    ├── tracksvis/{tracksvis.html, tracksvis.js}
    ├── marker-browser/{marker-browser.html, marker-browser.js}
    └── project-tabs/{project-tabs.html, project-tabs.js}
```

Los 5 popups del control remoto están completamente extraídos y testeados
en REAPER. Pasos 1-5 de la modularización de `core/` (ver tabla más abajo)
también completos y testeados: `core/utils.js`, `markers/markers.js`,
`core/state.js`, `core/faders.js`, `core/tracks-render.js`.
`nsaudio_remote_control.html` bajó de 2428 a ~2014 líneas tras los popups,
y bajó más todavía con estos 5 pasos (no remedido con precisión — pendiente
correr `wc -l` la próxima sesión).

### `config.js` — contenido
- `NIK_LUA_COMMANDS`: objeto `{ luaFile, commandId, pending? }` por acción.
  `luaFile: null` = wrapper no identificado todavía contra la carpeta real
  de Scripts (2 casos pendientes, ver "Pendientes" abajo). `pending: true`
  = el Command ID es un placeholder, no el real (caso ProjectTabs).
- `NIK_SLOW_POLL` / `NIK_ONDEMAND_READS`: string de poll consolidado.
  **Gotcha:** sumar una key nueva al Lua NO alcanza — hay que sumar su
  `GET/EXTSTATE/...` acá también, o el JS nunca la recibe.
- `NIK_MARKER_COLOR_MAP` + `NIK_MARKER_CHAIN_PATTERN`/`_STEP`: diccionario
  de colores/traducción de secciones de marker.
- `NIK_FADER_DBLTAP_MS`, `NIK_TRANSPORT_SCALE`: timing/UX.

### Convenciones establecidas (aplican a todo lo que sigue)
1. **Scripts clásicos, nunca `type="module"`.** El HTML tiene decenas de
   `onclick="nikAlgo()"` inline; con módulos ES esas funciones quedarían
   scopeadas al archivo y los onclick se romperían. Todo cuelga de
   `window`, cargado en orden (`config.js` → `modal-loader.js` →
   `modals/*/*.js`).
2. **Criterio de qué va en el JS de un modal vs. en el shell:** si una
   función es lógica de dominio del modal (aunque toque un elemento del
   DOM que vive fuera del modal, ej. el botón que lo abre en la UI
   principal), va en el JS del modal. Ejemplos ya resueltos así:
   - `nikReaPitchUpdateSemitoneDisplay`/`UpdateEnabledDisplay` (tocan
     `nikReaPitchReadout`, en el shell) → `reapitch.js`
   - `nikMarkerAreaClick` (trigger de apertura, vive en el shell como
     `onclick`) → `marker-browser.js`
   - `nikParseProjectTabs` (parser exclusivo del dominio) → `project-tabs.js`
   - Lo que SÍ queda en el shell: helpers usados por **más de un** módulo
     (ver `markers/markers.js` pendiente abajo) y el estado/dispatch core.
3. **Modal nuevo = 3 pasos:** crear `modals/<nombre>/<nombre>.html` +
   `.js`, sumar la ruta del `.html` a `NIK_MODAL_FRAGMENTS` en
   `modal-loader.js`, sumar `<script src="modals/<nombre>/<nombre>.js">`
   en `nsaudio_remote_control.html`.
4. **`fetch()` en `modal-loader.js` requiere same-origin** — servido por
   REAPER anda perfecto; abrir el `.html` directo por `file://` rompe los
   popups por CORS. No es un caso real de uso, pero vale saberlo si algún
   día se prueba distinto.
5. Las funciones de `wwr_onreply` que tocan elementos de un modal por ID
   ya están guardadas con `if (elemento) {...}` — el `fetch` async de
   `modal-loader.js` es seguro aunque un poll llegue antes de que el modal
   esté inyectado en el DOM (no revienta, simplemente no-opea esa vez).
6. **Gotcha de `hereCss = document.styleSheets[1]`** (usado en
   `calculateScale()` para buscar la regla `.optionsBar` en runtime): el
   índice sigue apuntando bien porque el `<link rel="stylesheet"
   href="styles.css">` quedó en la misma posición del DOM donde estaba el
   `<style>` inline original. Si en algún momento se reordenan los
   `<link>`/`<style>` del `<head>`, revisar este índice.

---

## Pendiente — separar el `core/` que queda en el shell

Pasos 1-5 completos y testeados (ver `## Estado actual (hecho)` arriba:
`core/utils.js`, `markers/markers.js`, `core/state.js`, `core/faders.js`,
`core/tracks-render.js`). Quedan los 2 módulos más grandes, dejados para
el final a propósito (ver razón en la tabla original — dispatch toca casi
todo lo demás, por eso conviene abordarlo con todo lo demás ya en su
lugar):

| Módulo propuesto | Contenido | Por qué separado |
|---|---|---|
| `core/wwr-dispatch.js` | `wwr_onreply()` — el bloque más grande del archivo, con diferencia | Parser central del feed de REAPER. Llama a funciones de casi todos los demás módulos (dispatch), por eso va al final del orden de implementación |
| `core/init.js` | `init()`, `on_record_button`, `prompt_abort`, `prompt_seek`, `calculateScale`, `nikCheckProjectNameWatchdog` | Bootstrapping + handlers sueltos de transporte que no encajan en otro bucket |

### Orden de implementación sugerido
1. `core/wwr-dispatch.js` — el más grande y el que más toca; abordar con
   tiempo para probar bien después, no apurar sobre el cierre de una
   sesión
2. `core/init.js` — al final, porque es el que ata todo (`wwr_req_recur`,
   `wwr_start`)

Al terminar esto, `nsaudio_remote_control.html` debería quedar como HTML
puro + `<script src>` en orden — sin ninguna lógica de negocio inline.

---

## Pendientes NO relacionados a la modularización (no perder de vista)

Documentados en detalle en `remote_control.md` — quedan citados acá solo
para que no se pierdan al seguir tocando `config.js`:

- `NIK_LUA_COMMANDS.reaPitchSet/reaPitchToggle/playrateSet/
  playrateTogglePreservePitch/tabPrev/tabNext`: `luaFile: null`, falta
  confirmar contra la reorg de la carpeta de Scripts.
- `NIK_LUA_COMMANDS.projectTabsRead/projectTabsSelect`:
  `pending: true` — Command IDs son placeholders, faltan registrar los
  scripts reales en el Action List.
- Reorg de la carpeta Lua (separar scripts del control remoto de los de
  otras funciones, normalizar nombres a la convención adoptada a mitad de
  desarrollo) — alcance propio, no arrancado todavía.
