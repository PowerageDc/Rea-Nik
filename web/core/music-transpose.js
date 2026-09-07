// core/music-transpose.js — transposición de tonalidad y acordes para la
// feature MusicState (ver IMPL_MusicState.md, secciones 10.x). Puro
// cálculo, sin estado propio y sin dependencia de DOM — el delta de
// semitonos vive en nikReaPitchLastSemitone (core/state.js), lo lee quien
// consuma este módulo, no este archivo.
//
// Patrón: wrapper de objeto único (ver 01_CONVENCIONES.md, "Patrón de
// módulos JS de puro cálculo") — primer caso de este patrón en el
// proyecto.
//
// Debe cargar antes que cualquier consumidor (core/music-state.js,
// todavía no existe — ver IMPL_MusicState.md sección 8.1).

var SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
var FLAT_NAMES  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];

// Círculo de quintas: por posición cromática (pc 0=C ... 11=B), ¿la
// tonalidad resultante en ESA posición se escribe tradicionalmente con
// sostenidos o con bemoles? Dos casos son empate enarmónico real
// (F#/Gb mayor, D#/Eb menor) — resueltos a mano hacia la grafía más común
// en la práctica, no derivados matemáticamente. Ver IMPL_MusicState.md
// sección 10.4.
var MAJOR_USES_SHARPS = [true, false, true, false, true, false, true, true, false, true, false, true];
// pc:                     C     Db    D     Eb    E     F     F#*   G     Ab    A     Bb    B
// * F# elegido a mano sobre Gb (empate enarmónico)

var MINOR_USES_SHARPS = [false, true, false, false, true, false, true, false, true, true, false, true];
// pc:                     C     C#    D     Eb*   E     F     F#    G     G#    A     Bb    B
// * Eb elegido a mano sobre D# (empate enarmónico)

// Nombres de nota reconocidos → pitch class. Incluye algunas grafías
// teóricas poco comunes (B#, Cb, E#, Fb) por robustez, aunque el dominio
// del proyecto son tonalidades mayores/menores comunes ("nada raro").
var NOTE_NAME_TO_PC = {
    "C": 0, "B#": 0,
    "C#": 1, "Db": 1,
    "D": 2,
    "D#": 3, "Eb": 3,
    "E": 4, "Fb": 4,
    "E#": 5, "F": 5,
    "F#": 6, "Gb": 6,
    "G": 7,
    "G#": 8, "Ab": 8,
    "A": 9,
    "A#": 10, "Bb": 10,
    "B": 11, "Cb": 11
};

// Acorde: raíz (A-G + accidental opcional #/b) + resto (calidad/tensiones,
// intacto) + bajo opcional tras "/" (misma forma que la raíz).
var CHORD_REGEX = /^([A-G])([#b]?)([^\/]*)(?:\/([A-G])([#b]?))?$/;

function nikTransposeMod12(n) {
    return ((n % 12) + 12) % 12;
}

var nikTranspose = {

    // Pitch class (0-11) de un nombre de nota, o null si no se reconoce.
    _noteNameToPc: function(noteName) {
        if (NOTE_NAME_TO_PC.hasOwnProperty(noteName)) return NOTE_NAME_TO_PC[noteName];
        return null;
    },

    // "sharps" | "flats" para una tonalidad dada (sin transponer).
    getKeySpelling: function(tonicName, mode) {
        var pc = this._noteNameToPc(tonicName);
        if (pc === null) return "sharps";
        var table = (mode === "minor") ? MINOR_USES_SHARPS : MAJOR_USES_SHARPS;
        return table[pc] ? "sharps" : "flats";
    },

    // Transpone una nota suelta (fundamental o bajo, sin calidad).
    // useSharps ya viene decidido por nikTranspose.key() para toda la
    // transposición — no se recalcula por nota.
    note: function(noteName, semitones, useSharps) {
        var pc = this._noteNameToPc(noteName);
        if (pc === null) return noteName; // no reconocida: se devuelve intacta
        var newPc = nikTransposeMod12(pc + semitones);
        return useSharps ? SHARP_NAMES[newPc] : FLAT_NAMES[newPc];
    },

    // Tonalidad resultante + grafía a usar para TODA la transposición
    // (uniforme — ver IMPL_MusicState.md 10.4).
    key: function(tonicName, mode, semitones) {
        var pc = this._noteNameToPc(tonicName);
        if (pc === null) return { tonic: tonicName, mode: mode, useSharps: true };
        var newPc = nikTransposeMod12(pc + semitones);
        var table = (mode === "minor") ? MINOR_USES_SHARPS : MAJOR_USES_SHARPS;
        var useSharps = table[newPc];
        var newTonic = useSharps ? SHARP_NAMES[newPc] : FLAT_NAMES[newPc];
        return { tonic: newTonic, mode: mode, useSharps: useSharps };
    },

    // Transpone un acorde completo (raíz + calidad intacta + bajo opcional).
    // useSharps: el mismo flag que devolvió nikTranspose.key() para esta
    // transposición — no se recalcula por acorde.
    chord: function(chordStr, semitones, useSharps) {
        var m = CHORD_REGEX.exec(chordStr);
        if (!m) return chordStr; // formato no reconocido: se devuelve intacto

        var rootName = m[1] + (m[2] || "");
        var quality = m[3] || "";
        var newRoot = this.note(rootName, semitones, useSharps);
        var result = newRoot + quality;

        if (m[4]) {
            var bassName = m[4] + (m[5] || "");
            var newBass = this.note(bassName, semitones, useSharps);
            result += "/" + newBass;
        }

        return result;
    }
};