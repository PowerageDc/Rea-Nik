// monitor.js — capa de datos de la UI de Monitor Mix
//
// Solo estado y pedidos, sin DOM (el bootstrap y el render llegan con la
// UI, ver monitor_mix.md). Los ganchos de ms-dispatch.js llaman acá con
// guard typeof: las UIs que no cargan este archivo no cambian.
//
// Requiere, ya cargados antes: main.js (wwr_req), config.js
// (NIK_LUA_COMMANDS.monitorMixPublish) y musicstate-ui/shared/ms-dispatch.js.

var nikMmList = null;                 // {status, bus, pair, tracks:[{track, guid, name, role, send}]} | null
var nikMmListRevision = 0;            // +1 en cada nikMmSetList: la UI re-renderiza solo si cambió
var nikMmLastKnownListVersion = null; // último list_version visto EN EL PROYECTO ACTIVO
var nikMmSendState = {};              // "track:send" -> {muted, vol (lineal), pan, dest}

// Des-escapa las barras que duplica el web control (data_model §3) antes
// del JSON.parse. Vacío, null, JSON inválido o sin tracks deja el estado en null.
function nikMmSetList(val) {
    var raw = (typeof val === "string") ? val.replace(/\\\\/g, "\\") : val;
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