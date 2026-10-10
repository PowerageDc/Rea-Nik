// monitor.js — capa de datos de la UI de Monitor Mix
//
// Solo estado y pedidos, sin DOM (el bootstrap y el render llegan con la
// UI, ver monitor_mix.md). Los ganchos de ms-dispatch.js llaman acá con
// guard typeof: las UIs que no cargan este archivo no cambian.
//
// Requiere, ya cargados antes: main.js (wwr_req), config.js
// (NIK_LUA_COMMANDS.monitorMixPublish) y musicstate-ui/shared/ms-dispatch.js.

var nikMmList = null;                 // {status, bus, pair, tracks:[{track, guid, name, role, send}]} | null
var nikMmListRevision = 0;            // +1 cuando cambia el contenido de la lista: la UI re-renderiza solo si cambió
var nikMmListRaw = null;              // último texto crudo recibido (para no contar lecturas idénticas)
var nikMmLastKnownListVersion = null; // último list_version visto EN EL PROYECTO ACTIVO
var nikMmSendState = {};              // "track:send" -> {muted, vol (lineal), pan, dest}

var nikMmLiveReq = null;              // string del GET recurrente de sends activo (para cancelarlo)
var NIK_MM_LIVE_MS = 200;

// GET/TRACK/<t>/SEND/<s> encadenado de toda la lista; null si no hay lista
// usable (sin lista, status distinto de ok o sin tracks).
function nikMmLiveRequestString() {
    if (!nikMmList || nikMmList.status !== "ok" || !nikMmList.tracks.length) return null;
    var parts = [];
    for (var i = 0; i < nikMmList.tracks.length; i++) {
        var t = nikMmList.tracks[i];
        parts.push("GET/TRACK/" + t.track + "/SEND/" + t.send);
    }
    return parts.join(";");
}

// Cancela el recurrente viejo y registra el nuevo solo si el string cambió.
// Al cambiar se descartan los valores: los índices nuevos pueden apuntar a
// otros sends.
function nikMmRearmLive() {
    var next = nikMmLiveRequestString();
    if (next === nikMmLiveReq) return;
    if (nikMmLiveReq !== null) wwr_req_recur_cancel(nikMmLiveReq);
    nikMmLiveReq = next;
    nikMmSendState = {};
    if (next !== null) wwr_req_recur(next, NIK_MM_LIVE_MS);
}

// Des-escapa las barras que duplica el web control (data_model §3) antes
// del JSON.parse. Vacío, null, JSON inválido o sin tracks deja el estado en null.
function nikMmSetList(val) {
    var raw = (typeof val === "string") ? val.replace(/\\\\/g, "\\") : val;
    var key = raw || "";
    if (key === nikMmListRaw) return;
    nikMmListRaw = key;
    var parsed = null;
    if (raw) {
        try {
            parsed = JSON.parse(raw);
        } catch (e) {
            console.warn("[monitor] list inválida:", e);
        }
    }
    if (parsed && !Array.isArray(parsed.tracks)) parsed = null;
    nikMmList = parsed;
    nikMmListRevision++;
    nikMmRearmLive();
}

// Llamado por ms-dispatch.js para cada EXTSTATE de NikMonitorMix. Un cambio
// de list_version solo dispara un GET (nunca el script): cada ejecución del
// publish incrementa la versión y esto haría un bucle.
function nikMmOnExtState(key, val) {
    if (key === "list") {
        nikMmSetList(val);
    } else if (key === "list_version") {
        var parsed = parseInt(val, 10);
        var v = isNaN(parsed) ? null : parsed;
        if (v !== nikMmLastKnownListVersion) {
            nikMmLastKnownListVersion = v;
            nikMmFetchList();
        }
    }
}

// Líneas del feed nativo que ms-dispatch.js no reconoce. Formato de SEND:
// SEND <track> <idx> <flags> <vol lineal> <pan> <track destino>
// (mute = flags & 8, máscara; destino -1 = hardware).
function nikMmOnLine(tok) {
    if (tok[0] !== "SEND" || tok.length < 7) return;
    var flags = parseInt(tok[3], 10) || 0;
    nikMmSendState[tok[1] + ":" + tok[2]] = {
        muted: (flags & 8) !== 0,
        vol: parseFloat(tok[4]),
        pan: parseFloat(tok[5]),
        dest: parseInt(tok[6], 10)
    };
}

// DISPARA el script (incrementa list_version): usar solo al conectar, al
// cambiar de proyecto y desde el botón Actualizar. Con guard: un
// config.local.js viejo sin esta key no debe romper a quien llama.
function nikMmRequestList() {
    var cmd = NIK_LUA_COMMANDS.monitorMixPublish;
    if (!cmd || !cmd.commandId) {
        console.warn("[monitor] monitorMixPublish sin commandId (config.local.js desactualizado?)");
        return;
    }
    wwr_req(cmd.commandId +
        ";GET/EXTSTATE/NikMonitorMix/list" +
        ";GET/EXTSTATE/NikMonitorMix/list_version");
}

// Escritura de volumen de send: LINEAL (verificado: VOL/0.5 y el GET devuelve
// vol 0.5), 4 decimales. final=true agrega "e" (fin de captura, como
// faders.js al soltar).
function nikMmSetSendVol(track, send, db, final) {
    var lin = Math.round(Math.pow(10, db / 20) * 10000) / 10000;
    wwr_req("SET/TRACK/" + track + "/SEND/" + send + "/VOL/" + lin + (final ? "e" : ""));
}

// Alterna el mute del send (el feed informa el estado resultante).
function nikMmToggleSendMute(track, send) {
    wwr_req("SET/TRACK/" + track + "/SEND/" + send + "/MUTE/-1");
}

// Solo lectura, sin disparar el script.
function nikMmFetchList() {
    wwr_req("GET/EXTSTATE/NikMonitorMix/list");
}

// Llamado por nikMsResetProjectState() al cambiar de proyecto.
function nikMmReset() {
    nikMmSetList(null);
    nikMmSendState = {};
    nikMmLastKnownListVersion = null;
}