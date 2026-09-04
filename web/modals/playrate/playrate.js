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
// BPM: nikPlayrateBaseTempo es el tempo de referencia leído on-demand al
// abrir el modal (Nik_Playrate_ReadBaseTempo.lua) — null hasta la primera
// respuesta o si no llegó ningún valor válido. La traducción fader↔BPM es
// puramente de cliente, no dispara un segundo wwr_req: el commit real
// (SET/EXTSTATE playrate_target) sale siempre a través del fader.
//
// Cargado como <script src> clásico (sin type="module"): las funciones
// cuelgan de `window` para que los onclick="..." inline de playrate.html
// las encuentren igual que antes.

var nikPlayrateFaderHandle = null;
var nikPlayrateBaseTempo = null;

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

// Recalcula el campo de BPM a partir del % del fader. No pisa el campo
// mientras el usuario lo tiene enfocado (está tipeando) — mismo criterio
// que ya usa nikPreservePitchCheckbox contra document.activeElement.
function nikPlayrateUpdateBpmField(percent) {
    var bpmInput = document.getElementById("nikPlayrateBpm");
    if (!bpmInput || document.activeElement == bpmInput) return;
    if (nikPlayrateBaseTempo == null || nikPlayrateBaseTempo <= 0) {
        bpmInput.value = "";
        bpmInput.placeholder = "—";
        bpmInput.disabled = true;
        return;
    }
    bpmInput.disabled = false;
    bpmInput.value = (nikPlayrateBaseTempo * (percent / 100)).toFixed(1);
}

// onchange del campo de BPM: traduce a %, clampea al rango del fader,
// commitea el % clampeado (nunca el BPM tipeado directo) y reescribe el
// campo con el BPM real aplicado — con flash visual si hubo cap.
function nikPlayrateBpmCommit(bpmInput) {
    var fader = nikPlayrateEnsureFader();
    if (!fader || nikPlayrateBaseTempo == null || nikPlayrateBaseTempo <= 0) return;
    var typedBpm = parseFloat(bpmInput.value);
    if (isNaN(typedBpm)) { nikPlayrateUpdateBpmField(fader.getValue()); return; }

    var rawPercent = (typedBpm / nikPlayrateBaseTempo) * 100;
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

// Llamada desde wwr-dispatch.js al llegar EXTSTATE/base_tempo (on-demand,
// disparado en nikOpenPlayrateModal).
function nikPlayrateSetBaseTempo(val) {
    var parsed = parseFloat(val);
    nikPlayrateBaseTempo = (isNaN(parsed) || parsed <= 0) ? null : parsed;
    var fader = nikPlayrateEnsureFader();
    if (fader) nikPlayrateUpdateBpmField(fader.getValue());
}

// Llamada desde wwr-dispatch.js al llegar EXTSTATE/playrate (poll de fondo
// o refresco on-demand) — reemplaza el bloque que antes vivía inline ahí.
function nikPlayrateUpdateDisplay(val) {
    var readout = document.getElementById("nikPlayrateReadout");
    if (readout) {
        readout.textContent = val + "%";
        readout.style.color = nikDeviationColor(parseFloat(val), 100, 50, 150);
    }
    if (!nikPlayrateDragging) {
        var fader = nikPlayrateEnsureFader();
        if (fader) fader.setValue(val, { silent: true });
        nikPlayrateUpdateBpmField(val);
    }
}

function nikOpenPlayrateModal() {
    nikPlayrateEnsureFader();
    wwr_req(NIK_ONDEMAND_READS + ";" + NIK_LUA_COMMANDS.playrateBaseTempoRead.commandId + ";GET/EXTSTATE/NikRemote/base_tempo");
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
