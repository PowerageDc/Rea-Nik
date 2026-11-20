local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Config = dofile(script_dir .. "MidiGen_config.lua")
local Pedal = dofile(script_dir .. "MidiGenPedal_common_logic.lua")

Pedal.run_cursor(Config, true)