// cantante.js — bootstrap de la UI de cantante (lyrics, MusicState)
//
// Mismo molde que instrumentista.js: polls propios, pedidos on-demand de
// boot. El render real de la UI de cantante está pendiente (ver
// musicstate_lyrics.md §5-6); nikCantanteDebugRender es un panel temporal.
//
// Requiere, ya cargados antes en el shell: main.js, config.js,
// config.local.js (opcional), core/utils.js, markers/markers.js,
// core/music-transpose.js, core/music-state.js,
// musicstate-ui/shared/ms-tempo.js, ms-dispatch.js.

// --- Roles del reel (musicstate_cantante.md §4.1-4.2) ---
// Toda línea se compone al font-size de --cn-lyric-size (rol "cur"); el rol
// se expresa solo con scale (cociente de font-size respecto de "cur") y
// opacity en reposo. Valores iniciales, a ajustar en pantalla.
var NIK_CANTANTE_ROLES = {
    cur:   { scale: 1.00, opacity: 1.00 },
    next1: { scale: 0.78, opacity: 0.70 },
    prev1: { scale: 0.62, opacity: 0.35 },
    next2: { scale: 0.62, opacity: 0.45 },
    prev2: { scale: 0.50, opacity: 0.20 }
};

// Orden de prioridad para agregar slots mientras entren en el escenario (§4.2).
var NIK_CANTANTE_SLOT_ORDER = ["cur", "next1", "prev1", "next2", "prev2"];

function nikCantanteBuildSlowPoll() {
    // reapitch_semitone solo para la tonalidad de la cabecera (transpuesta);
    // la letra no se transpone. Sin publish_version (es de armonía).
    // playrate: escala el adelanto de lyrics.
    return NIK_LUA_COMMANDS.statePoll.commandId +
        ";GET/EXTSTATE/NikRemote/active_project_name" +
        ";GET/EXTSTATE/NikRemote/reapitch_semitone" +
        ";GET/EXTSTATE/NikRemote/playrate" +
        ";GET/EXTSTATE/NikMusicState/lyrics_version";
}

function nikCantanteInit() {
    nikCantanteApplyTopOffset();
    window.addEventListener("resize", nikCantanteMarkMeasureDirty);
    window.addEventListener("orientationchange", nikCantanteMarkMeasureDirty);
    if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(nikCantanteMarkMeasureDirty);
    }
    // Opt-in: sin esto, ms-dispatch.js no dispara PublishLyrics en el
    // cambio de proyecto.
    NIK_MS_LYRICS_ENABLED = true;

    g_wwr_timer_freq = 20;
    wwr_req_recur("TRANSPORT", 100);
    wwr_req_recur("MARKER", 500);
    wwr_req_recur(nikCantanteBuildSlowPoll(), 1000);
    wwr_start();

    nikMsRequestTempoAndTimesig();
    nikMusicStateRequestLyrics();
}

// --- Medidor de renglones (musicstate_cantante.md §4.1-4.2) ---
// Mide una vez cada línea al ancho del escenario y a la fuente del rol
// "cur". rows[line.index] = cantidad de renglones. Se recalcula solo si
// cambió la letra o el tamaño (nunca por frame).

var nikCantanteMeasure = {
    el: null,
    dirty: true,
    linesRef: null,
    linesLen: -1,
    version: undefined,
    oneLineH: 0,
    width: 0,
    rowsPos: [],        // renglones por POSICIÓN en nikMusicStateLyricsLines
    pos: {},            // line.index -> posición en el array
    indexIsPos: true,   // diagnóstico: ¿index coincide con la posición?
    gap: 0,
    stageH: 0,
    stageTop: 0,
    viewH: 0,
    epoch: 0,           // sube en cada medición; invalida el layout cacheado
    counts: { one: 0, two: 0, more: 0 },
    moreIdx: []
};

function nikCantanteEnsureMeasurer() {
    if (nikCantanteMeasure.el) return nikCantanteMeasure.el;
    var stage = document.getElementById("cnStage");
    if (!stage) return null;
    var el = document.createElement("div");
    el.className = "cn-measurer";
    el.setAttribute("aria-hidden", "true");
    stage.appendChild(el);
    nikCantanteMeasure.el = el;
    return el;
}

function nikCantanteMeasureLines() {
    var M = nikCantanteMeasure;
    var el = nikCantanteEnsureMeasurer();
    if (!el) return;
    var lines = nikMusicStateLyricsLines;

    el.textContent = "M";
    M.oneLineH = el.offsetHeight;
    M.width = el.clientWidth;
    M.rowsPos = [];
    M.pos = {};
    M.indexIsPos = true;
    M.counts = { one: 0, two: 0, more: 0 };
    M.moreIdx = [];
    var stage = el.parentNode;
    M.stageH = stage.clientHeight;
    M.stageTop = stage.getBoundingClientRect().top;
    M.viewH = window.innerHeight;
    M.gap = parseFloat(window.getComputedStyle(el).marginBottom) || 0;

    if (M.oneLineH > 0) {
        for (var i = 0; i < lines.length; i++) {
            el.textContent = lines[i].text;
            var r = Math.max(1, Math.round(el.offsetHeight / M.oneLineH));
            M.rowsPos[i] = r;
            M.pos[lines[i].index] = i;
            if (lines[i].index !== i) M.indexIsPos = false;
            if (r === 1) M.counts.one++;
            else if (r === 2) M.counts.two++;
            else { M.counts.more++; M.moreIdx.push(lines[i].index); }
        }
    }
    el.textContent = "";

    M.epoch++;
    M.linesRef = lines;
    M.linesLen = lines.length;
    M.version = nikMsLastKnownLyricsVersion;
    // Con el nodo sin layout (alto 0) reintenta en el próximo tick.
    M.dirty = (M.oneLineH === 0);
}

function nikCantanteMeasureIfNeeded() {
    var M = nikCantanteMeasure;
    var lines = nikMusicStateLyricsLines;
    if (M.dirty || M.linesRef !== lines || M.linesLen !== lines.length ||
        M.version !== nikMsLastKnownLyricsVersion) {
        nikCantanteMeasureLines();
    }
}

function nikCantanteMarkMeasureDirty() {
    nikCantanteMeasure.dirty = true;
}

// --- Slots y foco (musicstate_cantante.md §4.2) ---
// Desplazamiento de cada rol respecto de la línea ancla.
var NIK_CANTANTE_ROLE_OFFSET = { cur: 0, next1: 1, prev1: -1, next2: 2, prev2: -2 };

// Posición (en nikMusicStateLyricsLines) de la línea que se está cantando
// (cur0, §4.3). -1 en intro, sin datos o si el index no está en el mapa.
function nikCantanteAnchorPos() {
    var cur0 = nikMusicStateCurrentLyric(0);
    if (!cur0) return -1;
    var p = nikCantanteMeasure.pos[cur0.index];
    return (p === undefined) ? -1 : p;
}

// Elige slots por prioridad mientras entren en el escenario y calcula el
// tope visual (y) y alto visual (h) de cada uno, en px del escenario.
function nikCantanteComputeLayout(anchorPos) {
    var M = nikCantanteMeasure;
    var n = nikMusicStateLyricsLines.length;
    var L = { slots: [], stageH: M.stageH, usedH: 0, focusY: null, clamped: false };
    if (M.oneLineH <= 0 || M.stageH <= 0 || n === 0) return L;

    // 1) Prioridad estricta; los inexistentes no ocupan lugar.
    var picked = [];
    var used = 0;
    for (var s = 0; s < NIK_CANTANTE_SLOT_ORDER.length; s++) {
        var role = NIK_CANTANTE_SLOT_ORDER[s];
        var pos = anchorPos + NIK_CANTANTE_ROLE_OFFSET[role];
        if (pos < 0 || pos >= n) continue;
        var rows = M.rowsPos[pos];
        var h = rows * M.oneLineH * NIK_CANTANTE_ROLES[role].scale;
        var need = h + (picked.length ? M.gap : 0);
        if (used + need > M.stageH) break;
        used += need;
        picked.push({ role: role, pos: pos, rows: rows, h: h });
    }
    if (!picked.length) return L;

    // 2) De arriba hacia abajo, con y relativo al tope de la pila.
    picked.sort(function (a, b) { return a.pos - b.pos; });
    var y = 0;
    var refCenter = null;
    for (var i = 0; i < picked.length; i++) {
        picked[i].y = y;
        if (picked[i].role === "cur") refCenter = y + picked[i].h / 2;
        y += picked[i].h + M.gap;
    }
    if (refCenter === null) refCenter = used / 2; // intro: sin "cur", centra la pila

    // 3) Foco: centro del viewport en coords del escenario, con tope.
    var target = M.viewH / 2 - M.stageTop;
    var top = target - refCenter;
    var clampedTop = Math.max(0, Math.min(top, M.stageH - used));
    L.focusY = target;
    L.clamped = (clampedTop !== top);
    L.usedH = used;
    for (var j = 0; j < picked.length; j++) {
        var r = NIK_CANTANTE_ROLES[picked[j].role];
        L.slots.push({
            role: picked[j].role,
            pos: picked[j].pos,
            rows: picked[j].rows,
            y: clampedTop + picked[j].y,
            h: picked[j].h,
            scale: r.scale,
            opacity: r.opacity
        });
    }
    return L;
}

// Cacheado: se recalcula solo si cambió el ancla o la medición (epoch).
var nikCantanteLayoutCache = { key: "", layout: null };

function nikCantanteGetLayout(anchorPos) {
    var key = nikCantanteMeasure.epoch + ":" + anchorPos;
    if (nikCantanteLayoutCache.key !== key) {
        nikCantanteLayoutCache.layout = nikCantanteComputeLayout(anchorPos);
        nikCantanteLayoutCache.key = key;
    }
    return nikCantanteLayoutCache.layout;
}

// --- Panel de debug temporal (se reemplaza por la UI real) ---

function nikCantanteDebugRender() {
    var el = document.getElementById("cantanteDebug");
    if (!el) return;
    nikCantanteMeasureIfNeeded();
    var next = nikMusicStateLyricsNextDistance();
    var win = nikMusicStateLyricsWindow(2, 2);
    var out = [];
    var stageEl = document.getElementById("cnStage");
    out.push("vp: " + window.innerWidth + "x" + window.innerHeight +
        "   stage: " + (stageEl ? stageEl.clientWidth + "x" + stageEl.clientHeight : "-"));
    out.push("playing: " + nikMusicStateIsPlaying() + "   pos: " + nikLastPositionBeatsStr);
    out.push("lyrics_version: " + nikMsLastKnownLyricsVersion + "   lineas: " + nikMusicStateLyricsLines.length);
    var M = nikCantanteMeasure;
    out.push("medidor: 1r=" + M.counts.one + " 2r=" + M.counts.two + " >2r=" + M.counts.more +
        "   ancho: " + M.width + "px   1r: " + M.oneLineH + "px");
    if (M.moreIdx.length) out.push("  >2r en indices: " + M.moreIdx.slice(0, 10).join(", "));
    var apos = nikCantanteAnchorPos();
    var L = nikCantanteGetLayout(apos);
    out.push("idx==pos: " + M.indexIsPos + "   ancla: " + apos + "   slots: " + L.slots.length +
        "   usado: " + Math.round(L.usedH) + "/" + L.stageH + "px");
    out.push("foco: " + (L.focusY === null ? "-" : Math.round(L.focusY) + "px") +
        (L.clamped ? " (con tope)" : "") + "   gap: " + Math.round(M.gap) + "px");
    var c0 = nikMusicStateCurrentLyric(0);
    var cL = nikMusicStateCurrentLyric();
    out.push("cur0: " + (c0 ? "#" + c0.index : "-") + "   curL: " + (cL ? "#" + cL.index : "-") +
        "   ended0: " + nikMusicStateLyricEnded(0));
    for (var k = 0; k < L.slots.length; k++) {
        var S = L.slots[k];
        out.push("  " + S.role + " #" + S.pos + " " + S.rows + "r y=" + Math.round(S.y) + " h=" + Math.round(S.h));
    }
    out.push("terminada: " + nikMusicStateLyricEnded() + "   proxima (QN): " + (next ? next.qn.toFixed(2) : "-"));
    out.push("");
    for (var i = 0; i < win.length; i++) {
        out.push((win[i].isCurrent ? "> " : "  ") + win[i].text);
    }
    el.textContent = out.join("\n");
}

var nikCantanteScreenEl = null;

function nikCantanteRender() {
    if (!nikCantanteScreenEl) nikCantanteScreenEl = document.querySelector(".ms-screen");
    nikMsUpdateStaleIndicator(nikCantanteScreenEl);
    nikMsHeaderRender();
    nikMsSectionRowRender(false); // sin reel todavía: ninguna otra capa hace jump
    nikCantanteDebugRender();
}

function nikCantanteStartRenderLoop(intervalMs) {
    window.setInterval(nikCantanteRender, intervalMs);
}

// Offset superior para separar el título de la barra del navegador.
// ?top=24 lo fija (px, tope 200) y queda guardado en este dispositivo;
// ?top=0 lo borra. Sin parámetro, usa el valor guardado.
var NIK_CANTANTE_TOP_KEY = "nikCantanteTopOffset";

function nikCantanteApplyTopOffset() {
    var px = null;
    var m = /[?&]top=(\d+)/.exec(window.location.search);
    try {
        if (m) {
            px = Math.min(parseInt(m[1], 10), 200);
            window.localStorage.setItem(NIK_CANTANTE_TOP_KEY, String(px));
        } else {
            var saved = window.localStorage.getItem(NIK_CANTANTE_TOP_KEY);
            if (saved !== null) px = parseInt(saved, 10);
        }
    } catch (e) {
        // localStorage no disponible (modo privado): el valor de la URL aplica igual
    }
    if (px !== null && !isNaN(px)) {
        document.documentElement.style.setProperty("--cn-top-offset", px + "px");
    }
}