local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiNav_config.lua")

local proj = 0
local tol = Config.measure.tolerance_sec
local eps = Config.measure.epsilon_sec

-- Devuelve inicio y fin (en segundos) del compás que contiene a `t`.
local function measure_bounds(t)
    local beats_in_measure, _, measure_len, fullbeats = reaper.TimeMap2_timeToBeats(proj, t)
    local start_beats = fullbeats - beats_in_measure
    local start_time = reaper.TimeMap2_beatsToTime(proj, start_beats)
    local end_time = reaper.TimeMap2_beatsToTime(proj, start_beats + measure_len)
    return start_time, end_time
end

local function compute_target(pos)
    local start_time, end_time = measure_bounds(pos)

    -- Cursor apenas antes del próximo compás: se lo trata como si ya estuviera en él.
    if end_time - pos <= tol then
        start_time = end_time
    end

    if pos - start_time > tol then
        return start_time
    end

    -- Ya está al inicio de su compás: ir al inicio del anterior.
    local prev_ref = start_time - eps
    if prev_ref < 0 then return nil end
    local prev_start = measure_bounds(prev_ref)
    return prev_start
end

local pos = reaper.GetCursorPosition()
local target = compute_target(pos)

if target and math.abs(target - pos) > eps then
    if Config.undo.enabled then reaper.Undo_BeginBlock() end
    reaper.SetEditCurPos(target, Config.move_view, Config.seek_play)
    if Config.undo.enabled then
        reaper.Undo_EndBlock("Move edit cursor to start of current/previous measure", -1)
    end
end