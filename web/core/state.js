// core/state.js — consolida el estado global desperdigado en el shell.
// No es optimización de performance, es documentación viva: un solo lugar
// para ver qué estado global existe (ver MODULARIZACION_CONTROL_REMOTO.md).
// Debe cargar antes que cualquier script que lo use (config.js/core/utils.js/
// markers/markers.js no dependen de esto, pero el resto del shell sí).

// --- Transporte / posición / firma de compás ---
var last_transport_state = -1, mouseDown = 0, last_time_str = "",
    last_metronome = false, last_soloinfront = false, nTrack = 0, last_repeat = false,
    nikLastProjectNameUpdate = Date.now(),
    drawnSig = 0, drawnBeat = 0, ts_numerator = 0, ts_denominator = 0, playPosSeconds = 0, statusPosition = [], statusPositionAr = [],
    startX = 0, joggerAgg = 0, recarmCountAr = [], recarmCount = 0, newPos = -1,
    trackHeightsAr = [], trackColoursAr = [], trackNumbersAr = [], trackNamesAr = [], trackVolumeAr = [],
    trackFlagsAr = [], trackSendCntAr = [], trackRcvCntAr = [], trackHwOutCntAr = [], trackSendHwCntAr = [], trackPeakAr = [], trackMeterAr = [], faderConAr = [],
    hereCss = null, transitions = 1;

// Hoja principal (styles.css): se busca por href en vez de por índice, para
// no depender del orden/cantidad de stylesheets cargadas antes que este script.
(function () {
    for (var i = 0; i < document.styleSheets.length; i++) {
        var h = document.styleSheets[i].href;
        if (h && h.indexOf("styles.css") !== -1) { hereCss = document.styleSheets[i]; break; }
    }
    if (!hereCss) console.warn("[state.js] No se encontró styles.css en document.styleSheets: calculateScale()/#options no van a funcionar.");
})();

// Modo de display de #status: "measures" | "minsec" — toggle sticky vía
// long tap (ver core/init.js / core/long-press.js). Independiente del
// ruler real del proyecto en REAPER.
var nikPositionDisplayMode = "measures";

// tok[5] cacheado crudo -sin importar modo de display- por wwr-dispatch.js 
// Consumido en cada tick por music-state.js
var nikLastPositionBeatsStr = "";

// --- ReaPitch / Playrate / markers (flags de estado runtime) ---
var nikReaPitchDragging = false;
var nikPlayrateDragging = false;
var nikPreservePitchServerState = null;
var nikReaPitchLastSemitone = null;
var nikReaPitchLastEnabled = null;
var nikMarkerBarsMap = {};

// --- Faders / sends ---
var volOutputdB = null;
var thisSendTrackId = 0, sendOutputdB = 0;
var faderLastTapAr = [];

// --- Panel de opciones / escala UI ---
var scaleFactor = 1, optionsOpen = 0;