// monitor-app.js — bootstrap de la UI de Monitor Mix
//
// Mismo molde que cantante.js: polls propios y render loop. La capa de
// datos (lista, sends) vive en monitor.js; acá solo el arranque, el render y
// el reparto de alto entre los layouts dock, inline y side.
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
    nikMonitorBindFade();
    nikMonitorPanBind();
    window.addEventListener("resize", function () {
        nikMonitorFitLayout();
        nikMonitorFadeAll();
    });

    g_wwr_timer_freq = 20;
    wwr_req_recur("TRANSPORT", 100);
    wwr_req_recur("MARKER", 500);
    wwr_req_recur(nikMonitorBuildSlowPoll(), 1000);
    wwr_start();

    nikMsRequestTempoAndTimesig();
    // El publish lo dispara nikMsHandleProjectSwitch al detectar el primer
    // active_project_name (arranca en null), no hace falta pedirlo acá.
}

// --- Lista del mixer: solo estructura, sin valores en vivo ---
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

function nikMonitorRowsBuild(tracks) {
    var sec = document.createDocumentFragment();
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
        var slider = document.createElement("div");
        slider.className = "mm-slider";
        slider.id = "mmSl_" + t.track + "_" + t.send;
        var db = document.createElement("span");
        db.className = "mm-db";
        db.id = "mmDb_" + t.track + "_" + t.send;
        ctl.appendChild(mute);
        ctl.appendChild(slider);
        ctl.appendChild(db);
        var head = document.createElement("div");
        head.className = "mm-row-head";
        head.appendChild(name);
        if (nikMonitorPanVisible()) head.appendChild(nikMonitorPanChipBuild());
        row.appendChild(head);
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
    var dockEl = document.getElementById("mmClickDock");
    var dockBody = document.getElementById("mmClickBody");
    var musicTitle = document.getElementById("mmMusicTitle");
    if (!listEl || !noticeEl || !pairEl || !dockEl || !dockBody || !musicTitle) return;
    listEl.textContent = "";
    dockBody.textContent = "";
    dockBody.style.maxHeight = "";
    dockEl.style.display = "none";
    musicTitle.style.display = "none";
    nikMonitorPanClose();
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
    if (notice) {
        nikMonitorFitLayout();
        nikMonitorFadeAll();
        return;
    }

    var music = [];
    var click = [];
    for (var i = 0; i < L.tracks.length; i++) {
        (L.tracks[i].role === "click" ? click : music).push(L.tracks[i]);
    }
    if (music.length) {
        listEl.appendChild(nikMonitorRowsBuild(music));
        musicTitle.style.display = "";
    }
    if (click.length) {
        dockBody.appendChild(nikMonitorRowsBuild(click));
        dockEl.style.display = "";
    }
    nikMonitorFadersBuild(L.tracks);
    nikMonitorFitLayout();
    nikMonitorFadeAll();
}

// --- Faders y valores en vivo ---

var nikMonitorFaders = {};   // "track:send" -> {handle, muteEl, rowEl, sig}

var NIK_MM_WRITE_MS = 60;   // separación mínima entre escrituras de un mismo send
var NIK_MM_LOCK_MS = 400;   // tras tocar un fader, el feed no pisa esa fila
var NIK_MM_MUTE_LOCK_MS = 500;   // tras tocar mute, el feed no pisa la M optimista

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
        lockUntil: 0,
        chipEl: rowEl.querySelector(".mm-pan-chip"),
        panSig: null,
        panPending: null,
        panTimer: null,
        panLockUntil: 0
    };
    F.handle = nikMmCreateSlider({
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
    if (F.chipEl) {
        F.chipEl.addEventListener("click", function () {
            nikMonitorPanOpen(F);
        }, false);
    }
    if (F.muteEl) {
        F.muteEl.addEventListener("click", function () {
            var muted = !F.rowEl.classList.contains("is-muted");
            F.muteEl.classList.toggle("is-muted", muted);
            F.rowEl.classList.toggle("is-muted", muted);
            F.lockUntil = performance.now() + NIK_MM_MUTE_LOCK_MS;
            F.sig = null; // al vencer la guarda, la fila se resincroniza con el feed
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
        if ((nikMonitorPanF !== F || !nikMonitorPanHandle.isActive()) &&
            performance.now() >= F.panLockUntil) {
            var panSig = String(s.pan);
            if (F.panSig !== panSig) {
                F.panSig = panSig;
                nikMonitorPanShow(F, s.pan);
            }
        }
        if (F.handle.isActive()) continue;
        if (performance.now() < F.lockUntil) continue;
        var sig = s.vol + ":" + s.muted;
        if (F.sig === sig) continue;
        F.sig = sig;
        F.handle.setValue(nikMmFader.dbToSlider(nikMmFader.volToDb(s.vol)), { silent: true });
        F.muteEl.classList.toggle("is-muted", s.muted);
        F.rowEl.classList.toggle("is-muted", s.muted);
    }
}

var NIK_MM_CLICK_VISIBLE_ROWS = 2;   // filas de Click visibles sin scrollear

// Alto del cuerpo del dock = alto real de las primeras N filas. Con N o
// menos filas no hay tope. No se resetea el max-height antes de medir: el
// rect de las filas no depende del contenedor y así el scroll no se pierde.
function nikMonitorDockFit() {
    var body = document.getElementById("mmClickBody");
    if (!body) return;
    if (nikMonitorDockFree()) {
        body.style.maxHeight = "";
        return;
    }
    var rows = body.querySelectorAll(".mm-row");
    var n = NIK_MM_CLICK_VISIBLE_ROWS;
    if (rows.length <= n) {
        body.style.maxHeight = "";
        return;
    }
    var top = rows[0].getBoundingClientRect().top;
    var bottom = rows[n - 1].getBoundingClientRect().bottom;
    body.style.maxHeight = (bottom - top) + "px";
}

var NIK_MM_MIN_STAGE_ROWS = 2;   // filas de Música que el stage debe poder mostrar
var NIK_MM_SHED_MAX = 2;         // niveles de cesión: 1 sin cues, 2 además sin fila de sección

// En inline y en side el dock no tiene tope de alto propio.
function nikMonitorDockFree() {
    var screen = document.querySelector(".ms-screen");
    var layout = screen ? screen.getAttribute("data-mm-layout") : null;
    return layout === "inline" || layout === "side";
}

// Apaisado: misma condición que el header de una sola fila de cantante.css.
var NIK_MM_SIDE_QUERY = "(min-aspect-ratio: 1/1)";

function nikMonitorIsSide() {
    return window.matchMedia(NIK_MM_SIDE_QUERY).matches;
}

function nikMonitorFitApply(screen, mixer, shed, scale, inline) {
    if (shed > 0) screen.setAttribute("data-mm-shed", String(shed));
    else screen.removeAttribute("data-mm-shed");
    if (inline) screen.setAttribute("data-mm-layout", "inline");
    else screen.removeAttribute("data-mm-layout");
    mixer.style.setProperty("--mm-row-scale", String(scale));
    nikMonitorDockFit();
}

// Cuánto se puede multiplicar la escala actual para que el mixer ocupe justo su
// alto: (alto del mixer - parte fija) / parte que escala. Mayor que 1 = sobra
// lugar. La parte fija es todo lo que hay sobre el stage menos las filas del dock.
function nikMonitorFitRatio(mixer, stage) {
    var rows = mixer.querySelectorAll(".mm-row");
    if (!rows.length) return null;
    var rowH = rows[0].getBoundingClientRect().height;
    if (!(rowH > 0)) return null;
    var clickRows = mixer.querySelectorAll("#mmClickBody .mm-row").length;
    var musicRows = mixer.querySelectorAll("#mmList .mm-row").length;
    var dockRows = Math.min(clickRows, NIK_MM_CLICK_VISIBLE_ROWS);
    var stageRows = Math.min(musicRows, NIK_MM_MIN_STAGE_ROWS);
    var fixed = stage.getBoundingClientRect().top - mixer.getBoundingClientRect().top -
        dockRows * rowH;
    return (mixer.clientHeight - fixed) / ((dockRows + stageRows) * rowH);
}

// Escala para un nivel de cesión dado. La relación no es exactamente lineal
// (los bordes de las filas son de 1 px), así que se corrige midiendo de nuevo.
function nikMonitorFitSolve(screen, mixer, stage, shed, floor) {
    var scale = 1;
    var want = 1;
    for (var i = 0; i < 4; i++) {
        nikMonitorFitApply(screen, mixer, shed, scale);
        var ratio = nikMonitorFitRatio(mixer, stage);
        if (ratio === null) return { scale: 1, fits: true };
        want = scale * ratio;
        var next = Math.max(floor, Math.min(1, want));
        if (Math.abs(next - scale) < 0.005) break;
        scale = next;
    }
    nikMonitorFitApply(screen, mixer, shed, scale);
    return { scale: scale, fits: want >= floor - 0.005 };
}

// Reparte el alto del mixer: primero reduce la escala de las filas hasta el
// piso, si no alcanza cede elementos fijos de a un nivel, y como último
// recurso pasa a layout inline (un solo scroll con Click y Música). En
// apaisado usa tiras verticales (layout side) con la cesión al máximo y sin
// medir.
function nikMonitorFitLayout() {
    var screen = document.querySelector(".ms-screen");
    var mixer = document.getElementById("mmMixer");
    var stage = document.getElementById("mmStage");
    if (!screen || !mixer || !stage) return;

    var side = nikMonitorIsSide();
    var sliders = mixer.querySelectorAll(".mm-slider");
    for (var s = 0; s < sliders.length; s++) sliders[s].classList.toggle("is-vertical", side);
    if (side) {
        screen.setAttribute("data-mm-layout", "side");
        screen.setAttribute("data-mm-shed", String(NIK_MM_SHED_MAX));
        mixer.style.setProperty("--mm-row-scale", "1");
        nikMonitorDockFit();
        return;
    }

    nikMonitorFitApply(screen, mixer, 0, 1);
    var slider = mixer.querySelector(".mm-slider");
    if (!slider) return;
    var thumb = (typeof NIK_MM_SLIDER !== "undefined") ? NIK_MM_SLIDER.THUMB_PX : 0;
    var floor = (thumb > 0 && slider.offsetHeight > 0)
        ? Math.min(1, thumb / slider.offsetHeight)
        : 1;

    for (var shed = 0; shed <= NIK_MM_SHED_MAX; shed++) {
        if (nikMonitorFitSolve(screen, mixer, stage, shed, floor).fits) return;
    }
    nikMonitorFitApply(screen, mixer, NIK_MM_SHED_MAX, floor, true);
}

// Fade de borde: marca cada scroller según haya más contenido arriba o abajo.
function nikMonitorFadeUpdate(el) {
    if (!el) return;
    var up = el.scrollTop > 1;
    var down = el.scrollTop + el.clientHeight < el.scrollHeight - 1;
    el.classList.toggle("has-more-up", up);
    el.classList.toggle("has-more-down", down);
}

function nikMonitorFadeAll() {
    nikMonitorFadeUpdate(document.getElementById("mmMixer"));
    nikMonitorFadeUpdate(document.getElementById("mmStage"));
    nikMonitorFadeUpdate(document.getElementById("mmClickBody"));
}

function nikMonitorBindFade() {
    var ids = ["mmMixer", "mmStage", "mmClickBody"];
    for (var i = 0; i < ids.length; i++) {
        var el = document.getElementById(ids[i]);
        if (el) {
            el.addEventListener("scroll", function (e) {
                nikMonitorFadeUpdate(e.currentTarget);
            }, { passive: true });
        }
    }
}

// --- Paneo por track: chip en la fila y un único popup reutilizado ---

var NIK_MM_PAN_ENABLED = true;

var nikMonitorPanF = null;        // fila (F) con el popup abierto
var nikMonitorPanHandle = null;   // slider del popup
var nikMonitorPanCfg = null;

// Con salida a una sola salida física (pair >= 1024) el paneo no se oye.
function nikMonitorPanVisible() {
    return NIK_MM_PAN_ENABLED && nikMmList && !(nikMmList.pair >= 1024);
}

function nikMonitorPanChipBuild() {
    var chip = document.createElement("button");
    chip.type = "button";
    chip.className = "mm-pan-chip";
    chip.textContent = "—";
    return chip;
}

// Paneo del feed (-1..1, REAPER no lo acota) -> porcentaje entero con signo.
function nikMonitorPanPct(pan) {
    return Math.round(Math.max(-1, Math.min(1, pan)) * 100);
}

function nikMonitorPanChipText(pct) {
    if (pct === 0) return "C";
    return (pct < 0 ? "L " : "R ") + Math.abs(pct);
}

// Refleja un paneo en el chip y, si el popup está abierto en esa fila, en el slider.
function nikMonitorPanShow(F, pan) {
    if (!isFinite(pan)) return;
    var pct = nikMonitorPanPct(pan);
    if (F.chipEl) {
        F.chipEl.textContent = nikMonitorPanChipText(pct);
        F.chipEl.classList.toggle("is-off-center", pct !== 0);
    }
    if (nikMonitorPanF === F && nikMonitorPanHandle) {
        nikMonitorPanHandle.setValue(pct, { silent: true });
    }
}

function nikMonitorPanWriteTick(F) {
    if (F.panPending === null) {
        F.panTimer = null;
        return;
    }
    var p = F.panPending;
    F.panPending = null;
    nikMmSetSendPan(F.t.track, F.t.send, p);
    F.panTimer = window.setTimeout(function () { nikMonitorPanWriteTick(F); }, NIK_MM_WRITE_MS);
}

function nikMonitorPanQueue(F, p) {
    F.panLockUntil = performance.now() + NIK_MM_LOCK_MS;
    F.panPending = p;
    if (F.panTimer === null) nikMonitorPanWriteTick(F);
}

// Valor final: cancela lo pendiente y manda el último.
function nikMonitorPanCommit(F, p) {
    if (F.panTimer !== null) {
        window.clearTimeout(F.panTimer);
        F.panTimer = null;
    }
    F.panPending = null;
    F.panLockUntil = performance.now() + NIK_MM_LOCK_MS;
    F.panSig = null; // al vencer la guarda, la fila se resincroniza con el feed
    nikMmSetSendPan(F.t.track, F.t.send, p);
}

function nikMonitorPanOpen(F) {
    var popup = document.getElementById("mmPanPopup");
    var nameEl = document.getElementById("mmPanName");
    if (!popup || !nameEl || !nikMonitorPanHandle) return;
    var s = nikMmSendState[F.t.track + ":" + F.t.send];
    nikMonitorPanF = F;
    nikMonitorPanCfg.key = "mm:pan:" + F.t.track + "_" + F.t.send;
    nameEl.textContent = F.t.name;
    var accent = window.getComputedStyle(F.rowEl).getPropertyValue("--mm-accent");
    if (accent && accent.trim()) popup.style.setProperty("--mm-accent", accent.trim());
    else popup.style.removeProperty("--mm-accent");
    nikMonitorPanHandle.setValue((s && isFinite(s.pan)) ? nikMonitorPanPct(s.pan) : 0, { silent: true });
    popup.classList.add("is-open");
}

// Cierra el popup y envía lo que haya quedado pendiente del coalescing.
function nikMonitorPanClose() {
    var F = nikMonitorPanF;
    if (F && F.panPending !== null) {
        nikMmSetSendPan(F.t.track, F.t.send, F.panPending);
        F.panPending = null;
    }
    nikMonitorPanF = null;
    var popup = document.getElementById("mmPanPopup");
    if (popup) popup.classList.remove("is-open");
}

function nikMonitorPanBind() {
    var popup = document.getElementById("mmPanPopup");
    if (!NIK_MM_PAN_ENABLED || !popup) return;
    nikMonitorPanCfg = {
        key: "mm:pan",
        sliderId: "mmPanSlider",
        displayId: "mmPanValue",
        min: -100,
        max: 100,
        step: 5,
        defaultValue: 0,
        initialValue: 0,
        fillFrom: 0,
        formatDisplay: function (v) {
            return v === 0 ? "Centro" : Math.abs(v) + "% " + (v < 0 ? "L" : "R");
        },
        onDragChange: function (v) {
            if (nikMonitorPanF) nikMonitorPanQueue(nikMonitorPanF, v / 100);
        },
        onCommit: function (v) {
            if (nikMonitorPanF) nikMonitorPanCommit(nikMonitorPanF, v / 100);
        }
    };
    nikMonitorPanHandle = nikMmCreateSlider(nikMonitorPanCfg);
    popup.addEventListener("click", function (e) {
        if (e.target === popup) nikMonitorPanClose();
    }, false);
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