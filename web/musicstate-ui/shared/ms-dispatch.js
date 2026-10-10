// musicstate-ui/shared/ms-dispatch.js
// wwr_onreply() propio de la UI de Instrumentista (perfil MusicState) — NO
// reusa core/wwr-dispatch.js del control remoto general (ver
// musicstate_instrumentista.md, sección 3: ese dispatcher tiene casos sin
// guard `if (elemento) {...}` que asumen DOM de tracks/faders/sends que acá
// no existe).
//
// Depende de (deben cargarse antes en el HTML):
//   config.js                → NIK_LUA_COMMANDS.playrateTempoMapRead
//   core/music-state.js      → nikMusicStateSetTimesigMap, nikMusicStateSetHarmonyData,
//                               nikMusicStateSetProjectKey, nikMusicStateSetProjectRoles,
//                               nikMusicStateSetCuesData, nikMusicStateRequestAll
//   musicstate-ui/shared/ms-tempo.js → nikMsTempoSetMap (ver TODO abajo, archivo
//                               todavía no escrito — este dispatcher ya lo referencia
//                               con guard de existencia para no romper antes de tiempo)
//
// NO depende de playrate.js / reapitch.js (no se cargan en esta UI, ver
// arquitectura de archivos del doc de perfil) — por eso el pedido on-demand
// de tempo_map/timesig_map y el manejo de reapitch_semitone se resuelven acá
// mismo, sin pasar por esos módulos (que están acoplados al DOM de sus popups).

// ---- Estado propio (sin ms-state.js separado, ver doc de arquitectura) ----

var nikTransportPlayState = 0;
var nikTransportPlayRate = 1;
var nikTransportAnchorMs = 0;
var playPosSeconds = 0;                // segundos, crudo de TRANSPORT tok[2]
var nikLastPositionBeatsStr = "1.1.00"; // "compas.beat.centesimas", TRANSPORT tok[5]
                                         // mismo nombre de variable que usa
                                         // core/music-state.js del lado del control
                                         // remoto general — no renombrar.

var nikCurrentProjectName = null;      // con extensión .rpp, igual criterio que el remoto general
var nikLastProjectNameUpdate = 0;      // Date.now() del último EXTSTATE recibido (para watchdog futuro)

var nikReaPitchLastSemitone = "none";  // sentinel inicial ("sin dato todavía"), mismo
                                        // criterio que reapitch.js: "none"/"mixed" son
                                        // estados válidos del Stem Bus, no se colapsan a 0.

var nikMsLastKnownPublishVersion = null; // último publish_version visto EN EL PROYECTO
                                          // ACTIVO -- se resetea a null en cada cambio de
                                          // proyecto (nikMsResetProjectState) para que la
                                          // comparación nunca cruce entre proyectos.

var g_markers = [];                    // mismo formato que main.js: array de tok completos
                                        // por marker ([.., nombre, id, pos, color]) — layout
                                        // confirmado contra core/wwr-dispatch.js (getValFromAr).

// Opt-in por UI: solo la UI que muestra letra lo pone en true (ej. cantante.js).
// Sin esto, el cambio de proyecto no dispara PublishLyrics. El typeof respeta
// un valor definido antes de cargar este archivo.
var NIK_MS_LYRICS_ENABLED = (typeof NIK_MS_LYRICS_ENABLED !== "undefined") ? NIK_MS_LYRICS_ENABLED : false;

var nikMsLastKnownLyricsVersion = null; // último lyrics_version visto EN EL PROYECTO
                                         // ACTIVO -- se resetea a null en cada cambio
                                         // de proyecto, igual criterio que
                                         // nikMsLastKnownPublishVersion.

var NIK_MS_DEBUG = false;
function nikMsLog(tag, extra) {
    if (!NIK_MS_DEBUG) return;
    console.log("[ms " + Math.round(performance.now()) + "] " + tag + (extra !== undefined ? " " + extra : ""));
}

// ---- Parser central ----

function wwr_onreply(results, sentAtMs) {
    var halfRttMs = (typeof sentAtMs === "number")
        ? Math.min(Math.max((Date.now() - sentAtMs) / 2, 0), 250) : 0;
    var ar = results.split("\n");
    for (var x = 0; x < ar.length; x++) {
        var tok = ar[x].split("\t");
        if (tok.length == 0) continue;

        switch (tok[0]) {
            case "TRANSPORT":
                if (tok.length > 4) {
                    nikTransportPlayState = parseInt(tok[1], 10);
                    if (tok[2] != playPosSeconds) playPosSeconds = tok[2];
                    // Crudo siempre, sin toggle de formato (esta UI no tiene el
                    // long-tap de measures/minsec del control remoto general).
                    nikLastPositionBeatsStr = tok[5];
                    nikTransportAnchorMs = performance.now() - halfRttMs;
                }
                break;

            case "EXTSTATE":
                if (tok[1] == "NikRemote" && tok[2] == "active_project_name") {
                    if (tok[3] != nikCurrentProjectName) {
                        nikCurrentProjectName = tok[3];
                        nikMsLog("NAME_CHANGE", JSON.stringify(tok[3]) + " markers=" + g_markers.length);
                        nikMsHandleProjectSwitch("name");
                    }
                    nikLastProjectNameUpdate = Date.now();
                }
                if (tok[1] == "NikRemote" && tok[2] == "reapitch_semitone") {
                    nikMsSetReaPitchSemitone(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "playrate") {
                    nikMsSetTransportPlayRate(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "tempo_map") {
                    // Duplicación deliberada respecto a playrate.js (ver
                    // remote_control_faders.md) — ms-tempo.js todavía no está
                    // escrito, guard de existencia para no romper este archivo
                    // en soledad durante el desarrollo por pasos.
                    if (typeof nikMsTempoSetMap === "function") nikMsTempoSetMap(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "timesig_map") {
                    // Reusado tal cual: music-state.js ya consume timesig_map
                    // para nikMusicStateCurrentPos/duración de compás.
                    if (typeof nikMusicStateSetTimesigMap === "function") nikMusicStateSetTimesigMap(tok[3]);
                }
                if (tok[1] == "NikMusicState" && tok[2] == "harmony_data") {
                    nikMsLog("HARMONY_IN", "len=" + (tok[3] ? tok[3].length : 0));
                    if (typeof nikMusicStateSetHarmonyData === "function") nikMusicStateSetHarmonyData(tok[3]);
                }
                if (tok[1] == "NikMusicState" && tok[2] == "project_key") {
                    if (typeof nikMusicStateSetProjectKey === "function") nikMusicStateSetProjectKey(tok[3]);
                }
                if (tok[1] == "NikMusicState" && tok[2] == "project_roles") {
                    if (typeof nikMusicStateSetProjectRoles === "function") nikMusicStateSetProjectRoles(tok[3]);
                }
                if (tok[1] == "NikMusicState" && tok[2] == "cues_data") {
                    if (typeof nikMusicStateSetCuesData === "function") nikMusicStateSetCuesData(tok[3]);
                }
                if (tok[1] == "NikMusicState" && tok[2] == "lyrics_data") {
                    nikMsLog("LYRICS_IN", "len=" + (tok[3] ? tok[3].length : 0));
                    if (typeof nikMusicStateSetLyricsData === "function") nikMusicStateSetLyricsData(tok[3]);
                }
                if (tok[1] == "NikMusicState" && tok[2] == "lyrics_version") {
                    // Un valor vacío (el script borró la key: proyecto sin track de
                    // lyrics) cuenta como cambio a null; así una letra que desaparece
                    // se refresca igual. Solo GET, nunca re-disparar el script: cada
                    // ejecución incrementa lyrics_version y esto haría un bucle.
                    var lvParsed = parseInt(tok[3], 10);
                    var lvNew = isNaN(lvParsed) ? null : lvParsed;
                    if (lvNew !== nikMsLastKnownLyricsVersion) {
                        nikMsLastKnownLyricsVersion = lvNew;
                        if (typeof nikMusicStateFetchLyrics === "function") nikMusicStateFetchLyrics();
                    }
                }
                if (tok[1] == "NikMonitorMix" && typeof nikMmOnExtState === "function") {
                    nikMmOnExtState(tok[2], tok[3]);
                }
                if (tok[1] == "NikMusicState" && tok[2] == "publish_version") {
                    var pv = parseInt(tok[3], 10);
                    if (!isNaN(pv) && pv !== nikMsLastKnownPublishVersion) {
                        // Antes: se saltaba el refresh en el primer publish_version visto
                        // tras un reset de proyecto (isFirstSight), asumiendo que el
                        // requestAll() del cambio de proyecto ya lo cubría. Esa premisa
                        // es insegura: si se publica armonía nueva antes del próximo tick
                        // del poll de 1000ms, el primer valor visto post-reset ya es el
                        // NUEVO, no el viejo -- y el refresh se perdía en silencio (bug
                        // reportado: no refresca si se publica justo después de abrir un
                        // proyecto en una tab que estaba "sin guardar" al conectar).
                        // Se pide siempre que cambie -- costo: algún requestAll()
                        // ocasionalmente redundante, inocuo comparado con perder un
                        // refresh real.
                        nikMsLastKnownPublishVersion = pv;
                        if (typeof nikMusicStateRequestAll === "function") {
                            nikMusicStateRequestAll();
                        }
                    }
                }
                break;

            case "MARKER_LIST":
                g_markers = [];
                break;
            case "MARKER":
                g_markers.push(tok);
                break;
            case "MARKER_LIST_END":
                nikMsLog("MARKERS_IN", "count=" + g_markers.length);
                // ms-section.js (todavía no escrito) resuelve la sección actual
                // sobre g_markers ya ordenado — guard de existencia, mismo
                // motivo que arriba.
                if (typeof nikMsSectionOnMarkersUpdated === "function") nikMsSectionOnMarkersUpdated();
                var markersSig = g_markers.length + ":" + g_markers.map(function (t) { return t.join("|"); }).join(";");
                var markersChanged = nikMsMarkersSig !== null && markersSig !== nikMsMarkersSig;
                nikMsMarkersSig = markersSig;
                if (markersChanged) nikMsHandleProjectSwitch("markers");
                break;

            default:
                if (typeof nikMmOnLine === "function") nikMmOnLine(tok);
                break;
        }
    }
}

var nikMsMarkersSig = null;
var nikMsLastSwitchAtMs = -Infinity;
var nikMsLastSwitchSource = "";
var NIK_MS_SWITCH_DEDUPE_MS = 2000;

// Punto único de "cambió el proyecto activo": reset del estado por-proyecto
// + re-pedido de datos (armonía, key, roles, cues, tempo/timesig).
// Dos disparadores:
//   "name"    -- cambio de active_project_name (poll lento de 1000 ms: llega
//                hasta ~1 s después del cambio real de tab).
//   "markers" -- cambio de la firma de la lista de markers en
//                MARKER_LIST_END (ciclo de 500 ms): casi siempre llega antes
//                que el nombre y deja acordes y secciones sincronizados.
// Dedupe: si el otro disparador ya actuó hace menos de NIK_MS_SWITCH_DEDUPE_MS
// se saltea, para no hacer reset y re-pedido dos veces por el mismo cambio.
// Falso positivo conocido e inocuo: editar markers a mano en REAPER con la UI
// abierta dispara "markers" (un reset y una recarga).
function nikMsHandleProjectSwitch(source) {
    var now = performance.now();
    if (source !== nikMsLastSwitchSource && now - nikMsLastSwitchAtMs < NIK_MS_SWITCH_DEDUPE_MS) {
        nikMsLog("SWITCH_SKIP", source);
        return;
    }
    nikMsLastSwitchAtMs = now;
    nikMsLastSwitchSource = source;
    nikMsLog("SWITCH", source);
    // Limpiar ANTES de re-pedir: si el proyecto nuevo no tiene datos
    // propios (pestaña "sin guardar"), el puente Lua no tiene ProjExtState
    // de origen para pisar el ExtState global -- sin este reset quedaban
    // colgados los valores del proyecto anterior (workaround del lado
    // cliente, causado por Nik_RemoteState_Poll.lua ensuciando el dirty
    // flag al cerrar la última tab).
    nikMsResetProjectState();
    if (typeof nikMmRequestList === "function") nikMmRequestList();
    if (typeof nikMusicStateRequestAll === "function") nikMusicStateRequestAll();
    if (NIK_MS_LYRICS_ENABLED && typeof nikMusicStateRequestLyrics === "function") nikMusicStateRequestLyrics();
    nikMsRequestTempoAndTimesig();
    // Mitigación de carrera: si una respuesta rezagada del proyecto
    // anterior llega DESPUÉS del reset, repuebla con datos viejos (las
    // respuestas no vienen etiquetadas por proyecto). Este segundo pedido
    // asume orden FIFO del server de REAPER -- no es garantía formal. Si
    // persiste, hace falta un token de generación o atacar la causa raíz
    // en Nik_RemoteState_Poll.lua.
    window.setTimeout(function () {
        if (typeof nikMusicStateRequestAll === "function") nikMusicStateRequestAll();
        if (NIK_MS_LYRICS_ENABLED && typeof nikMusicStateRequestLyrics === "function") nikMusicStateRequestLyrics();
        nikMsRequestTempoAndTimesig();
    }, 400);
}

// Vuelve todo el estado por-proyecto a "vacío" -- llamado al detectar
// cambio de active_project_name, antes de re-pedir. Reusa los setters ya
// existentes de music-state.js/ms-tempo.js pasándoles null/vacío en vez
// de duplicar la lógica de "qué es un estado vacío" acá.
function nikMsResetProjectState() {
    if (typeof nikMusicStateSetHarmonyData === "function") nikMusicStateSetHarmonyData(null);
    if (typeof nikMusicStateSetCuesData === "function") nikMusicStateSetCuesData(null);
    if (typeof nikMusicStateSetProjectKey === "function") nikMusicStateSetProjectKey(null);
    if (typeof nikMusicStateSetProjectRoles === "function") nikMusicStateSetProjectRoles(null);
    if (typeof nikMsTempoSetMap === "function") nikMsTempoSetMap(null);
    if (typeof nikMusicStateSetLyricsData === "function") nikMusicStateSetLyricsData(null);
    nikMsLastKnownLyricsVersion = null;
    nikMsLastKnownPublishVersion = null;
    if (typeof nikMmReset === "function") nikMmReset();
    nikMsLog("RESET");
    nikReaPitchLastSemitone = "none";
}

// Pendiente de doc
function nikMsSetTransportPlayRate(val) {
    var r = parseFloat(val);
    if (isNaN(r) || r <= 0) return;
    if (r > 5) r = r / 100;
    nikTransportPlayRate = r;
}

// Mismo criterio exacto que la parte no-DOM de nikReaPitchUpdateSemitoneDisplay()
// (reapitch.js): "none"/"mixed" son sentinels reales del Stem Bus (sin
// ReaPitch activo / instancias en desacuerdo entre sí), se guardan tal cual
// -- el consumidor (music-transpose.js) es quien decide qué hacer con ellos,
// acá no se decide un fallback numérico que podría mostrar una transposición
// falsa como si fuera válida.
function nikMsSetReaPitchSemitone(val) {
    nikReaPitchLastSemitone = (val == "none" || val == "mixed") ? val : Number(val);
}

// ---- Trigger on-demand: tempo_map + timesig_map ----
// Equivalente chico de nikPlayrateRequestTempoMap() (playrate.js), sin la
// parte de BPM/DOM del popup — esta UI no carga playrate.js. Mismo Command
// ID reusado (un solo script Lua publica las dos keys, ver
// remote_control_faders.md), no un script nuevo. Confirmado contra
// config.js: NIK_ONDEMAND_READS (= nikBuildSlowPoll) NO incluye
// tempo_map/timesig_map, así que este pedido separado es necesario, no
// una duplicación de algo que ya está en el bundle.
function nikMsRequestTempoAndTimesig() {
    wwr_req(NIK_LUA_COMMANDS.playrateTempoMapRead.commandId +
        ";GET/EXTSTATE/NikRemote/tempo_map;GET/EXTSTATE/NikRemote/timesig_map");
}
