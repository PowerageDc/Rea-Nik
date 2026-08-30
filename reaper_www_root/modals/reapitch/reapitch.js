// modals/reapitch/reapitch.js — lógica del popup de ReaPitch (semitonos, Stem Bus).
// Markup en reapitch.html (inyectado por modal-loader.js al boot).
// Depende de: NIK_ONDEMAND_READS, NIK_LUA_COMMANDS (config.js),
// nikReaPitchDragging/nikReaPitchLastSemitone/nikReaPitchLastEnabled y
// nikDeviationColor() (declaradas en index.html — pendiente de mover a
// core/state.js y core/utils.js respectivamente).
//
// nikReaPitchUpdateSemitoneDisplay() / nikReaPitchUpdateEnabledDisplay() son
// llamadas por nombre desde wwr_onreply (dispatch central en index.html) —
// se mantienen acá porque son lógica de dominio de ReaPitch, aunque también
// actualizan nikReaPitchReadout, que vive en la UI principal (fuera de este
// modal, es el botón que lo abre) — mismo criterio que agrupar toda la
// lógica de un dominio en su propio archivo, más allá de qué elemento del
// DOM toque en cada momento.
//
// Cargado como <script src> clásico (sin type="module"): las funciones
// cuelgan de `window` para que los onclick="..." inline de reapitch.html,
// y las llamadas desde wwr_onreply en index.html, las encuentren igual que
// antes.

function nikReaPitchUpdateSemitoneDisplay(val) {
    var readout = document.getElementById("nikReaPitchReadout");
    var numVal = (val == "none" || val == "mixed") ? 0 : val;
    if (readout) readout.textContent = (val == "none") ? "—" : (val == "mixed") ? "mix" : (numVal > 0 ? "+" + numVal : "" + numVal);
    nikReaPitchLastSemitone = (val == "none" || val == "mixed") ? val : numVal;
    nikRefreshReaPitchReadoutColor();
    if (!nikReaPitchDragging) {
        var slider = document.getElementById("nikReaPitchSlider");
        var valueLabel = document.getElementById("nikReaPitchValue");
        if (slider) slider.value = numVal;
        if (valueLabel) valueLabel.textContent = (val == "none") ? "—" : (val == "mixed") ? "mixed" : (numVal > 0 ? "+" + numVal : "" + numVal);
        }
    }

function nikReaPitchUpdateEnabledDisplay(val) {
    var btn = document.getElementById("nikReaPitchEnableToggle");
    if (btn) {
        var label = (val == "on") ? "ReaPitch: ON" : (val == "off") ? "ReaPitch: OFF" : (val == "mixed") ? "ReaPitch: mixed" : "ReaPitch: —";
        btn.textContent = label;
        btn.style.color = (val == "on") ? "#00D0FF" : (val == "off") ? "#5A5A5A" : "#A8A8A8";
        }
    nikReaPitchLastEnabled = val;
    nikRefreshReaPitchReadoutColor();
    }

// Color final del readout de semitonos: gris si esta apagado/mixto, si no, por desviacion del 0
function nikRefreshReaPitchReadoutColor() {
    var readout = document.getElementById("nikReaPitchReadout");
    if (!readout) return;
    if (nikReaPitchLastEnabled == "off") { readout.style.color = "#5A5A5A"; return; }
    if (nikReaPitchLastEnabled != "on" || nikReaPitchLastSemitone == null ||
        nikReaPitchLastSemitone == "none" || nikReaPitchLastSemitone == "mixed") {
        readout.style.color = "#A8A8A8";
        return;
        }
    readout.style.color = nikDeviationColor(nikReaPitchLastSemitone, 0, -12, 12);
    }

function nikOpenReaPitchModal() {
    wwr_req(NIK_ONDEMAND_READS);
    document.getElementById("nikReaPitchOverlay").style.display = "flex";
    }
function nikCloseReaPitchModal() {
    document.getElementById("nikReaPitchOverlay").style.display = "none";
    }
function nikReaPitchSliderInput(val) {
    nikReaPitchDragging = true;
    document.getElementById("nikReaPitchValue").textContent = (val > 0 ? "+" + val : val);
    }
function nikReaPitchSliderCommit(val) {
    wwr_req("SET/EXTSTATE/NikRemote/reapitch_semitone_target/" + val + ";" + NIK_LUA_COMMANDS.reaPitchSet.commandId + ";" + NIK_ONDEMAND_READS);
    window.setTimeout(function(){ nikReaPitchDragging = false; }, 400);
    }
function nikReaPitchReset() {
    document.getElementById("nikReaPitchSlider").value = 0;
    document.getElementById("nikReaPitchValue").textContent = "0";
    nikReaPitchSliderCommit(0);
    }

function nikReaPitchToggleEnable() {
    wwr_req(NIK_LUA_COMMANDS.reaPitchToggle.commandId);
    }
