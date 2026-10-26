// pa-mode.js — Modo PA del control remoto principal.
// Con el modo activo, M/S de cada fila (y el M del master) actúan sobre la
// capa PA (corte del send al master/padre, vía Nik_MonitorMix_PaRoute.lua) en
// vez de sobre el mute/solo reales de REAPER, y se dibujan con colores propios
// (styles.css, clases nikPa*). El estado llega en NikMonitorMix/pa_state.
// El modo no se persiste: al recargar la página arranca apagado.

var nikPaMode = false;
var nikPaState = null;   // { n, cut:{track:true}, solo:{track:true}, folders:{track:{n,cut,solo}}, cutCount, soloCount }
var nikPaLastRaw = null; // último pa_state recibido, para no reprocesar lo igual
var nikPaRowKey = {};    // por fila: { key, row } de lo último pintado

// Orden al script de ruteo + lectura inmediata del estado resultante.
function nikPaCmd(op, target) {
    return "SET/EXTSTATE/NikMonitorMix/pa_cmd/" + op + ":" + target + ";" +
        NIK_LUA_COMMANDS.monitorMixPaRoute.commandId +
        ";GET/EXTSTATE/NikMonitorMix/pa_state";
}

// Pedido de un botón M/S: PA con el modo activo, el pedido real si no.
function nikPaReq(op, target, realReq) {
    return nikPaMode ? nikPaCmd(op, target) : realReq;
}

function nikPaApplyState(raw) {
    raw = raw || "";
    if (raw === nikPaLastRaw) return;
    nikPaLastRaw = raw;
    var st = null;
    if (raw) {
        try {
            var j = JSON.parse(raw);
            st = { n: j.n || 0, cut: {}, solo: {}, folders: {}, cutCount: 0, soloCount: 0 };
            (j.cut || []).forEach(function (t) { st.cut[t] = true; st.cutCount++; });
            (j.solo || []).forEach(function (t) { st.solo[t] = true; st.soloCount++; });
            (j.folders || []).forEach(function (f) { st.folders[f.track] = f; });
        } catch (e) { st = null; }
    }
    nikPaState = st;
    nikPaRowKey = {};
    nikPaRenderChip();
}

// "none" | "part" | "all" para el M y el S de una fila (los folders cuentan hojas).
function nikPaRowStates(track) {
    var st = nikPaState;
    if (!st) return { mute: "none", solo: "none" };
    var f = st.folders[track];
    if (f) {
        return {
            mute: f.cut >= f.n ? "all" : (f.cut > 0 ? "part" : "none"),
            solo: f.solo >= f.n ? "all" : (f.solo > 0 ? "part" : "none")
        };
    }
    return { mute: st.cut[track] ? "all" : "none", solo: st.solo[track] ? "all" : "none" };
}

function nikPaSetBtn(group, offEl, onEl, state) {
    var on = state === "all";
    offEl.style.visibility = on ? "hidden" : "visible";
    onEl.style.visibility = on ? "visible" : "hidden";
    group.classList.toggle("nikPaAll", on);
    group.classList.toggle("nikPaPart", state === "part");
}

// Se llama en cada línea TRACK, después del bloque de flags (que repinta los
// botones desde los flags de REAPER): en modo PA los pisa con el estado PA.
function nikPaApplyRow(track, row, flags) {
    var key = "off";
    var s = null;
    if (nikPaMode) {
        s = nikPaRowStates(track);
        key = s.mute + "/" + s.solo + "/" + flags;
    }
    var prev = nikPaRowKey[track];
    if (prev && prev.key === key && prev.row === row) return;
    nikPaRowKey[track] = { key: key, row: row };

    var muteG = row.getElementsByClassName("mute")[0];
    var soloG = row.getElementsByClassName("solo")[0];
    if (!nikPaMode) {
        muteG.classList.remove("nikPaAll", "nikPaPart");
        soloG.classList.remove("nikPaAll", "nikPaPart");
        return;
    }
    // Con rec armado el botón mute está oculto y lo ocupa el de monitoreo.
    if (!(flags & 64)) {
        nikPaSetBtn(muteG, row.getElementsByClassName("mute-off")[0],
            row.getElementsByClassName("mute-on")[0], s.mute);
    }
    nikPaSetBtn(soloG, row.getElementsByClassName("solo-off")[0],
        row.getElementsByClassName("solo-on")[0], s.solo);
}

// El M del master en modo PA muestra si todo el PA está cortado.
function nikPaApplyMaster(offBtn, onBtn) {
    var group = offBtn.parentNode;
    var st = nikPaState;
    var state = "none";
    if (nikPaMode && st && st.n > 0) {
        state = st.cutCount >= st.n ? "all" : (st.cutCount > 0 ? "part" : "none");
    }
    if (nikPaMode) {
        offBtn.style.visibility = state === "all" ? "hidden" : "visible";
        onBtn.style.visibility = state === "all" ? "visible" : "hidden";
    }
    group.classList.toggle("nikPaAll", nikPaMode && state === "all");
    group.classList.toggle("nikPaPart", nikPaMode && state === "part");
}

// Con el modo apagado y cortes o solos activos el botón lo avisa: el corte
// queda guardado en el proyecto y tampoco sale en el render.
function nikPaRenderChip() {
    var chip = document.getElementById("nikPaChip");
    if (!chip) return;
    var cuts = nikPaState ? nikPaState.cutCount : 0;
    var solos = nikPaState ? nikPaState.soloCount : 0;
    chip.classList.toggle("nikPaOn", nikPaMode);
    chip.classList.toggle("nikPaCuts", !nikPaMode && (cuts > 0 || solos > 0));
    var label = "PA";
    if (!nikPaMode) {
        if (cuts > 0) label += " " + cuts;
        if (solos > 0) label += " S";
    }
    var txt = chip.getElementsByClassName("nikPaChipText")[0];
    if (txt && txt.textContent !== label) txt.textContent = label;
}

function nikPaToggleMode() {
    nikPaMode = !nikPaMode;
    // Fuerza que el próximo ciclo repinte los botones desde los flags reales.
    for (var k in trackFlagsAr) trackFlagsAr[k] = undefined;
    nikPaRowKey = {};
    nikPaRenderChip();
    if (nikPaMode) wwr_req("GET/EXTSTATE/NikMonitorMix/pa_state");
}