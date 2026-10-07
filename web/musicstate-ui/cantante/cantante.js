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
    // Sin reapitch_semitone (la letra no se transpone) ni publish_version
    // (es de armonía). playrate sí: escala el adelanto de lyrics.
    return NIK_LUA_COMMANDS.statePoll.commandId +
        ";GET/EXTSTATE/NikRemote/active_project_name" +
        ";GET/EXTSTATE/NikRemote/playrate" +
        ";GET/EXTSTATE/NikMusicState/lyrics_version";
}

function nikCantanteInit() {
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
    out.push("playing: " + nikMusicStateIsPlaying() + "   pos: " + nikLastPositionBeatsStr);
    out.push("lyrics_version: " + nikMsLastKnownLyricsVersion + "   lineas: " + nikMusicStateLyricsLines.length);
    out.push("terminada: " + nikMusicStateLyricEnded() + "   proxima (QN): " + (next ? next.qn.toFixed(2) : "-"));
    out.push("");
    for (var i = 0; i < win.length; i++) {
        out.push((win[i].isCurrent ? "> " : "  ") + win[i].text);
    }
    el.textContent = out.join("\n");
}

function nikCantanteStartRenderLoop(intervalMs) {
    window.setInterval(nikCantanteDebugRender, intervalMs);
}