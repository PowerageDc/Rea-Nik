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

// Tope del gap proporcional (§4.2): múltiplo de --cn-lyric-gap.
var NIK_CANTANTE_GAP_MAX = 4;

// Barrido de proximidad (§4.6): segundos antes del inicio de la línea en que
// arranca (a calibrar con una letra real) y dirección: "up" o "right".
var NIK_CANTANTE_PRELUDE_S = 2.0;
var NIK_CANTANTE_SWEEP_DIR = "right";

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
    // Intro (sin línea vigente): "cur" fantasma en la posición -1 (no se dibuja,
    // pero ocupa su lugar). Al empezar la línea 0 la pila sube igual que en
    // cualquier cambio de línea.
    var intro = (anchorPos < 0);

    // 1) Prioridad estricta; los inexistentes no ocupan lugar.
    var picked = [];
    var used = 0;
    for (var s = 0; s < NIK_CANTANTE_SLOT_ORDER.length; s++) {
        var role = NIK_CANTANTE_SLOT_ORDER[s];
        var pos = anchorPos + NIK_CANTANTE_ROLE_OFFSET[role];
        var phantom = (intro && role === "cur");
        if (!phantom && (pos < 0 || pos >= n)) continue;
        var rows = phantom ? 1 : M.rowsPos[pos];
        var h = rows * M.oneLineH * NIK_CANTANTE_ROLES[role].scale;
        var need = h + (picked.length ? M.gap : 0);
        if (used + need > M.stageH) break;
        used += need;
        picked.push({ role: role, pos: pos, rows: rows, h: h, phantom: phantom });
    }
    if (!picked.length) return L;

    // 1b) Gap proporcional al espacio que sobra, entre M.gap y el tope.
    var gap = M.gap;
    if (picked.length > 1) {
        var extra = M.stageH - used;
        gap = Math.min(M.gap * NIK_CANTANTE_GAP_MAX, M.gap + extra / (picked.length - 1));
        used += (picked.length - 1) * (gap - M.gap);
    }

    // 2) De arriba hacia abajo, con y relativo al tope de la pila.
    picked.sort(function (a, b) { return a.pos - b.pos; });
    var y = 0;
    var refCenter = null;
    for (var i = 0; i < picked.length; i++) {
        picked[i].y = y;
        if (picked[i].role === "cur") refCenter = y + picked[i].h / 2;
        y += picked[i].h + gap;
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
        if (picked[j].phantom) continue;
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

// --- Reel de letra: dibujo estático (musicstate_cantante.md §4.1-4.2) ---
// Un nodo por POSICIÓN de línea; el rol solo cambia transform/opacity.
// Se redibuja únicamente cuando cambia el layout cacheado, nunca por frame.

var nikCantanteReel = { nodes: {}, layout: null, epoch: -1, anchor: null, jumped: false };

function nikCantanteReelRender() {
    var stage = document.getElementById("cnStage");
    if (!stage) return;
    nikCantanteMeasureIfNeeded();
    var R = nikCantanteReel;
    var ap = nikCantanteAnchorPos();
    var L = nikCantanteGetLayout(ap);
    R.jumped = false;
    if (R.layout === L) return;

    // Medición nueva: el texto o el ancho pudieron cambiar, se recrea todo.
    if (R.epoch !== nikCantanteMeasure.epoch) {
        for (var p in R.nodes) {
            if (R.nodes[p].parentNode) R.nodes[p].parentNode.removeChild(R.nodes[p]);
        }
        R.nodes = {};
        R.epoch = nikCantanteMeasure.epoch;
    } else if (R.anchor !== null && Math.abs(ap - R.anchor) > 1) {
        // Salto (seek): crossfade en vez de deslizar la pila (§4.7).
        R.jumped = true;
        for (var o in R.nodes) nikCantanteReelFadeOut(R.nodes[o]);
        R.nodes = {};
    }
    R.anchor = ap;

    var keep = {};
    for (var i = 0; i < L.slots.length; i++) {
        var S = L.slots[i];
        keep[S.pos] = true;
        var node = R.nodes[S.pos];
        if (!node) {
            node = document.createElement("div");
            node.className = "cn-lyric";
            node.textContent = nikMusicStateLyricsLines[S.pos].text;
            var sweepEl = document.createElement("span");
            sweepEl.className = "cn-sweep";
            sweepEl.textContent = nikMusicStateLyricsLines[S.pos].text;
            node.appendChild(sweepEl);
            node.style.opacity = "0";
            node.style.transform = "translateY(" + S.y + "px) scale(" + S.scale + ")";
            stage.appendChild(node);
            void node.offsetWidth; // flush: el opacity final transiciona desde 0
            R.nodes[S.pos] = node;
        }
        node.style.transform = "translateY(" + S.y + "px) scale(" + S.scale + ")";
        node.style.opacity = S.opacity;
    }
    for (var q in R.nodes) {
        if (!keep[q]) {
            nikCantanteReelFadeOut(R.nodes[q]);
            delete R.nodes[q];
        }
    }
    R.layout = L;
}

function nikCantanteReelFadeOut(node) {
    node.style.opacity = "0";
    window.setTimeout(function () {
        if (node.parentNode) node.parentNode.removeChild(node);
    }, 600);
}

// --- Estados de la línea (musicstate_cantante.md §4.3-4.4) ---
// Solo color y opacity. Se reaplica cuando cambia el layout o el flag armada.

var nikCantanteStates = { layout: null, armed: null };

function nikCantanteIsArmed() {
    var c0 = nikMusicStateCurrentLyric(0);
    var cL = nikMusicStateCurrentLyric();
    if (!c0) return !!cL; // intro: se arma cuando abre la ventana de lectura
    return !!(nikMusicStateLyricEnded(0) || (cL && cL.index > c0.index));
}

function nikCantanteReelApplyStates() {
    var R = nikCantanteReel;
    var L = R.layout;
    if (!L) return;
    var armed = nikCantanteIsArmed();
    var ended = !!nikMusicStateLyricEnded(0);
    var T = nikCantanteStates;
    if (T.layout === L && T.armed === armed && T.ended === ended) return;
    for (var i = 0; i < L.slots.length; i++) {
        var S = L.slots[i];
        var node = R.nodes[S.pos];
        if (!node) continue;
        var op = S.opacity;
        var sung = false;
        var arm = false;
        if (S.role === "cur") {
            if (ended) op = NIK_CANTANTE_ROLES.prev1.opacity;
            else sung = true;
        }
        node.classList.toggle("is-sung", sung);
        node.classList.toggle("is-armed", arm);
        node.style.opacity = op;
    }
    T.layout = L;
    T.armed = armed;
    T.ended = ended;
}

// --- Barrido de proximidad (musicstate_cantante.md §4.6) ---
// Sobre el hijo .cn-sweep de la línea next1. Una transition de CSS cuya
// duración es el tiempo restante; el tick solo decide cuándo (re)armarla.

var nikCantanteSweep = { node: null, span: null, playing: null, endAt: 0, frac: -1 };

function nikCantanteSweepClip(frac) {
    var rest = Math.max(0, Math.min(1, 1 - frac)) * 100;
    return (NIK_CANTANTE_SWEEP_DIR === "right")
        ? "inset(0 " + rest + "% 0 0)"
        : "inset(" + rest + "% 0 0 0)";
}

// durSec > 0: parte de frac y llena hasta 1 en durSec; 0: queda fijo en frac.
function nikCantanteSweepSet(span, frac, durSec) {
    span.style.transition = "none";
    span.style.clipPath = nikCantanteSweepClip(frac);
    if (durSec > 0) {
        void span.offsetWidth; // flush: el estado inicial se aplica antes de animar
        span.style.transition = "clip-path " + durSec + "s linear";
        span.style.clipPath = nikCantanteSweepClip(1);
    }
}

function nikCantanteSweepReset() {
    var S = nikCantanteSweep;
    if (S.span) nikCantanteSweepSet(S.span, 0, 0);
    S.node = null;
    S.span = null;
    S.playing = null;
    S.frac = -1;
}

// Segundos reales hasta que empieza la línea siguiente; null si no se sabe.
// Usa el tempo del punto actual: un cambio de tempo dentro de la espera
// queda aproximado.
function nikCantanteSweepRemainingSec() {
    var d = nikMusicStateLyricsNextDistance(0);
    if (!d) return null;
    var bpm = nikMsTempoAt(nikMsEffectivePosSeconds());
    if (!bpm) return null;
    var rate = parseFloat(nikTransportPlayRate);
    if (!(rate > 0)) rate = 1;
    return d.qn * 60 / bpm / rate;
}

function nikCantanteSweepTick() {
    var R = nikCantanteReel;
    var L = R.layout;
    var S = nikCantanteSweep;
    var node = null;
    if (L) {
        for (var i = 0; i < L.slots.length; i++) {
            if (L.slots[i].role === "next1") node = R.nodes[L.slots[i].pos] || null;
        }
    }
    var sec = node ? nikCantanteSweepRemainingSec() : null;
    if (!node || sec === null || sec > NIK_CANTANTE_PRELUDE_S) {
        if (S.node) nikCantanteSweepReset();
        return;
    }
    var playing = !!nikMusicStateIsPlaying();
    var frac = 1 - Math.max(0, sec) / NIK_CANTANTE_PRELUDE_S;
    var now = window.performance.now();
    if (S.node === node && S.playing === playing) {
        if (playing) {
            if (Math.abs(now + sec * 1000 - S.endAt) < 400) return;
        } else if (Math.abs(frac - S.frac) < 0.01) {
            return;
        }
    }
    if (S.node && S.node !== node) nikCantanteSweepReset();
    S.node = node;
    S.span = node.querySelector(".cn-sweep");
    S.playing = playing;
    S.endAt = now + sec * 1000;
    S.frac = frac;
    if (S.span) nikCantanteSweepSet(S.span, frac, playing ? sec : 0);
}

// --- Panel de debug temporal (se reemplaza por la UI real) ---

var NIK_CANTANTE_DEBUG_ON = /[?&]debug=1/.test(window.location.search);

function nikCantanteDebugRender() {
    var el = document.getElementById("cantanteDebug");
    if (!el) return;
    if (!NIK_CANTANTE_DEBUG_ON) {
        el.style.display = "none";
        return;
    }
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
    nikCantanteReelRender();
    nikMsSectionRowRender(nikCantanteReel.jumped);
    nikCantanteReelApplyStates();
    nikCantanteSweepTick();
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