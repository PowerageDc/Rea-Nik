local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local cfg = dofile(script_dir .. "../GainRide/GainRide_config.lua")

local STEPS = 10
local SPAN = 10
local DB_END = -12
local CASES = {
    { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 1 }, { 3, 0 }, { 4, 0 }, { 5, -1 }, { 5, 0 }, { 5, 1 },
}

local function log(fmt, ...)
    reaper.ShowConsoleMsg(string.format(fmt, ...) .. "\n")
end

local function to_db(a)
    if a <= 0 then return -150 end
    return 20 * math.log(a, 10)
end

reaper.ClearConsole()

local tr = reaper.GetSelectedTrack(0, 0)
if not tr then
    log("Seleccioná un track que tenga el envelope '%s'.", cfg.apply.envelope)
    return
end
local env = reaper.GetTrackEnvelopeByName(tr, cfg.apply.envelope)
if not env then
    log("El track no tiene el envelope '%s'.", cfg.apply.envelope)
    return
end

local scaling = reaper.GetEnvelopeScalingMode(env)
local raw_a = reaper.ScaleToEnvelopeMode(scaling, 1)
local raw_b = reaper.ScaleToEnvelopeMode(scaling, 10 ^ (DB_END / 20))
local t0 = reaper.GetProjectLength(0) + 1000
local t1 = t0 + SPAN

log("Sonda de formas | escalado=%d | 0 dB -> %.4f | %d dB -> %.4f", scaling, raw_a, DB_END, raw_b)

reaper.Undo_BeginBlock()
for _, c in ipairs(CASES) do
    reaper.DeleteEnvelopePointRangeEx(env, -1, t0 - 1, t1 + 1)
    reaper.InsertEnvelopePointEx(env, -1, t0, raw_a, c[1], c[2], false, true)
    reaper.InsertEnvelopePointEx(env, -1, t1, raw_b, 0, 0, false, true)
    reaper.Envelope_SortPointsEx(env, -1)

    local fr, fd, fa = {}, {}, {}
    local v_first, v_last
    for k = 0, STEPS do
        local _, v = reaper.Envelope_Evaluate(env, t0 + SPAN * k / STEPS, 44100, 1)
        if k == 0 then v_first = v end
        if k == STEPS then v_last = v end
        fr[#fr + 1] = string.format("%.2f", (v - raw_a) / (raw_b - raw_a))
        fd[#fd + 1] = string.format("%.2f", to_db(reaper.ScaleFromEnvelopeMode(scaling, v)) / DB_END)
        fa[#fa + 1] = string.format("%.2f", to_db(v) / DB_END)
    end
    log("")
    log("forma %d tension %+d | v(0)=%.4f v(1)=%.4f", c[1], c[2], v_first, v_last)
    log("  fraccion en el valor del envelope : %s", table.concat(fr, " "))
    log("  fraccion en dB (valor escalado)   : %s", table.concat(fd, " "))
    log("  fraccion en dB (valor = amplitud) : %s", table.concat(fa, " "))
end
reaper.DeleteEnvelopePointRangeEx(env, -1, t0 - 1, t1 + 1)
reaper.PreventUIRefresh(0)
reaper.Undo_EndBlock("GainRide: sonda de formas de rampa", -1)