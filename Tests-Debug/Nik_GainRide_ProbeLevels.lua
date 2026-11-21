local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Source = dofile(script_dir .. "../GainRide/GainRideSource_common_logic.lua")
local Analysis = dofile(script_dir .. "../GainRide/GainRideAnalysis_common_logic.lua")
local cfg = dofile(script_dir .. "../GainRide/GainRide_config.lua")

local function log(fmt, ...)
    reaper.ShowConsoleMsg(string.format(fmt, ...) .. "\n")
end

local function fmt_t(t)
    return string.format("%02d:%06.3f", math.floor(t / 60), t % 60)
end

local function bar(db)
    local n = math.floor((db + 60) / 2)
    if n < 0 then n = 0 elseif n > 30 then n = 30 end
    return string.rep("#", n)
end

reaper.ClearConsole()

local segments, err = Source.resolve(cfg.probe_mode, cfg.merge_tolerance_ms / 1000)
if not segments then
    log("GainRide probe (%s): %s", cfg.probe_mode, err)
    return
end

local opts = {
    window_s = cfg.window_ms / 1000,
    sample_rate = cfg.sample_rate,
    floor_db = cfg.floor_db,
}
local every = math.max(1, math.floor(cfg.print_every_ms / cfg.window_ms + 0.5))

log("GainRide probe | modo=%s | tramos=%d | ventana=%d ms", cfg.probe_mode, #segments, cfg.window_ms)

for si, seg in ipairs(segments) do
    log("")
    log("== Tramo %d | track '%s' | %s -> %s | partes=%d",
        si, Source.track_name(seg.track), fmt_t(seg.t0), fmt_t(seg.t1), #seg.parts)

    local prev
    for pi, part in ipairs(seg.parts) do
        if prev then
            log("   empalme: %+.1f ms (+ hueco / - solape)", (part.t0 - prev.t1) * 1000)
        end

        local rows, info = Analysis.part_levels(part, opts)
        if not rows then
            log("   parte %d: omitida (%s)", pi, info)
        else
            log("   parte %d | item pos=%s | %s -> %s | acc=[%.3f, %.3f] s | canales=%d | vol item %.1f dB, take %.1f dB",
                pi, fmt_t(part.pos), fmt_t(part.t0), fmt_t(part.t1),
                info.acc_start, info.acc_end, info.channels, info.item_vol_db, info.take_vol_db)

            local lo, hi, sum, empty = 0, -math.huge, 0, 0
            lo = math.huge
            for i, r in ipairs(rows) do
                if r.rms_db < lo then lo = r.rms_db end
                if r.rms_db > hi then hi = r.rms_db end
                sum = sum + r.rms_db
                if r.got ~= 1 then empty = empty + 1 end
                if (i - 1) % every == 0 then
                    log("   %s  rms %6.1f  pk %6.1f  %s", fmt_t(r.t), r.rms_db, r.peak_db, bar(r.rms_db))
                end
            end
            if #rows > 0 then
                log("   ventanas=%d | rms min %.1f / max %.1f / media %.1f dB | sin audio=%d",
                    #rows, lo, hi, sum / #rows, empty)
            end
        end
        prev = part
    end
end