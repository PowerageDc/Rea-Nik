// markers/markers.js — parseo/resolución de nombres y colores de markers.
// Compartido entre modals/marker-browser/marker-browser.js y los
// indicadores prev/actual/next del transporte (que quedan en el shell).
// Depende de config.js (NIK_MARKER_COLOR_MAP, NIK_MARKER_CHAIN_PATTERN,
// NIK_MARKER_CHAIN_STEP) y de core/utils.js (nikLerpColor).

function nikNormalizeMarkerName(name) {
    if (!name) return "";
    return name.toString()
        .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .toLowerCase()
        .replace(/\s+/g, "");
}

function nikEscapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Resuelve nombre a mostrar + color para un marker dado el estado de cadena
// acumulado hasta el momento (mismo criterio que el popup de markers: un
// marker sin categoria en el medio no corta la cadena, ver 01_CONVENCIONES.md
// / remote_control.md). chainState = {color, step}, se muta in-place.
function nikResolveMarkerDisplay(rawName, chainState) {
    var normalized = nikNormalizeMarkerName(rawName);
    var displayName = rawName, resolvedColor = null;
    if (NIK_MARKER_CHAIN_PATTERN.test(normalized) && chainState.color) {
        resolvedColor = nikLerpColor(chainState.color, "#FFFFFF", NIK_MARKER_CHAIN_STEP * chainState.step);
        chainState.step++;
    }
    else {
        var cat = nikMatchMarkerCategory(normalized);
        if (cat) {
            resolvedColor = cat.color;
            if (cat.translated) displayName = cat.label + (cat.number ? (" " + cat.number) : "");
            chainState.color = cat.color;
            chainState.step = 1;
        }
    }
    return { displayName: displayName, resolvedColor: resolvedColor };
}

function nikFormatMinSec(totalSeconds) {
    var mins = Math.floor(totalSeconds / 60);
    var secs = Math.round(totalSeconds - mins * 60);
    if (secs == 60) { mins += 1; secs = 0; }
    var secsStr = (secs < 10) ? ("0" + secs) : ("" + secs);
    return mins + ":" + secsStr;
}

// Devuelve null si no matchea ninguna categoria, o {label, color, tint, translated, number}
function nikMatchMarkerCategory(normalized) {
    for (var i = 0; i < NIK_MARKER_COLOR_MAP.length; i++) {
        var cat = NIK_MARKER_COLOR_MAP[i];
        for (var w = 0; w < cat.words.length; w++) {
            var m = normalized.match(new RegExp("^" + nikEscapeRegex(cat.words[w]) + "\\d*.*$"));
            if (m) return { label: cat.label, color: cat.color, tint: cat.tint, translated: false, number: "" };
        }
        for (var a = 0; a < cat.abbrev.length; a++) {
            var ma = normalized.match(new RegExp("^" + nikEscapeRegex(cat.abbrev[a]) + "(\\d*)$"));
            if (ma) return { label: cat.label, color: cat.color, tint: cat.tint, translated: true, number: ma[1] };
        }
    }
    return null;
}

// "id1:compases1;id2:compases2;..." -> { "id1": "compases1", ... }
function nikParseMarkerBars(str) {
    var map = {};
    if (!str) return map;
    var pairs = str.split(";");
    for (var i = 0; i < pairs.length; i++) {
        var kv = pairs[i].split(":");
        if (kv.length == 2) map[kv[0]] = kv[1];
    }
    return map;
}