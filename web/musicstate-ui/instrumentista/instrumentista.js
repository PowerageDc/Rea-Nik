// instrumentista.js — bootstrap real del perfil Instrumentista (MusicState)
//
// Arma los polls definitivos (TRANSPORT, MARKER, slow poll) y dispara los
// pedidos on-demand de boot. Reemplaza, para este propósito, al bloque
// inline de nsaudio_musicstate_test.html -- el test HTML sigue teniendo su
// propio panel de debug (nikMsTestRefreshDebugPanel), que no es parte de
// este archivo (eso es rendering, no bootstrap).
//
// Requiere, ya cargados antes en el <script> del shell que lo use:
// main.js, config.js, config.local.js (opcional), core/utils.js,
// markers/markers.js, core/music-transpose.js, core/music-state.js,
// musicstate-ui/shared/ms-tempo.js, ms-section.js, ms-dispatch.js.

function nikInstrumentistaBuildSlowPoll() {
    // Mismo criterio que el test: reusa el script consolidado (ya escribe
    // reapitch_semitone y active_project_name en cada corrida) -- no un
    // script nuevo, y sin arrastrar el resto de NIK_ONDEMAND_READS
    // (playrate/preservepitch/marker_bars/solo-in-front, irrelevantes
    // para este perfil).
    return NIK_LUA_COMMANDS.statePoll.commandId +
        ";GET/EXTSTATE/NikRemote/active_project_name" +
        ";GET/EXTSTATE/NikRemote/reapitch_semitone" +
        ";GET/EXTSTATE/NikMusicState/publish_version";
}

function nikInstrumentistaInit() {
    wwr_req_recur("TRANSPORT", 10);
    wwr_req_recur("MARKER", 500);
    wwr_req_recur(nikInstrumentistaBuildSlowPoll(), 1000);
    wwr_start();

    // On-demand, mismo criterio que boot del remoto general (init.js real):
    // no esperar al primer cambio de proyecto para tener datos.
    nikMsRequestTempoAndTimesig();
    if (typeof nikMusicStateRequestAll === "function") nikMusicStateRequestAll();
}