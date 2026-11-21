local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Source = dofile(script_dir .. "../GainRide/GainRideSource_common_logic.lua")
local Analysis = dofile(script_dir .. "../GainRide/GainRideAnalysis_common_logic.lua")
local Segment = dofile(script_dir .. "../GainRide/GainRideSegment_common_logic.lua")
local cfg = dofile(script_dir .. "../GainRide/GainRide_config.lua")

local MAX_LINES = 40

local function log(fmt, ...)
    reaper.ShowConsoleMsg(string.format(fmt, ...) .. "\n")
end

local function fmt_t(t)
    return string.format("%02d:%06.3f", math.floor(t / 60), t % 60)
end

reaper.ClearConsole()

local segments, err = Source.resolve(cfg.probe_mode, cfg.merge_tolerance_ms / 1000)
if not segments then
    log("GainRide segmentación (%s): %s", cfg.probe_mode, err)
    return
end

local opts = {
    window_s = cfg.window_ms / 1000,
    sample_rate = cfg.sample_rate,
    floor_db = cfg.floor_db,
}

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
Segment.clear_regions(cfg.preview_prefix)

log("GainRide segmentación | modo=%s | tramos de fuente=%d", cfg.probe_mode, #segments)

local total = 0
for si, seg in ipairs(segments) do
    local rows = Analysis.segment_levels(seg, opts)
    local pieces = Segment.split(rows, cfg.seg, cfg.window_ms)

    log("")
    log("== Tramo %d | track '%s' | %s -> %s | piezas=%d",
        si, Source.track_name(seg.track), fmt_t(seg.t0), fmt_t(seg.t1), #pieces)

    for i, pc in ipairs(pieces) do
        if i <= MAX_LINES then
            log("   %03d  %s -> %s  %5.0f ms  %s  nivel %6.1f dB  pk %6.1f  hf %.2f  zc %5.0f Hz",
                total + i, fmt_t(pc.t0), fmt_t(pc.t1), (pc.t1 - pc.t0) * 1000,
                pc.class, pc.level_db, pc.peak_db, pc.hf, pc.zc_hz)
        end
    end
    if #pieces > MAX_LINES then
        log("   ... (+%d piezas más)", #pieces - MAX_LINES)
    end

    Segment.add_regions(cfg.preview_prefix, pieces, total)
    total = total + #pieces
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("GainRide: piezas de vista previa", -1)