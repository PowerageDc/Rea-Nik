-- Sonda del módulo de transposición: asserts con casos conocidos.
-- Salida a la consola de REAPER (o a stdout si se corre con un Lua suelto).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local T = dofile(script_dir .. "../_Shared/MusicTranspose_common_logic.lua")

local function out(msg)
    if reaper then reaper.ShowConsoleMsg(msg .. "\n") else print(msg) end
end

local passed, failed = 0, 0
local function check(name, got, expected)
    if got == expected then
        passed = passed + 1
    else
        failed = failed + 1
        out(("FALLA %s\n  esperado: %s\n  obtenido: %s"):format(name, tostring(expected), tostring(got)))
    end
end

-- Notas
check("nota con bemoles",     T.note("C", 1, false),  "Db")
check("nota con sostenidos",  T.note("C", 1, true),   "C#")
check("nota hacia abajo",     T.note("C", -1, false), "B")
check("nota hacia abajo -2",  T.note("C", -2, false), "Bb")
check("grafía de entrada",    T.note("Db", 2, true),  "D#")
check("nota no reconocida",   T.note("X", 2, true),   "X")

-- Acordes
check("slash",                T.chord("C/E", 1, false),    "Db/F")
check("calidad intacta",      T.chord("Fm7", 2, true),     "Gm7")
check("bemol de entrada",     T.chord("Bb", 2, false),     "C")
check("calidad y bajo",       T.chord("Dm7/G", 2, true),   "Em7/A")
check("alteración intacta",   T.chord("G7b9", 2, true),    "A7b9")
check("slash con bemoles",    T.chord("Ab/Eb", 2, false),  "Bb/F")
check("no reconocido",        T.chord("N.C.", 2, true),    "N.C.")
check("doble slash",          T.chord("C/E/G", 2, true),   "C/E/G")
check("bajo inválido",        T.chord("C/x", 2, true),     "C/x")
check("vacío",                T.chord("", 2, true),        "")

-- Tonalidades y grafía resultante
local k = T.key("F#", "major", 0)
check("F# mayor: sostenidos", k.use_sharps, true)
check("F# mayor: tónica",     k.tonic,      "F#")
k = T.key("Ab", "major", 2)
check("Ab+2: bemoles",        k.use_sharps, false)
check("Ab+2: tónica",         k.tonic,      "Bb")
k = T.key("Ab", "major", -1)
check("Ab-1: sostenidos",     k.use_sharps, true)
check("Ab-1: tónica",         k.tonic,      "G")
k = T.key("C", "major", 6)
check("empate F# mayor",      k.tonic,      "F#")
k = T.key("C", "minor", 3)
check("empate Eb menor",      k.tonic,      "Eb")
k = T.key("C#", "major", 0)
check("C# mayor se reescribe", k.tonic,     "Db")
k = T.key("?", "major", 3)
check("tónica no reconocida", k.tonic,      "?")
check("tónica no reconocida: sostenidos", k.use_sharps, true)

out(("MusicTranspose probe: %d ok, %d fallas"):format(passed, failed))