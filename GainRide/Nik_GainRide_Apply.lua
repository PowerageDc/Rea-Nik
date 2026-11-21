local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Source = dofile(script_dir .. "GainRideSource_common_logic.lua")
local Run = dofile(script_dir .. "GainRideRun_common_logic.lua")
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

local reads = Run.read(segments, cfg)
local by_track, order = Run.build(reads, cfg.seg, cfg.window_ms, ap)

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local results, missing = Run.write(order, by_track, ap)
for _, r in ipairs(results) do
    if r.empty then
        log("GainRide | track '%s' | sin piezas en la fuente", r.name)
    else
        local info = r.info
        log("GainRide | track '%s' | piezas=%d | puntos=%d | objetivo %s dB | ganancia [%.1f, %+.1f] dB | topes: bajar %d, subir %d",
            r.name, r.pieces, r.points, info.target_text, info.g_min, info.g_max,
            info.capped_down, info.capped_up)
    end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("GainRide: puntos de ganancia en el envelope", -1)

if #missing > 0 then
    reaper.ShowMessageBox(
        "No se encontró el envelope '" .. ap.envelope .. "' visible en: " .. table.concat(missing, ", ")
            .. ".\nMostralo en el track y volvé a correr el script.",
        "GainRide", 0)
end