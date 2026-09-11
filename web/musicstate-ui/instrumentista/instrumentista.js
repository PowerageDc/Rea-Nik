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

// --- Selector de rol: persistencia por dispositivo (localStorage, no ---
// --- tab-ui-memory.js -- el eje acá es "de quién es este celular",   ---
// --- no el proyecto/tab activo de REAPER, ver diseño §4).            ---

var NIK_INSTRUMENTISTA_ROLE_STORAGE_KEY = "nikInstrumentistaRole";

function nikInstrumentistaGetRole() {
    try { return window.localStorage.getItem(NIK_INSTRUMENTISTA_ROLE_STORAGE_KEY); }
    catch (e) { return null; }
}

function nikInstrumentistaSetRole(role) {
    try { window.localStorage.setItem(NIK_INSTRUMENTISTA_ROLE_STORAGE_KEY, role); }
    catch (e) { /* localStorage no disponible (modo privado, etc.) -- sin persistencia, no bloqueante */ }
}

// "todos" es válido siempre (reservado, IMPL_MusicState.md §11.1), sin
// necesidad de estar en nikMusicStateProjectRoles. Se calcula on-demand,
// sin cachear -- nikMusicStateProjectRoles llega on-demand (ver
// ms-dispatch.js) y puede no estar listo todavía al momento del boot, o
// puede cambiar tras un cambio de proyecto sin que haya un evento que avise.
function nikInstrumentistaIsRoleValid(role) {
    if (!role) return false;
    if (role === "todos") return true;
    return nikMusicStateProjectRoles.indexOf(role) !== -1;
}

// --- Render: layout vertical estático (roadmap punto 3, doc §5) ---
// Separado de nikInstrumentistaInit() a propósito: el bootstrap (polls,
// on-demand) tiene que poder correr solo, sin asumir que existen estos
// IDs de DOM -- así nsaudio_musicstate_test.html sigue funcionando sin
// tocar nada, y el render solo lo arranca el shell que sí tiene esta
// estructura (nsaudio_musicstate_instrumentista_preview.html).

// "maj"/"min" son los únicos casos confirmados (ejemplo del doc de
// diseño). Cualquier otro modo cae al fallback genérico -- no confirmado
// contra el string real que devuelve nikTranspose para modos no
// estándar (dórico, mixolidio, etc.), no debería aparecer en el uso
// actual pero no se descarta.
var NIK_INSTRUMENTISTA_MODE_ABBREV = { major: "maj", minor: "min" };

function nikInstrumentistaFormatKey(key) {
    if (!key) return "—";
    var mode = NIK_INSTRUMENTISTA_MODE_ABBREV[key.mode] || (key.mode ? key.mode.slice(0, 3) : "");
    return "♪ " + key.tonic + " " + mode;
}

function nikInstrumentistaFormatTempo() {
    var pos = parseFloat(playPosSeconds);
    var bpm = (typeof nikMsTempoAt === "function") ? nikMsTempoAt(pos) : null;
    return (bpm != null) ? Math.round(bpm) + " BPM" : "—";
}

function nikInstrumentistaFormatSongName() {
    return nikCurrentProjectName ? nikCurrentProjectName.replace(/\.rpp$/i, "") : "—";
}

function nikInstrumentistaRender() {
    var role = nikInstrumentistaGetRole();

    document.getElementById("msRole").textContent = role || "(sin rol)";
    document.getElementById("msKey").textContent = nikInstrumentistaFormatKey(
        (typeof nikMusicStateCurrentProjectKey === "function") ? nikMusicStateCurrentProjectKey() : null
    );
    document.getElementById("msTempo").textContent = nikInstrumentistaFormatTempo();
    document.getElementById("msSongName").textContent = nikInstrumentistaFormatSongName();

    var sectionEl = document.getElementById("msSection");
    var section = (typeof nikMsCurrentSection === "function") ? nikMsCurrentSection() : null;
    if (section) {
        sectionEl.textContent = "● " + section.displayName;
        sectionEl.style.color = section.resolvedColor || "";
    } else {
        sectionEl.textContent = "—";
        sectionEl.style.color = "";
    }

    nikInstrumentistaRenderChordStrip();

    // "todos" no se pasa tal cual a nikMusicStateActiveCues -- esa función
    // trata "sin filtro" como null/undefined (devuelve todas), no como el
    // string "todos" (que restringiría solo a cues con "todos" en roles,
    // perdiendo las cues de rol específico). Traducimos acá para no tocar
    // la firma ya cerrada de music-state.js.
    var roleFilter = (!role || role === "todos") ? undefined : role;
    var cues = (typeof nikMusicStateActiveCues === "function") ? nikMusicStateActiveCues(roleFilter) : [];
    var cueBandEl = document.getElementById("msCueBand");
    if (cues.length > 0) {
        cueBandEl.textContent = cues.map(function (c) { return c.text; }).join(" · ");
        cueBandEl.hidden = false;
    } else {
        cueBandEl.hidden = true;
    }
}

// Tira de acordes: 2 hacia atrás + actual + 2 hacia adelante -- punto de
// partida para el pendiente "cantidad final de slots" del doc de diseño
// §8, ahora resuelto en 5 (a confirmar que entre cómodo contra chords
// largos tipo "C#m7b5" en pantallas angostas, ver clamp() en el CSS).
// Reusa nikMusicStateChordWindow tal cual -- ya trae isCurrent por
// evento, solo se traduce a offset relativo para el atributo data-offset
// que usa el CSS (-2..2).
function nikInstrumentistaRenderChordStrip() {
    var stripEl = document.getElementById("msChordStrip");
    if (typeof nikMusicStateChordWindow !== "function") { stripEl.textContent = "—"; return; }

    var win = nikMusicStateChordWindow(2, 2);
    var currentIdx = -1;
    for (var i = 0; i < win.length; i++) { if (win[i].isCurrent) { currentIdx = i; break; } }

    // Los 5 offsets (-2..2) siempre existen en el DOM, aunque `win` traiga
    // menos elementos (ej. al principio de la canción, sin acordes previos
    // todavía) -- así la tira nunca cambia de ancho geométrico y el slot
    // central se mantiene alineado con el centro real del viewport. El
    // offset faltante queda como slot vacío (mismo ancho reservado, sin
    // texto), no se saca del flujo.
    var byOffset = {};
    for (var j = 0; j < win.length; j++) {
        var offset = (currentIdx === -1) ? 0 : (j - currentIdx);
        byOffset[offset] = win[j];
    }

    stripEl.innerHTML = "";
    for (var o = -2; o <= 2; o++) {
        var slot = document.createElement("span");
        slot.className = "ms-chord-slot";
        slot.setAttribute("data-offset", String(o));
        var entry = byOffset[o];
        // chord === null es el sentinel de silencio explícito (ver
        // core/music-state.js) -- se muestra distinguible de "sin dato".
        // undefined (offset sin entrada en `win`) se muestra vacío, no "—",
        // para no competir visualmente con el silencio explícito.
        slot.textContent = !entry ? "" : (entry.chord === null ? "—" : entry.chord);
        stripEl.appendChild(slot);
    }
}

function nikInstrumentistaStartRenderLoop(intervalMs) {
    window.setInterval(nikInstrumentistaRender, intervalMs || 200);
}