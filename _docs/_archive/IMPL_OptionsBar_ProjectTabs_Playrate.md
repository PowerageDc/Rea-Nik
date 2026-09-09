# IMPL — OptionsBar (Solo in front) / Project Tabs (stop + flicker) / Playrate readout

Sesión de continuación sobre `PENDING_optionsbar_markers.md` — cierra los
puntos 1 y 2 de ese doc (completo, con su bug secundario), y suma un tema
nuevo no listado ahí: el readout principal de Playrate. El punto 3
(compases pre-marker) queda tal cual estaba, sin tocar.

Decisiones ya cerradas acá — no reabrir sin pedido explícito de Nik.

---

## 1. Bug: selector de project tabs no detenía la reproducción

**Cerrado.** Causa: `Nik_ProjectTabs_Select.lua` cambiaba de proyecto sin
detener antes la reproducción del proyecto activo saliente.

**Fix:** un solo `reaper.Main_OnCommand(40667, 0)` (Transport: Stop, save
all recorded media) agregado en el propio script Lua, antes del
`SelectProjectInstance`. Se decidió del lado Lua (un solo lugar) en vez de
encadenarlo desde `project-tabs.js` como hacen `tabPrev`/`tabNext`, para no
duplicar el patrón en dos capas.

```lua
-- Nik_ProjectTabs_Select.lua
local target = tonumber(reaper.GetExtState("NikRemote", "project_tabs_target_idx"))
if target then
    local proj = reaper.EnumProjects(target)
    if proj then
        reaper.Main_OnCommand(40667, 0) -- Transport: Stop, save all recorded media
        reaper.SelectProjectInstance(proj)
        end
    end
```

Validado por Nik en REAPER.

## 2. Bug secundario: parpadeo del popup de project tabs

**Cerrado.** Causa: `nikOpenProjectTabsModal()` mostraba el overlay con el
`innerHTML` de la última apertura (resaltado viejo) hasta que llegaba la
respuesta on-demand de `Nik_ProjectTabs_Read.lua`.

**Fix:** se aprovecha que `nikCurrentProjectName` ya está siempre fresco
(actualizado por el poll de fondo cada 1000ms, en `wwr-dispatch.js`) — al
abrir el popup, se repinta el resaltado de la lista ya renderizada contra
ese valor, antes de esperar la respuesta on-demand. Para poder comparar,
cada ítem de la lista ahora guarda `data-name` (nombre completo del
proyecto) además de `data-idx`/`data-active`.

```js
// project-tabs.js
function nikOpenProjectTabsModal() {
    nikRefreshProjectTabsHighlight();
    wwr_req(NIK_LUA_COMMANDS.projectTabsRead.commandId + ";GET/EXTSTATE/NikRemote/project_tabs");
    document.getElementById("nikProjectTabsOverlay").style.display = "flex";
    }

function nikRefreshProjectTabsHighlight() {
    var list = document.getElementById("nikProjectTabsList");
    if (!list || typeof nikCurrentProjectName == "undefined" || nikCurrentProjectName == null) return;
    var items = list.children;
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var isActive = (item.getAttribute("data-name") == nikCurrentProjectName);
        item.setAttribute("data-active", isActive ? "1" : "0");
        item.style.color = isActive ? "#00FF99" : "#A8A8A8";
        }
    }
```

No-opea sola en la primera apertura de la sesión (lista todavía vacía) —
sin guardas extra necesarias.

## 3. UI/UX: resaltado del proyecto activo (popup de tabs)

**Cerrado.** No era un problema de tipografía fea — el `font-weight:bold`
condicional (solo en la fila activa) hacía que esa fila se sintiera
"colgada"/desalineada respecto a las demás. Se sacó el bold; el color
(`#00FF99` activo / `#A8A8A8` inactivo) alcanza para diferenciar sin
generar salto de layout entre filas.

## 4. Nuevo: toggle "Solo in front"

**Cerrado.** Command ID confirmado por Nik en el Action List de su PC:
`40745` (acción nativa, toggle). Reemplaza al botón `ClipClear` en
`#optionsBar` (sin uso real, mismo lugar/tamaño, sin tocar el `viewBox`).

**Ícono:** spotlight simple (fuente puntual + haz + óvalo de piso), tres
elementos con id propio para poder cambiar `fill` directo por JS:
`iconSoloInFrontSource`, `iconSoloInFrontBeam`, `iconSoloInFrontSpot`.
Apagado: `#808080` (gris, mismo tono que otros íconos secundarios de la
barra). Prendido: `#FFC107` (ámbar — color nuevo, no pisa ningún otro
botón). El fondo del botón (`.iconBg`) también se oscurece al activarse,
con una regla CSS propia por `id` (no la genérica `.button.nikToggledOn`
que ya usa LoopRec en rojo, para no mezclar el lenguaje visual de
"grabación" con el de "solo"):

```css
#buttonSoloInFront.nikToggledOn .iconBg {
    fill: #4a3a14;
}
```

**Feedback:** patrón inspirado en `buttonMetro` pero más simple/robusto —
en vez de togglear visibilidad de dos grupos SVG duplicados vía
`childNodes` por índice (frágil, depende de whitespace del markup), acá se
cambia el atributo `fill` de los 3 elementos por `id` directo, disparado
desde el mismo `case "CMDSTATE"` de `wwr-dispatch.js`. Variable de estado:
`last_soloinfront` (agregada a `core/state.js`, mismo bloque que
`last_metronome`).

**Timing:** el click dispara `wwr_req('40745;GET/40745')` — la lectura de
`CMDSTATE` va encadenada en la misma request en vez de esperar el próximo
tick del poll de fondo (1000ms). Con esto el ícono cambia en el mismo
round-trip que la acción, sin desfasaje perceptible contra el efecto en
audio (que es instantáneo del lado de REAPER).

**Poll de fondo:** se sumó `;GET/40745` al final de `NIK_SLOW_POLL`
(`config.js`) como respaldo/sincronización periódica — no es un
`EXTSTATE` del Lua poll consolidado, es `CMDSTATE` nativo de REAPER, así
que no aplica el gotcha de "sumarlo también a `Nik_RemoteState_Poll.lua`".

## 5. Nuevo: readout principal de Playrate — BPM equivalente

**Cerrado** (la UI; la precisión del cálculo queda pendiente, ver abajo).
El readout de `#nikPlayrateReadout` mostraba `%` de playrate, un valor sin
utilidad real en ensayo. Ahora muestra el tempo equivalente en BPM,
redondeado sin decimales — reusando (no duplicando) el cálculo que ya
existía en el popup de Playrate.

**Cálculo compartido**, extraído a una función pura en `playrate.js`:

```js
function nikPlayrateComputeEquivalentBpm(percent) {
    if (nikPlayrateBaseTempo == null || nikPlayrateBaseTempo <= 0) return null;
    return nikPlayrateBaseTempo * (percent / 100);
}
```

Consumida tanto por `nikPlayrateUpdateBpmField()` (campo del popup, con un
decimal) como por `nikPlayrateRefreshMainReadout()` (readout principal,
`Math.round()`, sin decimales). Un solo lugar para corregir el día que se
revise la precisión (ver pendiente).

**Disponibilidad de `nikPlayrateBaseTempo` sin abrir el popup** — antes
solo se leía on-demand al abrir el modal de Playrate. Decisión tomada con
Nik: la más eficiente de tres opciones evaluadas (sumarlo al poll de
fondo / placeholder hasta abrir el popup / disparo on-demand puntual en
los momentos que importan). Se implementó el disparo on-demand
(`nikPlayrateRequestBaseTempo()`) en tres momentos:

- **Boot** (`init()`, `core/init.js`) — una vez, al arrancar la app.
- **Cambio de proyecto activo** (`wwr-dispatch.js`, handler de
  `active_project_name`) — el tempo base puede ser distinto por canción.
- **Reconexión implícita**: al detectar REAPER desconectado
  (`nikCheckProjectNameWatchdog()`, timeout de 3500ms sin actualización),
  se resetea `nikPlayrateBaseTempo = null` y el readout muestra `—`; se
  vuelve a pedir solo (indirectamente) cuando el próximo cambio de
  proyecto o el próximo boot dispare la lectura — no hay reintento activo
  mientras sigue desconectado, es aceptado así.

**Ícono:** se agregó el carácter ♩ (negra musical, U+2669) a la izquierda
del número, en un `<span>` propio (`#nikPlayrateNoteIcon`). El contenedor
pasó a `display:inline-flex; align-items:center` porque el centrado por
`baseline` (default de texto) rompía la alineación vertical al usar un
glifo con `font-size` distinto al del número — con flex, el centrado es
por altura real de cada hijo, no por baseline.

**Espaciado de los tres readouts del bloque superior** (métrica /
ReaPitch / posición / Playrate / menú) — estaban pegados a sus vecinos
fijos (métrica y menú), afinado a mano con devTools:
- `#nikReaPitchReadout`: `left:16%` → `left:20%`
- `#nikPlayrateReadout`: `right:16%` → `right:18%`

Nota: el ancho de "posición" (centro del bloque) varía según el formato
mostrado (Compases.Beats, Timecode, etc.) — estos porcentajes son un
punto medio razonable contra el peor caso, no un centrado matemático
exacto contra un ancho fijo.

---

## Archivos tocados esta sesión

- `RemoteControl/Nik_ProjectTabs_Select.lua`
- `web/modals/project-tabs/project-tabs.js`
- `web/nsaudio_remote_control.html`
- `web/core/wwr-dispatch.js`
- `web/styles.css`
- `web/config.js`
- `web/core/state.js`
- `web/core/init.js`
- `web/modals/playrate/playrate.js`

(Rutas de `web/` asumidas según la estructura de `00_CONTEXTO_GENERAL.md` —
ajustar si algún archivo vive en otro subdirectorio real.)

## Pendientes actualizados

**Sacar de `PENDING_optionsbar_markers.md`:** puntos 1 y 2 completos
(incluyendo el bug secundario del parpadeo). Punto 3 (compases
pre-marker) queda intacto, sigue pendiente sin tocar.

**Pendiente nuevo, no bloqueante:** revisar la precisión del cálculo de
tempo equivalente (`nikPlayrateComputeEquivalentBpm`) — Nik mencionó que
"a veces no es muy preciso". Al estar centralizado en una sola función,
el fix (cuando se decida qué corregir) aplica automáticamente a los dos
displays (popup + readout principal) sin tocar dos lugares.

## Mensaje de commit usado

```
remote: fix stop en cambio de tab, toggle Solo in front (40745), readout de Playrate en BPM equivalente

- project-tabs: Nik_ProjectTabs_Select.lua detiene la reproducción (40667)
  antes de cambiar de proyecto; popup resalta el tab correcto sin
  parpadeo (repintado contra nikCurrentProjectName al abrir) y sin bold
- optionsBar: nuevo botón #buttonSoloInFront (reemplaza a ClipClear, sin
  uso) con ícono spotlight, feedback CMDSTATE encadenado al click para
  respuesta instantánea
- playrate: readout principal muestra BPM equivalente redondeado en vez
  de %, calculado vía nikPlayrateComputeEquivalentBpm() compartido con
  el popup (pendiente: revisar precisión del cálculo); base_tempo se
  refresca en boot, cambio de proyecto, y placeholder al desconectar
- ajustes visuales: ícono ♩ en el readout de Playrate, espaciado de los
  readouts de Playrate/ReaPitch contra métrica/posición/menú
```
