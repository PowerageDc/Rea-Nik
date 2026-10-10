// monitor-app.js — bootstrap de la UI de Monitor Mix
//
// Mismo molde que cantante.js: polls propios y render loop. La capa de
// datos (lista, sends) vive en monitor.js; acá solo el arranque y el render.
// En 2a el cuerpo del stage es un panel de debug temporal.
//
// Requiere, ya cargados antes: main.js, config.js, config.local.js (opcional),
// core/utils.js, markers/markers.js, core/music-transpose.js,
// core/music-state.js, musicstate-ui/shared/ms-*.js, monitor.js.

function nikMonitorBuildSlowPoll() {
    // reapitch_semitone: solo para la tonalidad de la cabecera (transpuesta).
    // list_version: ms-dispatch lo enruta a nikMmOnExtState (solo GET, nunca
    // dispara el script).
    return NIK_LUA_COMMANDS.statePoll.commandId +
        ";GET/EXTSTATE/NikRemote/active_project_name" +
        ";GET/EXTSTATE/NikRemote/reapitch_semitone" +
        ";GET/EXTSTATE/NikMonitorMix/list_version";
}

function nikMonitorInit() {
    nikMonitorApplyTopOffset();
    nikMonitorBindRefresh();

    g_wwr_timer_freq = 20;
    wwr_req_recur("TRANSPORT", 100);
    wwr_req_recur("MARKER", 500);
    wwr_req_recur(nikMonitorBuildSlowPoll(), 1000);
    wwr_start();

    nikMsRequestTempoAndTimesig();
    // El publish lo dispara nikMsHandleProjectSwitch al detectar el primer
    // active_project_name (arranca en null), no hace falta pedirlo acá.
}

// --- Lista del mixer (2b): solo estructura, sin valores en vivo (2c) ---
// Se redibuja únicamente cuando cambia nikMmListRevision (contenido nuevo).

var NIK_MONITOR_NOTICES = {
    no_bus_cfg: "No hay ningún bus definido en MonitorMix_config.lua.",
    no_pair: "No hay un par de salidas secundario disponible. Revisá Last output en Preferences > Audio o definí pair_override.",
    no_tracks: "Este proyecto no tiene tracks para el monitoreo."
};

var nikMonitorRenderedRevision = -1;

// pair = I_DSTCHAN del hardware out del bus: 2 = salidas 3/4, 1024+i = mono i.
function nikMonitorPairLabel(pair) {
    if (pair === null || pair === undefined) return "—";
    if (pair >= 1024) return "mono " + (pair - 1024 + 1);
    return (pair + 1) + "/" + (pair + 2);
}

function nikMonitorSectionBuild(title, tracks) {
    var sec = document.createElement("div");
    sec.className = "mm-section";
    var h = document.createElement("div");
    h.className = "mm-section-title";
    h.textContent = title;
    sec.appendChild(h);
    for (var i = 0; i < tracks.length; i++) {
        var t = tracks[i];
        var row = document.createElement("div");
        row.className = "mm-row";
        row.setAttribute("data-track", t.track);
        row.setAttribute("data-send", t.send);
        var name = document.createElement("div");
        name.className = "mm-row-name";
        name.textContent = t.name;
        var ctl = document.createElement("div");
        ctl.className = "mm-row-ctl";
        var mute = document.createElement("button");
        mute.type = "button";
        mute.className = "mm-mute";
        mute.textContent = "M";
        var slider = document.createElement("input");
        slider.type = "range";
        slider.className = "mm-slider";
        slider.id = "mmSl_" + t.track + "_" + t.send;
        var db = document.createElement("span");
        db.className = "mm-db";
        db.id = "mmDb_" + t.track + "_" + t.send;
        ctl.appendChild(mute);
        ctl.appendChild(slider);
        ctl.appendChild(db);
        row.appendChild(name);
        row.appendChild(ctl);
        sec.appendChild(row);
    }
    return sec;
}

function nikMonitorListRender() {
    if (nikMonitorRenderedRevision === nikMmListRevision) return;
    nikMonitorRenderedRevision = nikMmListRevision;

    var listEl = document.getElementById("mmList");
    var noticeEl = document.getElementById("mmNotice");
    var pairEl = document.getElementById("mmPair");
    if (!listEl || !noticeEl || !pairEl) return;
    listEl.textContent = "";
    nikMonitorFaders = {};

    var L = nikMmList;
    pairEl.textContent = (L && L.status === "ok")
        ? "Salida " + nikMonitorPairLabel(L.pair) + " · " + L.bus
        : "Salida —";

    var notice = "";
    if (!L) notice = "Esperando datos…";
    else if (NIK_MONITOR_NOTICES[L.status]) notice = NIK_MONITOR_NOTICES[L.status];
    else if (L.status !== "ok") notice = "Estado desconocido: " + L.status;
    else if (!L.tracks.length) notice = "El filtro no admite ningún track en este proyecto.";
    noticeEl.textContent = notice;
    noticeEl.style.display = notice ? "" : "none";
    if (notice) return;

    var music = [];
    var click = [];
    for (var i = 0; i < L.tracks.length; i++) {
        (L.tracks[i].role === "click" ? click : music).push(L.tracks[i]);
    }
    if (music.length) listEl.appendChild(nikMonitorSectionBuild("Música", music));
    if (click.length) listEl.appendChild(nikMonitorSectionBuild("Click", click));
    nikMonitorFadersBuild(L.tracks);
}

// --- Faders y valores en vivo (2c-1: solo lectura) ---

var nikMonitorFaders = {};   // "track:send" -> {handle, muteEl, rowEl, sig}

var NIK_MM_WRITE_MS = 60;   // separación mínima entre escrituras de un mismo send
var NIK_MM_LOCK_MS = 400;   // tras tocar un fader, el feed no pisa esa fila

// Primer valor inmediato; mientras haya pendiente, uno cada NIK_MM_WRITE_MS
// (siempre el último). Sin pendiente el temporizador se libera solo.
function nikMonitorWriteTick(F) {
    if (F.pendingDb === null) {
        F.timer = null;
        return;
    }
    var db = F.pendingDb;
    F.pendingDb = null;
    nikMmSetSendVol(F.t.track, F.t.send, db, false);
    F.timer = window.setTimeout(function () { nikMonitorWriteTick(F); }, NIK_MM_WRITE_MS);
}

function nikMonitorQueueWrite(F, db) {
    F.lockUntil = performance.now() + NIK_MM_LOCK_MS;
    F.pendingDb = db;
    if (F.timer === null) nikMonitorWriteTick(F);
}

// Valor final (change / doble tap): cancela lo pendiente y manda con "e".
function nikMonitorCommitWrite(F, db) {
    if (F.timer !== null) {
        window.clearTimeout(F.timer);
        F.timer = null;
    }
    F.pendingDb = null;
    F.lockUntil = performance.now() + NIK_MM_LOCK_MS;
    F.sig = null; // al vencer la guarda, la fila se resincroniza con el feed
    nikMmSetSendVol(F.t.track, F.t.send, db, true);
}

function nikMonitorFaderCreate(t, defDb) {
    var id = t.track + "_" + t.send;
    var sliderEl = document.getElementById("mmSl_" + id);
    if (!sliderEl) return null;
    var rowEl = sliderEl.closest(".mm-row");
    var F = {
        t: t,
        handle: null,
        muteEl: rowEl.querySelector(".mm-mute"),
        rowEl: rowEl,
        sig: null,
        pendingDb: null,
        timer: null,
        lockUntil: 0
    };
    F.handle = nikCreateVerticalFader({
        key: "mm:" + id,
        sliderId: "mmSl_" + id,
        displayId: "mmDb_" + id,
        min: 0,
        max: nikMmFader.POS_MAX,
        step: 1,
        defaultValue: nikMmFader.dbToSlider(defDb),
        formatDisplay: function (v) {
            return nikMmFader.dbLabel(nikMmFader.sliderToDb(v));
        },
        onDragChange: function (v) {
            nikMonitorQueueWrite(F, nikMmFader.snapDb(nikMmFader.sliderToDb(v)));
        },
        onCommit: function (v) {
            nikMonitorCommitWrite(F, nikMmFader.snapDb(nikMmFader.sliderToDb(v)));
        }
    });
    if (F.muteEl) {
        F.muteEl.addEventListener("click", function () {
            nikMmToggleSendMute(t.track, t.send);
        }, false);
    }
    // Hasta el primer valor del feed no se muestra un dB inventado.
    document.getElementById("mmDb_" + id).textContent = "—";
    return F;
}

function nikMonitorFadersBuild(tracks) {
    nikMonitorFaders = {};
    var defDb = (nikMmList && typeof nikMmList.default_db === "number")
        ? nikMmList.default_db : nikMmFader.DEFAULT_DB;
    for (var i = 0; i < tracks.length; i++) {
        var F = nikMonitorFaderCreate(tracks[i], defDb);
        if (F) nikMonitorFaders[tracks[i].track + ":" + tracks[i].send] = F;
    }
}

// Aplica nikMmSendState a las filas. Solo toca el DOM de una fila si su
// valor o su mute cambiaron desde el último ciclo.
function nikMonitorLiveRender() {
    for (var k in nikMonitorFaders) {
        var F = nikMonitorFaders[k];
        var s = nikMmSendState[k];
        if (!s) continue;
        if (performance.now() < F.lockUntil) continue;
        var sig = s.vol + ":" + s.muted;
        if (F.sig === sig) continue;
        F.sig = sig;
        F.handle.setValue(nikMmFader.dbToSlider(nikMmFader.volToDb(s.vol)), { silent: true });
        F.muteEl.classList.toggle("is-muted", s.muted);
        F.rowEl.classList.toggle("is-muted", s.muted);
    }
}

function nikMonitorBindRefresh() {
    var btn = document.getElementById("mmRefresh");
    if (!btn) return;
    btn.addEventListener("click", function () {
        if (btn.disabled) return;
        btn.disabled = true;
        btn.textContent = "Actualizando…";
        nikMmRequestList();
        window.setTimeout(function () {
            btn.disabled = false;
            btn.textContent = "Actualizar";
        }, 1500);
    });
}

var nikMonitorScreenEl = null;

function nikMonitorRender() {
    if (!nikMonitorScreenEl) nikMonitorScreenEl = document.querySelector(".ms-screen");
    nikMsUpdateStaleIndicator(nikMonitorScreenEl);
    nikMsHeaderRender();
    nikMsSectionRowRender(false);
    nikMonitorListRender();
    nikMonitorLiveRender();
}

function nikMonitorStartRenderLoop(intervalMs) {
    window.setInterval(nikMonitorRender, intervalMs);
}

// Offset superior para separar el título de la barra del navegador.
// ?top=24 lo fija (px, tope 200) y queda guardado en este dispositivo;
// ?top=0 lo borra. Sin parámetro, usa el valor guardado.
var NIK_MONITOR_TOP_KEY = "nikMonitorTopOffset";

function nikMonitorApplyTopOffset() {
    var px = null;
    var m = /[?&]top=(\d+)/.exec(window.location.search);
    try {
        if (m) {
            px = Math.min(parseInt(m[1], 10), 200);
            window.localStorage.setItem(NIK_MONITOR_TOP_KEY, String(px));
        } else {
            var saved = window.localStorage.getItem(NIK_MONITOR_TOP_KEY);
            if (saved !== null) px = parseInt(saved, 10);
        }
    } catch (e) {
        // localStorage no disponible (modo privado): el valor de la URL aplica igual
    }
    if (px !== null && !isNaN(px)) {
        document.documentElement.style.setProperty("--cn-top-offset", px + "px");
    }
}