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

// --- Panel de debug temporal (se reemplaza por la UI real) ---

function nikCantanteDebugRender() {
    var el = document.getElementById("cantanteDebug");
    if (!el) return;
    var next = nikMusicStateLyricsNextDistance();
    var win = nikMusicStateLyricsWindow(2, 2);
    var out = [];
    var stageEl = document.getElementById("cnStage");
    out.push("vp: " + window.innerWidth + "x" + window.innerHeight +
        "   stage: " + (stageEl ? stageEl.clientWidth + "x" + stageEl.clientHeight : "-"));
    out.push("playing: " + nikMusicStateIsPlaying() + "   pos: " + nikLastPositionBeatsStr);
    out.push("lyrics_version: " + nikMsLastKnownLyricsVersion + "   lineas: " + nikMusicStateLyricsLines.length);
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