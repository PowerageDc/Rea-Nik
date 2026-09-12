// musicstate-ui/shared/ms-section.js
// Resuelve la sección actual (nombre + color de familia) a partir de
// g_markers (poblado por ms-dispatch.js) + playPosSeconds -- mismo
// criterio que nikMarkerBrowserFindCurrentId() (marker-browser.js): el
// último marker con posición <= actual. Reusa nikResolveMarkerDisplay()
// (markers/markers.js) tal cual, sin fork.
//
// Depende de (deben cargarse antes en el HTML):
//   config.js            → NIK_MARKER_COLOR_MAP, NIK_MARKER_CHAIN_PATTERN, NIK_MARKER_CHAIN_STEP
//   markers/markers.js   → nikResolveMarkerDisplay
//   musicstate-ui/shared/ms-dispatch.js → g_markers, playPosSeconds
//
// Llamado desde ms-dispatch.js: nikMsSectionOnMarkersUpdated() en cada
// MARKER_LIST_END (poll de 500ms) -- NO solo en conexión/cambio de
// proyecto (ver discusión de sesión): recalcular cada 500ms es barato
// (pocos markers por canción) y cubre de yapa markers editados en vivo,
// sin necesidad de detectar "¿cambió algo?" -- si esto no es lo que se
// quería decir en musicstate_instrumentista.md §2/§3, es fácil acotar a
// project-change nada más.

var nikMsMarkersSorted = [];   // copia de g_markers ordenada por pos ascendente
var nikMsMarkerChainMap = {};  // id -> {displayName, resolvedColor}, resuelto una vez por actualización

// Recalcula nikMsMarkersSorted + nikMsMarkerChainMap desde g_markers.
// Mismo patrón que el bloque de wwr-dispatch.js (REGION_LIST_END): se
// resuelve TODA la timeline una sola vez, no marker por marker on-demand
// -- necesario para que una cadena "x2/x3..." herede el color correcto
// aunque su ancla no sea el marker actual (mismo bug ya documentado y
// resuelto ahí, ver remote_control_markers.md "Fix: color de markers xN").
function nikMsSectionOnMarkersUpdated() {
    nikMsMarkersSorted = g_markers.slice().sort(function (a, b) {
        return parseFloat(a[3]) - parseFloat(b[3]);
    });

    nikMsMarkerChainMap = {};
    var chainState = { color: null, step: 0 };
    for (var i = 0; i < nikMsMarkersSorted.length; i++) {
        var row = nikMsMarkersSorted[i];
        nikMsMarkerChainMap[row[2]] = nikResolveMarkerDisplay(row[1], chainState);
    }
}

// Índice en nikMsMarkersSorted del marker vigente en `posSeconds` -- último
// con pos <= posSeconds, o -1 si ninguno (posición anterior al primero).
// EPSILON: tok[2] de TRANSPORT llega truncado a 6 decimales, mientras que la
// posición de MARKER conserva precisión completa de double -- al aterrizar
// justo en un marker, el truncamiento puede caer una fracción de microsegundo
// por debajo del valor exacto del marker, y la comparación estricta fallaba
// hasta el próximo compás (bug reportado: display se quedaba en la sección
// anterior hasta avanzar un compás). Margen de 1ms, muy por encima del error
// de truncamiento real observado (~0.4 microsegundos) y sin relevancia
// musical a ningún tempo razonable.
var NIK_MS_SECTION_EPSILON_SEC = 0.001;

function nikMsFindSectionIndexAt(posSeconds) {
    var idx = -1;
    for (var i = 0; i < nikMsMarkersSorted.length; i++) {
        if (parseFloat(nikMsMarkersSorted[i][3]) <= posSeconds + NIK_MS_SECTION_EPSILON_SEC) idx = i;
        else break;
    }
    return idx;
}

// Sección vigente en una posición dada -- {id, pos, displayName, resolvedColor}
// o null si no hay ningún marker aún (antes del primero, o proyecto sin
// markers). resolvedColor puede venir null igual si el nombre no matchea
// ninguna categoría de NIK_MARKER_COLOR_MAP -- el fallback visual (gris,
// etc.) queda del lado de instrumentista.js, no acá.
function nikMsSectionAt(posSeconds) {
    var idx = nikMsFindSectionIndexAt(posSeconds);
    if (idx === -1) return null;
    var row = nikMsMarkersSorted[idx];
    var resolved = nikMsMarkerChainMap[row[2]];
    if (!resolved) return null;
    return {
        id: row[2],
        pos: parseFloat(row[3]),
        displayName: resolved.displayName,
        resolvedColor: resolved.resolvedColor
    };
}

// Atajo sobre la posición actual de reproducción -- mismo criterio que
// nikMsTempoAt(parseFloat(playPosSeconds)).
function nikMsCurrentSection() {
    return nikMsSectionAt(parseFloat(playPosSeconds));
}
