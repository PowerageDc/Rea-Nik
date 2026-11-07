-- Sonda de la lógica pura de SubtitleExport: asserts con datos falsos.
-- Salida a la consola de REAPER (o a stdout si se corre con un Lua suelto).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Logic  = dofile(script_dir .. "../SubtitleExport/SubtitleExport_common_logic.lua")
local Config = dofile(script_dir .. "../SubtitleExport/SubtitleExport_config.lua")
local Transpose = dofile(script_dir .. "../_Shared/MusicTranspose_common_logic.lua")

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

-- Formato de acordes
local function fmt(chord) return Logic.formatChord(chord, Config.chord_rules) end
check("raíz+número",        fmt("F7"),     "F 7")
check("bemol",              fmt("Bb"),     "B♭")
check("bemol+número",       fmt("Bb7"),    "B♭ 7")
check("alteración",         fmt("G7b9"),   "G 7♭9")
check("sostenido",          fmt("C#m"),    "C♯m")
check("sin espacio en Cmaj7", fmt("Cmaj7"), "Cmaj7")
check("menor con número",   fmt("Dm7"),    "Dm7")
check("slash",              fmt("C/G"),    "C / G")
check("slash con bemol",    fmt("Gm/Bb"),  "Gm / B♭")
check("slash ya espaciado", fmt("C / G"),  "C / G")
check("silencio nil",       fmt(nil),      nil)
check("silencio vacío",     fmt("  "),     nil)

-- Reproduce las primeras entradas del SRT hecho a mano (t0 = 10 para probar el offset)
local opts = { rules = Config.chord_rules, gap_ms = Config.gap_ms, carry_in = false }
local events = {
    { t = 12.788, chord = "F" },
    { t = 19.897, chord = "C/G" },
    { t = 22.268, chord = "Gm/Bb" },
    { t = 24.680, chord = "C/G" },
}
local e = Logic.buildEntries(events, 10, 29.407, opts)
check("cantidad", #e, 4)
local expected = {
    { "00:00:02,788", "00:00:09,887", "F" },
    { "00:00:09,897", "00:00:12,258", "C / G" },
    { "00:00:12,268", "00:00:14,670", "Gm / B♭" },
    { "00:00:14,680", "00:00:19,407", "C / G" },
}
for i, x in ipairs(expected) do
    check("entrada " .. i .. " inicio", Logic.srtTime(e[i].start), x[1])
    check("entrada " .. i .. " fin",    Logic.srtTime(e[i].stop),  x[2])
    check("entrada " .. i .. " texto",  e[i].text,                 x[3])
end

-- Silencio explícito: no genera subtítulo y corta el acorde anterior
local sil = Logic.buildEntries({
    { t = 0, chord = "F" }, { t = 4 }, { t = 6, chord = "G" },
}, 0, 8, opts)
check("silencio: cantidad", #sil, 2)
check("silencio: fin de F", Logic.srtTime(sil[1].stop), "00:00:03,990")
check("silencio: G hasta el final", Logic.srtTime(sil[2].stop), "00:00:08,000")

-- Recorte de ventana y carry_in
local win = {
    { t = 2, chord = "C" }, { t = 6, chord = "D" }, { t = 10, chord = "E" },
}
local a = Logic.buildEntries(win, 5, 10, { rules = Config.chord_rules, gap_ms = 10, carry_in = false })
check("sin carry_in: cantidad", #a, 1)
check("sin carry_in: inicio de D", Logic.srtTime(a[1].start), "00:00:01,000")
local b = Logic.buildEntries(win, 5, 10, { rules = Config.chord_rules, gap_ms = 10, carry_in = true })
check("con carry_in: cantidad", #b, 2)
check("con carry_in: C desde t0", Logic.srtTime(b[1].start), "00:00:00,000")
check("con carry_in: fin de C", Logic.srtTime(b[1].stop), "00:00:00,990")
check("evento en t_end ignorado", b[#b].text, "D")

-- Transposición: se aplica antes del formato de display
local up2 = Logic.buildEntries({ { t = 0, chord = "Ab/Eb" } }, 0, 4, {
    rules = Config.chord_rules, gap_ms = 10, carry_in = false,
    transpose = function(c) return Transpose.chord(c, 2, false) end,
})
check("transpone y luego formatea", up2[1].text, "B♭ / F")

-- Desfase de video: se suma a todos los tiempos
local off = Logic.buildEntries({ { t = 10, chord = "F" } }, 10, 20,
    { rules = Config.chord_rules, gap_ms = 10, offset_s = 1 })
check("desfase: inicio", Logic.srtTime(off[1].start), "00:00:01,000")
check("desfase: fin", Logic.srtTime(off[1].stop), "00:00:11,000")

-- Serialización SRT
local srt = Logic.toSrt({ { start = 2.788, stop = 9.887, text = "F" } }, { newline = "\n", bom = false })
check("srt", srt, "1\n00:00:02,788 --> 00:00:09,887\nF\n\n")
check("srt con BOM", Logic.toSrt({}, { bom = true }), "\239\187\191")

-- Parsers de harmony_data, project_key y semitonos
local ph = Logic.parseHarmony('{"3":[{"qn_offset":0,"chord":"Fm"}],"12":[{"qn_offset":0.0,"chord":"Cmaj7"},{"qn_offset":3.75,"chord":null}]}')
check("parse: cantidad", #ph, 3)
check("parse: compás", ph[1].measure, 3)
check("parse: acorde", ph[1].chord, "Fm")
check("parse: offset", ph[3].qn_offset, 3.75)
check("parse: null es silencio", ph[3].chord, nil)
check("parse: vacío", #Logic.parseHarmony(""), 0)

local pk = Logic.parseKey('{"tonic":"Ab","mode":"major"}')
check("key: tónica", pk.tonic, "Ab")
check("key: modo", pk.mode, "major")
check("key: incompleta", Logic.parseKey('{"tonic":"Ab"}'), nil)

local k1, n1 = Logic.parseSemitones("2.00")
check("semitonos: tipo", k1, "value")
check("semitonos: 2.00", n1, 2)
local _, n2 = Logic.parseSemitones("-3.50")
check("semitonos: truncado hacia cero", n2, -3)
check("semitonos: none", (Logic.parseSemitones("none")), "none")
check("semitonos: mixed", (Logic.parseSemitones("mixed")), "mixed")
check("semitonos: inválido", (Logic.parseSemitones("abc")), "invalid")

out(("SubtitleExport probe: %d ok, %d fallas"):format(passed, failed))