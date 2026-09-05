// core/init.js
// Bootstrapping + handlers sueltos de transporte que no encajan en otro
// bucket: nikCheckProjectNameWatchdog, on_record_button, prompt_abort,
// prompt_seek, calculateScale, nikToggleLoopRecSection,
// nikApplyLoopRecState, init(). Extraído sin cambios de
// nsaudio_remote_control.html como parte de la modularización (ver
// MODULARIZACION_CONTROL_REMOTO.md).
// Depende de: config.js, core/utils.js, markers/markers.js, core/state.js,
// core/faders.js, core/tracks-render.js, core/wwr-dispatch.js — deben
// cargarse antes en el HTML. init() llama a wwr_req_recur/wwr_start (main.js)
// y usa NIK_SLOW_POLL (config.js).

function nikCheckProjectNameWatchdog() {
    if (Date.now() - nikLastProjectNameUpdate > 3500) {
        var nameDisplay = document.getElementById("nikActiveProjectName");
        if (nameDisplay) nameDisplay.textContent = "-";
        // REAPER desconectado: nikPlayrateTempoMap queda desactualizado,
        // volvemos al placeholder en vez de mostrar un BPM potencialmente
        // viejo (se re-dispara solo al reconectar, ver init()).
        nikPlayrateTempoMap = null;
        var playrateReadout = document.getElementById("nikPlayrateBpmValue");
        if (playrateReadout) playrateReadout.textContent = "—";
    }
}

function on_record_button(e) {
    if (recarmCount > 0 || confirm("no tracks are armed, start record?")) wwr_req(1013);
    return false;
}

function prompt_abort() {
    if (!(last_transport_state & 4)) {
        wwr_req(1016);
    } else {
        if (confirm("abort recording? contents will be lost!")) wwr_req(40668);
    }
}

function prompt_seek() {
    if (!(last_transport_state & 4)) {
        var seekto = prompt("Seek to position:", last_time_str);
        if (seekto != null) {
            wwr_req("SET/POS_STR/" + encodeURIComponent(seekto));
        }
    }
}

// Tap corto en #status: abre prompt_seek() como siempre. Long tap: lo
// suprime (nikAttachLongPress marca _nikSuppressClick) y en su lugar
// alterna el formato del readout de posición.
function nikStatusAreaClick(el) {
    if (el._nikSuppressClick) { el._nikSuppressClick = false; return; }
    prompt_seek();
}

function nikTogglePositionDisplayMode() {
    nikPositionDisplayMode = (nikPositionDisplayMode == "measures") ? "minsec" : "measures";
}

// scaleFactor / optionsOpen viven ahora en core/state.js
// NIK_TRANSPORT_SCALE vive en config.js

function calculateScale(event) {
    var a = document.getElementById("transport_r2");
    if (a) { var drawnWidth = a.clientWidth; }
    else { drawnWidth = 303.6 }
    scaleFactor = drawnWidth / 303.6;

    if (a) {
        var origHeight = drawnWidth * (107.6 / 303.6);
        a.style.transformOrigin = "top center";
        a.style.transform = "scale(" + NIK_TRANSPORT_SCALE + ")";
        a.style.marginBottom = (-origHeight * (1 - NIK_TRANSPORT_SCALE)) + "px";
    }

    if (optionsOpen == 1) {
        for (var i = 0; i < hereCss.cssRules.length; i++) {
            if (hereCss.cssRules[i].selectorText == ".optionsBar") {
                hereCss.deleteRule(i);
                hereCss.insertRule(".optionsBar {height:" + (scaleFactor * 50) + "px;}", i);
            }
        }
    }

    document.getElementById("options").onclick = function () {
        if (optionsOpen != 1) {
            for (var i = 0; i < hereCss.cssRules.length; i++) {
                if (hereCss.cssRules[i].selectorText == ".optionsBar") {
                    hereCss.deleteRule(i);
                    hereCss.insertRule(".optionsBar {height:" + (scaleFactor * 50) + "px;}", i);
                }
            }
            optionsOpen = 1;
        }
        else {
            for (var i = 0; i < hereCss.cssRules.length; i++) {
                if (hereCss.cssRules[i].selectorText == ".optionsBar") {
                    hereCss.deleteRule(i);
                    hereCss.insertRule(".optionsBar {height:0px;}", i);
                }
            }
            optionsOpen = 0;
        }
    }
}

window.addEventListener('resize', calculateScale, false);

// Toggle de la sección Loop / Rec / Tracks armadas (#transport_r3),
// disparado desde #buttonLoopRec en #optionsBar (reemplaza a Snap — sin
// sentido en contexto remoto). Reemplaza al viejo #nikLoopRecToggle inline.
function nikToggleLoopRecSection() {
    var el = document.getElementById("transport_r3");
    if (!el) return;
    nikApplyLoopRecState(el.classList.contains("nikCollapsed"));
}

// Aplica el estado expandido/colapsado a #transport_r3 y al ícono de
// #buttonLoopRec. Separado del toggle para que core/tab-ui-memory.js pueda
// aplicar el estado guardado por tab directamente (clave loopRecExpanded).
function nikApplyLoopRecState(expanded) {
    var el = document.getElementById("transport_r3");
    if (el) el.classList.toggle("nikCollapsed", !expanded);

    var btn = document.getElementById("buttonLoopRec");
    var iconOff = document.getElementById("iconLoopRecOff");
    var iconOn = document.getElementById("iconLoopRecOn");
    if (btn) btn.classList.toggle("nikToggledOn", expanded);
    if (iconOff) iconOff.setAttribute("visibility", expanded ? "hidden" : "visible");
    if (iconOn) iconOn.setAttribute("visibility", expanded ? "visible" : "hidden");
}

trackHeightsAr[0] = 0;
// hitbox vive ahora en core/tracks-render.js

function init() {
    var statusEl = document.getElementById("status");
    if (statusEl) nikAttachLongPress(statusEl, { onLongPress: nikTogglePositionDisplayMode });

    wwr_req_recur("TRANSPORT;BEATPOS", 10);
    wwr_req_recur("NTRACK;TRACK;GET/40364", 10);
    wwr_req_recur("MARKER;REGION", 500);
    wwr_req_recur(NIK_SLOW_POLL, 1000);
    window.setInterval(nikCheckProjectNameWatchdog, 1000);
    wwr_start();
    nikPlayrateRequestTempoMap();

    if (/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream) {
        for (let l = 0; l < document.styleSheets.length; l++) {
            let ss = document.styleSheets[l];
            if (ss.cssRules) for (let i = 0; i < ss.cssRules.length; i++) {
                let st = ss.cssRules[i].selectorText;
                if (st != undefined && st.startsWith(".button")) ss.removeRule(i--);
                transitions = 0;
                doTransitionButton();
            }
        }
    }
}