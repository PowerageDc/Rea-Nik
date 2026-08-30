// modals/playrate/playrate.js — lógica del popup de Playrate.
// Markup en playrate.html (inyectado por modal-loader.js al boot).
// Depende de: NIK_ONDEMAND_READS, NIK_LUA_COMMANDS (config.js),
// nikPlayrateDragging, nikPreservePitchServerState (declaradas en index.html,
// core del estado runtime — pendiente de mover a core/state.js).
// Cargado como <script src> clásico (sin type="module"): las funciones
// cuelgan de `window` para que los onclick="..." inline de playrate.html
// las encuentren igual que antes.

function nikOpenPlayrateModal() {
    wwr_req(NIK_ONDEMAND_READS);
    document.getElementById("nikPlayrateOverlay").style.display = "flex";
    }
function nikClosePlayrateModal() {
    document.getElementById("nikPlayrateOverlay").style.display = "none";
    }
function nikPlayrateSliderInput(val) {
    nikPlayrateDragging = true;
    document.getElementById("nikPlayrateValue").textContent = val + "%";
    }
function nikPlayrateSliderCommit(val) {
    wwr_req("SET/EXTSTATE/NikRemote/playrate_target/" + val + ";" + NIK_LUA_COMMANDS.playrateSet.commandId + ";" + NIK_ONDEMAND_READS);
    window.setTimeout(function(){ nikPlayrateDragging = false; }, 400);
    }
function nikPlayrateReset() {
    document.getElementById("nikPlayrateSlider").value = 100;
    document.getElementById("nikPlayrateValue").textContent = "100%";
    nikPlayrateSliderCommit(100);
    }
function nikPlayratePreservePitchChange(checked) {
    var isOn = (nikPreservePitchServerState == "on");
    if (checked != isOn) {
        wwr_req(NIK_LUA_COMMANDS.playrateTogglePreservePitch.commandId);
        }
    }
