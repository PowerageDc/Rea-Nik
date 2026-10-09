// ms-header.js — bloque superior compartido (nombre de canción, tonalidad,
// tempo) de instrumentista y cantante
//
// Traslado 1:1 desde instrumentista.js, sin cambios de lógica.
//
// Contrato de DOM (los dos shells deben usar estos ids):
//   msSongName, msKeyTonicText, msTempo
// El rol (msRole) NO se maneja acá: es propio de instrumentista.
// Contrato de CSS: glifos de tonalidad (.ms-key-accidental-sharp / -flat /
// .ms-key-minor) y .ms-tempo-number, en ms-base.css.
//
// Punto de entrada: nikMsHeaderRender(), una vez por render.
//
// Requiere, ya cargados: core/music-state.js (nikMusicStateCurrentProjectKey,
// nikMusicStatePlayRate), ms-tempo.js (nikMsTempoAt), ms-section.js
// (nikMsEffectivePosSeconds) y la global nikCurrentProjectName.

function nikMsEscapeHtml(str) {
    return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// "maj"/"min" son los únicos casos confirmados (ejemplo del doc de
// diseño). Cualquier otro modo cae al fallback genérico -- no confirmado
// contra el string real que devuelve nikTranspose para modos no
// estándar (dórico, mixolidio, etc.), no debería aparecer en el uso
// actual pero no se descarta.
var NIK_MS_KEY_TONIC_REGEX = /^([A-G])([#b]?)$/;

function nikMsFormatKeyTonicHtml(key) {
    if (!key || !key.tonic) return "—";
    var m = NIK_MS_KEY_TONIC_REGEX.exec(key.tonic);
    if (!m) return nikMsEscapeHtml(key.tonic); // fallback si el formato no matchea

    var html = "<span>" + m[1] + "</span>";
    if (m[2]) {
        var isSharp = (m[2] === "#");
        var accClass = isSharp ? "ms-key-accidental-sharp" : "ms-key-accidental-flat";
        var accGlyph = isSharp ? "♯" : "♭";
        html += '<span class="' + accClass + '">' + accGlyph + "</span>";
    }
    if (key.mode === "minor") {
        html += '<span class="ms-key-minor">m</span>';
    }
    // major: no se agrega nada. Cualquier otro modo (dórico, mixolidio...):
    // tampoco se agrega nada por ahora -- no confirmado contra un caso real,
    // igual que el fallback que reemplaza.
    return html;
}

function nikMsFormatTempo() {
    var pos = nikMsEffectivePosSeconds();
    var bpm = (typeof nikMsTempoAt === "function") ? nikMsTempoAt(pos) : null;
    if (bpm == null) return "—";
    if (typeof nikMusicStatePlayRate === "function") bpm *= nikMusicStatePlayRate();
    return '<span class="ms-tempo-number">' + Math.round(bpm) + "</span> BPM";
}

function nikMsFormatSongName() {
    if (!nikCurrentProjectName || !/\.rpp$/i.test(nikCurrentProjectName)) return "\u00A0";
    return nikCurrentProjectName.replace(/\.rpp$/i, "");
}

function nikMsHeaderRender() {
    document.getElementById("msKeyTonicText").innerHTML = nikMsFormatKeyTonicHtml(
        (typeof nikMusicStateCurrentProjectKey === "function") ? nikMusicStateCurrentProjectKey() : null
    );
    document.getElementById("msTempo").innerHTML = nikMsFormatTempo();
    document.getElementById("msSongName").textContent = nikMsFormatSongName();
}
