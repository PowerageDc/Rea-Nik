local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Segment = dofile(script_dir .. "GainRideSegment_common_logic.lua")
local cfg = dofile(script_dir .. "GainRide_config.lua")

reaper.Undo_BeginBlock()
Segment.clear_regions(cfg.preview_prefix)
reaper.UpdateArrange()
reaper.Undo_EndBlock("GainRide: borrar piezas de vista previa", -1)