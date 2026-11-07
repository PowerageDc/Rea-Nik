-- Transposición de tonalidad y acordes. Puro cálculo, sin API de REAPER.
-- Misma lógica y mismas tablas que core/music-transpose.js: si una cambia,
-- cambia la otra.

local M = {}

local SHARP_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local FLAT_NAMES  = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }

-- Por pitch class (0 = C ... 11 = B, indexado desde 1): ¿la tonalidad que cae en
-- esa posición se escribe con sostenidos? Los empates enarmónicos reales
-- (F#/Gb mayor, D#/Eb menor) están resueltos a mano hacia la grafía más común.
local MAJOR_USES_SHARPS = { true, false, true, false, true, false, true, true, false, true, false, true }
local MINOR_USES_SHARPS = { false, true, false, false, true, false, true, false, true, true, false, true }

-- Nombres reconocidos como entrada (incluye grafías teóricas raras: B#, Cb, E#, Fb).
-- La salida siempre sale de SHARP_NAMES o FLAT_NAMES.
local NOTE_NAME_TO_PC = {
    ["C"] = 0, ["B#"] = 0,
    ["C#"] = 1, ["Db"] = 1,
    ["D"] = 2,
    ["D#"] = 3, ["Eb"] = 3,
    ["E"] = 4, ["Fb"] = 4,
    ["E#"] = 5, ["F"] = 5,
    ["F#"] = 6, ["Gb"] = 6,
    ["G"] = 7,
    ["G#"] = 8, ["Ab"] = 8,
    ["A"] = 9,
    ["A#"] = 10, ["Bb"] = 10,
    ["B"] = 11, ["Cb"] = 11,
}

-- Transpone una nota suelta (fundamental o bajo). Un nombre no reconocido
-- vuelve intacto. `semitones` debe ser entero.
function M.note(name, semitones, use_sharps)
    local pc = NOTE_NAME_TO_PC[name]
    if pc == nil then return name end
    local new_pc = (pc + semitones) % 12
    local names = use_sharps and SHARP_NAMES or FLAT_NAMES
    return names[new_pc + 1]
end

-- Tonalidad resultante y grafía a usar en toda la transposición.
-- Con una tónica no reconocida devuelve la tónica intacta y use_sharps = true.
function M.key(tonic, mode, semitones)
    local pc = NOTE_NAME_TO_PC[tonic]
    if pc == nil then
        return { tonic = tonic, mode = mode, use_sharps = true }
    end
    local new_pc = (pc + semitones) % 12
    local uses = (mode == "minor") and MINOR_USES_SHARPS or MAJOR_USES_SHARPS
    local use_sharps = uses[new_pc + 1]
    local names = use_sharps and SHARP_NAMES or FLAT_NAMES
    return { tonic = names[new_pc + 1], mode = mode, use_sharps = use_sharps }
end

-- Transpone un acorde: raíz + calidad intacta + bajo opcional tras "/".
-- Un formato no reconocido vuelve intacto.
function M.chord(chord, semitones, use_sharps)
    local letter, rest = chord:match("^([A-G])(.*)$")
    if not letter then return chord end

    local accidental = rest:match("^[#b]") or ""
    rest = rest:sub(#accidental + 1)

    local quality, bass = rest, nil
    local slash = rest:find("/", 1, true)
    if slash then
        quality = rest:sub(1, slash - 1)
        local b_letter, b_acc = rest:sub(slash + 1):match("^([A-G])([#b]?)$")
        if not b_letter then return chord end
        bass = b_letter .. b_acc
    end

    local result = M.note(letter .. accidental, semitones, use_sharps) .. quality
    if bass then
        result = result .. "/" .. M.note(bass, semitones, use_sharps)
    end
    return result
end

return M