local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Source = dofile(script_dir .. "GainRideSource_common_logic.lua")
local Analysis = dofile(script_dir .. "GainRideAnalysis_common_logic.lua")
local Segment = dofile(script_dir .. "GainRideSegment_common_logic.lua")
local Apply = dofile(script_dir .. "GainRideApply_common_logic.lua")
local cfg = dofile(script_dir .. "GainRide_config.lua")

local ap = cfg.apply

local function log(fmt, ...)
    reaper.ShowConsoleMsg(string.format(fmt, ...) .. "\n")
end

local segments, err = Source.resolve(ap.mode, cfg.merge_tolerance_ms / 1000)
if not segments then
    reaper.ShowMessageBox(err, "GainRide", 0)
    return
end

local opts = {
    window_s = cfg.window_ms / 1000,
    sample_rate = cfg.sample_rate,
    floor_db = cfg.floor_db,
    lf_hz = cfg.lf_hz,
}
local margin = math.max(ap.ramp_down_ms, ap.ramp_up_ms)
for _, cc in pairs(ap.classes) do
    margin = math.max(margin, cc.ramp_down_ms or 0, cc.ramp_up_ms or 0)
end
margin = margin / 1000

-- Las piezas de todos los tramos de un mismo track forman una sola secuencia,
-- para que las rampas entre tramos vecinos no se pisen.
local by_track, order = {}, {}
for _, seg in ipairs(segments) do
    local rows = Analysis.segment_levels(seg, opts)
    local pieces = Segment.split(rows, cfg.seg, cfg.window_ms)
    local entry = by_track[seg.track]
    if not entry then
        entry = { pieces = {}, ranges = {} }
        by_track[seg.track] = entry
        order[#order + 1] = seg.track
    end
    for _, pc in ipairs(pieces) do
        entry.pieces[#entry.pieces + 1] = pc
    end
    entry.ranges[#entry.ranges + 1] = { t0 = seg.t0 - margin, t1 = seg.t1 + margin }
end

local missing = {}

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for _, tr in ipairs(order) do
    local entry = by_track[tr]
    local name = Source.track_name(tr)
    if #entry.pieces > 0 then
        local env = reaper.GetTrackEnvelopeByName(tr, ap.envelope)
        if env then
            local pts, info = Apply.plan(entry.pieces, ap)
            Apply.write(env, pts, entry.ranges, ap)
            log("GainRide | track '%s' | piezas=%d | puntos=%d | objetivo %s dB | ganancia [%.1f, %+.1f] dB | topes: bajar %d, subir %d",
                name, #entry.pieces, #pts, info.target_text, info.g_min, info.g_max,
                info.capped_down, info.capped_up)
        else
            missing[#missing + 1] = name
        end
    else
        log("GainRide | track '%s' | sin piezas en la fuente", name)
    end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("GainRide: puntos de ganancia en el envelope", -1)

if #missing > 0 then
    reaper.ShowMessageBox(
        "No se encontró el envelope '" .. ap.envelope .. "' en: " .. table.concat(missing, ", ")
            .. ".\nMostralo en el track y volvé a correr el script.",
        "GainRide", 0)
end