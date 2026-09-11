// musicstate-ui/shared/ms-tempo.js
// Lookup de tempo puro, portado de modals/playrate/playrate.js
// (nikPlayrateTempoMap / nikPlayrateTempoAt / nikPlayrateSetTempoMap) --
// duplicación deliberada, no reuso (ver musicstate_instrumentista.md §2:
// playrate.js mezcla DOM del popup, esta UI no lo carga). Candidato a
// extraer a módulo compartido si playrate.js se refactoriza (deuda
// documentada, no bloqueante).
//
// Llamado desde ms-dispatch.js: nikMsTempoSetMap(tok[3]) al llegar
// EXTSTATE/NikRemote/tempo_map.
//
// Patrón: variables/funciones sueltas con prefijo (no wrapper de objeto
// único) -- mismo criterio que core/music-state.js, no el de
// core/music-transpose.js: este módulo tiene estado propio cacheado
// (nikMsTempoMap), no es puro cálculo sin memoria (01_CONVENCIONES.md).

var nikMsTempoMap = null; // array de {pos, bpm} ordenado por pos ascendente, o null

// "pos1:bpm1,pos2:bpm2,..." -> nikMsTempoMap. Mismo parseo que
// nikPlayrateSetTempoMap (playrate.js), sin el refresco de fader/readout
// del popup (no existe en esta UI).
function nikMsTempoSetMap(val) {
    var map = [];
    if (val) {
        var pairs = val.split(",");
        for (var i = 0; i < pairs.length; i++) {
            var kv = pairs[i].split(":");
            var pos = parseFloat(kv[0]);
            var bpm = parseFloat(kv[1]);
            if (!isNaN(pos) && !isNaN(bpm) && bpm > 0) map.push({ pos: pos, bpm: bpm });
        }
        map.sort(function (a, b) { return a.pos - b.pos; });
    }
    nikMsTempoMap = (map.length > 0) ? map : null;
}

// Bpm original vigente en una posición dada -- backward-lookup, sin
// interpolación (los cambios de tempo son saltos discretos). Si la
// posición es anterior al primer marker, usa el primero (mismo criterio
// que nikPlayrateTempoAt). null si todavía no hay mapa cargado.
function nikMsTempoAt(positionSeconds) {
    if (!nikMsTempoMap || nikMsTempoMap.length == 0) return null;
    var found = nikMsTempoMap[0].bpm;
    for (var i = 0; i < nikMsTempoMap.length; i++) {
        if (nikMsTempoMap[i].pos <= positionSeconds) found = nikMsTempoMap[i].bpm;
        else break;
    }
    return found;
}