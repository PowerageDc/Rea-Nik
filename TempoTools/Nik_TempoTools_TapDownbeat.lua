local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Tap = dofile(script_dir .. "TempoTools_common_logic.lua")

Tap.add_tap(true)