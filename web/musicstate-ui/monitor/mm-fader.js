// mm-fader.js — curva y conversiones del fader de Monitor Mix
//
// Puro cálculo, sin estado ni DOM (patrón de objeto único, ver
// 01_CONVENCIONES.md). Curva por tramos lineales en dB entre POINTS;
// posición del slider 0..1 <-> dB. Tope 0 dB, piso -60 dB.

var nikMmFader = {
    DB_MIN: -60,
    DB_MAX: 0,
    STEP_DB: 0.5,

    // [posición del slider 0..1, dB]; ascendentes en ambos ejes
    POINTS: [[0, -60], [0.25, -40], [0.5, -24], [0.75, -12], [1, 0]],

    // Volumen lineal del feed -> dB. 0 (o inválido) = piso. Por encima de
    // 0 dB (ganancia > 1) se muestra el tope: la UI no representa ganancia.
    volToDb: function (vol) {
        if (!(vol > 0)) return nikMmFader.DB_MIN;
        var db = 20 * Math.log(vol) / Math.LN10;
        return Math.max(nikMmFader.DB_MIN, Math.min(nikMmFader.DB_MAX, db));
    },

    // Redondea a pasos de STEP_DB (así no se mandan valores redundantes)
    snapDb: function (db) {
        var s = Math.round(db / nikMmFader.STEP_DB) * nikMmFader.STEP_DB;
        return s || 0; // evita -0
    },

    dbToPos: function (db) {
        var P = nikMmFader.POINTS;
        var d = Math.max(nikMmFader.DB_MIN, Math.min(nikMmFader.DB_MAX, db));
        for (var i = 1; i < P.length; i++) {
            if (d <= P[i][1]) {
                var t = (d - P[i - 1][1]) / (P[i][1] - P[i - 1][1]);
                return P[i - 1][0] + t * (P[i][0] - P[i - 1][0]);
            }
        }
        return 1;
    },

    posToDb: function (pos) {
        var P = nikMmFader.POINTS;
        var p = Math.max(0, Math.min(1, pos));
        for (var i = 1; i < P.length; i++) {
            if (p <= P[i][0]) {
                var t = (p - P[i - 1][0]) / (P[i][0] - P[i - 1][0]);
                return P[i - 1][1] + t * (P[i][1] - P[i - 1][1]);
            }
        }
        return nikMmFader.DB_MAX;
    },

    DEFAULT_DB: -12,   // respaldo; el valor real llega como default_db en la lista (2c-2)
    POS_MAX: 1000,     // resolución del <input type="range"> (0..POS_MAX)

    dbToSlider: function (db) {
        return Math.round(nikMmFader.dbToPos(db) * nikMmFader.POS_MAX);
    },

    sliderToDb: function (v) {
        return nikMmFader.posToDb(Number(v) / nikMmFader.POS_MAX);
    },

    // Atajo: posición del slider -> dB ya redondeado, listo para el SET
    posToSetDb: function (pos) {
        return nikMmFader.snapDb(nikMmFader.posToDb(pos));
    },

    // Texto para mostrar junto al fader
    dbLabel: function (db) {
        return nikMmFader.snapDb(db).toFixed(1) + " dB";
    }
};