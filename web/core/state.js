// core/state.js — consolida el estado global desperdigado en el shell.
// No es optimización de performance, es documentación viva: un solo lugar
// para ver qué estado global existe (ver MODULARIZACION_CONTROL_REMOTO.md).
// Debe cargar antes que cualquier script que lo use (config.js/core/utils.js/
// markers/markers.js no dependen de esto, pero el resto del shell sí).

// --- Transporte / posición / firma de compás ---
var last_transport_state = -1, mouseDown = 0, last_time_str = "",
    last_metronome = false, nTrack = 0, last_repeat = false,
    nikLastProjectNameUpdate = Date.now(),
    drawnSig = 0, drawnBeat = 0, ts_numerator = 0, ts_denominator = 0, playPosSeconds = 0, statusPosition = [], statusPositionAr = [],
    startX = 0, joggerAgg = 0, recarmCountAr = [], recarmCount = 0, newPos = -1,
    trackHeightsAr = [], trackColoursAr = [], trackNumbersAr = [], trackNamesAr = [], trackVolumeAr = [],
    trackFlagsAr = [], trackSendCntAr = [], trackRcvCntAr = [], trackHwOutCntAr = [], trackSendHwCntAr = [], trackPeakAr = [], trackMeterAr = [], faderConAr = [],
    hereCss = document.styleSheets[1], transitions = 1;

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