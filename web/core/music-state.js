// core/music-state.js — resuelve el estado musical (acorde vigente/próximo,
// indicaciones de rol activas) a partir de la posición actual del
// transporte + los 4 datos publicados por Nik_MusicState_PublishAll.lua
// (namespace NikMusicState: harmony_data, project_key, project_roles,
// cues_data) + NikRemote/timesig_map (ya implementado, ver
// Nik_Playrate_ReadTempoMap.lua).
//
// Depende de: nikLastPositionBeatsStr (core/state.js, cacheado en cada
// TRANSPORT por core/wwr-dispatch.js), nikReaPitchLastSemitone
// (core/state.js), nikTranspose (core/music-transpose.js — debe cargar
// antes que este archivo).
//
// Patrón: variables/funciones sueltas en global scope, prefijo
// nikMusicState* — igual que playrate.js, NO el wrapper de objeto único
// (ver 01_CONVENCIONES.md, "Patrón de módulos JS de puro cálculo"): este
// módulo tiene estado propio cacheado (los 5 arrays/objetos de abajo), no
// es puro cálculo como core/music-transpose.js.
//
// IMPL_MusicState.md, secciones 10-11, tiene el detalle de cada decisión
// de diseño referenciada en los comentarios de abajo.

// --- Estado cacheado (llenado por los setters, uno por key de EXTSTATE) ---
var nikMusicStateHarmonyFlat = [];   // array ordenado {bar, qn_offset, chord}
var nikMusicStateCuesFlat = [];      // array ordenado {bar, qn_offset, roles, text, duration_qn}
var nikMusicStateTimesigMap = [];    // array ordenado {bar, num, den}
var nikMusicStateProjectKey = null;  // {tonic, mode} | null
var nikMusicStateProjectRoles = [];  // array de strings, sin "todos" (reservado, ver 11.1)

// --- Setters, llamados desde core/wwr-dispatch.js al llegar cada EXTSTATE ---
// (misma responsabilidad que nikPlayrateSetTempoMap en playrate.js)

function nikMusicStateSetHarmonyData(val) {
    nikMusicStateHarmonyFlat = nikMusicStateFlattenBarKeyed(nikMusicStateParseJsonSafe(val));
}

function nikMusicStateSetCuesData(val) {
    nikMusicStateCuesFlat = nikMusicStateFlattenBarKeyed(nikMusicStateParseJsonSafe(val));
}

function nikMusicStateSetProjectKey(val) {
    nikMusicStateProjectKey = nikMusicStateParseJsonSafe(val);
}

function nikMusicStateSetProjectRoles(val) {
    var parsed = nikMusicStateParseJsonSafe(val);
    nikMusicStateProjectRoles = parsed || [];
}

// Formato "measure1:num1:den1,measure2:num2:den2,..." -- igual criterio
// que nikPlayrateSetTempoMap, measure ya viene 1-indexed (IMPL sección 5).
function nikMusicStateSetTimesigMap(val) {
    var map = [];
    if (val) {
        var entries = val.split(",");
        for (var i = 0; i < entries.length; i++) {
            var parts = entries[i].split(":");
            var bar = parseInt(parts[0], 10);
            var num = parseInt(parts[1], 10);
            var den = parseInt(parts[2], 10);
            if (!isNaN(bar) && !isNaN(num) && !isNaN(den)) map.push({ bar: bar, num: num, den: den });
        }
        map.sort(function (a, b) { return a.bar - b.bar; });
    }
    nikMusicStateTimesigMap = map;
}

function nikMusicStateParseJsonSafe(val) {
    if (!val) return null;
    try { return JSON.parse(val); } catch (e) { return null; }
}

// --- Aplanado genérico: sirve para harmony_data y cues_data por igual,   ---
// --- ambos son objetos keyed por número de compás (IMPL 4.2 y 11.2)     ---

// Ordena por (bar, qn_offset) -- alcanza porque el número de compás es
// monótono a lo largo de la canción, no hace falta QN absoluto para esto
// (ver charla de sesión, "no hace falta convertir a tiempo absoluto para
// ordenar").
function nikMusicStateComparePos(a, b) {
    if (a.bar !== b.bar) return a.bar - b.bar;
    return a.qn_offset - b.qn_offset;
}

function nikMusicStateFlattenBarKeyed(dataObj) {
    var flat = [];
    if (!dataObj) return flat;
    for (var barKey in dataObj) {
        if (!dataObj.hasOwnProperty(barKey)) continue;
        var bar = parseInt(barKey, 10);
        if (isNaN(bar)) continue;
        var events = dataObj[barKey];
        for (var i = 0; i < events.length; i++) {
            events[i].bar = bar; // anota el compás sobre el propio evento
            flat.push(events[i]);
        }
    }
    flat.sort(nikMusicStateComparePos);
    return flat;
}

// --- Posición actual: compás + qn_offset dentro del compás ---
// Fórmula confirmada en sesión (test manual en REAPER, 2/4 y 6/8): el
// beat de tok[5] está en unidades del DENOMINADOR del compás, no siempre
// negras -- de ahí el factor 4/den.

function nikMusicStateParseBarBeat(tokStr) {
    if (!tokStr) return null;
    var parts = tokStr.split(".");
    if (parts.length < 2) return null;
    var bar = parseInt(parts[0], 10);
    var beatIndex = parseInt(parts[1], 10);
    var hundredths = parts.length > 2 ? parseInt(parts[2], 10) : 0;
    if (isNaN(bar) || isNaN(beatIndex)) return null;
    return { bar: bar, beatIndex: beatIndex, hundredths: isNaN(hundredths) ? 0 : hundredths };
}

// Backward-lookup de time signature por compás -- mismo criterio que
// nikPlayrateTempoAt (playrate.js), pero indexado por compás en vez de
// por segundos.
function nikMusicStateTimesigAt(bar) {
    if (!nikMusicStateTimesigMap || nikMusicStateTimesigMap.length === 0) return { bar: 1, num: 4, den: 4 };
    var found = nikMusicStateTimesigMap[0];
    for (var i = 0; i < nikMusicStateTimesigMap.length; i++) {
        if (nikMusicStateTimesigMap[i].bar <= bar) found = nikMusicStateTimesigMap[i];
        else break;
    }
    return found;
}

function nikMusicStateBarDurationQn(bar) {
    var sig = nikMusicStateTimesigAt(bar);
    return sig.num * (4 / sig.den);
}

// QN absoluto del downbeat de `bar` -- suma la duración de todos los
// compases anteriores (IMPL 4.2, misma fórmula que duracion_compas_QN).
// Solo se usa para cues_data (10.5/11.2, duration_qn puede cruzar de
// compás) -- el lookup de acordes NO lo necesita, compara tuplas
// (bar, qn_offset) directo.
function nikMusicStateBarStartQn(bar) {
    var qn = 0.0;
    for (var b = 1; b < bar; b++) qn += nikMusicStateBarDurationQn(b);
    return qn;
}

// Posición actual como {bar, qn_offset} -- misma forma que los eventos
// aplanados, para poder reusar nikMusicStateComparePos sin traducir nada.
function nikMusicStateCurrentPos() {
    var parsed = nikMusicStateParseBarBeat(nikLastPositionBeatsStr);
    if (!parsed) return null;
    var sig = nikMusicStateTimesigAt(parsed.bar);
    var qnOffset = (parsed.beatIndex - 1 + parsed.hundredths / 100) * (4 / sig.den);
    return { bar: parsed.bar, qn_offset: qnOffset };
}

// --- Transposición: se aplica al leer, nunca sobre el array cacheado ---
// (así un cambio de semitonos en caliente no obliga a re-aplanar nada).
// chord === null es el sentinel de silencio explícito (IMPL, sección
// "carry-over") -- se propaga tal cual, no hay nada que transponer.
function nikMusicStateTransposeChordIfNeeded(chord) {
    if (chord === null || chord === undefined) return null;
    var delta = parseInt(nikReaPitchLastSemitone, 10);
    if (isNaN(delta) || delta === 0 || !nikMusicStateProjectKey) return chord;
    var newKey = nikTranspose.key(nikMusicStateProjectKey.tonic, nikMusicStateProjectKey.mode, delta);
    return nikTranspose.chord(chord, delta, newKey.useSharps);
}

// Índice del último evento de `flatArray` con posición <= pos, o -1 si
// ninguno (la posición actual es anterior al primer evento).
function nikMusicStateFindIndexAtOrBefore(flatArray, pos) {
    var idx = -1;
    for (var i = 0; i < flatArray.length; i++) {
        if (nikMusicStateComparePos(flatArray[i], pos) <= 0) idx = i;
        else break;
    }
    return idx;
}

// --- Consultas de armonía ---

function nikMusicStateCurrentChord() {
    var pos = nikMusicStateCurrentPos();
    if (!pos) return null;
    var idx = nikMusicStateFindIndexAtOrBefore(nikMusicStateHarmonyFlat, pos);
    if (idx === -1) return null;
    return nikMusicStateTransposeChordIfNeeded(nikMusicStateHarmonyFlat[idx].chord);
}

function nikMusicStateNextChord() {
    var pos = nikMusicStateCurrentPos();
    if (!pos) return null;
    var idx = nikMusicStateFindIndexAtOrBefore(nikMusicStateHarmonyFlat, pos);
    var nextIdx = idx + 1;
    if (nextIdx >= nikMusicStateHarmonyFlat.length) return null;
    return nikMusicStateTransposeChordIfNeeded(nikMusicStateHarmonyFlat[nextIdx].chord);
}

// Ventana de acordes alrededor del vigente -- base del prompter (pasado/
// futuro, sin límite fijo de 1 hacia atrás/adelante). lookBack/lookForward
// en cantidad de EVENTOS, no de tiempo.
function nikMusicStateChordWindow(lookBack, lookForward) {
    var pos = nikMusicStateCurrentPos();
    if (!pos || nikMusicStateHarmonyFlat.length === 0) return [];
    var idx = nikMusicStateFindIndexAtOrBefore(nikMusicStateHarmonyFlat, pos);
    var start = Math.max(0, idx - lookBack);
    var end = Math.min(nikMusicStateHarmonyFlat.length - 1, idx + lookForward);
    var win = [];
    for (var i = start; i <= end; i++) {
        var ev = nikMusicStateHarmonyFlat[i];
        win.push({
            bar: ev.bar,
            qn_offset: ev.qn_offset,
            chord: nikMusicStateTransposeChordIfNeeded(ev.chord),
            isCurrent: (i === idx)
        });
    }
    return win;
}

// --- Consultas de indicaciones por rol ---

// roleFilter: string de rol, o null/undefined para no filtrar (devuelve
// todas las cues activas). "todos" en cue.roles siempre matchea, sin
// importar roleFilter -- es el reservado (IMPL 11.1), no necesita estar
// en project_roles.
function nikMusicStateActiveCues(roleFilter) {
    var pos = nikMusicStateCurrentPos();
    if (!pos) return [];
    var currentAbsQn = nikMusicStateBarStartQn(pos.bar) + pos.qn_offset;
    var active = [];
    for (var i = 0; i < nikMusicStateCuesFlat.length; i++) {
        var cue = nikMusicStateCuesFlat[i];
        var startAbsQn = nikMusicStateBarStartQn(cue.bar) + cue.qn_offset;
        var endAbsQn = startAbsQn + (cue.duration_qn || 0);
        if (currentAbsQn < startAbsQn || currentAbsQn >= endAbsQn) continue;
        if (!roleFilter || cue.roles.indexOf(roleFilter) !== -1 || cue.roles.indexOf("todos") !== -1) {
            active.push(cue);
        }
    }
    return active;
}

// --- Trigger del one-shot (mismo criterio que nikPlayrateRequestTempoMap) ---
// TODO: confirmar el nombre real de NIK_LUA_COMMANDS.<key>.commandId una
// vez que se registre Nik_MusicState_PublishAll.lua en el Action List y
// se agregue a config.js/config.local.js -- "musicStatePublishAll" es un
// nombre propuesto, no confirmado contra el archivo real.
function nikMusicStateRequestAll() {
    wwr_req(NIK_LUA_COMMANDS.musicStatePublishAll.commandId +
        ";GET/EXTSTATE/NikMusicState/harmony_data" +
        ";GET/EXTSTATE/NikMusicState/project_key" +
        ";GET/EXTSTATE/NikMusicState/project_roles" +
        ";GET/EXTSTATE/NikMusicState/cues_data");
}