// modals/playrate/playrate.js — lógica del popup de Playrate.
// Markup en playrate.html (inyectado por modal-loader.js al boot).
// Depende de: NIK_ONDEMAND_READS, NIK_LUA_COMMANDS (config.js),
// nikPlayrateDragging, nikPreservePitchServerState (declaradas en index.html,
// core del estado runtime — pendiente de mover a core/state.js),
// nikCreateVerticalFader (core/vertical-fader.js), nikDeviationColor
// (core/utils.js).
// nikPlayrateUpdateDisplay() es llamada por nombre desde wwr_onreply
// (core/wwr-dispatch.js) — mismo criterio que ReaPitch: lógica de dominio
// del modal, aunque toque nikPlayrateReadout (vive fuera del modal, en la
// UI principal).
//
// BPM: nikPlayrateTempoMap es el mapa de tempo completo del proyecto
// (array de {pos, bpm}), leído on-demand al abrir el modal / boot / cambio
// de proyecto (Nik_Playrate_ReadTempoMap.lua) — null hasta la primera
// respuesta o si no llegó ningún valor válido. nikPlayrateTempoAt() resuelve
// el bpm original vigente en una posición dada -- necesario en proyectos
// con mapa de tempo variable (intros atípicas), donde no existe "un" tempo
// de referencia único (reemplaza al viejo nikPlayrateBaseTempo, un solo
// número fijo). La traducción fader↔BPM es puramente de cliente, no
// dispara un segundo wwr_req: el commit real (SET/EXTSTATE playrate_target)
// sale siempre a través del fader.
//
// Cargado como <script src> clásico (sin type="module"): las funciones
// cuelgan de `window` para que los onclick="..." inline de playrate.html
// las encuentren igual que antes.

var nikPlayrateFaderHandle = null;
// Mapa de tempo completo del proyecto: array de {pos, bpm} ordenado por pos
// ascendente, o null hasta la primera respuesta / si no llegó ningún valor
// válido. Reemplaza al viejo nikPlayrateBaseTempo (un solo número) -- ver
// Nik_Playrate_ReadTempoMap.lua.
var nikPlayrateTempoMap = null;

function nikPlayrateEnsureFader() {
    if (nikPlayrateFaderHandle) return nikPlayrateFaderHandle;
    nikPlayrateFaderHandle = nikCreateVerticalFader({
        key: "playrate",
        sliderId: "nikPlayrateSlider",
        displayId: "nikPlayrateValue",
        knobMountId: "nikPlayrateFaderWrap",
        knobOrientation: "vertical",
        min: 50, max: 150, step: 1, defaultValue: 100,
        formatDisplay: function (v) { return v + "%"; },
        onDragChange: function (v) {
            nikPlayrateDragging = true;
            nikPlayrateUpdateBpmField(v);
        },
        onCommit: nikPlayrateCommit
    });
    return nikPlayrateFaderHandle;
}

function nikPlayrateCommit(val) {
    wwr_req("SET/EXTSTATE/NikRemote/playrate_target/" + val + ";" + NIK_LUA_COMMANDS.playrateSet.commandId + ";" + NIK_ONDEMAND_READS);
    window.setTimeout(function () { nikPlayrateDragging = false; }, 400);
}

function nikPlayrateStep(direction) {
    var fader = nikPlayrateEnsureFader();
    if (fader) fader.stepBy(direction);
}

// Busca el bpm original vigente en una posicion dada (el marker de tempo
// mas cercano hacia atras; si la posicion es anterior al primer marker,
// usa el primero -- mismo criterio que aplica REAPER para el tramo previo
// al primer tempo marker). Devuelve null si todavia no hay mapa cargado.
function nikPlayrateTempoAt(positionSeconds) {
    if (!nikPlayrateTempoMap || nikPlayrateTempoMap.length == 0) return null;
    var found = nikPlayrateTempoMap[0].bpm;
    for (var i = 0; i < nikPlayrateTempoMap.length; i++) {
        if (nikPlayrateTempoMap[i].pos <= positionSeconds) found = nikPlayrateTempoMap[i].bpm;
        else break;
    }
    return found;
}

// Único punto de cálculo del tempo equivalente (% de playrate -> BPM),
// compartido por el campo BPM del popup y el readout principal (fuera del
// modal). Usa el bpm original vigente en `positionSeconds` (por defecto la
// posición actual de reproducción, playPosSeconds) en vez de un tempo fijo
// -- necesario en proyectos con mapa de tempo variable, donde "un" tempo de
// referencia único no representa a toda la canción. Devuelve null si
// todavía no se conoce el mapa (antes del primer boot / tras reconectar).
function nikPlayrateComputeEquivalentBpm(percent, positionSeconds) {
    var baseTempo = nikPlayrateTempoAt(positionSeconds != undefined ? positionSeconds : parseFloat(playPosSeconds));
    if (baseTempo == null || baseTempo <= 0) return null;
    return baseTempo * (percent / 100);
}

// Recalcula el campo de BPM a partir del % del fader. No pisa el campo
// mientras el usuario lo tiene enfocado (está tipeando) — mismo criterio
// que ya usa nikPreservePitchCheckbox contra document.activeElement.
function nikPlayrateUpdateBpmField(percent) {
    var bpmInput = document.getElementById("nikPlayrateBpm");
    if (!bpmInput || document.activeElement == bpmInput) return;
    var bpm = nikPlayrateComputeEquivalentBpm(percent);
    if (bpm == null) {
        bpmInput.value = "";
        bpmInput.placeholder = "—";
        bpmInput.disabled = true;
        return;
    }
    bpmInput.disabled = false;
    bpmInput.value = bpm.toFixed(1);
}

// Pinta el readout principal (#nikPlayrateReadout, fuera del modal) con el
// tempo equivalente redondeado sin decimales — placeholder "—" mientras no
// haya nikPlayrateBaseTempo disponible (boot / reconexión en curso).
function nikPlayrateRefreshMainReadout(percent) {
    var readout = document.getElementById("nikPlayrateReadout");
    var bpmValue = document.getElementById("nikPlayrateBpmValue");
    if (!readout || !bpmValue) return;
    var bpm = nikPlayrateComputeEquivalentBpm(percent);
    bpmValue.textContent = (bpm != null) ? Math.round(bpm) : "—";
    readout.style.color = nikDeviationColor(parseFloat(percent), 100, 50, 150);
}

// Dispara la lectura on-demand del mapa de tempo completo sin abrir el
// popup — usada al bootear la app (init.js) y al detectar cambio de
// proyecto activo (wwr-dispatch.js), para que el readout principal muestre
// BPM equivalente desde el arranque, no solo después de haber abierto el
// popup alguna vez. Reemplaza a nikPlayrateRequestBaseTempo.
function nikPlayrateRequestTempoMap() {
    wwr_req(NIK_LUA_COMMANDS.playrateTempoMapRead.commandId + ";GET/EXTSTATE/NikRemote/tempo_map");
}

// onchange del campo de BPM: traduce a %, clampea al rango del fader,
// commitea el % clampeado (nunca el BPM tipeado directo) y reescribe el
// campo con el BPM real aplicado — con flash visual si hubo cap.
function nikPlayrateBpmCommit(bpmInput) {
    var fader = nikPlayrateEnsureFader();
    var baseTempo = nikPlayrateTempoAt(parseFloat(playPosSeconds));
    if (!fader || baseTempo == null || baseTempo <= 0) return;
    var typedBpm = parseFloat(bpmInput.value);
    if (isNaN(typedBpm)) { nikPlayrateUpdateBpmField(fader.getValue()); return; }

    var rawPercent = (typedBpm / baseTempo) * 100;
    var clampedPercent = Math.round(Math.min(150, Math.max(50, rawPercent)));
    var wasClamped = (Math.round(rawPercent) != clampedPercent);

    fader.setValue(clampedPercent);
    nikPlayrateCommit(clampedPercent);
    nikPlayrateUpdateBpmField(clampedPercent);

    if (wasClamped) nikPlayrateFlashBpmClamp(bpmInput);
}

function nikPlayrateFlashBpmClamp(el) {
    el.classList.add("nikVFaderClampFlash");
    window.setTimeout(function () { el.classList.remove("nikVFaderClampFlash"); }, 400);
}

// Enter confirma sin depender de que el teclado virtual dispare blur solo
// (varía entre navegadores / Fully Kiosk).
function nikPlayrateBpmKeydown(event, el) {
    if (event.key == "Enter") { el.blur(); }
}

// Llamada desde wwr-dispatch.js al llegar EXTSTATE/tempo_map — ya sea
// on-demand al abrir el modal, o disparado sin abrirlo (boot/cambio de
// proyecto, ver nikPlayrateRequestTempoMap). Parsea "pos1:bpm1,pos2:bpm2,..."
// a un array ordenado, y refresca ambos displays de una: el campo BPM del
// popup (si existe fader) y el readout principal (con el % actual conocido
// por el fader, sin esperar el próximo poll). Reemplaza a
// nikPlayrateSetBaseTempo.
function nikPlayrateSetTempoMap(val) {
    var map = [];
    if (val) {
        var pairs = val.split(",");
        for (var i = 0; i < pairs.length; i++) {
            var kv = pairs[i].split(":");
            var pos = parseFloat(kv[0]);
            var bpm = parseFloat(kv[1]);
            if (!isNaN(pos) && !isNaN(bpm) && bpm > 0) map.push({ pos: pos, bpm: bpm });
        }
        map.sort(function (a, b) { return a.pos - b.pos; });
    }
    nikPlayrateTempoMap = (map.length > 0) ? map : null;
    var fader = nikPlayrateEnsureFader();
    if (fader) {
        nikPlayrateUpdateBpmField(fader.getValue());
        nikPlayrateRefreshMainReadout(fader.getValue());
    }
}

// Llamada desde wwr-dispatch.js al llegar EXTSTATE/playrate (poll de fondo
// o refresco on-demand) — reemplaza el bloque que antes vivía inline ahí.
function nikPlayrateUpdateDisplay(val) {
    nikPlayrateRefreshMainReadout(val);
    if (!nikPlayrateDragging) {
        var fader = nikPlayrateEnsureFader();
        if (fader) fader.setValue(val, { silent: true });
        nikPlayrateUpdateBpmField(val);
    }
}

function nikOpenPlayrateModal() {
    nikPlayrateEnsureFader();
    wwr_req(NIK_ONDEMAND_READS + ";" + NIK_LUA_COMMANDS.playrateTempoMapRead.commandId + ";GET/EXTSTATE/NikRemote/tempo_map");
    document.getElementById("nikPlayrateOverlay").style.display = "flex";
}
function nikClosePlayrateModal() {
    document.getElementById("nikPlayrateOverlay").style.display = "none";
}
function nikPlayrateReset() {
    var fader = nikPlayrateEnsureFader();
    if (fader) fader.reset();
}
function nikPlayratePreservePitchChange(checked) {
    var isOn = (nikPreservePitchServerState == "on");
    if (checked != isOn) {
        wwr_req(NIK_LUA_COMMANDS.playrateTogglePreservePitch.commandId);
    }
}
