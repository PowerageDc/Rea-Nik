// core/tab-ui-memory.js — memoria de UI por proyecto (tab).
// Los arrays de core/state.js (trackHeightsAr, trackColoursAr, trackFlagsAr,
// trackNamesAr, trackNumbersAr...) están indexados por número de track de
// REAPER, pero ese número identifica una POSICIÓN, no un track fijo: al
// cambiar de tab, el track 3 del proyecto nuevo no tiene relación con el
// track 3 del proyecto anterior. Sin este módulo, la UI hereda estado del
// proyecto anterior (fader desplegado que no corresponde, colores que no se
// redibujan porque el gate de diff los da por "sin cambios").
//
// Diseñado como mecanismo genérico: nikTabUiMemory[projectName] guarda
// cualquier parámetro de UI que haya que recordar por proyecto (hoy:
// expandedTracks + scrollTop; a futuro, sumar claves nuevas al objeto que
// arma nikTabMemorySnapshot() sin tocar el resto del mecanismo — reaplicar
// también en nikTabMemoryApplyPending() si el parámetro depende de que el
// DOM tenga su tamaño final, como scrollTop).
//
// Único punto de enganche: el handler de EXTSTATE "active_project_name" en
// core/wwr-dispatch.js, que ya detecta cambio de proyecto activo (llega en
// NIK_SLOW_POLL, sin costo de red adicional).
//
// Depende de: core/state.js (trackHeightsAr, trackColoursAr, trackFlagsAr,
// trackNamesAr, trackNumbersAr, trackSendHwCntAr, nTrack). Debe cargar
// después de core/state.js y antes de core/wwr-dispatch.js.

var nikTabUiMemory = {};        // { "<nombre proyecto>": { expandedTracks: {3:1,5:1}, scrollTop: 240 } }
var nikCurrentProjectName = null;

// estado pendiente del proyecto activo, consultado por wwr-dispatch.js al 
// poblar por primera vez un shell que todavía no existía en el momento del 
// restore (también reaplica scrollTop, ver nikTabMemoryApplyPending)
var nikTabMemoryPendingRestore = { expandedTracks: {}, scrollTop: 0 };

// Snapshot del estado de UI vivo del proyecto ACTUAL — se llama antes de
// pisar los arrays globales con datos del proyecto nuevo.
function nikTabMemorySnapshot() {
    var expandedTracks = {};
    var domCount = document.getElementsByClassName("trackRow2").length;
    for (var i = 0; i < domCount; i++) {
        if (trackHeightsAr[i] == 1) expandedTracks[i] = 1;
    }
    var tracksEl = document.getElementById("tracks");
    var transportR3 = document.getElementById("transport_r3");
    return {
        expandedTracks: expandedTracks,
        scrollTop: tracksEl ? tracksEl.scrollTop : 0,
        loopRecExpanded: transportR3 ? !transportR3.classList.contains("nikCollapsed") : false
    };
}

function nikTabMemorySave(projectName) {
    if (!projectName) return;
    nikTabUiMemory[projectName] = nikTabMemorySnapshot();
}

// Fuerza redraw completo en el próximo poll: limpia los arrays que se usan
// como gate de diff ("solo redibujo si cambió"), para que ningún valor
// heredado del proyecto anterior bloquee la actualización visual del nuevo
// (fix del bug de colores a gris al volver a una tab).
function nikTabMemoryResetRenderCaches() {
    trackColoursAr = [];
    trackFlagsAr = [];
    trackNamesAr = [];
    trackNumbersAr = [];
}

// Aplica el desplegado guardado (o colapsado por default si es la primera
// vez que se ve ese proyecto), sin animación — ver nikSetTrackExpandedInstant.
function nikTabMemoryRestore(projectName) {
    var saved = nikTabUiMemory[projectName] || { expandedTracks: {}, scrollTop: 0, loopRecExpanded: false };
    nikTabMemoryPendingRestore = { expandedTracks: saved.expandedTracks, scrollTop: saved.scrollTop || 0 };
    var domCount = document.getElementsByClassName("trackRow2").length;
    for (var i = 0; i < domCount; i++) {
        var shouldBeExpanded = !!saved.expandedTracks[i];
        if ((trackHeightsAr[i] == 1) != shouldBeExpanded) {
            nikSetTrackExpandedInstant(i, shouldBeExpanded);
        }
    }
    var tracksEl = document.getElementById("tracks");
    if (tracksEl) tracksEl.scrollTop = nikTabMemoryPendingRestore.scrollTop;
    nikApplyLoopRecState(!!saved.loopRecExpanded);
}

// Consultado por wwr-dispatch.js apenas un shell recién creado termina de
// poblarse con contenido SVG real (primera vez que ese índice existe en el
// proyecto activo) — cubre el caso en que el restore corrió ANTES de que
// el shell existiera en el DOM (proyecto de destino con más tracks que el
// actual al momento del cambio de tab).
function nikTabMemoryApplyPending(id) {
    if (nikTabMemoryPendingRestore.expandedTracks && nikTabMemoryPendingRestore.expandedTracks[id]) {
        nikSetTrackExpandedInstant(id, true);
    }
    var tracksEl = document.getElementById("tracks");
    if (tracksEl) tracksEl.scrollTop = nikTabMemoryPendingRestore.scrollTop || 0;
}

// Variante sin animación de la lógica de hitbox() (core/tracks-render.js):
// salta directo al viewBox final en vez de correr el loop de
// requestAnimationFrame. Misma limitación de indexado posicional que
// hitbox() (document.getElementsByClassName("trackRow2")[id]) — consistente
// con el patrón ya usado en el resto del archivo.
function nikSetTrackExpandedInstant(id, expanded) {
    var thisTrackRow2 = document.getElementsByClassName("trackRow2")[id];
    if (!thisTrackRow2 || !thisTrackRow2.firstChild) return;
    var thisTrackRow2Svg = thisTrackRow2.firstChild.firstElementChild;
    if (!thisTrackRow2Svg) return;

    var row2h = expanded ? 37 : 0.01;
    thisTrackRow2Svg.setAttributeNS(null, "viewBox", "0 1 320 " + row2h);

    if (trackSendHwCntAr[id] > 0) {
        var sendsTrackEl = document.getElementById("sendsTrack" + id);
        var sendH = expanded ? 50 : 0.01;
        if (sendsTrackEl) {
            for (var x = 0; x < trackSendHwCntAr[id]; x++) {
                var sendNode = sendsTrackEl.childNodes[x];
                if (!sendNode || !sendNode.firstElementChild) continue;
                var thisSendSvg = sendNode.firstElementChild.firstElementChild;
                if (thisSendSvg) thisSendSvg.setAttributeNS(null, "viewBox", "0 0 320 " + sendH);
            }
        }
    }

    trackHeightsAr[id] = expanded ? 1 : 0;
}