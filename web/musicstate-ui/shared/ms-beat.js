// musicstate-ui/shared/ms-beat.js
// Conteo de pulsos por compás + distancia en beats hasta el próximo evento
// de armonía, para el indicador visual de §10 (musicstate_instrumentista.md).
// Puro cálculo sobre el estado ya cacheado en core/music-state.js (timesig
// map, harmony flat) -- sin estado propio, wrapper de objeto único
// (01_CONVENCIONES.md, "Patrón de módulos JS de puro cálculo").
//
// No decide CUÁNDO disparar una animación ni cachea el último pulso visto
// -- eso es responsabilidad del render loop en instrumentista.js (mismo
// criterio que ms-section.js con la sección: acá solo "dónde estoy",
// arriba se decide "cambió, actualizo DOM").

var nikBeat = {

    // Cantidad de pulsos a marcar por compás. Compuesto (den=8, num
    // múltiplo de 3, num>3): agrupa de a 3 corcheas -- 6/8->2, 12/8->4
    // (confirmado en sesión). Simple: un pulso por unidad del denominador
    // (asume den=4 hoy; no cubre den=2 ni den=8 no compuesto, ej. 3/8).
    pulsesInBar: function (num, den) {
        if (den === 8 && num > 3 && num % 3 === 0) return num / 3;
        return num;
    },

    // Duración en QN de un pulso, mismo criterio de compuesto.
    qnPerPulse: function (num, den) {
        if (den === 8 && num > 3 && num % 3 === 0) return 1.5; // negra con puntillo
        return 4 / den;
    },

    // Índice de pulso vigente (1-indexed) dentro de `bar`, dado el
    // qn_offset efectivo (mismo par que devuelve nikMusicStateCurrentPos).
    currentPulseIndex: function (bar, qnOffset) {
        var sig = nikMusicStateTimesigAt(bar);
        var qpp = this.qnPerPulse(sig.num, sig.den);
        var idx = Math.floor(qnOffset / qpp) + 1;
        var total = this.pulsesInBar(sig.num, sig.den);
        if (idx > total) idx = total; // borde: último instante del compás
        if (idx < 1) idx = 1;
        return idx;
    },

    // Cantidad de pulsos que entran en `bar` -- separado de
    // currentPulseIndex para no resolver el timesig dos veces desde afuera.
    pulseCountAt: function (bar) {
        var sig = nikMusicStateTimesigAt(bar);
        return this.pulsesInBar(sig.num, sig.den);
    },

    currentPos: function () {
        var parsed = nikMusicStateParseBarBeat(nikLastPositionBeatsStr);
        if (!parsed) return null;
        var bar = parsed.bar;
        var beats = parsed.beatIndex - 1 + parsed.hundredths / 100;

        if (nikMusicStateIsPlaying()) {
            var advanceSec = (this.LATENCY_SEC + nikMusicStateExtrapolatedSec()) * nikMusicStatePlayRate();
            if (advanceSec > 0) {
                var bpm = nikMsTempoAt(parseFloat(playPosSeconds));
                if (bpm != null && bpm > 0) {
                    beats += advanceSec * bpm / 60;
                    var sig = nikMusicStateTimesigAt(bar);
                    while (sig.num > 0 && beats >= sig.num) {
                        beats -= sig.num;
                        bar++;
                        sig = nikMusicStateTimesigAt(bar);
                    }
                }
            }
        }

        var finalSig = nikMusicStateTimesigAt(bar);
        return { bar: bar, qn_offset: beats * (4 / finalSig.den) };
    },

    // QN absolutos desde la posición efectiva actual hasta el próximo
    // evento de armonía. null si no hay posición o no hay próximo evento
    // cargado. No reusa nikMusicStateNextChord porque esa función solo
    // devuelve el chord, no la posición del evento.
    qnUntilNextChordEvent: function () {
        var pos = nikMusicStateCurrentPos();
        if (!pos || nikMusicStateHarmonyFlat.length === 0) return null;
        var idx = nikMusicStateFindIndexAtOrBefore(nikMusicStateHarmonyFlat, pos);
        var nextIdx = idx + 1;
        if (nextIdx >= nikMusicStateHarmonyFlat.length) return null;
        var next = nikMusicStateHarmonyFlat[nextIdx];
        var curAbsQn = nikMusicStateBarStartQn(pos.bar) + pos.qn_offset;
        var nextAbsQn = nikMusicStateBarStartQn(next.bar) + next.qn_offset;
        return Math.max(0, nextAbsQn - curAbsQn);
    },

    // Segundos hasta el próximo evento de armonía, al BPM/playrate
    // vigentes en este instante. Se llama UNA VEZ al cruzar el evento
    // anterior (mismo criterio anti-tirón que la tira de acordes, §10) --
    // instrumentista.js no debe llamarla en cada render.
    secUntilNextChordEvent: function () {
        var qn = this.qnUntilNextChordEvent();
        if (qn === null) return null;
        var bpm = (typeof nikMsTempoAt === "function") ? nikMsTempoAt(parseFloat(playPosSeconds)) : null;
        if (!bpm || bpm <= 0) return null;
        return (qn * 60 / bpm) / nikMusicStatePlayRate();
    }
};